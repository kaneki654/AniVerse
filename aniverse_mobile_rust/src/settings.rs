use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

/// The same preference defaults as Flutter's AppSettings. Unknown/new fields
/// are harmless when moving between versions of this client.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub ui_style: String,
    pub theme: String,
    pub sfx: bool,
    pub volume: f32,
    pub data_saver: bool,
    pub sub_size: String,
    pub sub_bg: bool,
    pub sub_lang: String,
    pub sub_color: String,
    pub alerts: bool,
    pub pip_auto: bool,
    pub bg_audio: bool,
    pub speed: f32,
    pub quality: String,
    pub intro: bool,
    pub ep_view: String,
    pub browse_view: String,
    pub host: String,
    pub wifi_only: bool,
    pub download_limit_gb: f32,
    pub auto_delete_watched: bool,
    pub effects: String,
    pub seek_step: u32,
    pub skip_recap: bool,
    pub smart_downloads: bool,
    pub quiet_from: i32,
    pub quiet_to: i32,
    pub text_scale: f32,
    pub high_contrast: bool,
    pub recent_searches: Vec<String>,
    /// My List shows whose new-episode alerts are muted (av.alertsMuted).
    pub alerts_muted: Vec<String>,
    /// Shows being watched in their Tagalog dub (av.showAudio = 'tl').
    pub tagalog_shows: Vec<String>,
    /// Shows whose next episode should not play by itself (av.showAutoNext).
    pub no_auto_next: Vec<String>,
    /// Badges already announced; None until the first look (av.badges).
    pub badges_seen: Option<Vec<String>>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            ui_style: "manga".into(),
            theme: "blood".into(),
            sfx: true,
            volume: 0.35,
            data_saver: false,
            sub_size: "m".into(),
            sub_bg: true,
            sub_lang: String::new(),
            sub_color: "white".into(),
            alerts: false,
            pip_auto: true,
            bg_audio: false,
            speed: 1.0,
            quality: "auto".into(),
            intro: true,
            ep_view: "list".into(),
            browse_view: "grid".into(),
            host: String::new(),
            wifi_only: true,
            download_limit_gb: 0.0,
            auto_delete_watched: false,
            effects: "full".into(),
            seek_step: 10,
            skip_recap: false,
            smart_downloads: false,
            quiet_from: -1,
            quiet_to: 8,
            text_scale: 1.0,
            high_contrast: false,
            recent_searches: Vec::new(),
            alerts_muted: Vec::new(),
            tagalog_shows: Vec::new(),
            no_auto_next: Vec::new(),
            badges_seen: None,
        }
    }
}

impl Settings {
    pub fn path() -> PathBuf {
        data_dir().join("settings.json")
    }
    pub fn data_dir() -> PathBuf {
        data_dir()
    }

    pub fn load() -> Self {
        Self::load_from(&Self::path())
    }

    pub fn load_from(path: &Path) -> Self {
        let mut settings: Self = fs::read(path)
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        settings.normalize();
        settings
    }

    pub fn save(&self) -> Result<()> {
        self.save_to(&Self::path())
    }
    pub fn save_to(&self, path: &Path) -> Result<()> {
        atomic_write(path, &serde_json::to_vec_pretty(self)?)
    }

    pub fn add_recent_search(&mut self, query: &str) {
        let query = query.trim();
        if query.chars().count() < 2 {
            return;
        }
        self.recent_searches
            .retain(|old| !old.eq_ignore_ascii_case(query));
        self.recent_searches.insert(0, query.to_owned());
        self.recent_searches.truncate(10);
    }

