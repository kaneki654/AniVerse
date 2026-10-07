// The airing schedule: the next seven days, one tab per day, each episode with
// its local air time and a countdown; shows on My List are marked and float up.
import { h, sprite, pixelCover, clear } from "./px.js";
import { api, titleOf, coverOf } from "./api.js";
import { watchlist } from "./watchlist.js";
import { initShell, emptyState } from "./ui.js";

initShell();
const root = document.getElementById("page-root");
const days = h("div.days", { role: "tablist" });
const list = h("div.list");
root.append(days, list);
list.append(h("div.skel", { style: { height: "300px" } }));

const dayKey = (t) => new Date(t * 1000).toDateString();
const countdown = (secs) => {
  if (secs <= 0) return "Out now";
  const d = Math.floor(secs / 86400), hrs = Math.floor((secs % 86400) / 3600), m = Math.floor((secs % 3600) / 60);
  return d ? `in ${d}d ${hrs}h` : hrs ? `in ${hrs}h ${m}m` : `in ${m}m`;
};

api.schedule(7).then((items) => {
  clear(list);
  if (!items.length) {
    list.append(emptyState("No schedule right now", "AniList didn't answer. Try again in a moment."));
    return;
  }
  const byDay = new Map();
  for (const it of items) {
    const k = dayKey(it.airingAt);
    if (!byDay.has(k)) byDay.set(k, []);
    byDay.get(k).push(it);
  }
  const keys = [...byDay.keys()];
  const show = (k) => {
    [...days.children].forEach((b) => {
      const on = b.dataset.day === k;
      b.classList.toggle("dark", !on);
      b.setAttribute("aria-selected", String(on));
    });
    clear(list);
    const now = Date.now() / 1000;
    const following = new Set(watchlist.all().map((e) => e.anime_id));
    // Followed shows first within the day, then by time.
    const rows = byDay.get(k).slice().sort((a, b) =>
      (following.has(String(b.media.id)) - following.has(String(a.media.id))) || a.airingAt - b.airingAt);
    for (const it of rows) {
      const a = it.media;
      const when = new Date(it.airingAt * 1000);
      const aired = it.airingAt <= now;
      const mine = following.has(String(a.id));
      const followBtn = h("button.icon-btn.follow", {
        type: "button", "aria-label": mine ? "Remove from My List" : "Add to My List", title: mine ? "On My List" : "Add to My List",
        onclick: (e) => {
          e.preventDefault();
          if (watchlist.has(a.id)) watchlist.unfollow(a.id);
          else watchlist.follow(a, Math.max(0, it.episode - 1));
          show(k);
        },
      }, sprite(mine ? "bookmark" : "bookmarkOff", 2));
      list.append(h(`a.sched-row.px-box${aired ? ".aired" : ""}${mine ? ".following" : ""}`,
        { href: aired ? `/watch/${a.id}/${it.episode}` : `/anime/${a.id}` },
        h("div.time", null, when.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" }), h("small", null, countdown(it.airingAt - now))),
        h("div.thumb.px-box.flat", null, pixelCover(coverOf(a), 40, "")),
        h("div", null, h("b", null, titleOf(a)), h("small", null, `Episode ${it.episode}${a.format ? " · " + String(a.format).replace("_", " ") : ""}${mine ? " · On My List" : ""}`)),
        followBtn));
    }
  };
  for (const k of keys) {
    const d = new Date(k);
    const label = d.toDateString() === new Date().toDateString() ? "Today" : d.toLocaleDateString(undefined, { weekday: "short", day: "numeric" });
    days.append(h("button.px-btn.px-box.bevel.small", { type: "button", role: "tab", dataset: { day: k }, onclick: () => show(k) }, label));
  }
  show(keys[0]);
});
