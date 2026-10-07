// My List: the anime you follow, newest first, with new episodes flagged and
// one tap to watch the latest. Opening the page marks what you see as seen.
import { h, sprite, pixelCover, clear } from "./px.js";
import { api, airedEpisodes, history } from "./api.js";
import { watchlist } from "./watchlist.js";
import { settings } from "./settings.js";
import { initShell, emptyState } from "./ui.js";

initShell();
const root = document.getElementById("page-root");

const alertsRow = h("div.setting.px-box", { style: { marginBottom: "18px" } });
function renderAlertsRow() {
  const on = settings.get().alerts && "Notification" in window && Notification.permission === "granted";
  clear(alertsRow).append(
    h("div", null, h("b", null, "New-episode alerts"),
      h("span", null, "Get a notification when a show on your list airs a new episode, while AniVerse is open.")),
    h("button.px-switch", {
      type: "button", role: "switch", "aria-checked": String(on), "aria-label": "New-episode alerts",
      onclick: async () => {
        if (on) { settings.set({ alerts: false }); return renderAlertsRow(); }
        const perm = "Notification" in window ? await Notification.requestPermission() : "denied";
        settings.set({ alerts: perm === "granted" });
        renderAlertsRow();
      },
    }));
}
renderAlertsRow();
const list = h("div.list");
root.append(alertsRow, list);

async function render() {
  const entries = watchlist.all();
  clear(list);
  if (!entries.length) {
    list.append(emptyState("Your list is empty", "Tap the bookmark on any anime to follow it and get told when new episodes air.",
      h("a.px-btn.px-box.bevel", { href: "/schedule" }, "See what's airing")));
    return;
  }
  for (const e of entries) {
    const sub = h("div.sub", null, "Checking for new episodes…");
    const play = h("a.px-btn.px-box.bevel.small", { href: `/anime/${e.anime_id}` }, "Open");
    list.append(h("div.list-item.px-box", null,
      h("a.thumb.px-box.flat", { href: `/anime/${e.anime_id}`, "aria-label": e.title }, pixelCover(e.cover, 48, e.title)),
      h("div.body", null, h("a.name", { href: `/anime/${e.anime_id}` }, e.title || "Untitled"), sub),
      play,
      h("button.icon-btn", { type: "button", "aria-label": `Remove ${e.title}`, title: "Remove", onclick: () => watchlist.unfollow(e.anime_id) }, sprite("trash", 2))));
    api.info(e.anime_id).then((info) => {
      const aired = airedEpisodes(info);
      const fresh = e.seen_episode > 0 ? aired - e.seen_episode : 0;
      const watched = Math.max(0, ...history.forAnime(e.anime_id).map((x) => x.episode));
      const next = Math.min(aired, watched + 1) || 1;
      clear(sub).append(fresh > 0
        ? h("span", { style: { color: "var(--blood-light)" } }, `${fresh} new episode${fresh === 1 ? "" : "s"} · `)
        : "", `${aired} out${info.status === "RELEASING" && info.nextAiringEpisode ? " · airing" : ""}${watched ? ` · you're on ${watched}` : ""}`);
      play.setAttribute("href", `/watch/${e.anime_id}/${next}`);
      play.textContent = `EP ${next}`;
      // Seen now: the alert for these episodes has done its job.
      setTimeout(() => watchlist.markSeen(e.anime_id, aired), 1500);
    }).catch(() => { sub.textContent = ""; });
  }
}
render();
watchlist.onChange(() => { if (!document.hidden) render(); });
