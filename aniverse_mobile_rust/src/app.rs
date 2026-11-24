//! The UI-thread controller. It fills the Slint globals (ui/store.slint) from
//! the server, the device's storage and the player, and answers the screens'
//! Actions, the way lib/ui_manga's screens and lib/services do in Flutter.
//! Network, image decoding and downloads run on Tokio; their results come
//! back over a channel drained by a 50 ms timer, so nothing blocks a frame.
use crate::{
    achievements,
    api::{AniVerseApi, GENRES},
    downloads,
    models::{self, Anime, AuthConfig, AuthSession, AuthUser, DownloadItem, HistoryEntry, HomeData, SourceResponse, WatchEntry},
    player::{self, HostEvent, PlaybackEvent, PlaybackRequest},
    settings::Settings,
    storage::{self, LocalData},
    textures::{self, Axis, Tone, INK, TONE},
    theme::ThemeId,
};
use chrono::{Datelike, Local, TimeZone, Timelike};
use serde_json::Value;
use slint::{Color, ComponentHandle, Image, Model, ModelRc, Rgba8Pixel, SharedPixelBuffer, SharedString, VecModel};
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet, VecDeque},
    rc::Rc,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    time::{Duration, Instant},
};
use tokio::{runtime::Runtime, sync::Semaphore};

mod ui {
    slint::include_modules!();
}
use ui::{Actions, Airing, Badge, ChipRow, Choice, Day, Filter, Followed, GenreTile, Icons, Lines, MainWindow, Person, Prefs, Resume, Saved, Shelf, Slide, Store, Tex};
type Card = ui::Anime;
type EpisodeRow = ui::Episode;

type Outcome<T> = Result<T, String>;

// --- events from background work ---------------------------------------------------------------

enum Event {
    Connected(Outcome<AniVerseApi>),
    Home(Outcome<HomeData>),
    Because(String, String, Vec<Anime>),
    Info(String, Outcome<Anime>),
    Episodes(String, Vec<models::Episode>),
    Extra(String, Value),
    Tagalog(String, Option<Value>),
    Search(u64, Outcome<Vec<Anime>>),
    Filter(u64, bool, Outcome<Value>),
    Schedule(Outcome<Vec<Anime>>),
    GenreArt(Value),
    Genre(u64, u32, Outcome<Vec<Anime>>),
    Art(String, Option<SharedPixelBuffer<Rgba8Pixel>>),
    AuthConfig(Outcome<AuthConfig>),
    Auth(Outcome<AuthSession>),
    Me(Outcome<AuthUser>, bool),
    Synced(String, Outcome<Vec<HistoryEntry>>, Outcome<Vec<WatchEntry>>),
    Tracking(Value, Value),
    Toast(String),
    Sources(u64, Play, Outcome<SourceResponse>),
    Download(String, u64, f32, Option<Outcome<String>>),
}

#[derive(Clone, Debug, PartialEq)]
enum Page {
    Detail(String),
    Settings,
    Account,
    History,
    Genres,
    Genre(String),
    Player,
}
impl Page {
    fn name(&self) -> &'static str {
        match self {
            Page::Detail(_) => "detail",
            Page::Settings => "settings",
            Page::Account => "account",
            Page::History => "history",
            Page::Genres => "genres",
            Page::Genre(_) => "genre",
            Page::Player => "player",
        }
    }
}

/// An episode to open in the player.
#[derive(Clone, Debug, Default)]
struct Play {
    anime_id: String,
    episode: u32,
    category: String,
    title: String,
    cover: String,
    local: Option<String>,
}

#[derive(Clone, Default)]
struct DetailData {
    anime: Option<Anime>,
    episodes: HashMap<u32, models::Episode>,
    extra: Value,
    tagalog: Option<Value>,
    error: Option<String>,
}

enum SheetFor {
    Pref(String),
    Filter(String),
}
enum DialogFor {
    Server,
    SignOut,
    ClearHistory,
    AniList,
}
enum ToastAction {
    RefreshTracking,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Art {
    Cover,
    Banner,
    Slant,
}

struct ArtCache {
    images: HashMap<String, Image>,
    order: VecDeque<String>,
    asked: HashSet<String>,
    failed: HashSet<String>,
    scale: f32,
}

struct State {
    settings: Settings,
    local: LocalData,
    api: Option<AniVerseApi>,
    epoch: u64,
    connecting: bool,
    // home
    home: Option<HomeData>,
    home_failed: bool,
    because: Vec<(String, String, Vec<Anime>)>,
    because_asked: Vec<String>,
    // pages over the tabs
    stack: Vec<Page>,
    closing: bool,
    // the anime page
    details: HashMap<String, DetailData>,
    detail_id: String,
    window: (usize, usize),
    // search
    search_text: String,
    filters: HashMap<String, String>,
    results: Vec<Anime>,
    search_page: u32,
    search_more: bool,
    search_request: u64,
    debounce: Option<Instant>,
    // airing
    schedule: Option<Vec<Anime>>,
    schedule_loading: bool,
    day: String,
    // genres
    genre_art: Option<Value>,
    genre_art_loading: bool,
    genre_name: String,
    genre_items: Vec<Anime>,
    genre_seen: HashSet<String>,
    genre_page: u32,
    genre_loading: bool,
    genre_end: bool,
    genre_request: u64,
    // my list: episodes out per followed show, as last fetched
    aired: HashMap<String, u32>,
    releasing: HashSet<String>,
    info_asked: HashSet<String>,
    // account
    auth_config: Option<AuthConfig>,
    tracking: (Value, Value),
    // overlays
    sheet: Option<SheetFor>,
    dialog: Option<DialogFor>,
    toast_until: Option<Instant>,
    toast_action: Option<ToastAction>,
    // the player
    play_request: u64,
    playing: Option<Play>,
    last_position: u64,
    // downloads in flight
    cancels: HashMap<String, Arc<AtomicBool>>,
    // saving and syncing
    sync_busy: bool,
    history_syncing: bool,
    last_sync: Instant,
    dirty: bool,
    last_save: Instant,
    textures_key: (u32, u32, u32, u32),
    tone_scale: u32,
}

struct Models {
    resume: Rc<VecModel<Resume>>,
    slides: Rc<VecModel<Slide>>,
    shelves: Rc<VecModel<Shelf>>,
    shelf_items: RefCell<Vec<Rc<VecModel<Card>>>>,
    detail_genres: Rc<VecModel<SharedString>>,
    detail_facts: Rc<VecModel<ChipRow>>,
    episodes: Rc<VecModel<EpisodeRow>>,
    characters: Rc<VecModel<Person>>,
    related: Rc<VecModel<Card>>,
    recommended: Rc<VecModel<Card>>,
    results: Rc<VecModel<Card>>,
    filters: Rc<VecModel<Filter>>,
    recent: Rc<VecModel<ChipRow>>,
    days: Rc<VecModel<Day>>,
    airing: Rc<VecModel<Airing>>,
    followed: Rc<VecModel<Followed>>,
    saved: Rc<VecModel<Saved>>,
    genres: Rc<VecModel<GenreTile>>,
    genre_items: Rc<VecModel<Card>>,
    history: Rc<VecModel<Resume>>,
    badges: Rc<VecModel<Badge>>,
    sheet: Rc<VecModel<Choice>>,
}

#[derive(Clone)]
struct App {
    ui: slint::Weak<MainWindow>,
    state: Rc<RefCell<State>>,
    art: Rc<RefCell<ArtCache>>,
    models: Rc<Models>,
    runtime: Arc<Runtime>,
    tx: mpsc::Sender<(u64, Event)>,
    slots: Arc<Semaphore>,
}

// --- small helpers -----------------------------------------------------------------------------

fn ss(v: impl AsRef<str>) -> SharedString {
    SharedString::from(v.as_ref())
}

fn rows<T: Clone + 'static>(model: &VecModel<T>, items: Vec<T>) {
    model.set_vec(items);
}

/// Change the rows [f] says it changed.
fn patch<T: Clone + 'static>(model: &VecModel<T>, mut f: impl FnMut(&mut T) -> bool) {
    for i in 0..model.row_count() {
        if let Some(mut row) = model.row_data(i) {
            if f(&mut row) {
                model.set_row_data(i, row);
            }
        }
    }
}

/// "5m ago", "3h ago", "2d ago", or a date for anything older.
fn time_ago(millis: i64) -> String {
    let secs = ((chrono::Utc::now().timestamp_millis() - millis) / 1000).max(0);
    if secs < 60 {
        return "just now".into();
    }
    if secs < 3600 {
        return format!("{}m ago", secs / 60);
    }
    if secs < 86_400 {
        return format!("{}h ago", secs / 3600);
    }
    if secs < 7 * 86_400 {
        return format!("{}d ago", secs / 86_400);
    }
    Local.timestamp_millis_opt(millis).single().map(|t| t.format("%b %-d").to_string()).unwrap_or_default()
}

/// 4:05, or 1:02:03 past an hour.
fn clock(ms: u64) -> String {
    let s = ms / 1000;
    let (h, m, sec) = (s / 3600, (s % 3600) / 60, s % 60);
    if h > 0 {
        format!("{h}:{m:02}:{sec:02}")
    } else {
        format!("{m}:{sec:02}")
    }
}

fn countdown(secs: i64) -> String {
    if secs <= 0 {
        return "OUT NOW".into();
    }
    let (d, h, m) = (secs / 86_400, (secs % 86_400) / 3600, (secs % 3600) / 60);
    if d > 0 {
        format!("IN {d}D {h}H")
    } else if h > 0 {
        format!("IN {h}H {m}M")
    } else {
        format!("IN {m}M")
    }
}

fn day_key(t: i64) -> String {
    Local.timestamp_opt(t, 0).single().map(|d| d.format("%Y-%m-%d").to_string()).unwrap_or_default()
}

/// Chips laid out in rows (Flutter's Wrap), by an estimate of each one's width.
fn wrap_chips(items: &[String], max_width: f32, per_char: f32, padding: f32, gap: f32) -> Vec<Vec<String>> {
    let mut out: Vec<Vec<String>> = Vec::new();
    let mut width = 0.0;
    for item in items {
        let w = padding + per_char * item.chars().count() as f32;
        if out.is_empty() || (width + gap + w > max_width && !out.last().unwrap().is_empty()) {
            out.push(Vec::new());
            width = 0.0;
        } else {
            width += gap;
        }
        width += w;
        out.last_mut().unwrap().push(item.clone());
    }
    out
}

fn chip_rows(rows: Vec<Vec<String>>) -> Vec<ChipRow> {
    rows.into_iter()
        .map(|r| ChipRow { items: ModelRc::new(VecModel::from(r.into_iter().map(SharedString::from).collect::<Vec<_>>())) })
        .collect()
}

fn icon(name: &str, icons: &Icons) -> SharedString {
    match name {
        "blood-drop" => icons.get_blood_drop(),
        "skull-small" => icons.get_skull_small(),
        "skull" => icons.get_skull(),
        "grid" => icons.get_grid(),
        "play" => icons.get_play(),
        "check" => icons.get_check(),
        "star" => icons.get_star(),
        "clock" => icons.get_clock(),
        "sword" => icons.get_sword(),
        "bookmark" => icons.get_bookmark(),
        "bell" => icons.get_bell(),
        "trophy" => icons.get_trophy(),
        _ => icons.get_star(),
    }
}

fn str_of(v: &Value, key: &str) -> String {
    v.get(key).map(models::value_text).unwrap_or_default()
}

fn title_of(v: &Value) -> String {
    if let Some(Value::Object(t)) = v.get("title") {
        for k in ["english", "romaji"] {
            if let Some(s) = t.get(k).and_then(Value::as_str).filter(|s| !s.is_empty()) {
                return s.to_owned();
            }
        }
    }
    match v.get("title").or_else(|| v.get("name")) {
        Some(Value::String(s)) if !s.is_empty() => s.clone(),
        _ => "Untitled".into(),
    }
}

const RELATIONS: [(&str, &str); 12] = [
    ("PREQUEL", "Prequel"), ("SEQUEL", "Sequel"), ("SIDE_STORY", "Side story"), ("SPIN_OFF", "Spin-off"),
    ("ALTERNATIVE", "Alternative"), ("PARENT", "Main story"), ("SUMMARY", "Summary"), ("COMPILATION", "Compilation"),
    ("CHARACTER", "Shared cast"), ("OTHER", "Related"), ("CONTAINS", "Contains"), ("SOURCE", "Source"),
];

const LANGS: [&str; 10] = ["", "English", "Spanish", "Portuguese", "French", "German", "Italian", "Arabic", "Russian", "Indonesian"];

fn filter_defs() -> Vec<(&'static str, &'static str, Vec<(String, String)>)> {
    let year = Local::now().year();
    let pairs = |v: &[(&str, &str)]| v.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect::<Vec<_>>();
    let mut genres = vec![(String::new(), "Any genre".to_string())];
    genres.extend(GENRES.iter().map(|g| (g.to_string(), g.to_string())));
    let mut years = vec![(String::new(), "Any year".to_string())];
    years.extend((1970..=year + 1).rev().map(|y| (y.to_string(), y.to_string())));
    vec![
        ("genres", "Genre", genres),
        ("year", "Year", years),
        ("season", "Season", pairs(&[("", "Any season"), ("WINTER", "Winter"), ("SPRING", "Spring"), ("SUMMER", "Summer"), ("FALL", "Fall")])),
        ("format", "Format", pairs(&[("", "Any format"), ("TV", "TV"), ("MOVIE", "Movie"), ("OVA", "OVA"), ("ONA", "ONA"), ("SPECIAL", "Special"), ("TV_SHORT", "TV short")])),
        ("status", "Status", pairs(&[("", "Any status"), ("RELEASING", "Airing"), ("FINISHED", "Finished"), ("NOT_YET_RELEASED", "Upcoming")])),
        ("min_score", "Score", pairs(&[("", "Any score"), ("60", "60+"), ("70", "70+"), ("80", "80+"), ("90", "90+")])),
        ("sort", "Sort", pairs(&[("", "Best match"), ("POPULARITY_DESC", "Popular"), ("SCORE_DESC", "Top rated"), ("TRENDING_DESC", "Trending"), ("START_DATE_DESC", "Newest")])),
    ]
}

/// Each setting's choices: (value, label).
fn pref_options(key: &str) -> Option<(&'static str, Vec<(String, String)>)> {
    let pairs = |v: &[(&str, &str)]| v.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect::<Vec<_>>();
    Some(match key {
        "look" => ("App look", pairs(&[("manga", "Manga"), ("pixel", "Pixel art")])),
        "theme" => ("Palette", ThemeId::ALL.iter().map(|t| (t.id().to_string(), t.name().to_string())).collect()),
        "effects" => ("Effects", pairs(&[("full", "Full"), ("lite", "Lite"), ("off", "Off")])),
        "volume" => ("Effects volume", pairs(&[("0.15", "Quiet"), ("0.35", "Normal"), ("0.7", "Loud")])),
        "seekStep" => ("Skip length", pairs(&[("5", "5 seconds"), ("10", "10 seconds"), ("15", "15 seconds"), ("30", "30 seconds")])),
        "subColor" => ("Subtitle colour", pairs(&[("white", "White"), ("yellow", "Yellow"), ("cyan", "Cyan"), ("green", "Green")])),
        "subSize" => ("Subtitle size", pairs(&[("s", "Small"), ("m", "Medium"), ("l", "Large"), ("xl", "Extra large")])),
        "subLang" => ("Subtitle language", LANGS.iter().map(|l| (l.to_string(), if l.is_empty() { "Source default".into() } else { l.to_string() })).collect()),
        "downloadLimitGb" => ("Storage limit", pairs(&[("0", "No limit"), ("2", "2 GB"), ("5", "5 GB"), ("10", "10 GB"), ("20", "20 GB")])),
        "quietFrom" => ("Quiet hours", pairs(&[("-1", "Off"), ("22", "22:00 - 08:00"), ("23", "23:00 - 08:00"), ("0", "00:00 - 08:00")])),
        "textScale" => ("Text size", pairs(&[("1", "Normal"), ("1.15", "Large"), ("1.3", "Largest")])),
        _ => return None,
    })
}

fn label_of(options: &[(String, String)], value: &str, fallback: usize) -> String {
    options
        .iter()
        .find(|(v, _)| v == value)
        .or_else(|| options.get(fallback))
        .map(|(_, l)| l.to_uppercase())
        .unwrap_or_default()
}

fn num(v: f32) -> String {
    let s = format!("{v:.2}");
    s.trim_end_matches('0').trim_end_matches('.').to_owned()
}

fn bytes_text(bytes: u64) -> String {
    let b = bytes as f64;
    if b >= (1u64 << 30) as f64 {
        format!("{:.1} GB", b / (1u64 << 30) as f64)
    } else if b >= (1u64 << 20) as f64 {
        format!("{:.0} MB", b / (1u64 << 20) as f64)
    } else {
        format!("{:.0} KB", b / 1024.0)
    }
}

// --- the app -----------------------------------------------------------------------------------

impl App {
    fn task(&self, f: impl std::future::Future<Output = Event> + Send + 'static) {
        let tx = self.tx.clone();
        let epoch = self.state.borrow().epoch;
        self.runtime.spawn(async move {
            let _ = tx.send((epoch, f.await));
        });
    }

    fn api(&self) -> Option<AniVerseApi> {
        self.state.borrow().api.clone()
    }

    fn sfx(&self, name: &str) {
        let (on, volume) = {
            let s = self.state.borrow();
            (s.settings.sfx, s.settings.volume)
        };
        if on {
            player::sfx(name, volume);
        }
    }

