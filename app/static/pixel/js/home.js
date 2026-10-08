// Home: continue watching, the spotlight, then the catalogue shelves -- the
// app's home screen. "Because you watched" rows come from AniList's
// recommendations for the last two shows in this device's history.
import { h, clear } from "./px.js";
import { api, history, titleOf } from "./api.js";
import { initShell, continueWatching, heroSpotlight, heroSkeleton, sectionHead, shelf, shelfSkeleton, posterCard, emptyState } from "./ui.js";

initShell();
const root = document.getElementById("home");
const SECTIONS = [["Trending Now", "trending"], ["Popular", "popular"], ["Latest Episodes", "latest"]];

// History is local, so it shows while the server answers.
root.append(continueWatching());

/** Up to two shelves of recommendations, for the shows watched most recently. */
function becauseYouWatched(anchor) {
  const recent = history.latestPerAnime().slice(0, 2);
  let after = anchor;
  for (const e of recent) {
    const slot = h("section.section", null, sectionHead(`Because you watched ${e.title || "a show"}`), shelfSkeleton());
    after.after(slot);
    after = slot;
    api.extra(e.anime_id).then((x) => {
      const seen = new Set(history.latestPerAnime().map((y) => y.anime_id));
      const recs = (x.recommendations || []).filter((r) => r && r.id && !seen.has(String(r.id)));
      if (recs.length < 3) { slot.remove(); return; }
      clear(slot).append(sectionHead(`Because you watched ${e.title || titleOf(x)}`), shelf(recs.map(posterCard)));
    }).catch(() => slot.remove());
  }
}
const hero = root.appendChild(heroSkeleton());
const shelves = SECTIONS.map(([title]) => root.appendChild(h("section.section", null, sectionHead(title), shelfSkeleton())));

api.home().then((data) => {
  if (!data.trending.length && !data.popular.length && !data.latest.length) {
    hero.replaceWith(emptyState("Can't reach the catalogue", "The server did not answer. Try again in a moment.",
      h("button.px-btn.px-box.bevel", { type: "button", onclick: () => location.reload() }, "Retry")));
    shelves.forEach((s) => s.remove());
    return;
  }
  const spotlight = heroSpotlight(data.trending.length ? data.trending : data.popular);
  hero.replaceWith(spotlight);
  becauseYouWatched(spotlight);
  SECTIONS.forEach(([title, key], i) => {
    const items = data[key];
    if (!items.length) { shelves[i].remove(); return; }
    clear(shelves[i]).append(sectionHead(title), shelf(items.map(posterCard)));
  });
});
