//! Platform playback and the Android host's services. The catalogue UI stays
//! responsive while native playback reports progress back to the history used
//! by Continue Watching. The Android activity also hands Rust the back key,
//! the size of the system bars and the player overlay's own buttons, and plays
//! the manga sound effects and opens links for it.
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::sync::{Mutex, OnceLock};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct PlaybackRequest {
    pub url: String,
    pub title: String,
    pub anime_id: String,
    pub cover: String,
    pub episode: u32,
    pub position_ms: u64,
    pub speed: f32,
    pub seek_step: u32,
    pub subtitle_url: Option<String>,
    pub subtitle_language: String,
    pub subtitle_size: String,
    pub subtitle_background: bool,
    pub subtitle_color: String,
    pub intro_start_ms: Option<u64>,
    pub intro_end_ms: Option<u64>,
    pub outro_start_ms: Option<u64>,
    pub outro_end_ms: Option<u64>,
    pub pip_auto: bool,
    pub bg_audio: bool,
    /// sub | dub | tl: shown on the overlay's switch button.
    pub category: String,
    /// Another episode is out after this one: the overlay offers it.
    pub has_next: bool,
    /// A saved copy rather than a stream.
    pub local: bool,
}
impl Default for PlaybackRequest {
    fn default() -> Self {
        Self {
            url: String::new(),
            title: String::new(),
            anime_id: String::new(),
            cover: String::new(),
            episode: 1,
            position_ms: 0,
            speed: 1.0,
            seek_step: 10,
            subtitle_url: None,
            subtitle_language: String::new(),
            subtitle_size: "m".into(),
            subtitle_background: true,
            subtitle_color: "white".into(),
            intro_start_ms: None,
            intro_end_ms: None,
            outro_start_ms: None,
            outro_end_ms: None,
            pip_auto: true,
            bg_audio: false,
            category: "sub".into(),
            has_next: false,
            local: false,
        }
    }
}
impl PlaybackRequest {
    pub fn validate(&self) -> Result<()> {
        validate_media_url(&self.url)?;
        if let Some(subtitle) = &self.subtitle_url {
            validate_media_url(subtitle)?;
        }
        if self.episode == 0 {
            bail!("Choose an episode to play.");
        }
        if !self.speed.is_finite() || !(0.25..=3.0).contains(&self.speed) {
            bail!("Playback speed must be between 0.25 and 3.");
        }
        Ok(())
    }
}
fn validate_media_url(value: &str) -> Result<()> {
    let url = url::Url::parse(value).context("The stream URL is invalid.")?;
    match url.scheme() {
        "http" | "https" if url.host_str().is_some() => Ok(()),
        "file"
            if url
                .to_file_path()
                .map(|path| path.is_absolute())
                .unwrap_or(false) =>
        {
            Ok(())
        }
        _ => bail!("Use an HTTP(S) stream or an absolute downloaded file URL."),
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct PlaybackEvent {
    pub anime_id: String,
    pub title: String,
    pub cover: String,
    pub episode: u32,
    pub position_ms: u64,
    pub duration_ms: u64,
    pub ended: bool,
    /// The player overlay was closed (back, or its own back button).
    pub closed: bool,
    pub error: Option<String>,
}

/// What the Android activity tells the app outside playback progress.
#[derive(Clone, Debug, PartialEq)]
pub enum HostEvent {
    /// The system back key, with no player open.
    Back,
    /// The status and navigation bars drawn over the app, in dp.
    Insets { top: f32, bottom: f32 },
    /// A button on the player overlay: "next", "switch".
    Command(String),
}

static EVENTS: OnceLock<Mutex<Vec<PlaybackEvent>>> = OnceLock::new();
static HOST: OnceLock<Mutex<Vec<HostEvent>>> = OnceLock::new();

fn push_event(event: PlaybackEvent) {
    if let Ok(mut events) = EVENTS.get_or_init(|| Mutex::new(Vec::new())).lock() {
        if events.len() >= 200 {
            events.remove(0);
        }
        events.push(event);
    }
}
pub fn drain_events() -> Vec<PlaybackEvent> {
    EVENTS
        .get_or_init(|| Mutex::new(Vec::new()))
        .lock()
        .map(|mut events| std::mem::take(&mut *events))
        .unwrap_or_default()
}
#[allow(dead_code)]
fn push_host(event: HostEvent) {
    if let Ok(mut events) = HOST.get_or_init(|| Mutex::new(Vec::new())).lock() {
        if events.len() < 64 {
            events.push(event);
        }
    }
}
pub fn drain_host_events() -> Vec<HostEvent> {
    HOST.get_or_init(|| Mutex::new(Vec::new()))
        .lock()
        .map(|mut events| std::mem::take(&mut *events))
        .unwrap_or_default()
}

pub fn play(request: PlaybackRequest) -> Result<()> {
    request.validate()?;
    platform::play(request)
}
/// Close the player overlay, if one is open.
pub fn stop() {
    platform::stop();
}
/// Back pressed on the first screen: leave the app (it stays in recents).
pub fn exit_to_background() {
    platform::exit_to_background();
}
/// Sfx.play: one of the manga sounds (res/raw/manga_<name>.wav) at [volume].
pub fn sfx(name: &str, volume: f32) {
    if name.chars().all(|c| c.is_ascii_lowercase()) && !name.is_empty() {
        platform::sfx(name, volume.clamp(0.0, 1.0));
    }
}
/// Open a web page (a trailer, a sign-in page) in the system's browser or app.
pub fn open_url(url: &str) -> Result<()> {
    let parsed = url::Url::parse(url).context("That address is invalid.")?;
    if !["https", "http"].contains(&parsed.scheme()) {
        bail!("Only web addresses can be opened.");
    }
    platform::open_url(parsed.as_str())
}

#[cfg(target_os = "android")]
mod platform {
    use super::*;
    use jni::{
        objects::{GlobalRef, JObject, JString, JValue},
        sys::jfloat,
        JNIEnv, JavaVM,
    };
    struct Bridge {
        vm: JavaVM,
        activity: GlobalRef,
    }
    static BRIDGE: OnceLock<Mutex<Option<Bridge>>> = OnceLock::new();

    pub fn init(app: &slint::android::AndroidApp) -> Result<()> {
        // AndroidApp owns these handles for the activity lifetime. Keep a global
        // reference, and attach each Rust caller to the VM rather than caching JNIEnv.
        let vm = unsafe { JavaVM::from_raw(app.vm_as_ptr().cast())? };
        let activity = {
            let env = vm.attach_current_thread()?;
            let object = unsafe { JObject::from_raw(app.activity_as_ptr().cast()) };
            env.new_global_ref(&object)?
        };
        *BRIDGE
            .get_or_init(|| Mutex::new(None))
            .lock()
            .map_err(|_| anyhow::anyhow!("Android player lock failed"))? =
            Some(Bridge { vm, activity });
        Ok(())
    }
    fn call(method: &str, signature: &str, text: Option<&str>, number: Option<f32>) -> Result<()> {
        let context = BRIDGE
            .get_or_init(|| Mutex::new(None))
            .lock()
            .map_err(|_| anyhow::anyhow!("Android player lock failed"))?;
        let bridge = context.as_ref().context("The Android host is not ready.")?;
        let mut env = bridge.vm.attach_current_thread()?;
        let string = match text {
            Some(text) => Some(env.new_string(text)?),
            None => None,
        };
        let mut args: Vec<JValue> = Vec::new();
        if let Some(s) = &string {
            args.push(JValue::Object(s.as_ref()));
        }
        if let Some(n) = number {
            args.push(JValue::Float(n));
        }
        env.call_method(bridge.activity.as_obj(), method, signature, &args)?;
        Ok(())
    }
    pub fn play(request: PlaybackRequest) -> Result<()> {
        call("playStream", "(Ljava/lang/String;)V", Some(&serde_json::to_string(&request)?), None)
    }
    pub fn stop() {
        let _ = call("stopStream", "()V", None, None);
    }
    pub fn exit_to_background() {
        let _ = call("exitToBackground", "()V", None, None);
    }
    pub fn sfx(name: &str, volume: f32) {
        let _ = call("playSfx", "(Ljava/lang/String;F)V", Some(name), Some(volume));
    }
    pub fn open_url(url: &str) -> Result<()> {
        call("openUrl", "(Ljava/lang/String;)V", Some(url), None)
    }
    #[no_mangle]
    pub extern "system" fn Java_app_aniverse_rust_MainActivity_nativePlaybackEvent(
        mut env: JNIEnv,
        _this: JObject,
        payload: JString,
    ) {
        let result = env.get_string(&payload).map(String::from);
        if let Ok(json) = result {
            if let Ok(event) = serde_json::from_str(&json) {
                push_event(event);
            }
        }
    }
    #[no_mangle]
    pub extern "system" fn Java_app_aniverse_rust_MainActivity_nativeBack(_env: JNIEnv, _this: JObject) {
        push_host(HostEvent::Back);
    }
    #[no_mangle]
    pub extern "system" fn Java_app_aniverse_rust_MainActivity_nativeInsets(
        _env: JNIEnv,
        _this: JObject,
        top: jfloat,
        bottom: jfloat,
    ) {
        push_host(HostEvent::Insets { top, bottom });
    }
    #[no_mangle]
    pub extern "system" fn Java_app_aniverse_rust_MainActivity_nativePlayerCommand(
        mut env: JNIEnv,
        _this: JObject,
        command: JString,
    ) {
        if let Ok(command) = env.get_string(&command).map(String::from) {
            push_host(HostEvent::Command(command));
        }
    }
}
#[cfg(target_os = "android")]
pub fn init_android(app: &slint::android::AndroidApp) -> Result<()> {
    platform::init(app)
}

#[cfg(all(unix, not(target_os = "android")))]
mod platform {
    use super::*;
    use std::{
        io::{BufRead, BufReader, Write},
        os::unix::net::UnixStream,
        process::{Command, Stdio},
        sync::atomic::{AtomicU64, Ordering},
        time::Duration,
    };
    static GENERATION: AtomicU64 = AtomicU64::new(0);
    pub fn play(request: PlaybackRequest) -> Result<()> {
        let socket =
            std::env::temp_dir().join(format!("aniverse-player-{}.sock", uuid::Uuid::new_v4()));
        let mut command = Command::new("mpv");
        command
            .args([
                "--no-terminal",
                "--force-window=yes",
                "--save-position-on-quit=no",
            ])
            .arg(format!("--input-ipc-server={}", socket.display()))
            .arg(format!(
                "--title={} · Episode {}",
                request.title, request.episode
            ))
            .arg(format!(
                "--start={:.3}",
                request.position_ms as f64 / 1000.0
            ))
            .arg(format!("--speed={}", request.speed));
        if let Some(subtitle) = &request.subtitle_url {
            command.arg(format!("--sub-file={subtitle}"));
        }
        if !request.subtitle_language.is_empty() {
            command.arg(format!("--slang={}", request.subtitle_language));
        }
        let mut child = command
            .arg("--")
            .arg(&request.url)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .context("Install mpv to play video in the desktop preview.")?;
        let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
        std::thread::spawn(move || {
            let mut event = PlaybackEvent {
                anime_id: request.anime_id,
                title: request.title,
                cover: request.cover,
                episode: request.episode,
                position_ms: request.position_ms,
                ..Default::default()
            };
            loop {
                if GENERATION.load(Ordering::SeqCst) != generation {
                    let _ = child.kill();
                    let _ = child.wait();
                    break;
                }
                match child.try_wait() {
                    Ok(Some(status)) => {
                        if !status.success() {
                            event.error =
                                Some("The video could not be played. Try another source.".into());
                        }
                        event.ended = event.duration_ms > 0
                            && event.position_ms >= event.duration_ms.saturating_sub(1500);
                        break;
                    }
                    Err(error) => {
                        event.error = Some(error.to_string());
                        break;
                    }
                    Ok(None) => {}
                }
                if let Ok(mut stream) = UnixStream::connect(&socket) {
                    let _ = stream.set_read_timeout(Some(Duration::from_millis(400)));
                    let _ = stream.set_write_timeout(Some(Duration::from_millis(400)));
                    if let Some(position) = property(&mut stream, "time-pos") {
                        event.position_ms = (position.max(0.0) * 1000.0) as u64;
                    }
                    if let Some(duration) = property(&mut stream, "duration") {
                        event.duration_ms = (duration.max(0.0) * 1000.0) as u64;
                    }
                    if event.duration_ms > 0 {
                        push_event(event.clone());
                    }
                }
                std::thread::sleep(Duration::from_secs(2));
            }
            event.closed = true;
            push_event(event);
            let _ = std::fs::remove_file(socket);
        });
        Ok(())
    }
    fn property(stream: &mut UnixStream, name: &str) -> Option<f64> {
        let query = serde_json::json!({"command":["get_property",name],"request_id":7});
        writeln!(stream, "{query}").ok()?;
        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        for _ in 0..20 {
            line.clear();
            if reader.read_line(&mut line).ok()? == 0 {
                return None;
            }
            let message: serde_json::Value = serde_json::from_str(&line).ok()?;
            if message["request_id"] == 7 {
                return message["data"].as_f64();
            }
        }
        None
    }
    pub fn stop() {
        GENERATION.fetch_add(1, Ordering::SeqCst);
    }
    pub fn exit_to_background() {}
    pub fn sfx(_name: &str, _volume: f32) {}
    pub fn open_url(url: &str) -> Result<()> {
        let opener = if cfg!(target_os = "macos") { "open" } else { "xdg-open" };
        Command::new(opener)
            .arg(url)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .with_context(|| format!("Could not start {opener}."))?;
        Ok(())
    }
}
#[cfg(all(not(unix), not(target_os = "android")))]
mod platform {
    use super::*;
    pub fn play(_request: PlaybackRequest) -> Result<()> {
        bail!("Video playback is supported on Android and Unix desktops.")
    }
    pub fn stop() {}
    pub fn exit_to_background() {}
    pub fn sfx(_name: &str, _volume: f32) {}
    pub fn open_url(_url: &str) -> Result<()> {
        bail!("Opening links is not supported here.")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_network_and_local_playback() {
        for url in [
            "https://example.com/video.m3u8",
            "http://127.0.0.1/video.mp4",
            "file:///tmp/episode/index.m3u8",
        ] {
            assert!(PlaybackRequest {
                url: url.into(),
                ..Default::default()
            }
            .validate()
            .is_ok());
        }
        for url in [
            "--script=unsafe",
            "javascript:alert(1)",
            "/relative.mp4",
            "https://",
        ] {
            assert!(PlaybackRequest {
                url: url.into(),
                ..Default::default()
            }
            .validate()
            .is_err());
        }
    }
    #[test]
    fn validates_speed_and_episode() {
        let mut request = PlaybackRequest {
            url: "https://example.com/a".into(),
            ..Default::default()
        };
        request.speed = f32::NAN;
        assert!(request.validate().is_err());
        request.speed = 1.0;
        request.episode = 0;
        assert!(request.validate().is_err());
    }
    #[test]
    fn kotlin_progress_payload_deserializes() {
        let event: PlaybackEvent = serde_json::from_str(r#"{"anime_id":"21","episode":2,"position_ms":125000,"duration_ms":1400000,"ended":false,"closed":true}"#).unwrap();
        assert_eq!(event.episode, 2);
        assert_eq!(event.position_ms, 125000);
        assert!(event.closed);
        assert_eq!(event.error, None);
    }
    #[test]
    fn only_web_links_open() {
        assert!(open_url("javascript:alert(1)").is_err());
        assert!(open_url("file:///etc/passwd").is_err());
    }
}
