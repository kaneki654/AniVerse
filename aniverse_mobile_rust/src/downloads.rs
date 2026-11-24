//! Saved episodes, for watching offline (lib/services/download_service.dart,
//! simplified). An HLS stream is saved with its playlist, segments, keys and
//! init sections into downloads/<key>/, the playlist rewritten to the local
//! files; anything else is saved as one file. Work happens in <key>.part and
//! is moved into place only when complete, so a half download never plays.
use anyhow::{bail, Context, Result};
use std::{
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        Arc,
    },
    time::Duration,
};
use tokio::{io::AsyncWriteExt, sync::Semaphore, task::JoinSet};
use url::Url;

pub fn root() -> PathBuf {
    crate::storage::data_dir().join("downloads")
}

fn safe_key(key: &str) -> Result<&str> {
    if key.is_empty() || key.len() > 120 || !key.chars().all(|c| c.is_ascii_alphanumeric() || "-_.".contains(c)) || key.starts_with('.') {
        bail!("Invalid download name");
    }
    Ok(key)
}

fn client() -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(15))
        .timeout(Duration::from_secs(120))
        .user_agent(concat!("AniVerse-Rust/", env!("CARGO_PKG_VERSION")))
        .build()?)
}

/// Download [url] (a stream the server handed out) as episode [key].
/// [progress] gets (bytes so far, 0..1). Returns (bytes, playable path).
pub async fn save_episode(
    key: &str,
    url: &str,
    data_saver: bool,
    cancel: Arc<AtomicBool>,
    progress: impl Fn(u64, f32) + Send + Sync + 'static,
) -> Result<(u64, String)> {
    let key = safe_key(key)?.to_owned();
    let final_dir = root().join(&key);
    let work = root().join(format!("{key}.part"));
    let _ = tokio::fs::remove_dir_all(&work).await;
    tokio::fs::create_dir_all(&work).await.with_context(|| format!("Cannot create {}", work.display()))?;
    let progress = Arc::new(progress);
    let result = save_into(&work, url, data_saver, cancel, progress).await;
    match result {
        Ok((bytes, file)) => {
            let _ = tokio::fs::remove_dir_all(&final_dir).await;
            tokio::fs::rename(&work, &final_dir).await.context("Cannot finish the download")?;
            Ok((bytes, final_dir.join(file).to_string_lossy().into_owned()))
        }
        Err(error) => {
            let _ = tokio::fs::remove_dir_all(&work).await;
            Err(error)
        }
    }
}

async fn save_into(
    dir: &Path,
    url: &str,
    data_saver: bool,
    cancel: Arc<AtomicBool>,
    progress: Arc<dyn Fn(u64, f32) + Send + Sync>,
) -> Result<(u64, &'static str)> {
    let client = client()?;
    let mut base = Url::parse(url).context("The stream address is invalid")?;
    let response = client.get(base.clone()).send().await?.error_for_status()?;
    let is_playlist = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .map(|v| v.contains("mpegurl"))
        .unwrap_or(false)
        || base.path().ends_with(".m3u8")
        || base.path().contains("/proxy/m3u8");
    if !is_playlist {
        return save_file(dir, response, cancel, progress).await;
    }
    let mut text = response.text().await?;
    if !text.trim_start().starts_with("#EXTM3U") {
        bail!("The server did not return a playlist");
    }
    // A master playlist: take one rendition (the lowest with data saver on).
    if text.contains("#EXT-X-STREAM-INF") {
        let variant = pick_variant(&text, data_saver).context("The playlist has no streams")?;
        base = base.join(&variant)?;
        text = client.get(base.clone()).send().await?.error_for_status()?.text().await?;
    }
    let plan = plan_media_playlist(&text, &base)?;
    if plan.files.is_empty() {
        bail!("The playlist has no video segments");
    }
    let total = plan.files.len();
    let done = Arc::new(AtomicUsize::new(0));
    let bytes = Arc::new(AtomicU64::new(0));
    let slots = Arc::new(Semaphore::new(4));
    let mut jobs = JoinSet::new();
    for (remote, local) in plan.files.clone() {
        let (client, dir, cancel, done, bytes, slots, progress) =
            (client.clone(), dir.to_path_buf(), cancel.clone(), done.clone(), bytes.clone(), slots.clone(), progress.clone());
        jobs.spawn(async move {
            let _permit = slots.acquire_owned().await?;
            if cancel.load(Ordering::Relaxed) {
                bail!("Cancelled");
            }
            let mut tries = 0;
            let body = loop {
                tries += 1;
                match fetch(&client, &remote).await {
                    Ok(body) => break body,
                    Err(e) if tries >= 3 => return Err(e),
                    Err(_) => tokio::time::sleep(Duration::from_millis(600 * tries)).await,
                }
            };
            tokio::fs::write(dir.join(&local), &body).await?;
            let b = bytes.fetch_add(body.len() as u64, Ordering::Relaxed) + body.len() as u64;
            let d = done.fetch_add(1, Ordering::Relaxed) + 1;
            progress(b, d as f32 / total as f32);
            anyhow::Ok(())
        });
    }
    while let Some(joined) = jobs.join_next().await {
        if let Err(e) = joined.context("A download task stopped")? {
            jobs.abort_all();
            return Err(e);
        }
        if cancel.load(Ordering::Relaxed) {
            jobs.abort_all();
            bail!("Cancelled");
        }
    }
    tokio::fs::write(dir.join("index.m3u8"), plan.playlist).await?;
    Ok((bytes.load(Ordering::Relaxed), "index.m3u8"))
}