    /// mangaToast: a speech bubble at the foot of the screen for four seconds.
    fn toast(&self, text: impl Into<String>) {
        self.toast_with(text, None, "");
    }
    fn toast_with(&self, text: impl Into<String>, action: Option<ToastAction>, label: &str) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        store.set_toast_visible(false);
        store.set_toast_text(ss(text.into()));
        store.set_toast_action(ss(label));
        {
            let mut s = self.state.borrow_mut();
            s.toast_action = action;
            s.toast_until = Some(Instant::now() + Duration::from_secs(4));
        }
        // shown on the next tick, so the bubble pops again
        let weak = self.ui.clone();
        slint::Timer::single_shot(Duration::from_millis(30), move || {
            if let Some(ui) = weak.upgrade() {
                ui.global::<Store>().set_toast_visible(true);
            }
        });
        self.sfx("pop");
    }

    fn save_local(&self) {
        let result = self.state.borrow().local.save();
        if let Err(e) = result {
            self.toast(format!("Could not save your library: {e}"));
        }
        self.state.borrow_mut().last_save = Instant::now();
    }

    fn save_settings(&self) {
        let result = self.state.borrow().settings.save();
        if let Err(e) = result {
            self.toast(format!("Settings could not be saved: {e}"));
        }
    }

    // --- images ---------------------------------------------------------------------------------

    fn art_key(url: &str, kind: Art) -> String {
        match kind {
            Art::Cover => url.to_owned(),
            Art::Banner => format!("wide:{url}"),
            Art::Slant => format!("slant:{url}"),
        }
    }

    fn art_failed(&self, url: &str, kind: Art) -> bool {
        self.art.borrow().failed.contains(&Self::art_key(url, kind))
    }

    /// The picture at [url], if it is here; otherwise it is fetched and the
    /// rows showing it are filled in when it arrives.
    fn art(&self, url: &str, kind: Art) -> Image {
        if !(url.starts_with("https://") || url.starts_with("http://")) {
            return Image::default();
        }
        let key = Self::art_key(url, kind);
        let scale = {
            let mut cache = self.art.borrow_mut();
            if let Some(image) = cache.images.get(&key) {
                return image.clone();
            }
            if cache.failed.contains(&key) || !cache.asked.insert(key.clone()) {
                return Image::default();
            }
            cache.scale
        };
        let (tx, slots, url) = (self.tx.clone(), self.slots.clone(), url.to_owned());
        self.runtime.spawn(async move {
            let _permit = slots.acquire_owned().await;
            let image = load_art(&url, kind, scale).await;
            let _ = tx.send((0, Event::Art(key, image)));
        });
        Image::default()
    }

    fn arrived(&self, key: String, buffer: Option<SharedPixelBuffer<Rgba8Pixel>>) {
        let Some(buffer) = buffer else {
            self.art.borrow_mut().failed.insert(key.clone());
            self.fill_art(&key, None);
            return;
        };
        let image = Image::from_rgba8(buffer);
        {
            let mut cache = self.art.borrow_mut();
            cache.images.insert(key.clone(), image.clone());
            cache.order.push_back(key.clone());
            // Rows keep their own copies; the cache only saves refetching.
            while cache.order.len() > 600 {
                if let Some(old) = cache.order.pop_front() {
                    cache.images.remove(&old);
                    cache.asked.remove(&old);
                }
            }
        }
        self.fill_art(&key, Some(image));
    }

    /// Put an arrived picture into every row showing it ([None]: it failed,
    /// and those rows show the "no art" panel instead).
    fn fill_art(&self, key: &str, image: Option<Image>) {
        let m = &self.models;
        let (url, kind) = if let Some(u) = key.strip_prefix("slant:") {
            (u, Art::Slant)
        } else if let Some(u) = key.strip_prefix("wide:") {
            (u, Art::Banner)
        } else {
            (key, Art::Cover)
        };
        let img = image.clone().unwrap_or_default();
        let hit = |cover_url: &mut SharedString, cover: &mut Image| -> bool {
            if cover_url.as_str() != url {
                return false;
            }
            if image.is_some() {
                *cover = img.clone();
            } else {
                *cover_url = SharedString::default();
            }
            true
        };
        match kind {
            Art::Slant => patch(&m.slides, |r| {
                if r.cover_url.as_str() != url {
                    return false;
                }
                r.cover = img.clone();
                true
            }),
            Art::Banner => {
                if let Some(ui) = self.ui.upgrade() {
                    let store = ui.global::<Store>();
                    if store.get_detail_banner_url().as_str() == url {
                        match &image {
                            Some(i) => store.set_detail_banner(i.clone()),
                            None => store.set_detail_banner_url(SharedString::default()),
                        }
                    }
                }
                patch(&m.genres, |r| {
                    if r.art_url.as_str() != url {
                        return false;
                    }
                    match &image {
                        Some(i) => r.art = i.clone(),
                        None => r.art_url = SharedString::default(),
                    }
                    true
                });
            }
            Art::Cover => {
                patch(&m.resume, |r| hit(&mut r.cover_url, &mut r.cover));
                patch(&m.history, |r| hit(&mut r.cover_url, &mut r.cover));
                for shelf in m.shelf_items.borrow().iter() {
                    patch(shelf, |r| hit(&mut r.cover_url, &mut r.cover));
                }
                for model in [&m.related, &m.recommended, &m.results, &m.genre_items] {
                    patch(model, |r| hit(&mut r.cover_url, &mut r.cover));
                }
                patch(&m.episodes, |r| hit(&mut r.image_url, &mut r.image));
                patch(&m.characters, |r| hit(&mut r.image_url, &mut r.image));
                patch(&m.airing, |r| hit(&mut r.cover_url, &mut r.cover));
                patch(&m.followed, |r| hit(&mut r.cover_url, &mut r.cover));
                patch(&m.saved, |r| hit(&mut r.cover_url, &mut r.cover));
                if let Some(ui) = self.ui.upgrade() {
                    let store = ui.global::<Store>();
                    if store.get_detail_cover_url().as_str() == url {
                        match &image {
                            Some(i) => store.set_detail_cover(i.clone()),
                            None => store.set_detail_cover_url(SharedString::default()),
                        }
                    }
                    if store.get_trailer_thumb_url().as_str() == url {
                        match &image {
                            Some(i) => store.set_trailer_thumb(i.clone()),
                            None => store.set_trailer_thumb_url(SharedString::default()),
                        }
                    }
                    if store.get_user_avatar_url().as_str() == url {
                        match &image {
                            Some(i) => store.set_user_avatar(i.clone()),
                            None => store.set_user_avatar_url(SharedString::default()),
                        }
                    }
                }
            }
        }
    }

    fn card(&self, a: &Anime) -> Card {
        let url = a.poster_url();
        Card {
            id: ss(a.id_string()),
            title: ss(a.title_text()),
            cover: self.art(&url, Art::Cover),
            cover_url: if self.art_failed(&url, Art::Cover) { SharedString::default() } else { ss(&url) },
            score: ss(a.score_number()),
            meta: ss(a.list_meta()),
            chip: SharedString::default(),
        }
    }

    /// A card from loose JSON (recommendations, relations).
    fn card_from(&self, v: &Value) -> Card {
        match serde_json::from_value::<Anime>(v.clone()) {
            Ok(a) => self.card(&a),
            Err(_) => Card { id: ss(str_of(v, "id")), title: ss(title_of(v)), ..Default::default() },
        }
    }

    fn cover_row(&self, url: &str) -> (Image, SharedString) {
        let image = self.art(url, Art::Cover);
        let url = if self.art_failed(url, Art::Cover) { "" } else { url };
        (image, ss(url))
    }

    // --- connecting -----------------------------------------------------------------------------

    fn connect(&self) {
        let mut settings = {
            let mut s = self.state.borrow_mut();
            if s.connecting {
                return;
            }
            s.connecting = true;
            s.settings.clone()
        };
        self.task(async move { Event::Connected(AniVerseApi::load(&mut settings).await.map_err(|e| e.to_string())) });
    }

    fn connected(&self, result: Outcome<AniVerseApi>) {
        self.state.borrow_mut().connecting = false;
        let api = match result {
            Ok(api) => api,
            Err(e) => {
                self.state.borrow_mut().home_failed = true;
                self.render_home();
                self.toast(e);
                return;
            }
        };
        let session = {
            let mut s = self.state.borrow_mut();
            s.settings.host = api.host().to_owned();
            s.api = Some(api.clone());
            s.local.session.clone()
        };
        self.save_settings();
        self.render_prefs();
        self.load_home();
        if let Some(session) = session {
            self.task(async move {
                let result = api.me(&session.token).await;
                let expired = result
                    .as_ref()
                    .err()
                    .and_then(|e| e.downcast_ref::<crate::api::ApiError>())
                    .map(|e| e.status == 401)
                    .unwrap_or(false);
                Event::Me(result.map_err(|e| e.to_string()), expired)
            });
        }
        // My List's new-episode counts, for the tab's badge.
        self.refresh_followed_info();
        let tab = self.ui.upgrade().map(|ui| ui.global::<Store>().get_tab()).unwrap_or(0);
        if tab == 2 {
            self.load_schedule(false);
        }
    }

    // --- home -----------------------------------------------------------------------------------

    fn load_home(&self) {
        let Some(api) = self.api() else {
            self.connect();
            return;
        };
        self.state.borrow_mut().home_failed = false;
        if let Some(ui) = self.ui.upgrade() {
            if self.state.borrow().home.is_none() {
                ui.global::<Store>().set_home_loaded(false);
            }
        }
        self.task(async move { Event::Home(api.home().await.map_err(|e| e.to_string())) });
    }

    /// "Because you watched …": AniList's recommendations for the two shows
    /// watched most recently, leaving out ones already in the history.
    fn load_because(&self) {
        let Some(api) = self.api() else { return };
        let recent: Vec<(String, String)> = {
            let s = self.state.borrow();
            s.local.latest_history().iter().take(2).map(|e| (e.anime_id.clone(), e.title.clone())).collect()
        };
        let seen: HashSet<String> = self.state.borrow().local.latest_history().iter().map(|e| e.anime_id.clone()).collect();
        for (id, title) in recent {
            if self.state.borrow().because_asked.contains(&id) {
                continue;
            }
            self.state.borrow_mut().because_asked.push(id.clone());
            let (api, seen) = (api.clone(), seen.clone());
            self.task(async move {
                let extra = api.extra(&id).await.unwrap_or_default();
                let recs: Vec<Anime> = extra
                    .get("recommendations")
                    .and_then(Value::as_array)
                    .map(|a| {
                        a.iter()
                            .filter_map(|r| serde_json::from_value::<Anime>(r.clone()).ok())
                            .filter(|r| !r.id_string().is_empty() && !seen.contains(&r.id_string()))
                            .collect()
                    })
                    .unwrap_or_default();
                Event::Because(id, if title.is_empty() { "a show".into() } else { title }, recs)
            });
        }
    }

    fn render_home(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        self.render_resume();
        let (home, failed, because) = {
            let s = self.state.borrow();
            (s.home.clone(), s.home_failed, s.because.clone())
        };
        let Some(home) = home else {
            store.set_home_loaded(failed);
            if failed {
                rows(&self.models.slides, vec![]);
                rows(&self.models.shelves, vec![]);
            }
            return;
        };
        let slides: Vec<Slide> = home
            .trending
            .iter()
            .take(5)
            .map(|a| {
                let url = a.poster_url();
                let meta = match a.next_airing_episode() {
                    Some(n) if n > 1 => format!("Ep {} out now!", n - 1),
                    _ => match a.episode_count() {
                        0 => a.status_code().to_lowercase().replace('_', " "),
                        1 => "1 episode".into(),
                        n => format!("{n} episodes"),
                    },
                };
                Slide { id: ss(a.id_string()), title: ss(a.title_text()), cover: self.art(&url, Art::Slant), cover_url: ss(&url), meta: ss(meta) }
            })
            .collect();
        rows(&self.models.slides, slides);
        let mut sections: Vec<(String, Vec<Anime>)> = because
            .iter()
            .filter(|(_, _, recs)| recs.len() >= 3)
            .map(|(_, title, recs)| (format!("BECAUSE YOU WATCHED {}", title.to_uppercase()), recs.clone()))
            .collect();
        sections.push(("TRENDING NOW".into(), home.trending.clone()));
        sections.push(("TAGALOG DUB".into(), home.tagalog.clone()));
        sections.push(("POPULAR".into(), home.popular.clone()));
        sections.push(("LATEST EPISODES".into(), home.latest.clone()));
        let mut item_models = Vec::new();
        let shelves: Vec<Shelf> = sections
            .into_iter()
            .filter(|(_, items)| !items.is_empty())
            .map(|(title, items)| {
                let model = Rc::new(VecModel::from(items.iter().map(|a| self.card(a)).collect::<Vec<_>>()));
                item_models.push(model.clone());
                Shelf { title: ss(title), items: ModelRc::from(model) }
            })
            .collect();
        *self.models.shelf_items.borrow_mut() = item_models;
        rows(&self.models.shelves, shelves);
        store.set_home_loaded(true);
    }

    /// Continue Watching: the latest episode of each anime.
    fn render_resume(&self) {
        let entries: Vec<HistoryEntry> = {
            let s = self.state.borrow();
            s.local.latest_history().into_iter().cloned().collect()
        };
        let all: Vec<Resume> = entries.iter().map(|e| self.resume_row(e)).collect();
        rows(&self.models.resume, all.iter().take(15).cloned().collect());
        rows(&self.models.history, all);
    }

    fn resume_row(&self, e: &HistoryEntry) -> Resume {
        let (title, cover) = {
            let s = self.state.borrow();
            let cached = s.local.anime(&e.anime_id);
            (
                if e.title.is_empty() { cached.map(Anime::title_text).unwrap_or_else(|| format!("Episode {}", e.episode)) } else { e.title.clone() },
                if e.cover.is_empty() { cached.map(Anime::poster_url).unwrap_or_default() } else { e.cover.clone() },
            )
        };
        let (image, url) = self.cover_row(&cover);
        let watched = if e.finished() {
            "Watched".to_string()
        } else if e.duration_ms > 0 {
            format!("{} / {}", clock(e.position_ms), clock(e.duration_ms))
        } else {
            clock(e.position_ms)
        };
        Resume {
            id: ss(&e.anime_id),
            title: ss(title),
            cover: image,
            cover_url: url,
            episode: e.episode as i32,
            fraction: e.fraction(),
            finished: e.finished(),
            watched: ss(watched),
            ago: ss(time_ago(e.updated_at)),
        }
    }

    // --- pages ----------------------------------------------------------------------------------

    fn open_page(&self, page: Page) {
        {
            let mut s = self.state.borrow_mut();
            if s.closing {
                return;
            }
            if page != Page::Player && s.stack.last() == Some(&page) {
                return;
            }
            s.stack.push(page.clone());
        }
        if page != Page::Player {
            self.sfx("page");
        }
        self.show_page(&page, false);
    }

    fn show_page(&self, page: &Page, back: bool) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        match page {
            Page::Detail(id) => self.show_detail(id),
            Page::Settings => self.render_prefs(),
            Page::Account => {
                self.render_account();
                self.load_auth_config();
                self.load_tracking();
            }
            Page::History => {
                self.render_resume();
                self.sync_history_now();
            }
            Page::Genres => {
                self.render_genres();
                self.load_genre_art();
            }
            Page::Genre(name) => {
                if !back || self.state.borrow().genre_name != *name {
                    self.start_genre(name);
                }
                self.render_genre();
            }
            Page::Player => {}
        }
        store.set_page_back(back);
        store.set_page_serial(store.get_page_serial() + 1);
        store.set_page(ss(page.name()));
    }

    /// Back: an overlay closes first, then a page turns away, then the app leaves.
    fn back(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        if store.get_intro() {
            store.set_intro(false);
            return;
        }
        if store.get_dialog_open() {
            self.dialog_answer(false, String::new());
            return;
        }
        if store.get_sheet_open() {
            self.close_sheet();
            return;
        }
        let (has_page, closing, fx_off, top) = {
            let s = self.state.borrow();
            (!s.stack.is_empty(), s.closing, s.settings.effects == "off", s.stack.last().cloned())
        };
        if closing {
            return;
        }
        if !has_page {
            player::exit_to_background();
            return;
        }
        if top == Some(Page::Player) {
            self.state.borrow_mut().play_request += 1;
            self.finish_back();
            return;
        }
        self.sfx("page");
        if fx_off {
            self.finish_back();
            return;
        }
        self.state.borrow_mut().closing = true;
        store.set_closing(true);
        let app = self.clone();
        slint::Timer::single_shot(Duration::from_millis(320), move || app.finish_back());
    }

    fn finish_back(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let next = {
            let mut s = self.state.borrow_mut();
            s.closing = false;
            s.stack.pop();
            s.stack.last().cloned()
        };
        store.set_closing(false);
        match next {
            Some(page) => self.show_page(&page, true),
            None => {
                store.set_page_back(false);
                store.set_page(SharedString::default());
                // Come back to fresh numbers on the tab underneath.
                self.render_resume();
                self.render_followed();
                self.render_saved();
            }
        }
    }

    fn select_tab(&self, i: i32) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        if store.get_tab() == i {
            return;
        }
        self.sfx("page");
        store.set_tab(i);
        match i {
            1 => self.render_search(),
            2 => self.load_schedule(false),
            3 => {
                self.render_followed();
                self.refresh_followed_info();
                self.mark_followed_seen();
            }
            4 => self.render_saved(),
            _ => self.render_resume(),
        }
    }

    // --- the anime page -------------------------------------------------------------------------

    fn open_anime(&self, id: &str) {
        if id.is_empty() {
            return;
        }
        self.open_page(Page::Detail(id.to_owned()));
    }

    fn show_detail(&self, id: &str) {
        let need = {
            let mut s = self.state.borrow_mut();
            s.detail_id = id.to_owned();
            s.window = (0, 30);
            let known = s.details.get(id).map(|d| d.anime.is_some()).unwrap_or(false);
            if !known {
                s.details.entry(id.to_owned()).or_default();
            }
            !known
        };
        if need {
            self.request_detail(id);
        }
        if let Some(ui) = self.ui.upgrade() {
            ui.global::<Store>().set_detail_list_view(self.state.borrow().settings.ep_view == "list");
        }
        self.render_detail();
    }

    fn request_detail(&self, id: &str) {
        let Some(api) = self.api() else {
            self.toast("You're offline. Check your connection and try again.");
            return;
        };
        let id = id.to_owned();
        for kind in 0..4 {
            let (api, id) = (api.clone(), id.clone());
            self.task(async move {
                match kind {
                    0 => Event::Info(id.clone(), api.details(&id).await.map_err(|e| e.to_string())),
                    1 => Event::Episodes(id.clone(), api.episodes(&id).await.unwrap_or_default()),
                    2 => Event::Extra(id.clone(), api.extra(&id).await.unwrap_or_default()),
                    _ => Event::Tagalog(id.clone(), api.tagalog(&id).await.ok()),
                }
            });
        }
    }

    fn detail(&self) -> Option<(String, DetailData)> {
        let s = self.state.borrow();
        let d = s.details.get(&s.detail_id)?.clone();
        Some((s.detail_id.clone(), d))
    }

    fn render_detail(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let Some((id, d)) = self.detail() else { return };
        store.set_detail_id(ss(&id));
        let Some(anime) = d.anime.clone() else {
            store.set_detail_loading(d.error.is_none());
            if let Some(e) = &d.error {
                store.set_detail_loading(false);
                store.set_detail_title(ss("Untitled"));
                self.toast(e.clone());
            }
            return;
        };
        store.set_detail_loading(false);
        let title = anime.title_text();
        store.set_detail_title(ss(&title));
        store.set_detail_title_caps(ss(title.to_uppercase()));
        let cover = anime.poster_url();
        let banner = anime.extra.get("bannerImage").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_owned).unwrap_or_else(|| cover.clone());
        let (cover_img, cover_url) = self.cover_row(&cover);
        store.set_detail_cover(cover_img);
        store.set_detail_cover_url(cover_url);
        store.set_detail_banner(self.art(&banner, Art::Banner));
        store.set_detail_banner_url(if self.art_failed(&banner, Art::Banner) || banner.is_empty() { SharedString::default() } else { ss(&banner) });
        rows(&self.models.detail_genres, anime.genres.iter().take(3).map(|g| ss(g.to_uppercase())).collect());
        // the facts line: episodes, status, score, length, season, studio
        let mut facts = Vec::new();
        match anime.episode_count() {
            0 => {}
            1 => facts.push("1 episode".to_string()),
            n => facts.push(format!("{n} episodes")),
        }
        if !anime.status_code().is_empty() {
            facts.push(anime.status_code().replace('_', " ").to_lowercase());
        }
        if let Some(score) = anime.average_score.as_f64().filter(|s| *s > 0.0) {
            facts.push(format!("{score:.0}%"));
        }
        if anime.duration_minutes() > 0 {
            facts.push(format!("{}m", anime.duration_minutes()));
        }
        if let (Some(season), Some(year)) = (d.extra.get("season").and_then(Value::as_str), d.extra.get("seasonYear")) {
            facts.push(format!("{} {}", season.to_lowercase(), models::value_text(year)));
        }
        if let Some(studio) = d.extra.get("studio").and_then(Value::as_str).filter(|s| !s.is_empty()) {
            facts.push(studio.to_owned());
        }
        let facts: Vec<String> = facts.into_iter().map(|f| f.to_uppercase()).collect();
        let width = ui.window().size().width as f32 / ui.window().scale_factor();
        let avail = width - if cover.is_empty() { 30.0 } else { 164.0 };
        rows(&self.models.detail_facts, chip_rows(wrap_chips(&facts, avail, 5.4, 18.0, 6.0)));
        store.set_detail_synopsis(ss(anime.description_text()));
        let following = self.state.borrow().local.following(&id);
        store.set_detail_following(following);
        let tagalog = d.tagalog.as_ref().and_then(|t| t.get("episodes")).and_then(Value::as_object).map(|e| e.len()).unwrap_or(0);
        store.set_detail_tagalog(if tagalog == 0 { SharedString::default() } else { ss(format!("TAGALOG DUB · {} EP{}", tagalog, if tagalog == 1 { "" } else { "S" })) });
        let released = anime.status_code() != "NOT_YET_RELEASED";
        store.set_detail_released(released);
        let aired = anime.aired_episodes();
        store.set_detail_download_all(released && aired > 1);
        // "Continue EP 5 · 12 min left", or "Next: EP 6" once that one is done
        let last = {
            let s = self.state.borrow();
            s.local.episodes_of(&id).values().max_by_key(|e| e.updated_at).map(|e| (*e).clone())
        };
        let (rtitle, rtext, rfrac, rdone) = match last {
            Some(last) => {
                let next = if last.finished() { last.episode + 1 } else { last.episode };
                if next > aired {
                    (String::new(), String::new(), 0.0, false)
                } else if last.finished() {
                    (format!("NEXT: EPISODE {next}"), format!("You finished episode {}", last.episode), 1.0, true)
                } else if last.duration_ms > 0 {
                    (format!("CONTINUE EP {next}"), format!("{} min left", last.duration_ms.saturating_sub(last.position_ms) / 60_000), last.fraction(), false)
                } else {
                    (format!("CONTINUE EP {next}"), "Pick up where you stopped".into(), last.fraction(), false)
                }
            }
            None => (String::new(), String::new(), 0.0, false),
        };
        store.set_detail_resume_title(ss(rtitle));
        store.set_detail_resume_text(ss(rtext));
        store.set_detail_resume_fraction(rfrac);
        store.set_detail_resume_finished(rdone);
        store.set_episode_count(if released { aired.max(anime.episode_count()) as i32 } else { 0 });
        self.render_episodes();
        // trailer, characters, related seasons, recommendations
        let x = &d.extra;
        let trailer = x.get("trailer").filter(|t| t.get("id").is_some() && matches!(t.get("site").and_then(Value::as_str), Some("youtube") | Some("dailymotion")));
        store.set_trailer(trailer.is_some());
        if let Some(t) = trailer {
            let thumb = [str_of(t, "thumbnail"), str_of(x, "bannerImage"), cover.clone()].into_iter().find(|s| !s.is_empty()).unwrap_or_default();
            let (img, url) = self.cover_row(&thumb);
            store.set_trailer_thumb(img);
            store.set_trailer_thumb_url(url);
        }
        let people: Vec<Person> = x
            .get("characters")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter(|c| c.get("name").is_some())
                    .map(|c| {
                        let role = c.get("voiceActor").and_then(Value::as_str).map(str::to_owned).unwrap_or_else(|| if str_of(c, "role") == "MAIN" { "Main".into() } else { "Supporting".into() });
                        let (image, url) = self.cover_row(&str_of(c, "image"));
                        Person { name: ss(str_of(c, "name")), role: ss(role.to_uppercase()), image, image_url: url }
                    })
                    .collect()
            })
            .unwrap_or_default();
        rows(&self.models.characters, people);
        let related: Vec<Card> = x
            .get("relations")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter(|r| r.get("id").is_some())
                    .map(|r| {
                        let mut c = self.card_from(r);
                        let rel = str_of(r, "relation");
                        c.chip = ss(RELATIONS.iter().find(|(k, _)| *k == rel).map(|(_, v)| *v).unwrap_or("Related").to_uppercase());
                        c
                    })
                    .collect()
            })
            .unwrap_or_default();
        rows(&self.models.related, related);
        let recs: Vec<Card> = x.get("recommendations").and_then(Value::as_array).map(|a| a.iter().filter(|r| r.get("id").is_some()).map(|r| self.card_from(r)).collect()).unwrap_or_default();
        rows(&self.models.recommended, recs);
    }

    /// The episodes the page can see (it reports the rows in view).
    fn render_episodes(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let Some((id, d)) = self.detail() else { return };
        let Some(anime) = d.anime.clone() else {
            rows(&self.models.episodes, vec![]);
            return;
        };
        let list = store.get_detail_list_view();
        let cols = if list { 1 } else { 4 };
        let (first_row, count) = self.state.borrow().window;
        let total = store.get_episode_count().max(0) as usize;
        let start = (first_row * cols).min(total);
        let end = ((first_row + count) * cols).min(total);
        let aired = anime.aired_episodes();
        let cover = anime.poster_url();
        let (history, downloads): (HashMap<u32, HistoryEntry>, Vec<DownloadItem>) = {
            let s = self.state.borrow();
            (
                s.local.episodes_of(&id).into_iter().map(|(k, v)| (k, v.clone())).collect(),
                s.local.downloads.iter().filter(|x| x.anime_id == id).cloned().collect(),
            )
        };
        let items: Vec<EpisodeRow> = (start..end)
            .map(|i| {
                let n = (i + 1) as u32;
                let info = d.episodes.get(&n);
                let progress = history.get(&n);
                let done = progress.map(HistoryEntry::finished).unwrap_or(false);
                let future = n > aired;
                let mut meta = Vec::new();
                if let Some(day) = info.map(|e| models::value_text(&e.aired)).filter(|s| s.len() >= 10) {
                    if let Ok(date) = chrono::NaiveDate::parse_from_str(&day[..10], "%Y-%m-%d") {
                        meta.push(date.format("%-d %b %Y").to_string());
                    }
                }
                if let Some(runtime) = info.and_then(|e| e.runtime.as_f64()).filter(|r| *r > 0.0) {
                    meta.push(format!("{runtime:.0}m"));
                }
                if future {
                    meta.push("Not aired yet".into());
                } else if done {
                    meta.push("Watched".into());
                }
                let image = info.map(|e| e.thumbnail.clone()).filter(|s| !s.is_empty()).unwrap_or_else(|| cover.clone());
                let (img, url) = if list { self.cover_row(&image) } else { (Image::default(), SharedString::default()) };
                let download = downloads.iter().find(|x| x.episode == n && x.status != "failed").map(|x| if x.status == "ready" { "done".to_string() } else { format!("{:.0}%", x.progress * 100.0) }).unwrap_or_default();
                EpisodeRow {
                    number: n as i32,
                    title: ss(info.map(|e| e.title.clone()).filter(|t| !t.is_empty()).unwrap_or_else(|| format!("Episode {n}"))),
                    meta: ss(meta.join(" · ").to_uppercase()),
                    overview: ss(info.map(|e| e.synopsis.clone()).unwrap_or_default()),
                    image: img,
                    image_url: url,
                    fraction: progress.map(HistoryEntry::fraction).unwrap_or(0.0),
                    started: progress.is_some(),
                    finished: done,
                    future,
                    download: ss(download),
                }
            })
            .collect();
        store.set_episode_first(start as i32);
        rows(&self.models.episodes, items);
    }

    fn toggle_follow(&self) {
        let Some((id, d)) = self.detail() else { return };
        let Some(anime) = d.anime else { return };
        let on = self.state.borrow().local.following(&id);
        if on {
            self.state.borrow_mut().local.unfollow(&id);
            self.toast("Removed from My List.");
        } else {
            let alerts = {
                let mut s = self.state.borrow_mut();
                s.local.cache_anime(anime.clone());
                s.local.follow(&id, &anime.title_text(), &anime.poster_url(), anime.aired_episodes());
                s.aired.insert(id.clone(), anime.aired_episodes());
                s.settings.alerts
            };
            self.sfx("achieve");
            self.toast(if alerts { "On My List. You'll be told when new episodes air." } else { "On My List. Turn on alerts in Settings to hear about new episodes." });
        }
        self.save_local();
        self.render_detail();
        self.render_followed();
        self.sync_soon();
    }

    fn category_for(&self, id: &str) -> String {
        if self.state.borrow().settings.tagalog_shows.iter().any(|t| t == id) { "tl".into() } else { "sub".into() }
    }

    fn play_episode(&self, number: i32) {
        let Some((id, d)) = self.detail() else { return };
        let Some(anime) = d.anime else { return };
        let episode = if number > 0 {
            number as u32
        } else {
            // the resume banner: the episode it names
            let s = self.state.borrow();
            match s.local.episodes_of(&id).values().max_by_key(|e| e.updated_at) {
                Some(last) if last.finished() => last.episode + 1,
                Some(last) => last.episode,
                None => 1,
            }
        };
        let category = self.category_for(&id);
        self.play(Play { anime_id: id, episode, category, title: anime.title_text(), cover: anime.poster_url(), local: None });
    }

    /// The Tagalog dub, from the episode last watched if it is dubbed, else the
    /// first dubbed one. The show then opens in Tagalog until switched back.
    fn play_tagalog(&self) {
        let Some((id, d)) = self.detail() else { return };
        let Some(anime) = d.anime else { return };
        let mut eps: Vec<u32> = d.tagalog.as_ref().and_then(|t| t.get("episodes")).and_then(Value::as_object).map(|m| m.keys().filter_map(|k| k.parse().ok()).collect()).unwrap_or_default();
        eps.sort_unstable();
        let Some(first) = eps.first().copied() else { return };
        let last = self.state.borrow().local.episodes_of(&id).keys().copied().max().unwrap_or(0);
        let start = if eps.contains(&last) { last } else { first };
        {
            let mut s = self.state.borrow_mut();
            if !s.settings.tagalog_shows.contains(&id) {
                s.settings.tagalog_shows.push(id.clone());
            }
        }
        self.save_settings();
        self.play(Play { anime_id: id, episode: start, category: "tl".into(), title: anime.title_text(), cover: anime.poster_url(), local: None });
    }

    fn toggle_episode_view(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let list = !store.get_detail_list_view();
        self.sfx("select");
        store.set_detail_list_view(list);
        self.state.borrow_mut().settings.ep_view = if list { "list" } else { "grid" }.into();
        self.save_settings();
        self.render_episodes();
    }

    fn open_trailer(&self) {
        let Some((_, d)) = self.detail() else { return };
        let Some(t) = d.extra.get("trailer") else { return };
        let id = str_of(t, "id");
        let url = if str_of(t, "site") == "youtube" { format!("https://www.youtube.com/watch?v={id}") } else { format!("https://www.dailymotion.com/video/{id}") };
        self.sfx("start");
        if let Err(e) = player::open_url(&url) {
            self.toast(e.to_string());
        }
    }

    // --- search ---------------------------------------------------------------------------------

    fn render_search(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let (filters, recent, results, more) = {
            let s = self.state.borrow();
            (s.filters.clone(), s.settings.recent_searches.clone(), s.results.clone(), s.search_more)
        };
        let chips: Vec<Filter> = filter_defs()
            .iter()
            .map(|(key, label, options)| {
                let value = filters.get(*key).cloned().unwrap_or_default();
                let shown = if value.is_empty() { label.to_string() } else { options.iter().find(|(v, _)| *v == value).map(|(_, l)| l.clone()).unwrap_or_else(|| label.to_string()) };
                Filter { key: ss(key), label: ss(shown.to_uppercase()) }
            })
            .collect();
        rows(&self.models.filters, chips);
        store.set_filtered(filters.values().any(|v| !v.is_empty()));
        let width = ui.window().size().width as f32 / ui.window().scale_factor();
        let recent: Vec<String> = recent.iter().map(|q| q.to_uppercase()).collect();
        rows(&self.models.recent, chip_rows(wrap_chips(&recent, width - 32.0, 6.4, 36.0, 8.0)));
        rows(&self.models.results, results.iter().map(|a| self.card(a)).collect());
        store.set_has_more(more);
    }

    fn search_edited(&self, text: String) {
        let mut s = self.state.borrow_mut();
        s.search_text = text;
        // Wait for a pause in typing rather than a request per keystroke.
        s.debounce = Some(Instant::now() + Duration::from_millis(450));
    }

    fn run_search(&self, more: bool) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let Some(api) = self.api() else {
            self.toast("Can't reach the AniVerse server. Check your connection and try again.");
            return;
        };
        let (q, filters, id, page) = {
            let mut s = self.state.borrow_mut();
            s.debounce = None;
            if !more {
                s.search_request += 1;
            }
            let page = if more { s.search_page + 1 } else { 1 };
            (s.search_text.trim().to_owned(), s.filters.clone(), s.search_request, page)
        };
        let filtered = filters.values().any(|v| !v.is_empty());
        if filtered {
            if more {
                store.set_loading_more(true);
            } else {
                store.set_search_loading(true);
            }
            let mut query: Vec<(String, String)> = vec![("q".into(), q)];
            query.extend(filters.into_iter());
            query.push(("page".into(), page.to_string()));
            query.push(("per_page".into(), "24".into()));
            self.task(async move { Event::Filter(id, more, api.filter(&query).await.map_err(|e| e.to_string())) });
            return;
        }
        self.state.borrow_mut().search_more = false;
        if q.is_empty() {
            self.state.borrow_mut().results.clear();
            store.set_searched(false);
            store.set_search_loading(false);
            self.render_search();
            return;
        }
        store.set_search_loading(true);
        self.task(async move { Event::Search(id, api.search(&q).await.map_err(|e| e.to_string())) });
    }

    fn add_recent(&self) {
        let text = self.state.borrow().search_text.clone();
        self.state.borrow_mut().settings.add_recent_search(&text);
        self.save_settings();
    }

    // --- airing ---------------------------------------------------------------------------------

    fn load_schedule(&self, force: bool) {
        if !force && (self.state.borrow().schedule.is_some() || self.state.borrow().schedule_loading) {
            self.render_schedule();
            return;
        }
        let Some(api) = self.api() else {
            self.render_schedule();
            return;
        };
        self.state.borrow_mut().schedule_loading = true;
        if let Some(ui) = self.ui.upgrade() {
            ui.global::<Store>().set_schedule_state(0);
        }
        self.task(async move { Event::Schedule(api.schedule(7).await.map_err(|e| e.to_string())) });
    }

    fn airing_at(a: &Anime) -> i64 {
        a.extra.get("airingAt").and_then(Value::as_i64).unwrap_or(0)
    }
    fn airing_episode(a: &Anime) -> u32 {
        a.extra.get("airingEpisode").and_then(Value::as_u64).unwrap_or(0) as u32
    }

    /// The selected day's episodes, shows on My List first.
    fn airing_rows(&self) -> Vec<Anime> {
        let s = self.state.borrow();
        let mut items: Vec<Anime> = s.schedule.clone().unwrap_or_default().into_iter().filter(|a| day_key(Self::airing_at(a)) == s.day).collect();
        items.sort_by_key(|a| (if s.local.following(&a.id_string()) { 0 } else { 1 }, Self::airing_at(a)));
        items
    }

    fn render_schedule(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let (schedule, loading) = {
            let s = self.state.borrow();
            (s.schedule.clone(), s.schedule_loading)
        };
        let Some(items) = schedule else {
            store.set_schedule_state(if loading || self.api().is_none() { 0 } else { 1 });
            return;
        };
        if items.is_empty() {
            store.set_schedule_state(1);
            return;
        }
        let today = day_key(chrono::Utc::now().timestamp());
        let mut days: Vec<Day> = Vec::new();
        for a in &items {
            let at = Self::airing_at(a);
            let key = day_key(at);
            if days.iter().any(|d| d.key.as_str() == key) {
                continue;
            }
            let label = if key == today {
                "TODAY".to_string()
            } else {
                Local.timestamp_opt(at, 0).single().map(|t| t.format("%a %-d").to_string().to_uppercase()).unwrap_or_default()
            };
            days.push(Day { key: ss(&key), label: ss(label) });
        }
        {
            let mut s = self.state.borrow_mut();
            if s.day.is_empty() || !days.iter().any(|d| d.key.as_str() == s.day) {
                s.day = days.first().map(|d| d.key.to_string()).unwrap_or_default();
            }
        }
        store.set_day(ss(&self.state.borrow().day));
        rows(&self.models.days, days);
        let now = chrono::Utc::now().timestamp();
        let list: Vec<Airing> = self
            .airing_rows()
            .iter()
            .map(|a| {
                let at = Self::airing_at(a);
                let when = Local.timestamp_opt(at, 0).single();
                let (img, url) = self.cover_row(&a.poster_url());
                Airing {
                    id: ss(a.id_string()),
                    title: ss(a.title_text()),
                    cover: img,
                    cover_url: url,
                    time: ss(when.map(|t| format!("{:02}:{:02}", t.hour(), t.minute())).unwrap_or_default()),
                    countdown: ss(countdown(at - now)),
                    episode: Self::airing_episode(a) as i32,
                    aired: at <= now,
                    mine: self.state.borrow().local.following(&a.id_string()),
                }
            })
            .collect();
        rows(&self.models.airing, list);
        store.set_schedule_state(2);
    }

    fn open_airing(&self, i: usize) {
        let Some(a) = self.airing_rows().get(i).cloned() else { return };
        let now = chrono::Utc::now().timestamp();
        if Self::airing_at(&a) <= now {
            let id = a.id_string();
            let category = self.category_for(&id);
            self.play(Play { anime_id: id, episode: Self::airing_episode(&a).max(1), category, title: a.title_text(), cover: a.poster_url(), local: None });
        } else {
            self.open_anime(&a.id_string());
        }
    }

    fn follow_airing(&self, i: usize) {
        let Some(a) = self.airing_rows().get(i).cloned() else { return };
        let id = a.id_string();
        if self.state.borrow().local.following(&id) {
            self.state.borrow_mut().local.unfollow(&id);
        } else {
            let mut s = self.state.borrow_mut();
            s.local.cache_anime(a.clone());
            s.local.follow(&id, &a.title_text(), &a.poster_url(), Self::airing_episode(&a).saturating_sub(1));
            drop(s);
            self.sfx("achieve");
        }
        self.save_local();
        self.render_schedule();
        self.render_followed();
        self.sync_soon();
    }

    // --- my list --------------------------------------------------------------------------------

    /// Fetch the aired counts behind My List (and the tab's badge).
    fn refresh_followed_info(&self) {
        let Some(api) = self.api() else { return };
        let ids: Vec<String> = {
            let s = self.state.borrow();
            s.local.followed().iter().take(30).map(|e| e.anime_id.clone()).filter(|id| !s.info_asked.contains(id)).collect()
        };
        for id in ids {
            self.state.borrow_mut().info_asked.insert(id.clone());
            let api = api.clone();
            self.task(async move { Event::Info(id.clone(), api.details(&id).await.map_err(|e| e.to_string())) });
        }
    }

    /// Seen now: the alert for these episodes has done its job.
    fn mark_followed_seen(&self) {
        let app = self.clone();
        slint::Timer::single_shot(Duration::from_millis(1500), move || {
            let changed = {
                let mut s = app.state.borrow_mut();
                let pairs: Vec<(String, u32)> = s.local.followed().iter().filter_map(|e| s.aired.get(&e.anime_id).map(|a| (e.anime_id.clone(), *a))).collect();
                let mut changed = false;
                for (id, aired) in pairs {
                    changed |= s.local.mark_seen(&id, aired);
                }
                changed
            };
            if changed {
                app.save_local();
                app.render_followed();
                app.sync_soon();
            }
        });
    }

    fn render_followed(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let entries: Vec<WatchEntry> = self.state.borrow().local.followed().into_iter().cloned().collect();
        let mut fresh_count = 0;
        let list: Vec<Followed> = entries
            .iter()
            .map(|e| {
                let (aired, airing, watched, muted, alerts) = {
                    let s = self.state.borrow();
                    (
                        s.aired.get(&e.anime_id).copied(),
                        s.releasing.contains(&e.anime_id),
                        s.local.episodes_of(&e.anime_id).keys().copied().max().unwrap_or(0),
                        s.settings.alerts_muted.contains(&e.anime_id),
                        s.settings.alerts,
                    )
                };
                let _ = alerts;
                let fresh = match aired {
                    Some(a) if e.seen_episode > 0 && a > e.seen_episode => a - e.seen_episode,
                    _ => 0,
                };
                if fresh > 0 {
                    fresh_count += 1;
                }
                let (status, next) = match aired {
                    None => ("CHECKING…".to_string(), 0),
                    Some(a) => {
                        let mut status = format!("{a} OUT");
                        if airing {
                            status.push_str(" · AIRING");
                        }
                        if watched > 0 {
                            status.push_str(&format!(" · ON {watched}"));
                        }
                        let next = if a == 0 { 0 } else { (watched + 1).clamp(1, a) };
                        (status, next)
                    }
                };
                let (img, url) = self.cover_row(&e.cover);
                Followed {
                    id: ss(&e.anime_id),
                    title: ss(if e.title.is_empty() { "Untitled" } else { &e.title }),
                    cover: img,
                    cover_url: url,
                    fresh: ss(if fresh > 0 { format!("{fresh} NEW · ") } else { String::new() }),
                    status: ss(status),
                    next: next as i32,
                    alerts: !muted,
                    highlight: fresh > 0,
                }
            })
            .collect();
        rows(&self.models.followed, list);
        store.set_fresh_count(fresh_count);
    }

    fn followed_at(&self, i: usize) -> Option<WatchEntry> {
        self.state.borrow().local.followed().get(i).map(|e| (*e).clone())
    }

    // --- saved episodes -------------------------------------------------------------------------

    fn render_saved(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let items: Vec<DownloadItem> = self.state.borrow().local.downloads.clone();
        let total: u64 = items.iter().map(|d| d.bytes).sum();
        store.set_saved_summary(ss(format!(
            "{} EPISODE{} · {} · DOWNLOADS RUN WHILE ANIVERSE IS OPEN",
            items.len(),
            if items.len() == 1 { "" } else { "S" },
            bytes_text(total)
        )));
        let list: Vec<Saved> = items
            .iter()
            .map(|d| {
                let status = match d.status.as_str() {
                    "ready" => bytes_text(d.bytes),
                    "downloading" => format!("DOWNLOADING {:.0}% · {}", d.progress * 100.0, bytes_text(d.bytes)),
                    "queued" => "WAITING".into(),
                    _ => if d.error.is_empty() { "FAILED".into() } else { d.error.clone() },
                };
                let (img, url) = self.cover_row(&d.cover);
                Saved {
                    key: ss(&d.key),
                    title: ss(if d.title.is_empty() { format!("Anime {}", d.anime_id) } else { d.title.clone() }),
                    cover: img,
                    cover_url: url,
                    line: ss(format!("EP {} · {}", d.episode, d.category.to_uppercase())),
                    status: ss(status.to_uppercase()),
                    failed: d.status == "failed",
                    done: d.status == "ready",
                    downloading: d.status == "downloading",
                    progress: d.progress,
                }
            })
            .collect();
        rows(&self.models.saved, list);
    }

    /// Queue an episode for saving; false if it is saved or on its way already.
    fn enqueue(&self, anime_id: &str, episode: u32, category: &str, title: &str, cover: &str) -> bool {
        let key = format!("{anime_id}-{episode}-{category}");
        {
            let mut s = self.state.borrow_mut();
            if s.local.downloads.iter().any(|d| d.key == key && d.status != "failed") {
                return false;
            }
            s.local.downloads.retain(|d| d.key != key);
            s.local.downloads.push(DownloadItem {
                key,
                anime_id: anime_id.to_owned(),
                title: title.to_owned(),
                cover: cover.to_owned(),
                episode,
                category: category.to_owned(),
                status: "queued".into(),
                added_at: chrono::Utc::now().timestamp_millis(),
                ..Default::default()
            });
        }
        self.save_local();
        self.pump_downloads();
        true
    }

    /// Start queued downloads, two at a time.
    fn pump_downloads(&self) {
        let Some(api) = self.api() else { return };
        loop {
            let next = {
                let s = self.state.borrow();
                let active = s.local.downloads.iter().filter(|d| d.status == "downloading").count();
                if active >= 2 {
                    None
                } else {
                    let limit = s.settings.download_limit_gb;
                    let used: u64 = s.local.downloads.iter().filter(|d| d.status == "ready").map(|d| d.bytes).sum();
                    if limit > 0.0 && used as f64 >= limit as f64 * (1u64 << 30) as f64 {
                        s.local.downloads.iter().find(|d| d.status == "queued").map(|d| (d.clone(), true))
                    } else {
                        s.local.downloads.iter().find(|d| d.status == "queued").map(|d| (d.clone(), false))
                    }
                }
            };
            let Some((item, full)) = next else { break };
            if full {
                let mut s = self.state.borrow_mut();
                if let Some(d) = s.local.downloads.iter_mut().find(|d| d.key == item.key) {
                    d.status = "failed".into();
                    d.error = "Storage limit reached. Delete something or raise it in Settings.".into();
                }
                continue;
            }
            let cancel = Arc::new(AtomicBool::new(false));
            let data_saver = {
                let mut s = self.state.borrow_mut();
                if let Some(d) = s.local.downloads.iter_mut().find(|d| d.key == item.key) {
                    d.status = "downloading".into();
                    d.progress = 0.0;
                    d.error.clear();
                }
                s.cancels.insert(item.key.clone(), cancel.clone());
                s.settings.data_saver
            };
            let (tx, epoch, api) = (self.tx.clone(), self.state.borrow().epoch, api.clone());
            self.runtime.spawn(async move {
                let key = item.key.clone();
                let result = async {
                    let sources = api.sources(&item.anime_id, item.episode, &item.category, false).await?;
                    let url = sources.sources.first().map(|s| s.url.clone()).ok_or_else(|| anyhow::anyhow!(sources.error.clone().unwrap_or_else(|| "No stream found for this episode.".into())))?;
                    let (ptx, pkey) = (tx.clone(), key.clone());
                    downloads::save_episode(&key, &url, data_saver, cancel, move |bytes, progress| {
                        let _ = ptx.send((epoch, Event::Download(pkey.clone(), bytes, progress, None)));
                    })
                    .await
                }
                .await;
                let (bytes, path) = match result {
                    Ok((bytes, path)) => (bytes, Ok(path)),
                    Err(e) => (0, Err(e.to_string())),
                };
                let _ = tx.send((epoch, Event::Download(key, bytes, 1.0, Some(path))));
            });
        }
        self.render_saved();
    }

    fn delete_saved(&self, key: &str) {
        let cancel = self.state.borrow_mut().cancels.remove(key);
        if let Some(cancel) = cancel {
            cancel.store(true, Ordering::Relaxed);
        }
        self.state.borrow_mut().local.downloads.retain(|d| d.key != key);
        self.sfx("slash");
        self.save_local();
        self.render_saved();
        let key = key.to_owned();
        self.runtime.spawn_blocking(move || {
            let _ = downloads::remove_episode(&key);
        });
        self.pump_downloads();
    }

    // --- genres ---------------------------------------------------------------------------------

    fn load_genre_art(&self) {
        let Some(api) = self.api() else { return };
        {
            let mut s = self.state.borrow_mut();
            if s.genre_art.is_some() || s.genre_art_loading {
                return;
            }
            s.genre_art_loading = true;
        }
        self.task(async move { Event::GenreArt(api.genre_art(&GENRES).await.unwrap_or_default()) });
    }

    fn render_genres(&self) {
        let (art, loading, manga) = {
            let s = self.state.borrow();
            (s.genre_art.clone(), s.genre_art_loading, s.settings.ui_style != "pixel")
        };
        let palette = ThemeId::parse(&self.state.borrow().settings.theme).palette();
        let parse = |c: &str| c.parse_hex().unwrap_or(Color::from_rgb_u8(0x1b, 0x11, 0x14));
        let fills: [Color; 5] = if manga {
            [Color::from_rgb_u8(0x9E, 0x06, 0x10), Color::from_rgb_u8(0xEA, 0xE4, 0xD8), Color::from_rgb_u8(0xE5, 0x09, 0x14), Color::from_rgb_u8(0x4A, 0x03, 0x08), Color::from_rgb_u8(0xFF, 0xFF, 0xFF)]
        } else {
            [parse(palette.accent_dark), parse(palette.panel_high), parse(palette.accent), parse(palette.accent_deep), parse(palette.panel)]
        };
        let tiles: Vec<GenreTile> = GENRES
            .iter()
            .enumerate()
            .map(|(i, g)| {
                let a = art.as_ref().and_then(|v| v.get(*g));
                let banner = a.map(|a| str_of(a, "banner")).unwrap_or_default();
                let url = if banner.is_empty() { a.map(|a| str_of(a, "cover")).unwrap_or_default() } else { banner };
                let image = self.art(&url, Art::Banner);
                GenreTile {
                    name: ss(g.to_uppercase()),
                    art: image,
                    art_url: if url.is_empty() || self.art_failed(&url, Art::Banner) { SharedString::default() } else { ss(&url) },
                    title: ss(a.map(|a| str_of(a, "title")).unwrap_or_default()),
                    score: ss(a.map(|a| str_of(a, "score")).unwrap_or_default()),
                    fill: fills[i % fills.len()],
                    loading: loading || art.is_none(),
                }
            })
            .collect();
        rows(&self.models.genres, tiles);
    }

    fn start_genre(&self, name: &str) {
        {
            let mut s = self.state.borrow_mut();
            s.genre_name = name.to_owned();
            s.genre_items.clear();
            s.genre_seen.clear();
            s.genre_page = 1;
            s.genre_end = false;
            s.genre_loading = false;
            s.genre_request += 1;
        }
        if let Some(ui) = self.ui.upgrade() {
            let store = ui.global::<Store>();
            store.set_genre_name(ss(name.to_uppercase()));
            store.set_genre_list(self.state.borrow().settings.browse_view == "list");
        }
        self.genre_more();
    }

    /// The next page of the genre, as the bottom comes near.
    fn genre_more(&self) {
        let Some(api) = self.api() else { return };
        let (name, page, id) = {
            let mut s = self.state.borrow_mut();
            if s.genre_loading || s.genre_end || s.genre_name.is_empty() {
                return;
            }
            s.genre_loading = true;
            (s.genre_name.clone(), s.genre_page, s.genre_request)
        };
        if let Some(ui) = self.ui.upgrade() {
            ui.global::<Store>().set_genre_loading(true);
        }
        self.task(async move { Event::Genre(id, page, api.genre(&name, page, 24).await.map_err(|e| e.to_string())) });
    }

    fn render_genre(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let (items, loading) = {
            let s = self.state.borrow();
            (s.genre_items.clone(), s.genre_loading)
        };
        rows(&self.models.genre_items, items.iter().map(|a| self.card(a)).collect());
        store.set_genre_loading(loading);
    }

    // --- history --------------------------------------------------------------------------------

    fn sync_history_now(&self) {
        if self.state.borrow().local.session.is_none() {
            return;
        }
        self.state.borrow_mut().history_syncing = true;
        if let Some(ui) = self.ui.upgrade() {
            ui.global::<Store>().set_history_syncing(true);
        }
        self.sync();
    }

    // --- account --------------------------------------------------------------------------------

    fn render_account(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let (session, entries, config, tracking) = {
            let s = self.state.borrow();
            (s.local.session.clone(), s.local.history.clone(), s.auth_config.clone(), s.tracking.clone())
        };
        store.set_signed_in(session.is_some());
        if let Some(session) = &session {
            let u = &session.user;
            let name = if u.display_name.is_empty() { u.username.clone().unwrap_or_else(|| "Player".into()) } else { u.display_name.clone() };
            store.set_user_name(ss(name.to_uppercase()));
            store.set_user_initial(ss(name.trim().chars().next().map(|c| c.to_uppercase().to_string()).unwrap_or_else(|| "P".into())));
            let avatar = u.avatar_url.clone().unwrap_or_default();
            let (img, url) = self.cover_row(&avatar);
            store.set_user_avatar(img);
            store.set_user_avatar_url(url);
            store.set_account_handle(ss(u.username.as_ref().map(|h| format!("@{h}")).or_else(|| u.email.clone()).unwrap_or_default()));
            store.set_account_provider(ss(if u.provider == "google" { "GOOGLE ACCOUNT" } else { "ANIVERSE ACCOUNT" }));
        }
        let anime = {
            let s = self.state.borrow();
            s.local.latest_history().len()
        };
        store.set_history_line(ss(if anime == 0 { "Nothing yet".to_string() } else { format!("{anime} anime · synced to your account") }));
        store.set_auth_config_known(config.is_some());
        store.set_google_ready(false);
        // level, rank, stats and badges
        let stats = achievements::stats(&entries);
        let level = achievements::level(&stats);
        let got = achievements::unlocked(&stats);
        let name = session.as_ref().map(|s| s.user.display_name.clone()).filter(|n| !n.trim().is_empty()).unwrap_or_else(|| "Player".into());
        store.set_level_initial(ss(name.trim().chars().next().map(|c| c.to_uppercase().to_string()).unwrap_or_else(|| "P".into())));
        store.set_frame_color(achievements::frame_color(level.frame));
        store.set_level_line(ss(format!("LV {} · {}", level.level, level.rank.to_uppercase())));
        store.set_level_progress(level.progress);
        store.set_xp_line(ss(if level.level >= 99 { format!("{} XP · MAX LEVEL", level.xp) } else { format!("{} XP · {} TO LEVEL {}", level.xp, level.to_next(), level.level + 1) }));
        store.set_stat_episodes(ss(stats.finished.to_string()));
        store.set_stat_anime(ss(stats.anime.to_string()));
        store.set_stat_streak(ss(stats.streak.to_string()));
        store.set_stat_hours(ss(format!("{}h", stats.hours.floor())));
        store.set_badges_title(ss(format!("ACHIEVEMENTS {}/{}", got.len(), achievements::BADGES.len())));
        let icons = ui.global::<Icons>();
        rows(
            &self.models.badges,
            achievements::BADGES.iter().map(|b| Badge { name: ss(b.name.to_uppercase()), text: ss(b.text), icon: icon(b.icon, &icons), got: got.contains(&b.id) }).collect(),
        );
        // AniList / MyAnimeList
        let (cfg, status) = tracking;
        for (id, set_text, set_action) in [("anilist", 0, 0), ("mal", 1, 1)] {
            let _ = (set_text, set_action);
            let st = status.get(id).cloned().unwrap_or_default();
            let enabled = cfg.get(id).and_then(|c| c.get("enabled")).and_then(Value::as_bool).unwrap_or(false);
            let connected = st.get("connected").and_then(Value::as_bool).unwrap_or(false);
            let text = if connected {
                match st.get("account").map(models::value_text).filter(|a| !a.is_empty()) {
                    Some(a) => format!("Connected as {a}."),
                    None => "Connected.".into(),
                }
            } else if enabled {
                "Episodes you finish update your list.".into()
            } else {
                "Not set up on this server yet.".into()
            };
            let action = if connected { "DISCONNECT" } else if enabled { "CONNECT" } else { "" };
            if id == "anilist" {
                store.set_anilist_text(ss(text));
                store.set_anilist_action(ss(action));
            } else {
                store.set_mal_text(ss(text));
                store.set_mal_action(ss(action));
            }
        }
    }

    fn load_auth_config(&self) {
        if self.state.borrow().auth_config.is_some() {
            return;
        }
        let Some(api) = self.api() else { return };
        self.task(async move { Event::AuthConfig(api.auth_config().await.map_err(|e| e.to_string())) });
    }

    fn load_tracking(&self) {
        let (api, session) = (self.api(), self.state.borrow().local.session.clone());
        let (Some(api), Some(session)) = (api, session) else { return };
        self.task(async move {
            let cfg = api.tracking_config().await.unwrap_or_default();
            let status = api.tracking_status(&session.token).await.unwrap_or_default();
            Event::Tracking(cfg, status)
        });
    }

    fn auth_submit(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        if store.get_auth_busy() {
            return;
        }
        let creating = store.get_creating();
        let username = store.get_username().trim().to_string();
        let password = store.get_password().to_string();
        let confirm = store.get_confirm().to_string();
        let problem = if username.is_empty() {
            Some("Enter a username")
        } else if creating && !(3..=24).contains(&username.len()) || creating && !username.chars().all(|c| c.is_ascii_alphanumeric() || "_.-".contains(c)) {
            Some("3-24 letters, numbers, or . _ -")
        } else if password.is_empty() {
            Some("Enter your password")
        } else if creating && password.chars().count() < 8 {
            Some("At least 8 characters")
        } else if creating && confirm != password {
            Some("Passwords don't match")
        } else {
            None
        };
        if let Some(p) = problem {
            store.set_auth_error(ss(p));
            return;
        }
        let Some(api) = self.api() else {
            store.set_auth_error(ss("Can't reach the AniVerse server. Check your connection and try again."));
            return;
        };
        store.set_auth_error(SharedString::default());
        store.set_auth_busy(true);
        self.task(async move {
            let result = if creating { api.register(&username, &password, None).await } else { api.login(&username, &password).await };
            Event::Auth(result.map_err(|e| e.to_string()))
        });
    }

    fn signed_out(&self) {
        {
            let mut s = self.state.borrow_mut();
            s.local.session = None;
            // The history belongs to the account; the next person to use the
            // phone should not see it.
            s.local.clear_local();
            s.tracking = (Value::Null, Value::Null);
        }
        if let Some(ui) = self.ui.upgrade() {
            let store = ui.global::<Store>();
            store.set_signing_out(false);
            store.set_user_avatar_url(SharedString::default());
            store.set_password(SharedString::default());
            store.set_confirm(SharedString::default());
        }
        self.save_local();
        self.render_account();
        self.render_resume();
    }

    fn tracking(&self, id: &str) {
        let (api, session, cfg, status) = {
            let s = self.state.borrow();
            (s.api.clone(), s.local.session.clone(), s.tracking.0.clone(), s.tracking.1.clone())
        };
        let (Some(api), Some(session)) = (api, session) else { return };
        let connected = status.get(id).and_then(|s| s.get("connected")).and_then(Value::as_bool).unwrap_or(false);
        let id = id.to_owned();
        if connected {
            self.task(async move {
                let _ = api.tracking_disconnect(&session.token, &id).await;
                let cfg = api.tracking_config().await.unwrap_or_default();
                let status = api.tracking_status(&session.token).await.unwrap_or_default();
                Event::Tracking(cfg, status)
            });
            return;
        }
        if id == "mal" {
            self.task(async move {
                match api.mal_start(&session.token).await {
                    Ok(url) => match player::open_url(&url) {
                        Ok(()) => Event::Toast("@mal".into()),
                        Err(e) => Event::Toast(e.to_string()),
                    },
                    Err(_) => Event::Toast("Couldn't start the MyAnimeList sign-in.".into()),
                }
            });
            return;
        }
        // AniList shows a token on its own page; it is pasted back here.
        let Some(url) = cfg.get("anilist").and_then(|a| a.get("authorize_url")).and_then(Value::as_str).map(str::to_owned) else { return };
        if let Err(e) = player::open_url(&url) {
            self.toast(e.to_string());
            return;
        }
        self.open_dialog(DialogFor::AniList, "ANILIST TOKEN", "Approve AniVerse on the AniList page, then copy the long token it shows into this box.", "CONNECT", "CANCEL", Some(("Paste the token", "")), false);
    }

    // --- settings -------------------------------------------------------------------------------

    fn apply_look(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let theme = ui.global::<ui::Theme>();
        let s = self.state.borrow();
        theme.set_style(ss(&s.settings.ui_style));
        let fx = match s.settings.effects.as_str() {
            "off" => 0,
            "lite" => 1,
            _ => {
                if s.settings.high_contrast { 1 } else { 2 }
            }
        };
        theme.set_fx(fx);
        theme.set_text_scale(s.settings.text_scale);
        theme.set_high_contrast(s.settings.high_contrast);
        let p = ThemeId::parse(&s.settings.theme).palette();
        let c = |v: &str| v.parse_hex().unwrap_or(Color::from_rgb_u8(0x12, 0x10, 0x10));
        theme.set_px_ink(c(p.ink));
        theme.set_px_panel(c(p.panel));
        theme.set_px_panel_high(c(p.panel_high));
        theme.set_px_blood(c(p.accent));
        theme.set_px_blood_dark(c(p.accent_dark));
        theme.set_px_blood_deep(c(p.accent_deep));
        theme.set_px_blood_light(c(p.accent_light));
    }

    fn render_prefs(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let prefs = ui.global::<Prefs>();
        let s = self.state.borrow().settings.clone();
        let label = |key: &str, value: &str, fallback: usize| pref_options(key).map(|(_, o)| label_of(&o, value, fallback)).unwrap_or_default();
        prefs.set_host(ss(if s.host.is_empty() { crate::api::DEFAULT_HOST.to_string() } else { s.host.clone() }));
        prefs.set_look(ss(if s.ui_style == "pixel" { "PIXEL" } else { "MANGA" }));
        prefs.set_palette(ss(ThemeId::parse(&s.theme).name().to_uppercase()));
        prefs.set_effects(ss(label("effects", &s.effects, 0)));
        prefs.set_intro(s.intro);
        prefs.set_sfx(s.sfx);
        prefs.set_volume(ss(label("volume", &num(s.volume), 1)));
        prefs.set_data_saver(s.data_saver);
        prefs.set_pip(s.pip_auto);
        prefs.set_pip_supported(cfg!(target_os = "android"));
        prefs.set_bg_audio(s.bg_audio);
        prefs.set_seek(ss(format!("{} SECONDS", s.seek_step)));
        prefs.set_skip_recap(s.skip_recap);
        prefs.set_sub_color(ss(label("subColor", &s.sub_color, 0)));
        prefs.set_sub_size(ss(label("subSize", &s.sub_size, 1)));
        prefs.set_sub_bg(s.sub_bg);
        prefs.set_sub_lang(ss(if s.sub_lang.is_empty() { "DEFAULT".to_string() } else { s.sub_lang.to_uppercase() }));
        prefs.set_wifi_only(s.wifi_only);
        prefs.set_storage(ss(if s.download_limit_gb <= 0.0 { "NO LIMIT".to_string() } else { format!("{:.0} GB", s.download_limit_gb) }));
        prefs.set_smart_downloads(s.smart_downloads);
        prefs.set_auto_delete(s.auto_delete_watched);
        prefs.set_alerts(s.alerts);
        prefs.set_quiet(ss(if s.quiet_from < 0 { "OFF".to_string() } else { format!("{}:00 - {}:00", s.quiet_from, s.quiet_to) }));
        prefs.set_text_size(ss(label("textScale", &num(s.text_scale), 0)));
        prefs.set_high_contrast(s.high_contrast);
        prefs.set_version(ss(format!("ANIVERSE RUST {}", env!("CARGO_PKG_VERSION"))));
    }

    fn toggle_pref(&self, key: &str) {
        let mut note: Option<&str> = None;
        {
            let mut s = self.state.borrow_mut();
            let st = &mut s.settings;
            match key {
                "intro" => st.intro = !st.intro,
                "sfx" => st.sfx = !st.sfx,
                "dataSaver" => st.data_saver = !st.data_saver,
                "pipAuto" => st.pip_auto = !st.pip_auto,
                "bgAudio" => st.bg_audio = !st.bg_audio,
                "skipRecap" => st.skip_recap = !st.skip_recap,
                "subBg" => st.sub_bg = !st.sub_bg,
                "wifiOnly" => st.wifi_only = !st.wifi_only,
                "smartDownloads" => st.smart_downloads = !st.smart_downloads,
                "autoDeleteWatched" => st.auto_delete_watched = !st.auto_delete_watched,
                "alerts" => {
                    st.alerts = !st.alerts;
                    if st.alerts {
                        note = Some("Alerts are saved, but this build can't send notifications yet.");
                    }
                }
                "highContrast" => st.high_contrast = !st.high_contrast,
                _ => return,
            }
        }
        self.save_settings();
        self.apply_look();
        self.render_prefs();
        self.render_followed();
        if let Some(n) = note {
            self.toast(n);
        }
    }

    fn choose_pref(&self, key: &str) {
        let Some((title, options)) = pref_options(key) else { return };
        let current = {
            let s = &self.state.borrow().settings;
            match key {
                "look" => s.ui_style.clone(),
                "theme" => s.theme.clone(),
                "effects" => s.effects.clone(),
                "volume" => num(s.volume),
                "seekStep" => s.seek_step.to_string(),
                "subColor" => s.sub_color.clone(),
                "subSize" => s.sub_size.clone(),
                "subLang" => s.sub_lang.clone(),
                "downloadLimitGb" => num(s.download_limit_gb),
                "quietFrom" => s.quiet_from.to_string(),
                "textScale" => num(s.text_scale),
                _ => String::new(),
            }
        };
        self.open_sheet(SheetFor::Pref(key.to_owned()), title, &options, &current);
    }

    fn set_pref(&self, key: &str, value: &str) {
        {
            let mut s = self.state.borrow_mut();
            let st = &mut s.settings;
            match key {
                "look" => st.ui_style = if value == "pixel" { "pixel" } else { "manga" }.into(),
                "theme" => st.theme = ThemeId::parse(value).id().into(),
                "effects" => st.effects = value.into(),
                "volume" => st.volume = value.parse().unwrap_or(0.35),
                "seekStep" => st.seek_step = value.parse().unwrap_or(10),
                "subColor" => st.sub_color = value.into(),
                "subSize" => st.sub_size = value.into(),
                "subLang" => st.sub_lang = value.into(),
                "downloadLimitGb" => st.download_limit_gb = value.parse().unwrap_or(0.0),
                "quietFrom" => st.quiet_from = value.parse().unwrap_or(-1),
                "textScale" => st.text_scale = value.parse().unwrap_or(1.0),
                _ => return,
            }
        }
        self.save_settings();
        self.apply_look();
        self.render_prefs();
        if key == "look" || key == "theme" {
            self.render_genres();
        }
        if key == "volume" {
            self.sfx("select");
        }
        if key == "downloadLimitGb" {
            self.pump_downloads();
        }
    }

    fn edit_server(&self) {
        let host = self.state.borrow().settings.host.clone();
        self.open_dialog(DialogFor::Server, "SERVER ADDRESS", "", "SAVE", "CANCEL", Some(("https://xxxx.trycloudflare.com", &host)), false);
    }

    fn set_host(&self, value: &str) {
        match AniVerseApi::new(value) {
            Err(e) => self.toast(e.to_string()),
            Ok(api) => {
                {
                    let mut s = self.state.borrow_mut();
                    let host = api.host().to_owned();
                    // A session belongs to a server and is never sent to another one.
                    if s.api.as_ref().map(|a| a.host()) != Some(host.as_str()) {
                        s.local.session = None;
                    }
                    s.epoch += 1;
                    s.settings.host = host;
                    s.api = Some(api);
                    s.home = None;
                    s.because.clear();
                    s.because_asked.clear();
                    s.details.clear();
                    s.schedule = None;
                    s.schedule_loading = false;
                    s.genre_art = None;
                    s.genre_art_loading = false;
                    s.info_asked.clear();
                    s.auth_config = None;
                }
                self.save_settings();
                self.save_local();
                self.render_prefs();
                self.render_account();
                self.load_home();
                self.refresh_followed_info();
            }
        }
    }

    // --- overlays -------------------------------------------------------------------------------

    fn open_sheet(&self, kind: SheetFor, title: &str, options: &[(String, String)], current: &str) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        rows(&self.models.sheet, options.iter().map(|(v, l)| Choice { value: ss(v), label: ss(l.to_uppercase()) }).collect());
        store.set_sheet_title(ss(title.to_uppercase()));
        store.set_sheet_current(ss(current));
        store.set_sheet_open(true);
        self.state.borrow_mut().sheet = Some(kind);
    }

    fn close_sheet(&self) {
        if let Some(ui) = self.ui.upgrade() {
            ui.global::<Store>().set_sheet_open(false);
        }
        self.state.borrow_mut().sheet = None;
    }

    fn sheet_pick(&self, value: String) {
        let kind = self.state.borrow_mut().sheet.take();
        self.close_sheet();
        self.sfx("select");
        match kind {
            Some(SheetFor::Pref(key)) => self.set_pref(&key, &value),
            Some(SheetFor::Filter(key)) => {
                self.state.borrow_mut().filters.insert(key, value);
                self.render_search();
                self.run_search(false);
            }
            None => {}
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn open_dialog(&self, kind: DialogFor, title: &str, text: &str, ok: &str, cancel: &str, input: Option<(&str, &str)>, danger: bool) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        store.set_dialog_title(ss(title));
        store.set_dialog_text(ss(text));
        store.set_dialog_ok(ss(ok));
        store.set_dialog_cancel(ss(cancel));
        store.set_dialog_input(input.is_some());
        store.set_dialog_hint(ss(input.map(|i| i.0).unwrap_or("")));
        store.set_dialog_value(ss(input.map(|i| i.1).unwrap_or("")));
        store.set_dialog_danger(danger);
        store.set_dialog_open(true);
        self.state.borrow_mut().dialog = Some(kind);
    }

    fn dialog_answer(&self, ok: bool, value: String) {
        if let Some(ui) = self.ui.upgrade() {
            ui.global::<Store>().set_dialog_open(false);
        }
        let Some(kind) = self.state.borrow_mut().dialog.take() else { return };
        if !ok {
            return;
        }
        match kind {
            DialogFor::Server => {
                if !value.trim().is_empty() {
                    self.set_host(value.trim());
                }
            }
            DialogFor::SignOut => {
                if let Some(ui) = self.ui.upgrade() {
                    ui.global::<Store>().set_signing_out(true);
                }
                let (api, session) = (self.api(), self.state.borrow().local.session.clone());
                if let (Some(api), Some(session)) = (api, session) {
                    self.runtime.spawn(async move {
                        let _ = api.logout(&session.token).await;
                    });
                }
                self.signed_out();
            }
            DialogFor::ClearHistory => {
                self.state.borrow_mut().local.clear_all_history();
                self.save_local();
                self.render_resume();
                self.render_account();
                self.sync_soon();
            }
            DialogFor::AniList => {
                let token = value.trim().to_owned();
                let (api, session) = (self.api(), self.state.borrow().local.session.clone());
                let (Some(api), Some(session)) = (api, session) else { return };
                if token.is_empty() {
                    return;
                }
                self.task(async move {
                    match api.anilist_connect(&session.token, &token).await {
                        Ok(()) => Event::Toast("@anilist".into()),
                        Err(_) => Event::Toast("AniList didn't accept that token.".into()),
                    }
                });
            }
        }
    }

    // --- the player -----------------------------------------------------------------------------

    /// Open an episode: the player page while the server finds a stream, then
    /// the native player over it. A saved copy plays straight away.
    fn play(&self, target: Play) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        let request = {
            let mut s = self.state.borrow_mut();
            s.play_request += 1;
            s.playing = Some(target.clone());
            s.play_request
        };
        store.set_player_title(ss(format!("{} · EP {}", target.title.to_uppercase(), target.episode)));
        store.set_player_error(SharedString::default());
        store.set_player_status(ss("FINDING SOURCES"));
        let on_player = self.state.borrow().stack.last() == Some(&Page::Player);
        if !on_player {
            self.open_page(Page::Player);
        }
        if let Some(path) = target.local.clone() {
            match url::Url::from_file_path(&path) {
                Ok(url) => self.start_player(&target, url.into(), None),
                Err(_) => store.set_player_error(ss("The saved file could not be found.")),
            }
            return;
        }
        let Some(api) = self.api() else {
            store.set_player_status(ss("NO CONNECTION"));
            store.set_player_error(ss("Can't reach the AniVerse server. Check your connection and try again."));
            return;
        };
        let t = target.clone();
        self.task(async move {
            let result = api.sources(&t.anime_id, t.episode, &t.category, false).await;
            Event::Sources(request, t, result.map_err(|e| e.to_string()))
        });
    }

    fn sources_arrived(&self, request: u64, target: Play, result: Outcome<SourceResponse>) {
        if request != self.state.borrow().play_request {
            return;
        }
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        match result {
            Ok(sources) if !sources.sources.is_empty() => {
                let source = sources.sources[0].clone();
                // The subtitle file timed to this source: the language picked
                // in Settings, else the source's default, else English.
                let tracks: Vec<Value> = source.subtitles.iter().chain(sources.subtitles.iter()).cloned().collect();
                let want = self.state.borrow().settings.sub_lang.to_lowercase();
                let named = |t: &Value| format!("{} {}", str_of(t, "lang"), str_of(t, "label")).to_lowercase();
                let pick = if target.category != "sub" {
                    None
                } else {
                    tracks
                        .iter()
                        .find(|t| !want.is_empty() && named(t).contains(&want))
                        .or_else(|| tracks.iter().find(|t| t.get("default").and_then(Value::as_bool).unwrap_or(false)))
                        .or_else(|| tracks.iter().find(|t| named(t).contains("english")))
                        .or_else(|| tracks.first())
                };
                let subtitle = pick.and_then(|t| t.get("url").and_then(Value::as_str)).map(str::to_owned);
                let markers = |v: Option<&Value>| {
                    let point = |k: &str| v.and_then(|v| v.get(k)).and_then(Value::as_f64).filter(|x| x.is_finite() && *x >= 0.0).map(|x| (x * 1000.0) as u64);
                    (point("start"), point("end"))
                };
                let (is, ie) = markers(sources.intro.as_ref());
                let (os, oe) = markers(sources.outro.as_ref());
                self.start_player(&target, source.url, Some((subtitle, is, ie, os, oe)));
            }
            Ok(sources) => {
                store.set_player_status(ss("NO STREAM FOUND"));
                store.set_player_error(ss(sources.error.unwrap_or_else(|| "No provider has this episode right now. Try again later, or switch between sub and dub.".into())));
                self.sfx("error");
            }
            Err(e) => {
                store.set_player_status(ss("NO STREAM FOUND"));
                store.set_player_error(ss(e));
                self.sfx("error");
            }
        }
    }

    #[allow(clippy::type_complexity)]
    fn start_player(&self, target: &Play, url: String, extra: Option<(Option<String>, Option<u64>, Option<u64>, Option<u64>, Option<u64>)>) {
        let request = {
            let s = self.state.borrow();
            let st = &s.settings;
            let position = s
                .local
                .history
                .iter()
                .find(|h| h.anime_id == target.anime_id && h.episode == target.episode && !h.deleted)
                .map(|h| if h.fraction() > 0.95 { 0 } else { h.position_ms })
                .unwrap_or(0);
            let aired = s.aired.get(&target.anime_id).copied().or_else(|| s.details.get(&target.anime_id).and_then(|d| d.anime.as_ref()).map(Anime::aired_episodes)).unwrap_or(0);
            let (subtitle_url, intro_start_ms, intro_end_ms, outro_start_ms, outro_end_ms) = extra.unwrap_or((None, None, None, None, None));
            PlaybackRequest {
                url,
                title: target.title.clone(),
                anime_id: target.anime_id.clone(),
                cover: target.cover.clone(),
                episode: target.episode,
                position_ms: position,
                speed: st.speed,
                seek_step: st.seek_step,
                subtitle_url,
                subtitle_language: st.sub_lang.clone(),
                subtitle_size: st.sub_size.clone(),
                subtitle_background: st.sub_bg,
                subtitle_color: st.sub_color.clone(),
                intro_start_ms,
                intro_end_ms,
                outro_start_ms,
                outro_end_ms,
                pip_auto: st.pip_auto,
                bg_audio: st.bg_audio,
                category: target.category.clone(),
                has_next: aired == 0 || target.episode < aired,
                local: target.local.is_some(),
            }
        };
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        store.set_player_status(ss("OPENING"));
        if let Err(e) = player::play(request) {
            store.set_player_status(ss("COULD NOT PLAY"));
            store.set_player_error(ss(e.to_string()));
        }
    }

    fn playback(&self, event: PlaybackEvent) {
        if let Some(error) = &event.error {
            if let Some(ui) = self.ui.upgrade() {
                ui.global::<Store>().set_player_error(ss(error));
            }
        }
        if !event.anime_id.is_empty() && event.duration_ms > 0 {
            let finished_now = {
                let mut s = self.state.borrow_mut();
                let (title, cover) = s.local.anime(&event.anime_id).map(|a| (a.title_text(), a.poster_url())).unwrap_or_default();
                s.local.record_progress(HistoryEntry {
                    anime_id: event.anime_id.clone(),
                    episode: event.episode,
                    title: if event.title.is_empty() { title } else { event.title.clone() },
                    cover: if event.cover.is_empty() { cover } else { event.cover.clone() },
                    position_ms: event.position_ms,
                    duration_ms: event.duration_ms,
                    updated_at: chrono::Utc::now().timestamp_millis(),
                    deleted: false,
                    dirty: true,
                });
                s.dirty = true;
                s.last_position = event.position_ms;
                event.duration_ms > 0 && event.position_ms >= event.duration_ms * 9 / 10
            };
            if finished_now && self.state.borrow().settings.auto_delete_watched {
                let key = {
                    let s = self.state.borrow();
                    s.local.downloads.iter().find(|d| d.anime_id == event.anime_id && d.episode == event.episode && d.status == "ready").map(|d| d.key.clone())
                };
                if let Some(key) = key {
                    self.delete_saved(&key);
                }
            }
            self.render_resume();
            self.check_achievements();
        }
        if event.ended {
            // The next episode plays by itself unless this show was told not to.
            let next = {
                let s = self.state.borrow();
                let auto = !s.settings.no_auto_next.contains(&event.anime_id);
                let aired = s.aired.get(&event.anime_id).copied().or_else(|| s.details.get(&event.anime_id).and_then(|d| d.anime.as_ref()).map(Anime::aired_episodes)).unwrap_or(0);
                s.playing.clone().filter(|p| auto && p.anime_id == event.anime_id && p.local.is_none() && event.episode < aired)
            };
            if let Some(mut p) = next {
                p.episode = event.episode + 1;
                self.play(p);
                return;
            }
        }
        if event.closed {
            self.player_closed();
        }
    }

    fn player_closed(&self) {
        let on_player = self.state.borrow().stack.last() == Some(&Page::Player);
        self.state.borrow_mut().playing = None;
        if on_player {
            self.state.borrow_mut().play_request += 1;
            self.finish_back();
        }
        self.render_detail();
        self.render_followed();
        self.sync_soon();
    }

    fn player_command(&self, command: &str) {
        let Some(mut p) = self.state.borrow().playing.clone() else { return };
        match command {
            "next" => {
                p.episode += 1;
                p.local = None;
                self.play(p);
            }
            "switch" => {
                // SUB ⇄ DUB (Tagalog switches back to sub), picking up where it was.
                p.category = if p.category == "sub" { "dub".into() } else { "sub".into() };
                p.local = None;
                {
                    let mut s = self.state.borrow_mut();
                    s.settings.tagalog_shows.retain(|t| *t != p.anime_id);
                }
                self.save_settings();
                self.play(p);
            }
            _ => {}
        }
    }

    // --- syncing, saving, achievements ------------------------------------------------------------

    fn sync(&self) {
        let mut s = self.state.borrow_mut();
        if s.sync_busy {
            return;
        }
        let (Some(api), Some(session)) = (s.api.clone(), s.local.session.clone()) else {
            s.history_syncing = false;
            drop(s);
            if let Some(ui) = self.ui.upgrade() {
                ui.global::<Store>().set_history_syncing(false);
            }
            return;
        };
        s.sync_busy = true;
        s.last_sync = Instant::now();
        let history = s.local.history.clone();
        let watchlist = s.local.watch_entries.clone();
        let token = session.token;
        drop(s);
        self.task(async move {
            let (h, w) = tokio::join!(api.sync_history(&token, &history), api.sync_watchlist(&token, &watchlist));
            Event::Synced(token, h.map_err(|e| e.to_string()), w.map_err(|e| e.to_string()))
        });
    }

    /// A change the user made on purpose goes up soon rather than with the next batch.
    fn sync_soon(&self) {
        let app = self.clone();
        slint::Timer::single_shot(Duration::from_secs(2), move || app.sync());
    }

    /// Badges newly earned, each announced once; the first look announces none.
    fn check_achievements(&self) {
        let fresh: Vec<&'static achievements::BadgeDef> = {
            let mut s = self.state.borrow_mut();
            let now = achievements::unlocked(&achievements::stats(&s.local.history));
            let seen = s.settings.badges_seen.clone();
            if seen.as_ref().map(|v| v.len()) == Some(now.len()) && seen.as_ref().map(|v| now.iter().all(|n| v.iter().any(|x| x == n))).unwrap_or(false) {
                return;
            }
            s.settings.badges_seen = Some(now.iter().map(|x| x.to_string()).collect());
            match seen {
                None => Vec::new(),
                Some(seen) => achievements::BADGES.iter().filter(|b| now.contains(&b.id) && !seen.iter().any(|x| x == b.id)).collect(),
            }
        };
        self.save_settings();
        for b in fresh {
            self.sfx("achieve");
            self.toast(format!("Achievement unlocked! {} — {}", b.name, b.text));
        }
    }

    // --- textures -------------------------------------------------------------------------------

    /// Screentone and focus lines for the window's size and pixel density.
    fn refresh_textures(&self) {
        let Some(ui) = self.ui.upgrade() else { return };
        let scale = ui.window().scale_factor().max(1.0);
        let size = ui.window().size();
        let (w, h) = (size.width as f32 / scale, size.height as f32 / scale);
        if w < 50.0 || h < 50.0 {
            return;
        }
        let top = ui.global::<ui::Theme>().get_safe_top();
        let key = (w.round() as u32, h.round() as u32, (scale * 100.0) as u32, top.round() as u32);
        if self.state.borrow().textures_key == key {
            return;
        }
        let s = scale.min(3.5);
        let tex = ui.global::<Tex>();
        let tone_scale = (s * 100.0) as u32;
        if self.state.borrow().tone_scale != tone_scale {
            tex.set_paper_top(textures::halftone(600.0, 140.0, s, Tone::fade(TONE, 8.0, 0.16, 0.0, Axis::Vertical)));
            tex.set_paper_bottom(textures::halftone(600.0, 110.0, s, Tone::fade(TONE, 8.0, 0.0, 0.14, Axis::Vertical)));
            tex.set_cover_foot(textures::halftone(600.0, 28.0, s, Tone::fade(INK, 5.0, 0.0, 0.5, Axis::Vertical)));
            tex.set_bevel(textures::halftone(200.0, 60.0, s, Tone::fade(INK, 6.0, 0.0, 0.22, Axis::Vertical)));
            tex.set_tone(textures::halftone(420.0, 260.0, s, Tone::flat(TONE, 8.0, 0.32)));
            tex.set_bar_tone(textures::halftone(600.0, 14.0, s, Tone::flat(TONE, 4.0, 0.25)));
            self.state.borrow_mut().tone_scale = tone_scale;
            self.art.borrow_mut().scale = s.min(3.0);
        }
        // the spotlight's inside: list padding, slide padding and its border off
        let (hw, hh) = ((w - 49.0).max(100.0), 221.0);
        tex.set_hero_ground(textures::halftone(hw, hh, s, Tone::fade(TONE, 7.0, 0.05, 0.3, Axis::Horizontal)));
        let lines = ui.global::<Lines>();
        lines.set_hero(ss(textures::focus_lines(hw, hh, hw * 0.725, hh * 0.5, 3, 60, 0.5)));
        lines.set_hero_w(hw);
        lines.set_hero_h(hh);
        // the detail banner's lines: drawn round its middle, spilling over the header
        let (bw, bh) = (w - 30.0, 122.0);
        let header_h = top + 360.0;
        lines.set_header(ss(textures::focus_lines(bw, bh, 15.0 + bw * 0.65, top + 55.0 + bh * 0.6, 5, 70, 0.55)));
        lines.set_header_w(w);
        lines.set_header_h(header_h);
        lines.set_intro_a(ss(textures::focus_lines(w, h, w * 0.5, h * 0.41, 0, 110, 0.33)));
        lines.set_intro_b(ss(textures::focus_lines(w, h, w * 0.5, h * 0.41, 1, 110, 0.33)));
        lines.set_intro_c(ss(textures::focus_lines(w, h, w * 0.5, h * 0.41, 2, 110, 0.33)));
        lines.set_impact(ss(textures::focus_lines(w, h, w * 0.5, h * 0.5, 9, 120, 0.2)));
        lines.set_screen_w(w);
        lines.set_screen_h(h);
        self.state.borrow_mut().textures_key = key;
    }

    // --- background results -----------------------------------------------------------------------

    fn handle(&self, event: Event) {
        let Some(ui) = self.ui.upgrade() else { return };
        let store = ui.global::<Store>();
        match event {
            Event::Connected(result) => self.connected(result),
            Event::Home(result) => {
                match result {
                    Ok(home) => {
                        {
                            let mut s = self.state.borrow_mut();
                            for a in home.popular.iter().chain(&home.trending).chain(&home.latest).chain(&home.tagalog) {
                                s.local.cache_anime(a.clone());
                            }
                            s.home = Some(home);
                            s.home_failed = false;
                            s.dirty = true;
                        }
                        self.load_because();
                    }
                    Err(e) => {
                        let had = self.state.borrow().home.is_some();
                        self.state.borrow_mut().home_failed = !had;
                        self.toast(e);
                    }
                }
                self.render_home();
            }
            Event::Because(id, title, recs) => {
                {
                    let mut s = self.state.borrow_mut();
                    s.because.retain(|(i, _, _)| *i != id);
                    s.because.push((id, title, recs));
                    // most recent first, as the history has them
                    let order: Vec<String> = s.local.latest_history().iter().map(|e| e.anime_id.clone()).collect();
                    s.because.sort_by_key(|(i, _, _)| order.iter().position(|o| o == i).unwrap_or(usize::MAX));
                }
                self.render_home();
            }
            Event::Info(id, result) => {
                if let Ok(anime) = &result {
                    let mut s = self.state.borrow_mut();
                    s.aired.insert(id.clone(), anime.aired_episodes());
                    if anime.status_code() == "RELEASING" {
                        s.releasing.insert(id.clone());
                    } else {
                        s.releasing.remove(&id);
                    }
                    s.local.cache_anime(anime.clone());
                    s.dirty = true;
                }
                let is_detail = {
                    let mut s = self.state.borrow_mut();
                    if let Some(d) = s.details.get_mut(&id) {
                        match &result {
                            Ok(anime) => {
                                d.anime = Some(anime.clone());
                                d.error = None;
                            }
                            Err(e) if d.anime.is_none() => d.error = Some(e.clone()),
                            Err(_) => {}
                        }
                    }
                    s.detail_id == id
                };
                if is_detail {
                    self.render_detail();
                }
                self.render_followed();
            }
            Event::Episodes(id, list) => {
                let is_detail = {
                    let mut s = self.state.borrow_mut();
                    if let Some(d) = s.details.get_mut(&id) {
                        d.episodes = list.into_iter().map(|e| (e.number, e)).collect();
                    }
                    s.detail_id == id
                };
                if is_detail {
                    self.render_episodes();
                }
            }
            Event::Extra(id, extra) => {
                let is_detail = {
                    let mut s = self.state.borrow_mut();
                    if let Some(d) = s.details.get_mut(&id) {
                        d.extra = extra;
                    }
                    s.detail_id == id
                };
                if is_detail {
                    self.render_detail();
                }
            }
            Event::Tagalog(id, value) => {
                let is_detail = {
                    let mut s = self.state.borrow_mut();
                    if let Some(d) = s.details.get_mut(&id) {
                        d.tagalog = value;
                    }
                    s.detail_id == id
                };
                if is_detail {
                    self.render_detail();
                }
            }
            Event::Search(id, result) => {
                if id != self.state.borrow().search_request {
                    return;
                }
                store.set_search_loading(false);
                match result {
                    Ok(items) => {
                        let mut s = self.state.borrow_mut();
                        for a in &items {
                            s.local.cache_anime(a.clone());
                        }
                        s.results = items;
                        s.search_more = false;
                    }
                    Err(e) => {
                        self.state.borrow_mut().results.clear();
                        self.toast(e);
                    }
                }
                store.set_searched(true);
                self.render_search();
            }
            Event::Filter(id, more, result) => {
                if id != self.state.borrow().search_request {
                    return;
                }
                store.set_search_loading(false);
                store.set_loading_more(false);
                let body = result.unwrap_or_default();
                let media: Vec<Anime> = body.get("media").and_then(Value::as_array).map(|a| a.iter().filter_map(|m| serde_json::from_value(m.clone()).ok()).collect()).unwrap_or_default();
                {
                    let mut s = self.state.borrow_mut();
                    for a in &media {
                        s.local.cache_anime(a.clone());
                    }
                    if more {
                        s.results.extend(media);
                        s.search_page += 1;
                    } else {
                        s.results = media;
                        s.search_page = 1;
                    }
                    s.search_more = body.get("hasNextPage").and_then(Value::as_bool).unwrap_or(false);
                }
                store.set_searched(true);
                self.render_search();
            }
            Event::Schedule(result) => {
                {
                    let mut s = self.state.borrow_mut();
                    s.schedule_loading = false;
                    s.schedule = Some(result.unwrap_or_default());
                    s.day.clear();
                }
                self.render_schedule();
            }
            Event::GenreArt(value) => {
                {
                    let mut s = self.state.borrow_mut();
                    s.genre_art_loading = false;
                    s.genre_art = Some(value);
                }
                self.render_genres();
            }
            Event::Genre(id, page, result) => {
                if id != self.state.borrow().genre_request {
                    return;
                }
                {
                    let mut s = self.state.borrow_mut();
                    s.genre_loading = false;
                    let batch = result.unwrap_or_default();
                    if batch.len() < 24 {
                        s.genre_end = true;
                    }
                    for a in batch {
                        // the API can repeat entries across pages
                        if s.genre_seen.insert(a.id_string()) {
                            s.local.cache_anime(a.clone());
                            s.genre_items.push(a);
                        }
                    }
                    s.genre_page = page + 1;
                }
                self.render_genre();
            }
            Event::Art(key, buffer) => self.arrived(key, buffer),
            Event::AuthConfig(result) => {
                if let Ok(config) = result {
                    self.state.borrow_mut().auth_config = Some(config);
                }
                self.render_account();
            }
            Event::Auth(result) => {
                store.set_auth_busy(false);
                match result {
                    Ok(session) => {
                        let name = session.user.display_name.clone();
                        self.state.borrow_mut().local.session = Some(session);
                        store.set_password(SharedString::default());
                        store.set_confirm(SharedString::default());
                        store.set_auth_error(SharedString::default());
                        self.save_local();
                        self.render_account();
                        self.load_tracking();
                        self.sync();
                        self.toast(if name.is_empty() { "Signed in".to_string() } else { format!("Signed in as {name}") });
                    }
                    Err(e) => store.set_auth_error(ss(e)),
                }
            }
            Event::Me(result, expired) => {
                match result {
                    Ok(user) => {
                        if let Some(session) = &mut self.state.borrow_mut().local.session {
                            session.user = user;
                        }
                    }
                    Err(_) if expired => self.state.borrow_mut().local.session = None,
                    Err(_) => {}
                }
                self.save_local();
                self.render_account();
                self.sync();
            }
            Event::Synced(token, history, watchlist) => {
                {
                    let mut s = self.state.borrow_mut();
                    s.sync_busy = false;
                    s.history_syncing = false;
                    if s.local.session.as_ref().map(|x| x.token.as_str()) == Some(token.as_str()) {
                        if let Ok(h) = history {
                            s.local.merge_history(h);
                        }
                        if let Ok(w) = watchlist {
                            s.local.merge_watchlist(w);
                        }
                    }
                }
                store.set_history_syncing(false);
                self.save_local();
                self.render_resume();
                self.render_followed();
                self.render_account();
            }
            Event::Tracking(cfg, status) => {
                self.state.borrow_mut().tracking = (cfg, status);
                self.render_account();
            }
            Event::Toast(text) => match text.as_str() {
                "@mal" => self.toast_with("Finish on the MyAnimeList page, then come back here.", Some(ToastAction::RefreshTracking), "REFRESH"),
                "@anilist" => {
                    self.sfx("achieve");
                    self.toast("AniList connected.");
                    self.load_tracking();
                }
                _ => self.toast(text),
            },
            Event::Sources(request, target, result) => self.sources_arrived(request, target, result),
            Event::Download(key, bytes, progress, outcome) => {
                let finished = outcome.is_some();
                {
                    let mut s = self.state.borrow_mut();
                    if let Some(d) = s.local.downloads.iter_mut().find(|d| d.key == key) {
                        if d.status == "downloading" || finished {
                            d.bytes = bytes.max(d.bytes);
                            d.progress = progress;
                            if let Some(result) = outcome {
                                match result {
                                    Ok(path) => {
                                        d.path = path;
                                        d.status = "ready".into();
                                        d.progress = 1.0;
                                        d.bytes = bytes;
                                    }
                                    Err(e) => {
                                        d.status = "failed".into();
                                        d.error = e;
                                    }
                                }
                            }
                        }
                    }
                    if finished {
                        s.cancels.remove(&key);
                    }
                    s.dirty = true;
                }
                self.render_saved();
                if finished {
                    self.render_episodes();
                    self.pump_downloads();
                } else {
                    // progress shows on the anime page's rows too, not too often
                    patch(&self.models.episodes, |r| {
                        let want = format!("{:.0}%", progress * 100.0);
                        if key.starts_with(&format!("{}-{}-", self.state.borrow().detail_id, r.number)) && r.download.as_str() != want {
                            r.download = ss(want);
                            true
                        } else {
                            false
                        }
                    });
                }
            }
        }
    }

    /// Every 50 ms: background results, the Android host, the player,
    /// debounced searches, the toast's time, textures, saving and syncing.
    fn tick(&self, rx: &mpsc::Receiver<(u64, Event)>) {
        let epoch = self.state.borrow().epoch;
        for (e, event) in rx.try_iter().take(32) {
            if e == 0 || e == epoch {
                self.handle(event);
            }
        }
        for event in player::drain_host_events() {
            match event {
                HostEvent::Back => self.back(),
                // The window covers the whole screen (see run()); the bars are
                // kept clear here, the way Flutter's SafeArea does.
                HostEvent::Insets { top, bottom } => {
                    if let Some(ui) = self.ui.upgrade() {
                        let theme = ui.global::<ui::Theme>();
                        theme.set_safe_top(top.max(0.0));
                        theme.set_safe_bottom(bottom.max(0.0));
                    }
                }
                HostEvent::Command(c) => self.player_command(&c),
            }
        }
        for event in player::drain_events() {
            self.playback(event);
        }
        let due = self.state.borrow().debounce.map(|d| Instant::now() >= d).unwrap_or(false);
        if due {
            self.run_search(false);
        }
        let toast_over = self.state.borrow().toast_until.map(|t| Instant::now() >= t).unwrap_or(false);
        if toast_over {
            self.state.borrow_mut().toast_until = None;
            if let Some(ui) = self.ui.upgrade() {
                ui.global::<Store>().set_toast_visible(false);
            }
        }
        self.refresh_textures();
        let (save, sync) = {
            let s = self.state.borrow();
            (s.dirty && s.last_save.elapsed() > Duration::from_secs(2), s.local.session.is_some() && s.local.history.iter().any(|h| h.dirty) && s.last_sync.elapsed() > Duration::from_secs(20))
        };
        if save {
            self.state.borrow_mut().dirty = false;
            self.save_local();
        }
        if sync {
            self.sync();
        }
    }

    fn wire(&self, ui: &MainWindow) {
        let actions = ui.global::<Actions>();
        macro_rules! on {
            ($name:ident, |$app:ident $(, $arg:ident)*| $body:expr) => {{
                let $app = self.clone();
                actions.$name(move |$($arg),*| $body);
            }};
        }
        on!(on_sfx, |a, name| a.sfx(name.as_str()));
        on!(on_select_tab, |a, i| a.select_tab(i));
        on!(on_back, |a| a.back());
        on!(on_open_page, |a, page| {
            let page = match page.as_str() {
                "settings" => Page::Settings,
                "account" => Page::Account,
                "history" => Page::History,
                "genres" => Page::Genres,
                _ => return,
            };
            a.open_page(page);
        });
        on!(on_open_anime, |a, id| a.open_anime(id.as_str()));
        on!(on_open_resume, |a, id| {
            let entry = a.state.borrow().local.latest_history().into_iter().find(|e| e.anime_id == id.as_str()).cloned();
            if let Some(e) = entry {
                let category = a.category_for(&e.anime_id);
                let (title, cover) = (e.title.clone(), e.cover.clone());
                a.play(Play { anime_id: e.anime_id, episode: e.episode, category, title, cover, local: None });
            }
        });
        on!(on_refresh_home, |a| {
            a.state.borrow_mut().home_failed = false;
            if a.api().is_some() {
                a.load_home();
            } else {
                a.connect();
            }
            a.render_home();
        });
        on!(on_toggle_follow, |a| a.toggle_follow());
        on!(on_play_episode, |a, n| a.play_episode(n));
        on!(on_download_episode, |a, n| {
            let Some((id, d)) = a.detail() else { return };
            let Some(anime) = d.anime else { return };
            let category = a.category_for(&id);
            let ok = a.enqueue(&id, n.max(1) as u32, &category, &anime.title_text(), &anime.poster_url());
            a.sfx("select");
            a.toast(if ok { format!("Episode {n} is downloading. It will be under Saved.") } else { format!("Episode {n} is already saved or on its way.") });
            a.render_episodes();
        });
        on!(on_download_all, |a| {
            let Some((id, d)) = a.detail() else { return };
            let Some(anime) = d.anime else { return };
            let aired = anime.aired_episodes();
            let category = a.category_for(&id);
            let mut n = 0;
            for ep in 1..=aired {
                if a.enqueue(&id, ep, &category, &anime.title_text(), &anime.poster_url()) {
                    n += 1;
                }
            }
            a.sfx("select");
            a.toast(if n == 0 { "Every aired episode is already saved or on its way.".to_string() } else { format!("{n} episode{} queued. They will be under Saved.", if n == 1 { "" } else { "s" }) });
            a.render_episodes();
        });
        on!(on_toggle_episode_view, |a| a.toggle_episode_view());
        on!(on_play_tagalog, |a| a.play_tagalog());
        on!(on_open_trailer, |a| a.open_trailer());
        on!(on_episodes_window, |a, first, count| {
            let window = (first.max(0) as usize, count.clamp(1, 200) as usize);
            if a.state.borrow().window != window {
                a.state.borrow_mut().window = window;
                a.render_episodes();
            }
        });
        on!(on_search_edited, |a, text| a.search_edited(text.to_string()));
        on!(on_search_submit, |a, text| {
            a.state.borrow_mut().search_text = text.to_string();
            a.add_recent();
            a.run_search(false);
        });
        on!(on_search_clear, |a| {
            a.state.borrow_mut().search_text.clear();
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<Store>().set_search_text(SharedString::default());
            }
            a.run_search(false);
        });
        on!(on_pick_filter, |a, key| {
            let defs = filter_defs();
            let Some((_, label, options)) = defs.iter().find(|(k, _, _)| *k == key.as_str()) else { return };
            let current = a.state.borrow().filters.get(key.as_str()).cloned().unwrap_or_default();
            a.open_sheet(SheetFor::Filter(key.to_string()), label, options, &current);
        });
        on!(on_clear_filters, |a| {
            a.state.borrow_mut().filters.clear();
            a.render_search();
            a.run_search(false);
        });
        on!(on_load_more, |a| a.run_search(true));
        on!(on_run_recent, |a, q| {
            let original = a.state.borrow().settings.recent_searches.iter().find(|r| r.to_uppercase() == q.as_str()).cloned().unwrap_or_else(|| q.to_string());
            a.state.borrow_mut().search_text = original.clone();
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<Store>().set_search_text(ss(&original));
            }
            a.run_search(false);
        });
        on!(on_clear_recent, |a| {
            a.state.borrow_mut().settings.recent_searches.clear();
            a.save_settings();
            a.render_search();
        });
        on!(on_select_day, |a, key| {
            a.sfx("select");
            a.state.borrow_mut().day = key.to_string();
            a.render_schedule();
        });
        on!(on_open_airing, |a, i| a.open_airing(i.max(0) as usize));
        on!(on_follow_airing, |a, i| a.follow_airing(i.max(0) as usize));
        on!(on_retry_schedule, |a| a.load_schedule(true));
        on!(on_open_followed, |a, i| {
            if let Some(e) = a.followed_at(i.max(0) as usize) {
                a.open_anime(&e.anime_id);
            }
        });
        on!(on_play_followed, |a, i| {
            let Some(e) = a.followed_at(i.max(0) as usize) else { return };
            let next = {
                let s = a.state.borrow();
                let aired = s.aired.get(&e.anime_id).copied().unwrap_or(0);
                let watched = s.local.episodes_of(&e.anime_id).keys().copied().max().unwrap_or(0);
                if aired == 0 { 1 } else { (watched + 1).clamp(1, aired) }
            };
            let category = a.category_for(&e.anime_id);
            a.play(Play { anime_id: e.anime_id.clone(), episode: next, category, title: e.title.clone(), cover: e.cover.clone(), local: None });
        });
        on!(on_mute_followed, |a, i| {
            let Some(e) = a.followed_at(i.max(0) as usize) else { return };
            let on = {
                let mut s = a.state.borrow_mut();
                let muted = s.settings.alerts_muted.contains(&e.anime_id);
                if muted {
                    s.settings.alerts_muted.retain(|x| *x != e.anime_id);
                } else {
                    s.settings.alerts_muted.push(e.anime_id.clone());
                }
                muted
            };
            a.sfx("select");
            a.save_settings();
            a.render_followed();
            a.toast(if on { format!("Alerts back on for {}.", e.title) } else { format!("No more alerts for {}.", e.title) });
        });
        on!(on_remove_followed, |a, i| {
            let Some(e) = a.followed_at(i.max(0) as usize) else { return };
            a.sfx("slash");
            a.state.borrow_mut().local.unfollow(&e.anime_id);
            a.save_local();
            a.render_followed();
            a.sync_soon();
        });
        on!(on_play_saved, |a, i| {
            let item = a.state.borrow().local.downloads.get(i.max(0) as usize).cloned();
            if let Some(d) = item.filter(|d| d.status == "ready") {
                a.play(Play { anime_id: d.anime_id.clone(), episode: d.episode, category: d.category.clone(), title: d.title.clone(), cover: d.cover.clone(), local: Some(d.path.clone()) });
            }
        });
        on!(on_retry_saved, |a, i| {
            let item = a.state.borrow().local.downloads.get(i.max(0) as usize).cloned();
            if let Some(d) = item {
                a.enqueue(&d.anime_id, d.episode, &d.category, &d.title, &d.cover);
            }
        });
        on!(on_delete_saved, |a, i| {
            let key = a.state.borrow().local.downloads.get(i.max(0) as usize).map(|d| d.key.clone());
            if let Some(key) = key {
                a.delete_saved(&key);
            }
        });
        on!(on_open_genre, |a, name| {
            let original = GENRES.iter().find(|g| g.to_uppercase() == name.as_str()).map(|g| g.to_string()).unwrap_or_else(|| name.to_string());
            a.open_page(Page::Genre(original));
        });
        on!(on_toggle_genre_view, |a| {
            let list = {
                let mut s = a.state.borrow_mut();
                s.settings.browse_view = if s.settings.browse_view == "list" { "grid" } else { "list" }.into();
                s.settings.browse_view == "list"
            };
            a.save_settings();
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<Store>().set_genre_list(list);
            }
        });
        on!(on_genre_more, |a| a.genre_more());
        on!(on_sync_history, |a| a.sync_history_now());
        on!(on_clear_history, |a| {
            let signed_in = a.state.borrow().local.session.is_some();
            a.open_dialog(DialogFor::ClearHistory, "CLEAR HISTORY?", if signed_in { "This removes it from your account on every device." } else { "This removes it from this phone." }, "CLEAR", "CANCEL", None, true);
        });
        on!(on_remove_history, |a, id| {
            let title = a.state.borrow().local.latest_history().into_iter().find(|e| e.anime_id == id.as_str()).map(|e| e.title.clone()).unwrap_or_default();
            a.state.borrow_mut().local.remove_history(id.as_str());
            a.sfx("slash");
            a.save_local();
            a.render_resume();
            a.sync_soon();
            a.toast(if title.is_empty() { "Removed from history".to_string() } else { format!("Removed {title}") });
        });
        on!(on_history_details, |a, id| a.open_anime(id.as_str()));
        on!(on_auth_mode, |a, creating| {
            if let Some(ui) = a.ui.upgrade() {
                let store = ui.global::<Store>();
                if store.get_auth_busy() || store.get_creating() == creating {
                    return;
                }
                store.set_creating(creating);
                store.set_auth_error(SharedString::default());
                store.set_confirm(SharedString::default());
                store.set_hide_password(true);
            }
        });
        on!(on_auth_submit, |a| a.auth_submit());
        on!(on_google, |a| a.toast("Google sign-in isn't available in this build. Use your AniVerse username and password."));
        on!(on_sign_out, |a| a.open_dialog(DialogFor::SignOut, "SIGN OUT?", "Your history stays in your account. It will be removed from this phone until you sign in again.", "SIGN OUT", "CANCEL", None, true));
        on!(on_share_card, |a| a.toast("Sharing the card isn't available in this build yet."));
        on!(on_tracking, |a, id| a.tracking(id.as_str()));
        on!(on_toggle_pref, |a, key| a.toggle_pref(key.as_str()));
        on!(on_choose_pref, |a, key| a.choose_pref(key.as_str()));
        on!(on_edit_server, |a| a.edit_server());
        on!(on_replay_intro, |a| {
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<Store>().set_intro(true);
            }
        });
        on!(on_sheet_pick, |a, value| a.sheet_pick(value.to_string()));
        on!(on_sheet_dismiss, |a| a.close_sheet());
        on!(on_dialog_answer, |a, ok, value| a.dialog_answer(ok, value.to_string()));
        on!(on_toast_tapped, |a| {
            let action = a.state.borrow_mut().toast_action.take();
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<Store>().set_toast_visible(false);
            }
            if let Some(ToastAction::RefreshTracking) = action {
                a.load_tracking();
            }
        });
        on!(on_intro_done, |a| {
            if let Some(ui) = a.ui.upgrade() {
                ui.global::<Store>().set_intro(false);
            }
        });
        on!(on_player_retry, |a| {
            let target = a.state.borrow().playing.clone();
            if let Some(t) = target {
                a.play(t);
            }
        });
    }
}

