use crate::{
    models::{
        Anime, AuthConfig, AuthSession, AuthUser, Episode, HistoryEntry, HomeData, SourceResponse,
        WatchEntry,
    },
    settings::Settings,
};
use anyhow::{bail, Context, Result};
use reqwest::{Client, Method, Response, Url};
use serde::de::DeserializeOwned;
use serde_json::{json, Value};
use std::time::Duration;

const GITHUB_DISCOVERY: &str =
    "https://raw.githubusercontent.com/kaneki654/AniVerse/main/discovery/host.json";
pub const DEFAULT_HOST: &str = "https://anime.xolums.world";
const REQUEST_TIMEOUT: Duration = Duration::from_secs(25);

pub const GENRES: &[&str] = &[
    "Action",
    "Adventure",
    "Comedy",
    "Drama",
    "Ecchi",
    "Fantasy",
    "Horror",
    "Mahou Shoujo",
    "Mecha",
    "Music",
    "Mystery",
    "Psychological",
    "Romance",
    "Sci-Fi",
    "Slice of Life",
    "Sports",
    "Supernatural",
    "Thriller",
];

#[derive(Debug)]
pub struct ApiError {
    pub status: u16,
    pub message: String,
}
impl std::fmt::Display for ApiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}
impl std::error::Error for ApiError {}

#[derive(Clone)]
pub struct AniVerseApi {
    client: Client,
    host: String,
}

