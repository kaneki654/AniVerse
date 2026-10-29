// Watch history: the last episode of each anime, newest first, with progress.
// Synced with the account when signed in -- the app's history screen.
import { h, sprite, pixelCover, clear, fmtTime, confirmDialog } from "./px.js";
import { history, auth } from "./api.js";
import { initShell, emptyState } from "./ui.js";

initShell();
const list = document.getElementById("history");
const clearBtn = document.getElementById("clear");
const note = document.getElementById("sync-note");

function render() {
  clear(list);
  const user = auth.user;
  note.textContent = user
    ? `Synced with your account (${user.display_name || user.username}) and the app.`
    : "Saved in this browser only. Sign in to keep it in sync with the app.";
  const entries = history.latestPerAnime();
  clearBtn.hidden = !entries.length;
  if (!entries.length) {
    list.append(emptyState("Nothing watched yet", "Episodes you watch show up here.", h("a.px-btn.px-box.bevel", { href: "/" }, "Find something")));
    return;
  }
  for (const e of entries) {
    const done = history.finished(e);
    const frac = e.duration_ms ? Math.min(1, e.position_ms / e.duration_ms) : 0;
    const href = `/watch/${e.anime_id}/${done ? e.episode + 1 : e.episode}`;
    const when = new Date(e.updated_at);
    list.append(h("div.list-item.px-box", null,
      h("a.thumb.px-box.flat", { href: `/anime/${e.anime_id}`, "aria-label": e.title }, pixelCover(e.cover, 48, e.title)),
      h("div.body", null,
        h("a.name", { href: `/anime/${e.anime_id}` }, e.title || "Untitled"),
        h("div.sub", null, done ? `EP ${e.episode} · watched` : `EP ${e.episode} · ${fmtTime(e.position_ms / 1000)} / ${fmtTime(e.duration_ms / 1000)}`,
          " · ", when.toLocaleDateString(undefined, { month: "short", day: "numeric" })),
        h("div.px-bar", null, h("i", null, h("b", { style: { width: `${(done ? 1 : frac) * 100}%` } })))),
      h("a.px-btn.px-box.bevel.small", { href }, sprite("play", 1.3), done ? `EP ${e.episode + 1}` : "Resume"),
      h("button.icon-btn", { type: "button", "aria-label": `Remove ${e.title}`, title: "Remove", onclick: () => history.removeAnime(e.anime_id) }, sprite("trash", 2))));
  }
}

clearBtn.addEventListener("click", async () => {
  if (await confirmDialog("Clear history?", auth.user ? "This removes it from your account and the app too." : "This removes everything watched in this browser.", "Clear")) history.clear();
});
history.onChange(render);
auth.onChange(render);
render();