trait ParseHex {
    fn parse_hex(&self) -> Option<Color>;
}
impl ParseHex for str {
    fn parse_hex(&self) -> Option<Color> {
        let h = self.trim_start_matches('#');
        let v = u32::from_str_radix(h, 16).ok()?;
        match h.len() {
            6 => Some(Color::from_argb_encoded(0xFF00_0000 | v)),
            8 => Some(Color::from_argb_encoded(v)),
            _ => None,
        }
    }
}

/// Fetch a picture (from the disk cache when it is there), decode it within
/// limits and size it for where it is drawn.
async fn load_art(url: &str, kind: Art, scale: f32) -> Option<SharedPixelBuffer<Rgba8Pixel>> {
    use std::hash::{Hash, Hasher};
    let mut hash = std::collections::hash_map::DefaultHasher::new();
    url.hash(&mut hash);
    let dir = storage::data_dir().join("covers");
    let path = dir.join(format!("{:x}.image", hash.finish()));
    let bytes = match tokio::fs::read(&path).await {
        Ok(bytes) if !bytes.is_empty() => bytes,
        _ => {
            let client = reqwest::Client::builder().timeout(Duration::from_secs(20)).build().ok()?;
            let mut response = client.get(url).send().await.ok()?.error_for_status().ok()?;
            let mut bytes = Vec::new();
            while let Some(chunk) = response.chunk().await.ok()? {
                if bytes.len() + chunk.len() > 12 * 1024 * 1024 {
                    return None;
                }
                bytes.extend_from_slice(&chunk);
            }
            let _ = tokio::fs::create_dir_all(&dir).await;
            let _ = tokio::fs::write(&path, &bytes).await;
            bytes
        }
    };
    tokio::task::spawn_blocking(move || {
        let mut reader = image::ImageReader::new(std::io::Cursor::new(bytes)).with_guessed_format().ok()?;
        let mut limits = image::Limits::default();
        limits.max_image_width = Some(8192);
        limits.max_image_height = Some(8192);
        limits.max_alloc = Some(96 * 1024 * 1024);
        reader.limits(limits);
        let decoded = reader.decode().ok()?;
        let buffer = match kind {
            Art::Slant => textures::slant_cover(&decoded.into_rgba8(), 150.0, 221.0, 28.0, scale),
            Art::Banner => {
                let img = decoded.thumbnail(800, 800).into_rgba8();
                SharedPixelBuffer::clone_from_slice(img.as_raw(), img.width(), img.height())
            }
            Art::Cover => {
                let img = decoded.thumbnail(320, 640).into_rgba8();
                SharedPixelBuffer::clone_from_slice(img.as_raw(), img.width(), img.height())
            }
        };
        Some(buffer)
    })
    .await
    .ok()
    .flatten()
}