    fn normalize(&mut self) {
        if !["manga", "pixel"].contains(&self.ui_style.as_str()) {
            self.ui_style = "manga".into();
        }
        if !["blood", "neon", "sakura", "gameboy", "samurai"].contains(&self.theme.as_str()) {
            self.theme = "blood".into();
        }
        for list in [&mut self.alerts_muted, &mut self.tagalog_shows, &mut self.no_auto_next] {
            if list.len() > 200 {
                let extra = list.len() - 200;
                list.drain(..extra);
            }
        }
        if !["list", "grid"].contains(&self.ep_view.as_str()) {
            self.ep_view = "list".into();
        }
        if !["list", "grid"].contains(&self.browse_view.as_str()) {
            self.browse_view = "grid".into();
        }
        if !["s", "m", "l", "xl"].contains(&self.sub_size.as_str()) {
            self.sub_size = "m".into();
        }
        if !["white", "yellow", "cyan", "green"].contains(&self.sub_color.as_str()) {
            self.sub_color = "white".into();
        }
        if !["full", "lite", "off"].contains(&self.effects.as_str()) {
            self.effects = "full".into();
        }
        self.volume = self.volume.clamp(0.0, 1.0);
        self.speed = self.speed.clamp(0.25, 3.0);
        self.text_scale = self.text_scale.clamp(1.0, 1.3);
        self.download_limit_gb = self.download_limit_gb.max(0.0);
        self.seek_step = self.seek_step.clamp(5, 120);
        self.quiet_from = self.quiet_from.clamp(-1, 23);
        self.quiet_to = self.quiet_to.clamp(0, 23);
        self.recent_searches.truncate(10);
    }
}

/// Android's activity supplies its app-private files directory before starting
/// Rust. The environment override also keeps preview/tests away from user data.
pub fn data_dir() -> PathBuf {
    if let Some(path) = std::env::var_os("ANIVERSE_DATA_DIR").filter(|s| !s.is_empty()) {
        return PathBuf::from(path);
    }
    directories::ProjectDirs::from("app", "AniVerse", "AniVerseRust")
        .map(|p| p.data_local_dir().to_path_buf())
        .unwrap_or_else(|| std::env::temp_dir().join("aniverse-rust"))
}

/// Write complete JSON to a private temporary file, then replace the old one.
/// Interrupted writes cannot truncate the last saved session/history/settings.
pub(crate) fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .context("Storage path has no parent directory")?;
    fs::create_dir_all(parent).with_context(|| format!("Cannot create {}", parent.display()))?;
    let temporary = parent.join(format!(".aniverse-{}.tmp", uuid::Uuid::new_v4()));
    let result = (|| -> Result<()> {
        let mut options = fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        drop(file);
        fs::rename(&temporary, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result.with_context(|| format!("Cannot save {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_new_settings_keep_flutter_defaults() {
        let value: Settings =
            serde_json::from_str(r#"{"theme":"neon","host":"https://example.test"}"#).unwrap();
        assert_eq!(value.theme, "neon");
        assert_eq!(value.ui_style, "manga");
        assert_eq!(value.ep_view, "list");
        assert!(value.intro && value.wifi_only);
        assert_eq!(value.seek_step, 10);
    }

    #[test]
    fn searches_are_deduplicated_and_bounded() {
        let mut settings = Settings::default();
        settings.add_recent_search("One Piece");
        settings.add_recent_search(" one piece ");
        assert_eq!(settings.recent_searches, ["one piece"]);
        for n in 0..20 {
            settings.add_recent_search(&format!("show {n}"));
        }
        assert_eq!(settings.recent_searches.len(), 10);
        assert_eq!(settings.recent_searches[0], "show 19");
    }

    #[test]
    fn saving_replaces_complete_json_and_normalizes_invalid_values() {
        let root = std::env::temp_dir().join(format!("av-settings-test-{}", uuid::Uuid::new_v4()));
        let path = root.join("settings.json");
        let mut settings = Settings::default();
        settings.save_to(&path).unwrap();
        settings.ui_style = "pixel".into();
        settings.volume = 8.0;
        settings.save_to(&path).unwrap();
        let loaded = Settings::load_from(&path);
        assert_eq!(loaded.ui_style, "pixel");
        assert_eq!(loaded.volume, 1.0);
        assert_eq!(fs::read_dir(&root).unwrap().count(), 1);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
        fs::remove_dir_all(root).unwrap();
    }
}
