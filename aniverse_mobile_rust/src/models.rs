use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;

/// AniList-compatible cards returned by the same API as the Flutter app.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Anime {
    #[serde(default)]
    pub id: Value,
    #[serde(default)]
    pub title: Value,
    #[serde(default, rename = "coverImage")]
    pub cover_image: Value,
    #[serde(default)]
    pub description: Value,
    #[serde(default, deserialize_with = "null_vec")]
    pub genres: Vec<String>,
    #[serde(default)]
    pub episodes: Value,
    #[serde(default)]
    pub status: Value,
    #[serde(default, rename = "averageScore", alias = "avarageScore")]
    pub average_score: Value,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

impl Anime {
    pub fn id_string(&self) -> String {
        value_text(&self.id)
    }

    pub fn title_text(&self) -> String {
        let title = localized_title(&self.title);
        if title.trim().is_empty() {
            "Untitled anime".into()
        } else {
            title
        }
    }

    pub fn cover_url(&self) -> String {
        if let Some(object) = self.cover_image.as_object() {
            return ["extraLarge", "large", "medium"]
                .iter()
                .filter_map(|key| object.get(*key).and_then(Value::as_str))
                .find(|value| !value.is_empty())
                .unwrap_or_default()
                .to_owned();
        }
        let cover = value_text(&self.cover_image);
        if cover.is_empty() {
            self.extra
                .get("cover")
                .or_else(|| self.extra.get("image"))
                .map(value_text)
                .unwrap_or_default()
        } else {
            cover
        }
    }

    pub fn banner_url(&self) -> String {
        self.extra
            .get("bannerImage")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
            .unwrap_or_else(|| self.cover_url())
    }

    pub fn episode_count(&self) -> u32 {
        self.episodes
            .as_u64()
            .and_then(|n| n.try_into().ok())
            .or_else(|| self.episodes.as_str().and_then(|s| s.parse().ok()))
            .unwrap_or(0)
    }

    pub fn score_text(&self) -> String {
        self.average_score
            .as_f64()
            .filter(|score| *score > 0.0)
            .map(|score| format!("{score:.0}%"))
            .unwrap_or_default()
    }

    pub fn description_text(&self) -> String {
        plain_description(&value_text(&self.description))
    }

    /// The poster cover the Flutter app shows (coverImage.large first).
    pub fn poster_url(&self) -> String {
        if let Some(object) = self.cover_image.as_object() {
            return ["large", "extraLarge", "medium"]
                .iter()
                .filter_map(|key| object.get(*key).and_then(Value::as_str))
                .find(|value| !value.is_empty())
                .unwrap_or_default()
                .to_owned();
        }
        self.cover_url()
    }

    /// The score as the starburst letters it: "79", or "" when unrated.
    pub fn score_number(&self) -> String {
        self.average_score
            .as_f64()
            .filter(|score| *score > 0.0)
            .map(|score| format!("{score:.0}"))
            .unwrap_or_default()
    }

    pub fn status_code(&self) -> String {
        value_text(&self.status)
    }

    /// "RELEASING", "NOT YET RELEASED".
    pub fn status_words(&self) -> String {
        self.status_code().replace('_', " ")
    }

    /// The episode AniList says airs next, if one is scheduled.
    pub fn next_airing_episode(&self) -> Option<u32> {
        self.extra
            .get("nextAiringEpisode")
            .and_then(|n| n.get("episode"))
            .and_then(Value::as_u64)
            .map(|n| n as u32)
    }

    /// Episodes that can be played now: aired ones for a show still airing
    /// (airedEpisodes in lib/ui_manga/widgets/manga_extras.dart).
    pub fn aired_episodes(&self) -> u32 {
        if let Some(next) = self.next_airing_episode().filter(|n| *n > 1) {
            return next - 1;
        }
        if self.status_code() == "NOT_YET_RELEASED" {
            return 0;
        }
        match self.episode_count() {
            0 => 12,
            n => n,
        }
    }

    pub fn duration_minutes(&self) -> u32 {
        self.extra.get("duration").and_then(Value::as_u64).unwrap_or(0) as u32
    }