async fn fetch(client: &reqwest::Client, url: &Url) -> Result<Vec<u8>> {
    let response = client.get(url.clone()).send().await?.error_for_status()?;
    let mut body = Vec::new();
    let mut response = response;
    while let Some(chunk) = response.chunk().await? {
        if body.len() + chunk.len() > 256 * 1024 * 1024 {
            bail!("A segment is unexpectedly large");
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

async fn save_file(
    dir: &Path,
    mut response: reqwest::Response,
    cancel: Arc<AtomicBool>,
    progress: Arc<dyn Fn(u64, f32) + Send + Sync>,
) -> Result<(u64, &'static str)> {
    let length = response.content_length().unwrap_or(0);
    let mut file = tokio::fs::File::create(dir.join("episode.mp4")).await?;
    let mut bytes = 0u64;
    let mut last = 0u64;
    while let Some(chunk) = response.chunk().await? {
        if cancel.load(Ordering::Relaxed) {
            bail!("Cancelled");
        }
        file.write_all(&chunk).await?;
        bytes += chunk.len() as u64;
        if bytes - last > 512 * 1024 {
            last = bytes;
            progress(bytes, if length > 0 { bytes as f32 / length as f32 } else { 0.0 });
        }
    }
    file.flush().await?;
    if bytes == 0 {
        bail!("The stream was empty");
    }
    Ok((bytes, "episode.mp4"))
}

/// The rendition to keep from a master playlist: the highest bandwidth up to
/// 1080p, or the lowest with data saver on.
fn pick_variant(master: &str, lowest: bool) -> Option<String> {
    let mut variants: Vec<(u64, u32, String)> = Vec::new();
    let mut pending: Option<(u64, u32)> = None;
    for line in master.lines().map(str::trim) {
        if let Some(attrs) = line.strip_prefix("#EXT-X-STREAM-INF:") {
            let bandwidth = attribute(attrs, "BANDWIDTH").and_then(|v| v.parse().ok()).unwrap_or(0);
            let height = attribute(attrs, "RESOLUTION")
                .and_then(|r| r.split('x').nth(1).and_then(|h| h.parse().ok()))
                .unwrap_or(0);
            pending = Some((bandwidth, height));
        } else if !line.is_empty() && !line.starts_with('#') {
            if let Some((bandwidth, height)) = pending.take() {
                variants.push((bandwidth, height, line.to_owned()));
            }
        }
    }
    if lowest {
        return variants.into_iter().min_by_key(|v| v.0).map(|v| v.2);
    }
    let capped: Vec<_> = variants.iter().filter(|v| v.1 == 0 || v.1 <= 1080).cloned().collect();
    let pool = if capped.is_empty() { variants } else { capped };
    pool.into_iter().max_by_key(|v| v.0).map(|v| v.2)
}

fn attribute<'a>(attrs: &'a str, name: &str) -> Option<&'a str> {
    let mut rest = attrs;
    while !rest.is_empty() {
        let (pair, tail) = split_attribute(rest);
        if let Some((k, v)) = pair.split_once('=') {
            if k.trim() == name {
                return Some(v.trim().trim_matches('"'));
            }
        }
        rest = tail;
    }
    None
}

/// One `KEY=VALUE` (values may be quoted and hold commas), and what follows.
fn split_attribute(s: &str) -> (&str, &str) {
    let mut quoted = false;
    for (i, c) in s.char_indices() {
        match c {
            '"' => quoted = !quoted,
            ',' if !quoted => return (&s[..i], &s[i + 1..]),
            _ => {}
        }
    }
    (s, "")
}

#[derive(Debug)]
struct Plan {
    playlist: String,
    files: Vec<(Url, String)>,
}

/// Rewrite a media playlist to local names, listing what to download.
fn plan_media_playlist(text: &str, base: &Url) -> Result<Plan> {
    let mut out = String::with_capacity(text.len());
    let mut files = Vec::new();
    let mut segments = 0usize;
    let mut extras = 0usize;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("#EXT-X-KEY") || trimmed.starts_with("#EXT-X-MAP") {
            if let Some(uri) = quoted_uri(trimmed) {
                if !uri.starts_with("skd://") && !uri.starts_with("data:") {
                    extras += 1;
                    let local = format!("{}{extras:03}{}", if trimmed.starts_with("#EXT-X-KEY") { "key" } else { "init" }, extension(&uri, ".bin"));
                    files.push((base.join(&uri)?, local.clone()));
                    out.push_str(&trimmed.replacen(&format!("URI=\"{uri}\""), &format!("URI=\"{local}\""), 1));
                    out.push('\n');
                    continue;
                }
            }
            out.push_str(trimmed);
        } else if !trimmed.is_empty() && !trimmed.starts_with('#') {
            segments += 1;
            let local = format!("seg{segments:05}{}", extension(trimmed, ".ts"));
            files.push((base.join(trimmed)?, local.clone()));
            out.push_str(&local);
        } else {
            out.push_str(trimmed);
        }
        out.push('\n');
    }
    Ok(Plan { playlist: out, files })
}

