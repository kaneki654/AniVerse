// Genres: one tile each, its background the top-rated anime in that genre,
// pixelated like the rest of the UI -- the app's genres screen.
import { h, sprite, pixelCover, clear } from "./px.js";
import { api, GENRES } from "./api.js";
import { initShell } from "./ui.js";

initShell();
const grid = document.getElementById("genres");
const FILLS = ["#7a0410", "#2a1a1f", "#d10a1a", "#3d0107", "#1b1114"];

const tiles = GENRES.map((genre, i) => {
  const art = h("div.px-cover.skel", { style: { position: "absolute", inset: "0" } });
  const top = h("div.top");
  const tile = h("a.genre-tile.px-box", { href: `/genre/${encodeURIComponent(genre)}`, style: { background: FILLS[i % FILLS.length] }, "aria-label": genre },
    art, h("div.bands"), h("div.txt", null, h("span.name", null, genre), top));
  grid.append(tile);
  return { genre, art, top, tile };
});

api.genreArt().then((all) => {
  for (const { genre, art, top, tile } of tiles) {
    const a = all && all[genre];
    if (!a) { art.remove(); continue; }
    // Banners are wide like the tile; the portrait cover only when there is none.
    art.replaceWith(pixelCover(a.banner || a.cover, a.banner ? 180 : 72, ""));
    clear(top).append(sprite("star", 1.4, "#e8b23a"), a.score ? h("span.s", null, String(a.score)) : null, h("span.t", null, a.title));
    tile.setAttribute("aria-label", `${genre}. Top rated: ${a.title}`);
  }
});