    /// The list rows' facts: ★ 77  ·  12 EPS  ·  RELEASING.
    pub fn list_meta(&self) -> String {
        let mut parts = Vec::new();
        if !self.average_score.is_null() {
            parts.push(format!("★ {}", value_text(&self.average_score)));
        }
        if !self.episodes.is_null() {
            parts.push(format!("{} EPS", value_text(&self.episodes)));
        }
        if !self.status.is_null() {
            parts.push(self.status_words());
        }
        parts.join("  ·  ")
    }
}

pub fn value_text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        Value::Bool(b) => b.to_string(),
        _ => String::new(),
    }
}

fn localized_title(value: &Value) -> String {
    match value {
        Value::Object(fields) => ["english", "romaji", "userPreferred", "native"]
            .iter()
            .filter_map(|key| fields.get(*key).and_then(Value::as_str))
            .find(|s| !s.trim().is_empty())
            .unwrap_or_default()
            .to_owned(),
        _ => value_text(value),
    }
}

fn plain_description(value: &str) -> String {
    let value = value
        .replace("<br>", "\n")
        .replace("<br />", "\n")
        .replace("<br/>", "\n");
    let mut in_tag = false;
    let text: String = value
        .chars()
        .filter(|c| match c {
            '<' => {
                in_tag = true;
                false
            }
            '>' => {
                in_tag = false;
                false
            }
            _ => !in_tag,
        })
        .collect();
    text.replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&nbsp;", " ")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .trim()
        .to_owned()
}

fn string_or_default<'de, D: Deserializer<'de>>(deserializer: D) -> Result<String, D::Error> {
    Value::deserialize(deserializer).map(|v| value_text(&v))
}

fn null_vec<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<Vec<T>>::deserialize(deserializer).map(Option::unwrap_or_default)
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Episode {
    #[serde(default, alias = "episode")]
    pub number: u32,
    #[serde(default, deserialize_with = "string_or_default")]
    pub title: String,
    #[serde(default, alias = "image", deserialize_with = "string_or_default")]
    pub thumbnail: String,
    #[serde(default, alias = "overview", deserialize_with = "string_or_default")]
    pub synopsis: String,
    #[serde(default, alias = "airDate")]
    pub aired: Value,
    #[serde(default)]
    pub runtime: Value,
}

