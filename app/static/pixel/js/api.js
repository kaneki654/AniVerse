// Data for the pixel website: the same endpoints the AniVerse Pixel app uses
// (/api/anime/* through this server, /api/source, /api/auth, /api/history), so
// the site and the app see the same catalogue, streams, accounts and history.

async function getJson(url, { timeout = 30000, headers } = {}) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeout);
  try {
    const r = await fetch(url, { signal: ctl.signal, headers });
    if (!r.ok) throw Object.assign(new Error(`HTTP ${r.status}`), { status: r.status });
    return await r.json();
  } finally {
    clearTimeout(timer);
  }
}

const list = (v) => (Array.isArray(v) ? v : []);

export const GENRES = [
  "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy",
  "Horror", "Mahou Shoujo", "Mecha", "Music", "Mystery",
  "Psychological", "Romance", "Sci-Fi", "Slice of Life", "Sports",
  "Supernatural", "Thriller",
];

export const api = {
  async home() {
    const get = (p) => getJson(`/api/anime/${p}`).then(list).catch(() => []);
    const [trending, popular, latest] = await Promise.all([
      get("trending?per_page=12"), get("popular?per_page=12"), get("latest?per_page=12"),
    ]);
    return { trending, popular, latest };
  },
  info: (id) => getJson(`/api/anime/info/${encodeURIComponent(id)}`),
  async search(q) {
    q = q.trim();
    if (!q) return [];
    return list(await getJson(`/api/anime/search/${encodeURIComponent(q)}`).catch(() => []));
  },
  genreArt: () => getJson(`/api/anime/genres/top?genres=${encodeURIComponent(GENRES.join(","))}`, { timeout: 25000 }).catch(() => ({})),
  async byGenre(genre, page = 1, perPage = 24) {
    return list(await getJson(`/api/anime/genre/${encodeURIComponent(genre)}?page=${page}&per_page=${perPage}`).catch(() => []));
  },
  /** Playable sources; {sources, subtitles, intro, outro, hasDub, error}. */
  async sources(id, ep, category, fresh = false) {
    const q = `episode_id=${encodeURIComponent(id)}/${ep}&category=${category}${fresh ? "&fresh=true" : ""}`;
    try {
      const body = await getJson(`/api/source?${q}`, { timeout: 200000 });
      const d = body.data || {};
      return { sources: list(d.sources), intro: d.intro, outro: d.outro, hasDub: d.hasDub ?? null, error: d.error || null };
    } catch (e) {
      return { sources: [], error: e.name === "AbortError" ? "The server took too long to find a stream." : "Can't reach the AniVerse server.", offline: e.name !== "AbortError" };
    }
  },
  appRelease: () => getJson("/app/version.json", { timeout: 8000 }).catch(() => null),
  extra: (id) => getJson(`/api/anime/extra/${encodeURIComponent(id)}`, { timeout: 20000 }).catch(() => ({})),
  episodes: (id) => getJson(`/api/anime/episodes/${encodeURIComponent(id)}`, { timeout: 20000 }).then(list).catch(() => []),
  schedule: (days = 7) => getJson(`/api/anime/schedule?days=${days}`, { timeout: 30000 }).then(list).catch(() => []),
  /** filters: {q, genres[], year, season, format[], status, min_score, sort, page} */
  filter(f = {}) {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(f)) {
      if (v === undefined || v === null || v === "" || (Array.isArray(v) && !v.length)) continue;
      q.set(k, Array.isArray(v) ? v.join(",") : String(v));
    }
    return getJson(`/api/anime/filter?${q}`, { timeout: 25000 }).catch(() => ({ media: [], hasNextPage: false, available: false }));
  },
  status: () => getJson("/api/anime/status", { timeout: 15000 }),
  /** This server's own health: disk space, the daily stream sweep, error reports. */
  ops: () => getJson("/api/ops", { timeout: 10000 }).catch(() => null),
  /** Tell the server a stream plays wrong, so it is left out for a while. */
  report: (id, ep, category, url, reason) => fetch("/api/report", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ episode_id: `${id}/${ep}`, category, url, reason }),
  }).then((r) => r.ok).catch(() => false),
  authConfig: () => getJson("/api/auth/config", { timeout: 10000 }).catch(() => ({})),
  trackingConfig: () => getJson("/api/tracking/config", { timeout: 10000 }).catch(() => ({})),
  /** Intro/outro for the video playing: {intro, outro, source, pending}. */
  skipTimes(id, ep, duration, server, category) {
    const q = `duration=${duration.toFixed(2)}&server=${encodeURIComponent(server || "")}&category=${category}`;
    return getJson(`/api/anime/skip/${encodeURIComponent(id)}/${ep}?${q}`, { timeout: 30000 }).catch(() => null);
  },
};

