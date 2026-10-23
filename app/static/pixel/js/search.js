// Search: results as you type, plus filters (genre, year, season, format,
// status, minimum score, sort). The URL keeps the query and filters, so a
// filtered search can be shared or bookmarked. Searches that led somewhere (a
// result opened, or Enter pressed) are remembered on this device and offered
// again while the box is empty.
import { h, clear } from "./px.js";
import { api, GENRES } from "./api.js";
import { initShell, posterCard, posterSkeleton, emptyState, sectionHead } from "./ui.js";

initShell();
const input = document.getElementById("q");
const results = document.getElementById("results");
const form = document.getElementById("search-form");
let timer = 0, seq = 0;

// --- recent searches ------------------------------------------------------------------
const RECENT = "av.search.recent";
const recent = () => { try { return JSON.parse(localStorage.getItem(RECENT) || "[]").filter((x) => typeof x === "string"); } catch { return []; } };
function remember(q) {
  q = q.trim();
  if (q.length < 2) return;
  try { localStorage.setItem(RECENT, JSON.stringify([q, ...recent().filter((x) => x.toLowerCase() !== q.toLowerCase())].slice(0, 10))); } catch { /* private mode */ }
}
function recentChips() {
  const list = recent();
  if (!list.length) return null;
  const wrap = h("div.recent-searches", { role: "group", "aria-label": "Recent searches" },
    list.map((q) => h("button.chip.px-box", { type: "button", onclick: () => { input.value = q; run(q); } }, q)),
    h("button.px-btn.dark.px-box.bevel.small", { type: "button", onclick: () => {
      try { localStorage.removeItem(RECENT); } catch { /* ignore */ }
      wrap.previousSibling?.remove();
      wrap.remove();
    } }, "Clear"));
  return [sectionHead("Recent searches"), wrap];
}

const YEAR = new Date().getFullYear();
const FILTERS = {
  genres: ["Genre", { "": "Any genre", ...Object.fromEntries(GENRES.map((g) => [g, g])) }],
  year: ["Year", { "": "Any year", ...Object.fromEntries(Array.from({ length: YEAR + 2 - 1970 }, (_, i) => [String(YEAR + 1 - i), String(YEAR + 1 - i)])) }],
  season: ["Season", { "": "Any season", WINTER: "Winter", SPRING: "Spring", SUMMER: "Summer", FALL: "Fall" }],
  format: ["Format", { "": "Any format", TV: "TV", MOVIE: "Movie", OVA: "OVA", ONA: "ONA", SPECIAL: "Special", TV_SHORT: "TV short" }],
  status: ["Status", { "": "Any status", RELEASING: "Airing", FINISHED: "Finished", NOT_YET_RELEASED: "Upcoming" }],
  min_score: ["Score", { "": "Any score", 60: "60+", 70: "70+", 80: "80+", 90: "90+" }],
  sort: ["Sort", { "": "Best match", POPULARITY_DESC: "Popular", SCORE_DESC: "Top rated", TRENDING_DESC: "Trending", START_DATE_DESC: "Newest" }],
};
const params = new URLSearchParams(location.search);
const selects = {};
const bar = h("div.filters", { role: "group", "aria-label": "Filters" },
  Object.entries(FILTERS).map(([key, [label, opts]]) => {
    const sel = h("select.px-select", { "aria-label": label, onchange: () => run(input.value.trim()) },
      Object.entries(opts).map(([v, t]) => h("option", { value: v, selected: (params.get(key) || "") === v }, t)));
    selects[key] = sel;
    return sel;
  }),
  h("button.px-btn.dark.px-box.bevel.small", { type: "button", onclick: () => { Object.values(selects).forEach((s) => { s.value = ""; }); run(input.value.trim()); } }, "Clear"));
form.after(bar);

const chosen = () => Object.fromEntries(Object.entries(selects).map(([k, s]) => [k, s.value]).filter(([, v]) => v));

async function run(q, page = 1, more = null) {
  const mine = ++seq;
  const f = chosen();
  const filtered = Object.keys(f).length > 0;
  const url = new URLSearchParams({ ...(q ? { q } : {}), ...f });
  history.replaceState(null, "", `/search${url.toString() ? "?" + url : ""}`);
  document.title = q ? `${q} · Search · AniVerse` : "Search · AniVerse";

  if (!q && !filtered) {
    const chips = recentChips() || [];
    clear(results).append(...chips, sectionHead("Trending Now"), h("div.grid", null, Array.from({ length: 12 }, posterSkeleton)));
    const { trending } = await api.home();
    if (mine !== seq) return;
    clear(results).append(...(recentChips() || []), sectionHead("Trending Now"), h("div.grid", null, trending.map(posterCard)));
    return;
  }
  if (!more) clear(results).append(h("div.grid", null, Array.from({ length: 12 }, posterSkeleton)));

  let list, hasNext = false;
  if (filtered) {
    const r = await api.filter({ q, ...f, page, per_page: 24 });
    if (mine !== seq) return;
    if (!r.available) {
      clear(results).append(emptyState("Filters need AniList", "AniList didn't answer, and filtering needs it. Try again in a moment."));
      return;
    }
    list = r.media;
    hasNext = r.hasNextPage;
  } else {
    list = await api.search(q);
    if (mine !== seq) return;
  }

  if (more) {
    more.grid.append(...list.map(posterCard));
    more.button.remove();
  } else {
    clear(results);
    if (!list.length) {
      results.append(emptyState("Nothing found", q ? `No anime matched "${q}"${filtered ? " with these filters" : ". Try the English or romaji title"}.` : "No anime match these filters."));
      return;
    }
    const grid = h("div.grid", null, list.map(posterCard));
    if (!filtered) results.append(h("p.muted", { style: { margin: "0 0 14px" } }, `${list.length} result${list.length === 1 ? "" : "s"}`));
    results.append(grid);
    more = { grid };
  }
  if (hasNext) {
    const button = h("button.px-btn.dark.px-box.bevel", { type: "button", style: { margin: "22px auto 0", display: "flex" },
      onclick: () => { button.disabled = true; run(q, page + 1, { grid: more.grid, button }); } }, "Load more");
    results.append(button);
  }
}

input.addEventListener("input", () => {
  clearTimeout(timer);
  timer = setTimeout(() => run(input.value.trim()), 350);
});
form.addEventListener("submit", (e) => { e.preventDefault(); clearTimeout(timer); remember(input.value); run(input.value.trim()); });
// Opening a result means the search found what it was for.
results.addEventListener("click", (e) => { if (e.target.closest("a") && input.value.trim()) remember(input.value); });
run(input.value.trim());
if (!input.value && !Object.keys(chosen()).length) input.focus();
