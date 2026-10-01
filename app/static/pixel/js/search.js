// Search: results as you type, the URL kept in step so a search can be shared.
import { h, clear } from "./px.js";
import { api } from "./api.js";
import { initShell, posterCard, posterSkeleton, emptyState, sectionHead } from "./ui.js";

initShell();
const input = document.getElementById("q");
const results = document.getElementById("results");
const form = document.getElementById("search-form");
let timer = 0, seq = 0;

async function run(q) {
  const mine = ++seq;
  const url = q ? `/search?q=${encodeURIComponent(q)}` : "/search";
  history.replaceState(null, "", url);
  document.title = q ? `${q} · Search · AniVerse` : "Search · AniVerse";
  if (!q) {
    clear(results).append(sectionHead("Trending Now"), h("div.grid", null, Array.from({ length: 12 }, posterSkeleton)));
    const { trending } = await api.home();
    if (mine !== seq) return;
    clear(results).append(sectionHead("Trending Now"), h("div.grid", null, trending.map(posterCard)));
    return;
  }
  clear(results).append(h("div.grid", null, Array.from({ length: 12 }, posterSkeleton)));
  const list = await api.search(q);
  if (mine !== seq) return;
  clear(results);
  if (!list.length) results.append(emptyState("Nothing found", `No anime matched "${q}". Try the English or romaji title.`));
  else results.append(h("p.muted", { style: { margin: "0 0 14px" } }, `${list.length} result${list.length === 1 ? "" : "s"}`), h("div.grid", null, list.map(posterCard)));
}

input.addEventListener("input", () => {
  clearTimeout(timer);
  timer = setTimeout(() => run(input.value.trim()), 350);
});
form.addEventListener("submit", (e) => { e.preventDefault(); clearTimeout(timer); run(input.value.trim()); });
run(input.value.trim());
if (!input.value) input.focus();