impl AniVerseApi {
    pub fn new(host: &str) -> Result<Self> {
        let host = if host.trim().is_empty() {
            DEFAULT_HOST.to_owned()
        } else {
            clean_host(host)
        };
        if host.is_empty() {
            bail!("Enter a valid HTTP or HTTPS server address.");
        }
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(10))
            .user_agent(concat!("AniVerse-Rust/", env!("CARGO_PKG_VERSION")))
            .build()?;
        Ok(Self { client, host })
    }

    /// Honor a reachable saved server first, then the same discovery document
    /// as Flutter. The caller owns persistence so an in-flight startup request
    /// cannot overwrite newer theme/preferences changes.
    pub async fn load(settings: &mut Settings) -> Result<Self> {
        let api = Self::new("")?;
        let saved = clean_host(&settings.host);
        if !saved.is_empty() && reachable(&api.client, &saved).await {
            settings.host = saved.clone();
            return Ok(Self {
                client: api.client,
                host: saved,
            });
        }
        let host = discover(&api.client, GITHUB_DISCOVERY)
            .await
            .unwrap_or_else(|| {
                if saved.is_empty() {
                    DEFAULT_HOST.to_owned()
                } else {
                    saved
                }
            });
        settings.host = host.clone();
        Ok(Self {
            client: api.client,
            host,
        })
    }

    pub fn host(&self) -> &str {
        &self.host
    }
    pub fn base_url(&self) -> String {
        format!("{}/api", self.host)
    }

    fn endpoint(&self, path: &str) -> String {
        format!("{}{}", self.base_url(), path)
    }

    async fn get_json(&self, url: String, timeout: Duration) -> Result<Value> {
        decode_response(
            self.client
                .get(url)
                .timeout(timeout)
                .send()
                .await
                .context("Can't reach the AniVerse server. Check your connection and try again.")?,
            false,
        )
        .await
    }

    async fn catalog(&self, path: &str) -> Result<Value> {
        self.get_json(self.endpoint(path), REQUEST_TIMEOUT).await
    }

    pub async fn home(&self) -> Result<HomeData> {
        // One unavailable optional collection must not erase the other rows.
        let (popular, trending, latest, tagalog) = tokio::join!(
            self.catalog("/anime/popular?per_page=12"),
            self.catalog("/anime/trending?per_page=12"),
            self.catalog("/anime/latest?per_page=12"),
            self.catalog("/tagalog")
        );
        if popular.is_err() && trending.is_err() && latest.is_err() {
            return Err(popular.unwrap_err());
        }
        Ok(HomeData {
            popular: popular.map(parse_list).unwrap_or_default(),
            trending: trending.map(parse_list).unwrap_or_default(),
            latest: latest.map(parse_list).unwrap_or_default(),
            tagalog: tagalog
                .map(|body| parse_list(body.get("media").cloned().unwrap_or_default()))
                .unwrap_or_default(),
        })
    }

    pub async fn search(&self, query: &str) -> Result<Vec<Anime>> {
        if query.trim().is_empty() {
            return Ok(Vec::new());
        }
        Ok(parse_list(
            self.catalog(&format!("/anime/search/{}", encode_segment(query.trim())))
                .await?,
        ))
    }

    pub async fn details(&self, id: &str) -> Result<Anime> {
        serde_json::from_value(
            self.catalog(&format!("/anime/info/{}", encode_segment(id)))
                .await?,
        )
        .context("The server returned invalid anime details.")
    }

    pub async fn episodes(&self, id: &str) -> Result<Vec<Episode>> {
        let body = self
            .catalog(&format!("/anime/episodes/{}", encode_segment(id)))
            .await?;
        let mut episodes = parse_array::<Episode>(body)?;
        episodes.retain(|episode| episode.number > 0);
        episodes.sort_by_key(|episode| episode.number);
        Ok(episodes)
    }

    pub async fn extra(&self, id: &str) -> Result<Value> {
        self.catalog(&format!("/anime/extra/{}", encode_segment(id)))
            .await
    }

    pub async fn tagalog(&self, id: &str) -> Result<Value> {
        self.catalog(&format!("/tagalog/{}", encode_segment(id)))
            .await
    }

    /// The actual wire format is [{airingAt, episode, media}], not Anime[].
    /// Keep schedule fields on the card so views can group by day and episode.
    pub async fn schedule(&self, days: u32) -> Result<Vec<Anime>> {
        let body = self
            .get_json(
                self.endpoint(&format!("/anime/schedule?days={}", days.clamp(1, 30))),
                Duration::from_secs(30),
            )
            .await?;
        parse_schedule(body)
    }

    pub async fn genre(&self, genre: &str, page: u32, per_page: u32) -> Result<Vec<Anime>> {
        Ok(parse_list(
            self.catalog(&format!(
                "/anime/genre/{}?page={}&per_page={}",
                encode_segment(genre),
                page.max(1),
                per_page.clamp(1, 50)
            ))
            .await?,
        ))
    }

    pub async fn genre_art(&self, genres: &[&str]) -> Result<Value> {
        let mut url = Url::parse(&self.endpoint("/anime/genres/top"))?;
        url.query_pairs_mut()
            .append_pair("genres", &genres.join(","));
        self.get_json(url.into(), Duration::from_secs(20)).await
    }

    pub async fn filter(&self, filters: &[(String, String)]) -> Result<Value> {
        let mut url = Url::parse(&self.endpoint("/anime/filter"))?;
        for (key, value) in filters {
            if !value.is_empty() {
                url.query_pairs_mut().append_pair(key, value);
            }
        }
        self.get_json(url.into(), REQUEST_TIMEOUT).await
    }

    pub async fn sources(
        &self,
        id: &str,
        episode: u32,
        category: &str,
        fresh: bool,
    ) -> Result<SourceResponse> {
        let mut url = Url::parse(&self.endpoint("/source"))?;
        url.query_pairs_mut()
            .append_pair("episode_id", &format!("{id}/{episode}"))
            .append_pair("category", category);
        if fresh {
            url.query_pairs_mut().append_pair("fresh", "true");
        }
        let body = self.get_json(url.into(), Duration::from_secs(200)).await?;
        let mut data = body.get("data").cloned().unwrap_or(body);
        normalize_source_urls(&mut data, &self.host);
        serde_json::from_value(data).context("The server returned an invalid source response.")
    }

    pub async fn skip_times(
        &self,
        id: &str,
        episode: u32,
        duration: f64,
        server: &str,
        category: &str,
    ) -> Result<Value> {
        let mut url =
            Url::parse(&self.endpoint(&format!("/anime/skip/{}/{episode}", encode_segment(id))))?;
        url.query_pairs_mut()
            .append_pair("duration", &format!("{duration:.2}"))
            .append_pair("server", server)
            .append_pair("category", category);
        self.get_json(url.into(), Duration::from_secs(30)).await
    }

    pub async fn report(
        &self,
        id: &str,
        episode: u32,
        category: &str,
        stream_url: &str,
        reason: &str,
    ) -> Result<bool> {
        let response = self.client.post(self.endpoint("/report"))
            .json(&json!({"episode_id":format!("{id}/{episode}"),"category":category,"url":stream_url,"reason":reason}))
            .timeout(Duration::from_secs(15)).send().await?;
        Ok(response.status().is_success())
    }

    pub async fn tracking_config(&self) -> Result<Value> {
        self.catalog("/tracking/config").await
    }

    /// Which tracking services this account has connected: {anilist: {connected, account}, mal: {...}}.
    pub async fn tracking_status(&self, token: &str) -> Result<Value> {
        self.account_request(Method::GET, "/tracking", Some(token), None).await
    }

    pub async fn tracking_disconnect(&self, token: &str, service: &str) -> Result<()> {
        let service = if service == "mal" { "mal" } else { "anilist" };
        self.account_request(Method::DELETE, &format!("/tracking/{service}"), Some(token), None).await.map(|_| ())
    }

    /// The MyAnimeList sign-in page to open.
    pub async fn mal_start(&self, token: &str) -> Result<String> {
        let body = self.account_request(Method::POST, "/tracking/mal/start", Some(token), None).await?;
        body.get("url").and_then(Value::as_str).map(str::to_owned).context("The server did not start the MyAnimeList sign-in.")
    }

    /// Connect AniList with the token its page showed.
    pub async fn anilist_connect(&self, token: &str, anilist_token: &str) -> Result<()> {
        self.account_request(Method::POST, "/tracking/anilist", Some(token), Some(json!({"token": anilist_token}))).await.map(|_| ())
    }

    pub fn resolve_url(&self, value: &str) -> String {
        resolve_url(&self.host, value)
    }

    pub async fn auth_config(&self) -> Result<AuthConfig> {
        serde_json::from_value(
            self.account_request(Method::GET, "/auth/config", None, None)
                .await?,
        )
        .context("The server returned invalid account configuration.")
    }

    pub async fn register(
        &self,
        username: &str,
        password: &str,
        display_name: Option<&str>,
    ) -> Result<AuthSession> {
        self.authenticate(
            "/auth/register",
            json!({"username":username.trim(),"password":password,"display_name":display_name}),
        )
        .await
    }

    pub async fn login(&self, username: &str, password: &str) -> Result<AuthSession> {
        self.authenticate(
            "/auth/login",
            json!({"username":username.trim(),"password":password}),
        )
        .await
    }

    pub async fn google_login(&self, id_token: &str) -> Result<AuthSession> {
        self.authenticate("/auth/google", json!({"id_token":id_token}))
            .await
    }

    async fn authenticate(&self, path: &str, body: Value) -> Result<AuthSession> {
        let session: AuthSession = serde_json::from_value(
            self.account_request(Method::POST, path, None, Some(body))
                .await?,
        )
        .context("The server sent an incomplete account reply. Please try again.")?;
        if session.token.is_empty() || session.user.id <= 0 {
            bail!("The server sent an incomplete account reply. Please try again.");
        }
        Ok(session)
    }

    pub async fn me(&self, token: &str) -> Result<AuthUser> {
        let body = self
            .account_request(Method::GET, "/auth/me", Some(token), None)
            .await?;
        serde_json::from_value(body.get("user").cloned().unwrap_or_default())
            .context("The server returned an invalid account profile.")
    }

    pub async fn logout(&self, token: &str) -> Result<()> {
        self.account_request(Method::POST, "/auth/logout", Some(token), None)
            .await?;
        Ok(())
    }

    pub async fn sync_history(
        &self,
        token: &str,
        entries: &[HistoryEntry],
    ) -> Result<Vec<HistoryEntry>> {
        let pending: Vec<Value> = entries
            .iter()
            .filter(|entry| entry.dirty)
            .map(|entry| {
                let mut value = serde_json::to_value(entry).expect("HistoryEntry serialization");
                value.as_object_mut().unwrap().remove("dirty");
                value
            })
            .collect();
        let mut body;
        if pending.is_empty() {
            body = self
                .account_request(Method::GET, "/history", Some(token), None)
                .await?;
        } else {
            body = Value::Null;
            for chunk in pending.chunks(200) {
                body = self
                    .account_request(
                        Method::PUT,
                        "/history",
                        Some(token),
                        Some(json!({"entries":chunk})),
                    )
                    .await?;
            }
        }
        parse_array(body.get("entries").cloned().unwrap_or_default())
    }

    pub async fn sync_watchlist(
        &self,
        token: &str,
        entries: &[WatchEntry],
    ) -> Result<Vec<WatchEntry>> {
        let mut body;
        if entries.is_empty() {
            body = self
                .account_request(Method::GET, "/watchlist", Some(token), None)
                .await?;
        } else {
            body = Value::Null;
            for chunk in entries.chunks(200) {
                body = self
                    .account_request(
                        Method::PUT,
                        "/watchlist",
                        Some(token),
                        Some(json!({"entries":chunk})),
                    )
                    .await?;
            }
        }
        parse_array(body.get("entries").cloned().unwrap_or_default())
    }

    async fn account_request(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<Value>,
    ) -> Result<Value> {
        let mut request = self
            .client
            .request(method, self.endpoint(path))
            .timeout(Duration::from_secs(30));
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        if let Some(body) = body {
            request = request.json(&body);
        }
        decode_response(
            request
                .send()
                .await
                .context("Can't reach the AniVerse server. Check your connection and try again.")?,
            true,
        )
        .await
    }
}

