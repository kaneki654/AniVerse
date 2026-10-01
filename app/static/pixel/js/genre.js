// One genre's anime, loading the next page as the end comes into view.
import { h } from "./px.js";
import { api } from "./api.js";
import { initShell, posterCard, posterSkeleton, emptyState } from "./ui.js";

initShell();
const grid = document.getElementById("results");
const sentinel = document.getElementById("more");
const genre = grid.dataset.genre;
let page = 0, loading = false, done = false;
const seen = new Set();

async function next() {
  if (loading || done) return;
  loading = true;
  const skels = Array.from({ length: 12 }, posterSkeleton);
  grid.append(...skels);
  const list = await api.byGenre(genre, ++page);
  skels.forEach((s) => s.remove());
  const fresh = list.filter((a) => !seen.has(a.id));
  fresh.forEach((a) => seen.add(a.id));
  grid.append(...fresh.map(posterCard));
  if (list.length < 24 || !fresh.length) {
    done = true;
    if (!seen.size) grid.replaceWith(emptyState("Nothing here", `No anime found for ${genre}.`));
  }
  loading = false;
  // Still room on a tall screen: keep filling.
  if (!done && sentinel.getBoundingClientRect().top < innerHeight + 400) next();
}

new IntersectionObserver((e) => { if (e[0].isIntersecting) next(); }, { rootMargin: "600px" }).observe(sentinel);
next();