fn quoted_uri(line: &str) -> Option<String> {
    let start = line.find("URI=\"")? + 5;
    let end = line[start..].find('"')? + start;
    Some(line[start..end].to_owned())
}

/// The file extension of an address's path, if it is a plain one.
fn extension(uri: &str, fallback: &str) -> String {
    let path = uri.split(['?', '#']).next().unwrap_or("");
    let name = path.rsplit('/').next().unwrap_or("");
    match name.rsplit_once('.') {
        Some((_, ext)) if !ext.is_empty() && ext.len() <= 5 && ext.chars().all(|c| c.is_ascii_alphanumeric()) => format!(".{}", ext.to_ascii_lowercase()),
        _ => fallback.to_owned(),
    }
}

/// Delete a saved episode and anything half-downloaded for it.
pub fn remove_episode(key: &str) -> Result<()> {
    let key = safe_key(key)?;
    for dir in [root().join(key), root().join(format!("{key}.part"))] {
        if dir.exists() {
            std::fs::remove_dir_all(&dir).with_context(|| format!("Cannot delete {}", dir.display()))?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn master_playlists_pick_a_rendition() {
        let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS=\"avc1,mp4a\"\nlow/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\nhigh/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=3840x2160\nuhd/index.m3u8\n";
        assert_eq!(pick_variant(master, false).as_deref(), Some("high/index.m3u8"));
        assert_eq!(pick_variant(master, true).as_deref(), Some("low/index.m3u8"));
    }

    #[test]
    fn media_playlists_are_rewritten_to_local_files() {
        let base = Url::parse("https://anime.test/proxy/m3u8?url=x").unwrap();
        let text = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"/proxy/key?k=1\",IV=0x1\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:4.0,\n/proxy/seg?u=a\n#EXTINF:4.0,\nhttps://cdn.test/b/seg2.m4s?t=1\n#EXT-X-ENDLIST\n";
        let plan = plan_media_playlist(text, &base).unwrap();
        assert_eq!(plan.files.len(), 4);
        assert_eq!(plan.files[0].0.as_str(), "https://anime.test/proxy/key?k=1");
        assert_eq!(plan.files[3].1, "seg00002.m4s");
        assert!(plan.playlist.contains("URI=\"key001.bin\""));
        assert!(plan.playlist.contains("URI=\"init002.mp4\""));
        assert!(plan.playlist.contains("\nseg00001.ts\n"));
        assert!(plan.playlist.ends_with("#EXT-X-ENDLIST\n"));
    }

    #[test]
    fn download_names_cannot_escape_the_folder() {
        assert!(safe_key("16498-3-sub").is_ok());
        assert!(safe_key("../x").is_err());
        assert!(safe_key("a/b").is_err());
        assert!(safe_key("").is_err());
    }
}