async fn decode_response(response: Response, account: bool) -> Result<Value> {
    let status = response.status();
    let body: Value = response.json().await.unwrap_or(Value::Null);
    if !status.is_success() {
        let detail = body.get("detail").and_then(|detail| match detail {
            Value::String(value) => Some(value.clone()),
            Value::Array(items) => items.first()?.get("msg")?.as_str().map(str::to_owned),
            _ => None,
        });
        let message = if account && [404, 405].contains(&status.as_u16()) {
            "Account services are unavailable on this server. Please try again later.".to_owned()
        } else if status.is_server_error() {
            "The AniVerse server is temporarily unavailable. Please try again later.".to_owned()
        } else {
            detail.unwrap_or_else(|| format!("The server returned HTTP {}.", status.as_u16()))
        };
        return Err(ApiError {
            status: status.as_u16(),
            message,
        }
        .into());
    }
    if body.is_null() {
        bail!("The server sent an unexpected reply. Please try again.");
    }
    Ok(body)
}

fn parse_list(value: Value) -> Vec<Anime> {
    value
        .as_array()
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|value| serde_json::from_value::<Anime>(value).ok())
        .filter(|anime| !anime.id_string().is_empty())
        .collect()
}

fn parse_array<T: DeserializeOwned>(value: Value) -> Result<Vec<T>> {
    serde_json::from_value(value).context("The server returned an invalid list.")
}