pub fn run_desktop() -> anyhow::Result<()> {
    run()
}
pub fn run_android() -> anyhow::Result<()> {
    run()
}

fn run() -> anyhow::Result<()> {
    let ui = MainWindow::new()?;
    // Slint 1.9 places a non-fullscreen Android view from getWindowVisibleDisplayFrame,
    // which lands ~33 dp low on edge-to-edge Android 15+. Fullscreen draws edge to edge
    // and the screens keep clear of the bars with Theme.safe-top/bottom.
    #[cfg(target_os = "android")]
    ui.window().set_fullscreen(true);
    let runtime = Arc::new(tokio::runtime::Builder::new_multi_thread().worker_threads(4).enable_all().build()?);
    let (tx, rx) = mpsc::channel();
    let settings = Settings::load();
    let mut local = LocalData::load();
    for d in &mut local.downloads {
        if d.status == "queued" || d.status == "downloading" {
            d.status = "failed".into();
            d.error = "Interrupted. Tap retry to save it again.".into();
        }
    }
    let models = Rc::new(Models {
        resume: Rc::new(VecModel::default()),
        slides: Rc::new(VecModel::default()),
        shelves: Rc::new(VecModel::default()),
        shelf_items: RefCell::new(Vec::new()),
        detail_genres: Rc::new(VecModel::default()),
        detail_facts: Rc::new(VecModel::default()),
        episodes: Rc::new(VecModel::default()),
        characters: Rc::new(VecModel::default()),
        related: Rc::new(VecModel::default()),
        recommended: Rc::new(VecModel::default()),
        results: Rc::new(VecModel::default()),
        filters: Rc::new(VecModel::default()),
        recent: Rc::new(VecModel::default()),
        days: Rc::new(VecModel::default()),
        airing: Rc::new(VecModel::default()),
        followed: Rc::new(VecModel::default()),
        saved: Rc::new(VecModel::default()),
        genres: Rc::new(VecModel::default()),
        genre_items: Rc::new(VecModel::default()),
        history: Rc::new(VecModel::default()),
        badges: Rc::new(VecModel::default()),
        sheet: Rc::new(VecModel::default()),
    });
    {
        let store = ui.global::<Store>();
        store.set_resume(ModelRc::from(models.resume.clone()));
        store.set_slides(ModelRc::from(models.slides.clone()));
        store.set_shelves(ModelRc::from(models.shelves.clone()));
        store.set_detail_genres(ModelRc::from(models.detail_genres.clone()));
        store.set_detail_facts(ModelRc::from(models.detail_facts.clone()));
        store.set_episodes(ModelRc::from(models.episodes.clone()));
        store.set_characters(ModelRc::from(models.characters.clone()));
        store.set_related(ModelRc::from(models.related.clone()));
        store.set_recommended(ModelRc::from(models.recommended.clone()));
        store.set_results(ModelRc::from(models.results.clone()));
        store.set_filters(ModelRc::from(models.filters.clone()));
        store.set_recent_rows(ModelRc::from(models.recent.clone()));
        store.set_days(ModelRc::from(models.days.clone()));
        store.set_airing(ModelRc::from(models.airing.clone()));
        store.set_followed(ModelRc::from(models.followed.clone()));
        store.set_saved(ModelRc::from(models.saved.clone()));
        store.set_genres(ModelRc::from(models.genres.clone()));
        store.set_genre_items(ModelRc::from(models.genre_items.clone()));
        store.set_history(ModelRc::from(models.history.clone()));
        store.set_badges(ModelRc::from(models.badges.clone()));
        store.set_sheet_options(ModelRc::from(models.sheet.clone()));
        store.set_intro(settings.intro && std::env::var_os("ANIVERSE_NO_INTRO").is_none());
        store.set_detail_list_view(settings.ep_view == "list");
        store.set_genre_list(settings.browse_view == "list");
    }
    let app = App {
        ui: ui.as_weak(),
        runtime,
        tx,
        slots: Arc::new(Semaphore::new(6)),
        models,
        art: Rc::new(RefCell::new(ArtCache { images: HashMap::new(), order: VecDeque::new(), asked: HashSet::new(), failed: HashSet::new(), scale: 2.0 })),
        state: Rc::new(RefCell::new(State {
            settings,
            local,
            api: None,
            epoch: 1,
            connecting: false,
            home: None,
            home_failed: false,
            because: Vec::new(),
            because_asked: Vec::new(),
            stack: Vec::new(),
            closing: false,
            details: HashMap::new(),
            detail_id: String::new(),
            window: (0, 30),
            search_text: String::new(),
            filters: HashMap::new(),
            results: Vec::new(),
            search_page: 1,
            search_more: false,
            search_request: 0,
            debounce: None,
            schedule: None,
            schedule_loading: false,
            day: String::new(),
            genre_art: None,
            genre_art_loading: false,
            genre_name: String::new(),
            genre_items: Vec::new(),
            genre_seen: HashSet::new(),
            genre_page: 1,
            genre_loading: false,
            genre_end: false,
            genre_request: 0,
            aired: HashMap::new(),
            releasing: HashSet::new(),
            info_asked: HashSet::new(),
            auth_config: None,
            tracking: (Value::Null, Value::Null),
            sheet: None,
            dialog: None,
            toast_until: None,
            toast_action: None,
            play_request: 0,
            playing: None,
            last_position: 0,
            cancels: HashMap::new(),
            sync_busy: false,
            history_syncing: false,
            last_sync: Instant::now(),
            dirty: false,
            last_save: Instant::now(),
            textures_key: (0, 0, 0, 0),
            tone_scale: 0,
        })),
    };
    app.wire(&ui);
    app.apply_look();
    app.render_prefs();
    app.render_home();
    app.render_search();
    app.render_followed();
    app.render_saved();
    app.render_account();
    app.render_genres();
    app.check_achievements();
    let timer = slint::Timer::default();
    {
        let tick = app.clone();
        timer.start(slint::TimerMode::Repeated, Duration::from_millis(50), move || tick.tick(&rx));
    }
    app.connect();

    // Local visual checks: ANIVERSE_PREVIEW=tab:2 | page:settings | detail:<id> | genre:<name>,
    // then ANIVERSE_SCREENSHOT=<png> after ANIVERSE_SCREENSHOT_DELAY seconds. No effect otherwise.
    let preview = slint::Timer::default();
    if let Some(scroll) = std::env::var("ANIVERSE_PREVIEW_SCROLL").ok().and_then(|v| v.parse::<f32>().ok()) {
        ui.global::<Store>().set_preview_scroll(scroll);
    }
    if let Ok(spec) = std::env::var("ANIVERSE_PREVIEW") {
        if let Ok(style) = std::env::var("ANIVERSE_PREVIEW_STYLE") {
            app.set_pref("look", &style);
        }
        let a = app.clone();
        preview.start(slint::TimerMode::SingleShot, Duration::from_millis(2500), move || {
            let (kind, value) = spec.split_once(':').unwrap_or((spec.as_str(), ""));
            match kind {
                "tab" => a.select_tab(value.parse().unwrap_or(0)),
                "page" => match value {
                    "settings" => a.open_page(Page::Settings),
                    "account" => a.open_page(Page::Account),
                    "history" => a.open_page(Page::History),
                    "genres" => a.open_page(Page::Genres),
                    _ => {}
                },
                "detail" => a.open_anime(value),
                "genre" => a.open_page(Page::Genre(value.to_owned())),
                "toast" => a.toast(value.to_owned()),
                "sheet" => a.choose_pref(value),
                _ => {}
            }
        });
    }
    let capture = slint::Timer::default();
    if let Ok(path) = std::env::var("ANIVERSE_SCREENSHOT") {
        let delay = std::env::var("ANIVERSE_SCREENSHOT_DELAY").ok().and_then(|v| v.parse().ok()).unwrap_or(12);
        let weak = ui.as_weak();
        capture.start(slint::TimerMode::SingleShot, Duration::from_secs(delay), move || {
            if let Some(ui) = weak.upgrade() {
                match ui.window().take_snapshot() {
                    Ok(p) => {
                        let _ = image::save_buffer(&path, p.as_bytes(), p.width(), p.height(), image::ColorType::Rgba8);
                    }
                    Err(e) => eprintln!("Screenshot failed: {e}"),
                }
                let _ = slint::quit_event_loop();
            }
        });
    }
    // One log line when the first frame is on screen, for timing cold starts
    // (`adb logcat -s AniVerse`; stderr on desktop).
    let first_frame = std::cell::Cell::new(false);
    let _ = ui.window().set_rendering_notifier(move |state, _| {
        if matches!(state, slint::RenderingState::AfterRendering) && !first_frame.replace(true) {
            log_line("first frame");
        }
    });
    ui.run()?;
    app.save_local();
    app.save_settings();
    Ok(())
}

