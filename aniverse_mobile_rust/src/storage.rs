use crate::{
    models::{Anime, AuthSession, DownloadItem, HistoryEntry, WatchEntry},
    settings::atomic_write,
};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    fs,
    path::{Path, PathBuf},
};

pub use crate::settings::data_dir;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct LocalData {
    pub history: Vec<HistoryEntry>,
    #[serde(alias = "wathclist")]
    pub watchlist: Vec<String>,
    pub saved_episodes: Vec<String>,
    pub downloads: Vec<DownloadItem>,
    pub anime_cache: Vec<Anime>,
    pub session: Option<AuthSession>,
    pub watch_entries: Vec<WatchEntry>,
}

impl LocalData {
    pub fn path() -> PathBuf {
        data_dir().join("local-data.json")
    }
    pub fn load() -> Self {
        Self::load_from(&Self::path())
    }

    pub fn load_from(path: &Path) -> Self {
        let mut data: Self = fs::read(path)
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        // Older prototypes stored only IDs, including the misspelling above.
        // Keep them as memberships and create mergeable entries for sync.
        for id in data.watchlist.clone() {
            if !data.watch_entries.iter().any(|entry| entry.anime_id == id) {
                let anime = data.anime(&id);
                data.watch_entries.push(WatchEntry {
                    anime_id: id,
                    title: anime.map(Anime::title_text).unwrap_or_default(),
                    cover: anime.map(Anime::cover_url).unwrap_or_default(),
                    ..Default::default()
                });
            }
        }
        data.rebuild_watchlist();
        data.sort_history();
        data
    }

    pub fn save(&self) -> Result<()> {
        self.save_to(&Self::path())
    }
    pub fn save_to(&self, path: &Path) -> Result<()> {
        atomic_write(path, &serde_json::to_vec_pretty(self)?)
    }

    pub fn anime(&self, id: &str) -> Option<&Anime> {
        self.anime_cache
            .iter()
            .find(|anime| anime.id_string() == id)
    }

    pub fn cache_anime(&mut self, anime: Anime) {
        let id = anime.id_string();
        if id.is_empty() {
            return;
        }
        for entry in &mut self.watch_entries {
            if entry.anime_id == id {
                entry.title = anime.title_text();
                entry.cover = anime.cover_url();
            }
        }
        self.anime_cache.retain(|old| old.id_string() != id);
        self.anime_cache.insert(0, anime);
        // Keep posters for offline My List / Continue Watching. Bound the
        // unpinned catalogue cache without evicting the user's saved titles.
        if self.anime_cache.len() > 1000 {
            let pinned: HashSet<_> = self
                .watchlist
                .iter()
                .cloned()
                .chain(
                    self.history
                        .iter()
                        .filter(|e| !e.deleted)
                        .map(|e| e.anime_id.clone()),
                )
                .collect();
            let mut unpinned = 0;
            self.anime_cache.retain(|a| {
                if pinned.contains(&a.id_string()) {
                    true
                } else {
                    unpinned += 1;
                    unpinned <= 500
                }
            });
        }
    }

    /// Returns whether the anime is followed after the operation.
    pub fn toggle_watchlist(&mut self, id: &str) -> bool {
        if id.trim().is_empty() {
            return false;
        }
        let followed = !self.watchlist.iter().any(|old| old == id);
        let previous_timestamp = self
            .watch_entries
            .iter()
            .find(|entry| entry.anime_id == id)
            .map(|entry| entry.updated_at)
            .unwrap_or_default();
        let anime = self.anime(id);
        let entry = WatchEntry {
            anime_id: id.to_owned(),
            title: anime.map(Anime::title_text).unwrap_or_default(),
            cover: anime.map(Anime::cover_url).unwrap_or_default(),
            updated_at: chrono::Utc::now()
                .timestamp_millis()
                .max(previous_timestamp.saturating_add(1)),
            deleted: !followed,
            ..Default::default()
        };
        self.watch_entries.retain(|old| old.anime_id != id);
        self.watch_entries.push(entry);
        self.rebuild_watchlist();
        followed
    }