fn parse_schedule(value: Value) -> Result<Vec<Anime>> {
    let rows = value
        .as_array()
        .context("The server returned an invalid schedule.")?;
    let mut anime = Vec::new();
    for row in rows {
        let Some(media) = row.get("media") else {
            continue;
        };
        let Ok(mut card) = serde_json::from_value::<Anime>(media.clone()) else {
            continue;
        };
        if card.id_string().is_empty() {
            continue;
        }
        card.extra.insert(
            "airingAt".into(),
            row.get("airingAt").cloned().unwrap_or_default(),
        );
        card.extra.insert(
            "airingEpisode".into(),
            row.get("episode").cloned().unwrap_or_default(),
        );
        anime.push(card);
    }
    anime.sort_by_key(|card| {
        card.extra
            .get("airingAt")
            .and_then(Value::as_i64)
            .unwrap_or_default()
    });
    Ok(anime)
}

fn encode_segment(value: &str) -> String {
    let mut url = Url::parse("https://example.invalid/").expect("constant URL");
    url.path_segments_mut().expect("base URL").push(value);
    url.path().trim_start_matches('/').to_owned()
}

/// A web origin, never an API URL with credentials/query strings attached.
pub fn clean_host(value: &str) -> String {
    let value = value.trim().trim_end_matches('/');
    if value.is_empty() {
        return String::new();
    }
    if value.contains("://") && !value.starts_with("http://") && !value.starts_with("https://") {
        return String::new();
    }
    let candidate = if value.starts_with("http://") || value.starts_with("https://") {
        value.to_owned()
    } else {
        format!("https://{value}")
    };
    let Ok(mut url) = Url::parse(&candidate) else {
        return String::new();
    };
    if !["https", "http"].contains(&url.scheme())
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return String::new();
    }
    url.set_query(None);
    url.set_fragment(None);
    url.set_path("");
    url.as_str().trim_end_matches('/').to_owned()
}

async fn reachable(client: &Client, host: &str) -> bool {
    client
        .get(format!("{host}/app/version.json"))
        .timeout(Duration::from_secs(5))
        .send()
        .await
        .map(|r| r.status().is_success())
        .unwrap_or(false)
}