// --- anime helpers --------------------------------------------------------------

export function titleOf(a) {
  const t = (a && a.title) || {};
  return t.english || t.romaji || a?.name || "Untitled";
}
export function coverOf(a) { return (a && a.coverImage && a.coverImage.large) || a?.cover || ""; }

/** Episodes that can be played now: aired ones for a show still airing. */
export function airedEpisodes(a) {
  const next = a && a.nextAiringEpisode;
  if (next && typeof next.episode === "number" && next.episode > 1) return next.episode - 1;
  if (a && a.status === "NOT_YET_RELEASED") return 0;
  return (a && a.episodes) || 12;
}

// --- accounts -------------------------------------------------------------------

const TOKEN = "av.token", USER = "av.user";
const read = (k) => { try { return localStorage.getItem(k); } catch { return null; } };
const write = (k, v) => { try { v === null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* storage off */ } };

const authListeners = new Set();
export const auth = {
  get token() { return read(TOKEN); },
  get user() { try { return JSON.parse(read(USER) || "null"); } catch { return null; } },
  onChange(fn) { authListeners.add(fn); return () => authListeners.delete(fn); },
  _set(token, user) {
    write(TOKEN, token);
    write(USER, user ? JSON.stringify(user) : null);
    authListeners.forEach((fn) => fn(user));
  },
  async _post(path, body) {
    const r = await fetch(`/api/auth/${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(typeof data.detail === "string" ? data.detail : "Something went wrong. Try again.");
    return data;
  },
  async login(username, password) {
    const d = await this._post("login", { username, password });
    this._set(d.token, d.user);
    await history.sync({ full: true });
    return d.user;
  },
  async register(username, password, displayName) {
    const d = await this._post("register", { username, password, display_name: displayName || null });
    this._set(d.token, d.user);
    await history.sync({ full: true });
    return d.user;
  },
  async google(idToken) {
    const d = await this._post("google", { id_token: idToken });
    this._set(d.token, d.user);
    await history.sync({ full: true });
    return d.user;
  },
  /** Authorized JSON calls for the account's tracking links. */
  async call(method, path, body) {
    const r = await fetch(path, {
      method,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${this.token}` },
      body: body ? JSON.stringify(body) : undefined,
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(typeof data.detail === "string" ? data.detail : "Something went wrong.");
    return data;
  },
  async logout() {
    const token = this.token;
    this._set(null, null);
    write(SYNCED, null);
    if (token) fetch("/api/auth/logout", { method: "POST", headers: { Authorization: `Bearer ${token}` } }).catch(() => {});
  },
  /** Re-checks a saved session; signs out locally if the server dropped it. */
  async refresh() {
    const token = this.token;
    if (!token) return null;
    try {
      const d = await getJson("/api/auth/me", { headers: { Authorization: `Bearer ${token}` }, timeout: 10000 });
      this._set(token, d.user);
      return d.user;
    } catch (e) {
      if (e.status === 401) this._set(null, null);
      return this.user;
    }
  },
};

// --- watch history ------------------------------------------------------------------
// Same entries as the app and the server: one per (anime_id, episode), newest
// updated_at wins, deletions kept as tombstones so they sync to other devices.

const HIST = "av.history.v1", SYNCED = "av.history.synced";
const MAX = 400;
const histListeners = new Set();
const key = (e) => `${e.anime_id}/${e.episode}`;