    pub fn following(&self, id: &str) -> bool {
        self.watchlist.iter().any(|old| old == id)
    }

    /// Follow [id], remembering [seen] episodes as already out (new ones count from there).
    pub fn follow(&mut self, id: &str, title: &str, cover: &str, seen: u32) {
        if id.trim().is_empty() {
            return;
        }
        let previous = self.watch_entries.iter().find(|e| e.anime_id == id).map(|e| e.updated_at).unwrap_or_default();
        self.watch_entries.retain(|old| old.anime_id != id);
        self.watch_entries.push(WatchEntry {
            anime_id: id.to_owned(),
            title: title.to_owned(),
            cover: cover.to_owned(),
            seen_episode: seen,
            updated_at: chrono::Utc::now().timestamp_millis().max(previous.saturating_add(1)),
            deleted: false,
        });
        self.rebuild_watchlist();
    }

    pub fn unfollow(&mut self, id: &str) {
        let now = chrono::Utc::now().timestamp_millis();
        for e in self.watch_entries.iter_mut().filter(|e| e.anime_id == id) {
            e.deleted = true;
            e.updated_at = now.max(e.updated_at.saturating_add(1));
        }
        self.rebuild_watchlist();
    }

    /// The viewer has seen that [aired] episodes are out: no longer new.
    pub fn mark_seen(&mut self, id: &str, aired: u32) -> bool {
        let now = chrono::Utc::now().timestamp_millis();
        let mut changed = false;
        for e in self.watch_entries.iter_mut().filter(|e| e.anime_id == id && !e.deleted && e.seen_episode < aired) {
            e.seen_episode = aired;
            e.updated_at = now.max(e.updated_at.saturating_add(1));
            changed = true;
        }
        if changed {
            self.rebuild_watchlist();
        }
        changed
    }

    pub fn watch_entry(&self, id: &str) -> Option<&WatchEntry> {
        self.watch_entries.iter().find(|e| e.anime_id == id && !e.deleted)
    }

    /// Followed anime, most recently changed first.
    pub fn followed(&self) -> Vec<&WatchEntry> {
        self.watch_entries.iter().filter(|e| !e.deleted).collect()
    }

    /// Every episode watched of [id], by episode number.
    pub fn episodes_of(&self, id: &str) -> std::collections::HashMap<u32, &HistoryEntry> {
        let mut out = std::collections::HashMap::new();
        for e in self.history.iter().filter(|e| e.anime_id == id && !e.deleted) {
            out.entry(e.episode).or_insert(e);
        }
        out
    }

    /// Remove all history, as markers so the removal reaches the account.
    pub fn clear_all_history(&mut self) {
        let now = chrono::Utc::now().timestamp_millis();
        for e in self.history.iter_mut().filter(|e| !e.deleted) {
            e.deleted = true;
            e.dirty = true;
            e.updated_at = now;
        }
    }

    /// Forget this device's history (on sign-out: it belongs to the account).
    pub fn clear_local(&mut self) {
        self.history.clear();
    }

    pub fn record_progress(&mut self, entry: HistoryEntry) {
        if entry.anime_id.is_empty() || entry.episode == 0 {
            return;
        }
        if self.history.iter().any(|old| {
            old.anime_id == entry.anime_id
                && old.episode == entry.episode
                && old.updated_at > entry.updated_at
        }) {
            return;
        }
        self.history
            .retain(|old| old.anime_id != entry.anime_id || old.episode != entry.episode);
        self.history.push(entry);
        self.sort_history();
    }

    pub fn latest_history(&self) -> Vec<&HistoryEntry> {
        let mut seen = HashSet::new();
        self.history
            .iter()
            .filter(|entry| !entry.deleted && seen.insert(entry.anime_id.clone()))
            .collect()
    }