#[derive(Clone, Debug, Default)]
pub struct HomeData {
    pub popular: Vec<Anime>,
    pub trending: Vec<Anime>,
    pub latest: Vec<Anime>,
    pub tagalog: Vec<Anime>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct SourceResponse {
    #[serde(default, deserialize_with = "null_vec")]
    pub sources: Vec<StreamSource>,
    #[serde(default, deserialize_with = "null_vec")]
    pub subtitles: Vec<Value>,
    pub intro: Option<Value>,
    pub outro: Option<Value>,
    #[serde(rename = "hasDub")]
    pub has_dub: Option<bool>,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct StreamSource {
    #[serde(default)]
    pub url: String,
    #[serde(default, deserialize_with = "string_or_default")]
    pub quality: String,
    #[serde(default, alias = "serverName", deserialize_with = "string_or_default")]
    pub server: String,
    #[serde(default, deserialize_with = "null_vec")]
    pub subtitles: Vec<Value>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, Value>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub anime_id: String,
    pub episode: u32,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub cover: String,
    #[serde(default)]
    pub position_ms: u64,
    #[serde(default)]
    pub duration_ms: u64,
    pub updated_at: i64,
    #[serde(default)]
    pub deleted: bool,
    #[serde(default)]
    pub dirty: bool,
}

impl HistoryEntry {
    pub fn fraction(&self) -> f32 {
        if self.duration_ms == 0 {
            0.0
        } else {
            (self.position_ms as f64 / self.duration_ms as f64).clamp(0.0, 1.0) as f32
        }
    }
    pub fn finished(&self) -> bool {
        self.duration_ms > 0 && self.fraction() >= 0.9
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct WatchEntry {
    pub anime_id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub cover: String,
    #[serde(default)]
    pub seen_episode: u32,
    pub updated_at: i64,
    #[serde(default)]
    pub deleted: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct AuthUser {
    pub id: i64,
    pub username: Option<String>,
    #[serde(default)]
    pub display_name: String,
    pub email: Option<String>,
    pub avatar_url: Option<String>,
    #[serde(default)]
    pub provider: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct AuthSession {
    pub token: String,
    pub user: AuthUser,
}

impl std::fmt::Debug for AuthSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AuthSession")
            .field("token", &"[redacted]")
            .field("user", &self.user)
            .finish()
    }
}

#[derive(Clone, Debug, Default, Deserialize)]
pub struct AuthConfig {
    #[serde(default)]
    pub password: bool,
    #[serde(default)]
    pub google: GoogleConfig,
}

#[derive(Clone, Debug, Default, Deserialize)]
pub struct GoogleConfig {
    #[serde(default)]
    pub enabled: bool,
    pub server_client_id: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn anilist_titles_covers_and_scores_match_flutter() {
        let anime: Anime = serde_json::from_value(json!({"id":16498,"title":{"english":null,"romaji":"Shingeki no Kyojin","native":"進撃の巨人"},"coverImage":{"extraLarge":"large.jpg","large":"small.jpg"},"averageScore":84,"episodes":25})).unwrap();
        assert_eq!(anime.title_text(), "Shingeki no Kyojin");
        assert_eq!(anime.id_string(), "16498");
        assert_eq!(anime.cover_url(), "large.jpg");
        assert_eq!(anime.episode_count(), 25);
        assert_eq!(anime.score_text(), "84%");
        assert_eq!(Anime::default().title_text(), "Untitled anime");
    }

    #[test]
    fn descriptions_and_episode_images_accept_api_format() {
        let anime: Anime = serde_json::from_value(
            json!({"description":"A <i>new</i> story.<br />Tom &amp; Jerry"}),
        )
        .unwrap();
        assert_eq!(anime.description_text(), "A new story.\nTom & Jerry");
        let episode: Episode = serde_json::from_value(
            json!({"number":2,"title":null,"image":"https://example.test/ep.jpg"}),
        )
        .unwrap();
        assert_eq!(episode.number, 2);
        assert_eq!(episode.thumbnail, "https://example.test/ep.jpg");
        assert_eq!(episode.title, "");
    }

    #[test]
    fn progress_is_clamped_and_finished_uses_flutter_threshold() {
        let mut e = HistoryEntry {
            duration_ms: 100,
            position_ms: 89,
            ..Default::default()
        };
        assert!(!e.finished());
        e.position_ms = 90;
        assert!(e.finished());
        e.position_ms = 120;
        assert_eq!(e.fraction(), 1.0);
    }

    #[test]
    fn optional_null_arrays_and_age_flags_do_not_drop_valid_cards_or_streams() {
        let anime: Anime = serde_json::from_value(json!({
            "id": 42, "title": {"english": "Example"}, "genres": null,
            "averageScore": null, "isAdult": true
        }))
        .unwrap();
        assert!(anime.genres.is_empty());
        assert_eq!(anime.extra["isAdult"], true);
        assert_eq!(anime.score_text(), "");
        let response: SourceResponse = serde_json::from_value(json!({
            "sources": [{"url":"https://example.test/video.m3u8", "quality":null, "server":null, "subtitles":null}],
            "subtitles":null, "intro":null, "outro":null, "hasDub":null
        })).unwrap();
        assert_eq!(response.sources.len(), 1);
        assert!(response.sources[0].subtitles.is_empty());
        assert!(response.subtitles.is_empty());
        let empty: SourceResponse = serde_json::from_value(json!({"sources":null})).unwrap();
        assert!(empty.sources.is_empty());
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct DownloadItem {
    pub key: String,
    pub anime_id: String,
    pub title: String,
    pub cover: String,
    pub episode: u32,
    pub category: String,
    pub url: String,
    pub path: String,
    pub status: String,
    pub error: String,
    pub bytes: u64,
    pub added_at: i64,
    pub progress: f32,
}