function load() {
  try { return JSON.parse(read(HIST) || "[]").filter((e) => e && e.anime_id && e.episode); } catch { return []; }
}
function store(entries) {
  entries.sort((a, b) => b.updated_at - a.updated_at);
  const live = entries.filter((e) => !e.deleted);
  if (live.length > MAX) {
    const drop = new Set(live.slice(MAX).map(key));
    entries = entries.filter((e) => !drop.has(key(e)));
  }
  write(HIST, JSON.stringify(entries));
  histListeners.forEach((fn) => fn());
}

let syncTimer = 0;
export const history = {
  onChange(fn) { histListeners.add(fn); return () => histListeners.delete(fn); },
  all: () => load().filter((e) => !e.deleted),
  finished: (e) => e.duration_ms > 0 && e.position_ms >= e.duration_ms * 0.9,

  /** The most recent entry for each anime, newest first. */
  latestPerAnime() {
    const seen = new Set(), out = [];
    for (const e of this.all()) {
      if (seen.has(e.anime_id)) continue;
      seen.add(e.anime_id);
      out.push(e);
    }
    return out;
  },
  forAnime(animeId) { return this.all().filter((e) => e.anime_id === String(animeId)); },
  progressFor(animeId, ep) { return this.all().find((e) => e.anime_id === String(animeId) && e.episode === Number(ep)) || null; },

  save(entry) {
    const e = { title: "", cover: "", position_ms: 0, duration_ms: 0, deleted: false, ...entry,
      anime_id: String(entry.anime_id), episode: Number(entry.episode), updated_at: Date.now() };
    const all = load().filter((x) => key(x) !== key(e));
    all.push(e);
    store(all);
    this.syncSoon();
  },
  removeAnime(animeId) {
    const now = Date.now();
    store(load().map((e) => (e.anime_id === String(animeId) ? { ...e, deleted: true, updated_at: now } : e)));
    this.syncSoon(0);
  },
  async clear() {
    const now = Date.now();
    store(load().map((e) => ({ ...e, deleted: true, updated_at: now })));
    const token = auth.token;
    if (token) {
      const r = await fetch("/api/history", { method: "DELETE", headers: { Authorization: `Bearer ${token}` } }).catch(() => null);
      if (r && r.ok) this._merge((await r.json()).entries || []);
    }
  },

  syncSoon(delay = 15000) {
    if (!auth.token) return;
    clearTimeout(syncTimer);
    syncTimer = setTimeout(() => this.sync(), delay);
  },

  /** Sends what changed since the last sync and merges back the server's list. */
  async sync({ full = false, keepalive = false } = {}) {
    const token = auth.token;
    if (!token) return false;
    clearTimeout(syncTimer);
    const since = full ? 0 : Number(read(SYNCED) || 0);
    const pending = load().filter((e) => e.updated_at > since);
    const startedAt = Date.now();
    try {
      let merged = null;
      for (let i = 0; i < Math.max(1, pending.length); i += 200) {
        const r = await fetch("/api/history", {
          method: "PUT",
          keepalive,
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
          body: JSON.stringify({ entries: pending.slice(i, i + 200) }),
        });
        if (r.status === 401) { auth._set(null, null); return false; }
        if (!r.ok) return false;
        if (!keepalive) merged = (await r.json()).entries || [];
      }
      if (merged) this._merge(merged);
      write(SYNCED, String(startedAt));
      return true;
    } catch {
      return false;
    }
  },

  _merge(serverEntries) {
    const byKey = new Map(load().map((e) => [key(e), e]));
    for (const s of serverEntries) {
      const e = { ...s, anime_id: String(s.anime_id), episode: Number(s.episode) };
      const mine = byKey.get(key(e));
      if (!mine || e.updated_at > mine.updated_at) byKey.set(key(e), e);
    }
    store([...byKey.values()]);
  },
};

// A tab being closed sends what it has not synced yet.
addEventListener("pagehide", () => { if (auth.token) history.sync({ keepalive: true }); });