    pub fn remove_history(&mut self, id: &str) {
        let now = chrono::Utc::now().timestamp_millis();
        for entry in self.history.iter_mut().filter(|e| e.anime_id == id) {
            entry.deleted = true;
            entry.dirty = true;
            entry.updated_at = now;
        }
        self.sort_history();
    }

    pub fn merge_history(&mut self, entries: Vec<HistoryEntry>) {
        for mut entry in entries {
            entry.dirty = false;
            self.record_progress(entry);
        }
    }

    pub fn merge_watchlist(&mut self, entries: Vec<WatchEntry>) {
        for entry in entries {
            if entry.anime_id.is_empty() {
                continue;
            }
            if self
                .watch_entries
                .iter()
                .any(|old| old.anime_id == entry.anime_id && old.updated_at > entry.updated_at)
            {
                continue;
            }
            self.watch_entries
                .retain(|old| old.anime_id != entry.anime_id);
            self.watch_entries.push(entry);
        }
        self.rebuild_watchlist();
    }

    fn rebuild_watchlist(&mut self) {
        self.watch_entries
            .sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        self.watchlist = self
            .watch_entries
            .iter()
            .filter(|entry| !entry.deleted)
            .map(|entry| entry.anime_id.clone())
            .collect();
    }

    fn sort_history(&mut self) {
        self.history.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        self.history.truncate(400);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn prototype_watchlist_typo_is_read_without_losing_history() {
        let root = std::env::temp_dir().join(format!("av-storage-test-{}", uuid::Uuid::new_v4()));
        let path = root.join("local-data.json");
        fs::create_dir_all(&root).unwrap();
        fs::write(
            &path,
            r#"{"wathclist":["1","2"],"history":[],"saved_episodes":["1|2"]}"#,
        )
        .unwrap();
        let data = LocalData::load_from(&path);
        assert_eq!(data.watchlist, ["1", "2"]);
        assert_eq!(data.saved_episodes, ["1|2"]);
        assert_eq!(data.watch_entries.len(), 2);
        data.save_to(&path).unwrap();
        assert_eq!(LocalData::load_from(&path).watchlist, data.watchlist);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn history_merges_preserve_newer_local_progress_and_deletions() {
        let mut data = LocalData::default();
        data.record_progress(HistoryEntry {
            anime_id: "1".into(),
            episode: 1,
            updated_at: 20,
            position_ms: 500,
            dirty: true,
            ..Default::default()
        });
        data.merge_history(vec![HistoryEntry {
            anime_id: "1".into(),
            episode: 1,
            updated_at: 10,
            position_ms: 100,
            ..Default::default()
        }]);
        assert_eq!(data.history[0].position_ms, 500);
        assert!(data.history[0].dirty);
        data.merge_history(vec![HistoryEntry {
            anime_id: "1".into(),
            episode: 1,
            updated_at: 30,
            deleted: true,
            ..Default::default()
        }]);
        assert!(data.latest_history().is_empty());
        assert!(!data.history[0].dirty);
    }

    #[test]
    fn following_retains_metadata_and_unfollowing_creates_tombstone() {
        let mut data = LocalData::default();
        data.cache_anime(
            serde_json::from_value(
                json!({"id":1,"title":"One Piece","coverImage":{"large":"poster.jpg"}}),
            )
            .unwrap(),
        );
        assert!(data.toggle_watchlist("1"));
        assert_eq!(data.watch_entries[0].title, "One Piece");
        assert!(!data.toggle_watchlist("1"));
        assert!(data.watchlist.is_empty());
        assert!(data.watch_entries[0].deleted);
        data.merge_watchlist(vec![WatchEntry {
            anime_id: "1".into(),
            updated_at: 0,
            ..Default::default()
        }]);
        assert!(data.watchlist.is_empty());
    }
}
