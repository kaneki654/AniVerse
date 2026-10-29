// My List: the anime you follow, synced with your account like history (one
// entry per anime, newest change wins, removals as tombstones), plus the
// "new episode" check: an entry remembers how many episodes were out when you
// last looked, and anything aired since is new.
import { api, auth, airedEpisodes } from "./api.js";

const KEY = "av.watchlist.v1", SYNCED = "av.watchlist.synced";
const listeners = new Set();
let syncTimer = 0;

const read = (k) => { try { return localStorage.getItem(k); } catch { return null; } };
const write = (k, v) => { try { localStorage.setItem(k, v); } catch { /* storage off */ } };

function load() {
  try { return JSON.parse(read(KEY) || "[]").filter((e) => e && e.anime_id); } catch { return []; }
}
function store(entries) {
  entries.sort((a, b) => b.updated_at - a.updated_at);
  write(KEY, JSON.stringify(entries));
  listeners.forEach((fn) => fn());
}

export const watchlist = {
  onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
  all: () => load().filter((e) => !e.deleted),
  has: (id) => load().some((e) => e.anime_id === String(id) && !e.deleted),

  follow(anime, seen = 0) {
    const id = String(anime.id);
    const entries = load().filter((e) => e.anime_id !== id);
    const t = anime.title || {};
    entries.push({ anime_id: id, title: t.english || t.romaji || anime.name || "", cover: anime.coverImage?.large || "",
      seen_episode: seen, updated_at: Date.now(), deleted: false });
    store(entries);
    this.syncSoon(0);
  },
  unfollow(id) {
    store(load().map((e) => (e.anime_id === String(id) ? { ...e, deleted: true, updated_at: Date.now() } : e)));
    this.syncSoon(0);
  },
  markSeen(id, aired) {
    const entries = load();
    const e = entries.find((x) => x.anime_id === String(id) && !x.deleted);
    if (!e || e.seen_episode >= aired) return;
    e.seen_episode = aired;
    e.updated_at = Date.now();
    store(entries);
    this.syncSoon();
  },

  /** [{entry, aired, fresh}] for followed shows with episodes out since you looked. */
  async newEpisodes() {
    const out = [];
    await Promise.all(this.all().map(async (e) => {
      try {
        const info = await api.info(e.anime_id);
        const aired = airedEpisodes(info);
        if (aired > e.seen_episode && e.seen_episode > 0) out.push({ entry: e, info, aired, fresh: aired - e.seen_episode });
      } catch { /* one show failing to load says nothing about the rest */ }
    }));
    return out;
  },

  syncSoon(delay = 8000) {
    if (!auth.token) return;
    clearTimeout(syncTimer);
    syncTimer = setTimeout(() => this.sync(), delay);
  },

  async sync({ full = false } = {}) {
    const token = auth.token;
    if (!token) return false;
    const since = full ? 0 : Number(read(SYNCED) || 0);
    const startedAt = Date.now();
    try {
      const r = await fetch("/api/watchlist", {
        method: "PUT",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ entries: load().filter((e) => e.updated_at > since).slice(0, 200) }),
      });
      if (!r.ok) return false;
      const byId = new Map(load().map((e) => [e.anime_id, e]));
      for (const s of (await r.json()).entries || []) {
        const mine = byId.get(String(s.anime_id));
        if (!mine || s.updated_at > mine.updated_at) byId.set(String(s.anime_id), { ...s, anime_id: String(s.anime_id) });
      }
      store([...byId.values()]);
      write(SYNCED, String(startedAt));
      return true;
    } catch {
      return false;
    }
  },
};
