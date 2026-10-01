// Home: continue watching, the spotlight, then the catalogue shelves -- the
// app's home screen.
import { h, clear } from "./px.js";
import { api } from "./api.js";
import { initShell, continueWatching, heroSpotlight, heroSkeleton, sectionHead, shelf, shelfSkeleton, posterCard, emptyState } from "./ui.js";

initShell();
const root = document.getElementById("home");
const SECTIONS = [["Trending Now", "trending"], ["Popular", "popular"], ["Latest Episodes", "latest"]];

// History is local, so it shows while the server answers.
root.append(continueWatching());
const hero = root.appendChild(heroSkeleton());
const shelves = SECTIONS.map(([title]) => root.appendChild(h("section.section", null, sectionHead(title), shelfSkeleton())));

api.home().then((data) => {
  if (!data.trending.length && !data.popular.length && !data.latest.length) {
    hero.replaceWith(emptyState("Can't reach the catalogue", "The server did not answer. Try again in a moment.",
      h("button.px-btn.px-box.bevel", { type: "button", onclick: () => location.reload() }, "Retry")));
    shelves.forEach((s) => s.remove());
    return;
  }
  hero.replaceWith(heroSpotlight(data.trending.length ? data.trending : data.popular));
  SECTIONS.forEach(([title, key], i) => {
    const items = data[key];
    if (!items.length) { shelves[i].remove(); return; }
    clear(shelves[i]).append(sectionHead(title), shelf(items.map(posterCard)));
  });
});