async fn discover(client: &Client, url: &str) -> Option<String> {
    let response = client
        .get(url)
        .timeout(Duration::from_secs(6))
        .send()
        .await
        .ok()?;
    if !response.status().is_success() {
        return None;
    }
    let value: Value = response.json().await.ok()?;
    let host = clean_host(value.get("host")?.as_str()?);
    (!host.is_empty()).then_some(host)
}

fn resolve_url(host: &str, value: &str) -> String {
    if value.trim().is_empty() {
        return String::new();
    }
    Url::parse(host)
        .and_then(|base| base.join(value))
        .map(|url| url.to_string())
        .unwrap_or_else(|_| value.to_owned())
}

fn normalize_source_urls(data: &mut Value, host: &str) {
    if let Some(sources) = data.get_mut("sources").and_then(Value::as_array_mut) {
        for source in sources {
            normalize_one(source, host);
        }
    }
    if let Some(subtitles) = data.get_mut("subtitles").and_then(Value::as_array_mut) {
        for subtitle in subtitles {
            normalize_one(subtitle, host);
        }
    }
}

fn normalize_one(value: &mut Value, host: &str) {
    let Some(map) = value.as_object_mut() else {
        return;
    };
    if let Some(url) = map.get_mut("url") {
        if let Some(raw) = url.as_str() {
            *url = Value::String(resolve_url(host, raw));
        }
    }
    if let Some(subtitles) = map.get_mut("subtitles").and_then(Value::as_array_mut) {
        for subtitle in subtitles {
            normalize_one(subtitle, host);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origin_and_path_encoding_match_flutter_contract() {
        let api = AniVerseApi::new(" https://example.test:8443/api/ ").unwrap();
        assert_eq!(api.base_url(), "https://example.test:8443/api");
        assert_eq!(
            api.endpoint("/anime/popular"),
            "https://example.test:8443/api/anime/popular"
        );
        assert_eq!(
            encode_segment("Slice of Life/a?b"),
            "Slice%20of%20Life%2Fa%3Fb"
        );
        assert_eq!(clean_host("localhost:8000"), "https://localhost:8000");
        assert_eq!(clean_host("https://user:secret@example.test"), "");
        assert_eq!(clean_host("ftp://example.test"), "");
    }

    #[test]
    fn source_and_all_subtitle_urls_are_resolved_without_changing_external_hosts() {
        let mut value = json!({"sources":[{"url":"/proxy/stream?x=1","subtitles":[{"url":"/proxy/sub.vtt"}]}],"subtitles":[{"url":"https://cdn.test/sub.vtt"},{"url":"//cdn.test/other.vtt"}]});
        normalize_source_urls(&mut value, "https://anime.test");
        assert_eq!(
            value["sources"][0]["url"],
            "https://anime.test/proxy/stream?x=1"
        );
        assert_eq!(
            value["sources"][0]["subtitles"][0]["url"],
            "https://anime.test/proxy/sub.vtt"
        );
        assert_eq!(value["subtitles"][0]["url"], "https://cdn.test/sub.vtt");
        assert_eq!(value["subtitles"][1]["url"], "https://cdn.test/other.vtt");
    }

    #[test]
    fn schedule_unwraps_media_and_preserves_time_and_episode() {
        let cards = parse_schedule(json!([
            {"airingAt":200,"episode":3,"media":{"id":2,"title":{"english":"Second"}}},
            {"airingAt":100,"episode":5,"media":{"id":1,"title":"First"}}
        ]))
        .unwrap();
        assert_eq!(cards[0].title_text(), "First");
        assert_eq!(cards[0].extra["airingEpisode"], 5);
        assert_eq!(cards[1].extra["airingAt"], 200);
    }

    #[tokio::test]
    async fn missing_account_route_is_not_reported_as_missing_user() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            let mut request = [0_u8; 4096];
            let count = socket.read(&mut request).unwrap();
            assert!(String::from_utf8_lossy(&request[..count]).starts_with("POST /api/auth/login "));
            let body = r#"{"detail":"Not Found"}"#;
            write!(socket,"HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
        });
        let api = AniVerseApi::new(&format!("http://{address}")).unwrap();
        let error = api
            .login("test-user", "not-a-real-password")
            .await
            .unwrap_err();
        assert_eq!(error.downcast_ref::<ApiError>().unwrap().status, 404);
        assert!(error
            .to_string()
            .contains("Account services are unavailable"));
        server.join().unwrap();
    }
}