/// A line for `adb logcat -s AniVerse` on Android, stderr elsewhere.
pub(crate) fn log_line(message: &str) {
    #[cfg(target_os = "android")]
    {
        use std::os::raw::{c_char, c_int};
        #[link(name = "log")]
        extern "C" {
            fn __android_log_write(prio: c_int, tag: *const c_char, text: *const c_char) -> c_int;
        }
        if let Ok(text) = std::ffi::CString::new(message) {
            // 4 = ANDROID_LOG_INFO. Both pointers are valid NUL-terminated strings for the call.
            unsafe { __android_log_write(4, c"AniVerse".as_ptr(), text.as_ptr()) };
        }
    }
    #[cfg(not(target_os = "android"))]
    eprintln!("AniVerse: {message}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chips_wrap_into_rows_that_fit() {
        let items: Vec<String> = ["12 EPISODES", "RELEASING", "77%", "24M", "FALL 2026", "J.C.STAFF"].iter().map(|s| s.to_string()).collect();
        let rows = wrap_chips(&items, 247.0, 5.4, 18.0, 6.0);
        assert!(rows.len() >= 2);
        assert_eq!(rows.iter().map(Vec::len).sum::<usize>(), items.len());
    }

    #[test]
    fn countdowns_and_clocks_read_like_flutter() {
        assert_eq!(countdown(0), "OUT NOW");
        assert_eq!(countdown(6 * 3600 + 34 * 60), "IN 6H 34M");
        assert_eq!(countdown(2 * 86_400 + 3600), "IN 2D 1H");
        assert_eq!(clock(65_000), "1:05");
        assert_eq!(clock(3_725_000), "1:02:05");
    }

    #[test]
    fn hex_colours_parse_with_and_without_alpha() {
        assert_eq!("#E50914".parse_hex(), Some(Color::from_rgb_u8(0xE5, 0x09, 0x14)));
        assert_eq!("33050305".parse_hex().map(|c| c.alpha()), Some(0x33));
        assert_eq!("zz".parse_hex(), None);
    }

    #[test]
    fn every_setting_choice_has_a_label() {
        for key in ["look", "theme", "effects", "volume", "seekStep", "subColor", "subSize", "subLang", "downloadLimitGb", "quietFrom", "textScale"] {
            let (_, options) = pref_options(key).unwrap();
            assert!(!options.is_empty());
        }
        assert_eq!(label_of(&pref_options("volume").unwrap().1, &num(0.35), 1), "NORMAL");
        assert_eq!(label_of(&pref_options("textScale").unwrap().1, &num(1.0), 0), "NORMAL");
    }
}
