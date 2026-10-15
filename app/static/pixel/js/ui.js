// Shared pieces of the pixel website: the header, poster cards, shelves, the
// spotlight and continue-watching rows -- the app's widgets, as DOM.
import { h, sprite, hydrateSprites, pixelCover, drips, clear, plainText, embers, dissolve, speedLines, emblemUrl, paletteSwitch } from "./px.js";
import { api, auth, history, titleOf, coverOf } from "./api.js";
import { watchlist } from "./watchlist.js";
import { settings } from "./settings.js";
import { sfx } from "./sfx.js";
import { newlyUnlocked } from "./achievements.js";
import { toast } from "./px.js";

export function sectionHead(title, more) {
  return h("div.section-head", null,
    sprite("mark", 2),
    h("h2", null, title),
    h("span.blade", { "aria-hidden": "true" }),
    more ? h("a.more", { href: more.href }, more.label || "More", sprite("chevron", 1)) : null);
}

/** Poster tile: the cover in a hard pixel frame, the score as a badge. */
export function posterCard(anime) {
  const title = titleOf(anime);
  const score = anime.averageScore;
  return h("a.poster", { href: `/anime/${anime.id}`, title },
    h("div.frame.px-box", null,
      pixelCover(coverOf(anime), 96, title),
      score ? h("span.score", null, sprite("star", 1, "#e8b23a"), String(score)) : null,
      anime.format && anime.format !== "TV" ? h("span.badge", null, String(anime.format).replace("_", " ")) : null),
    h("div.title", null, title));
}

export function posterSkeleton() {
  return h("div.poster", { "aria-hidden": "true" },
    h("div.frame.px-box", null, h("div.px-cover.skel", { style: { position: "absolute", inset: "0" } })),
    h("div.title", null, h("div.skel", { style: { height: "10px", width: "70%", marginTop: "6px" } })));
}

/** A horizontal shelf with scroll buttons on wide screens. */
export function shelf(items, extraClass = "") {
  const track = h(`div.shelf-track${extraClass ? "." + extraClass : ""}`, null, items);
  const scroll = (dir) => track.scrollBy({ left: dir * track.clientWidth * 0.85, behavior: "smooth" });
  const prev = h("button.shelf-nav.prev.px-box", { type: "button", "aria-label": "Scroll left", hidden: true, onclick: () => scroll(-1) },
    h("span", { style: { transform: "scaleX(-1)", display: "grid" } }, sprite("chevron", 2)));
  const next = h("button.shelf-nav.next.px-box", { type: "button", "aria-label": "Scroll right", hidden: true, onclick: () => scroll(1) }, sprite("chevron", 2));
  // Each arrow only when there is something that way.
  const sync = () => {
    prev.hidden = track.scrollLeft <= 2;
    next.hidden = track.scrollLeft + track.clientWidth >= track.scrollWidth - 2;
  };
  track.addEventListener("scroll", sync, { passive: true });
  if ("ResizeObserver" in window) new ResizeObserver(sync).observe(track);
  return h("div.shelf", null, prev, track, next);
}

export function shelfSkeleton(n = 7) {
  return shelf(Array.from({ length: n }, posterSkeleton));
}

export function emptyState(title, text, action) {
  return h("div.empty-state", null, sprite("skull", 5), h("h3", null, title), text ? h("p", null, text) : null, action || null);
}

// --- continue watching ---------------------------------------------------------

export function continueWatching(limit = 15) {
  const host = h("section.section", { "aria-label": "Continue watching" });
  const render = () => {
    clear(host);
    const entries = history.latestPerAnime().slice(0, limit);
    if (!entries.length) { host.hidden = true; return; }
    host.hidden = false;
    host.append(
      sectionHead("Continue Watching", { href: "/history", label: "More" }),
      shelf(entries.map(cwCard), "cw"));
  };
  render();
  history.onChange(render);
  return host;
}

function cwCard(e) {
  const done = history.finished(e);
  // A finished episode continues with the next one.
  const ep = done ? e.episode + 1 : e.episode;
  const frac = e.duration_ms ? Math.min(1, e.position_ms / e.duration_ms) : 0;
  return h("a.poster.cw-card", { href: `/watch/${e.anime_id}/${ep}`, title: e.title },
    h("div.frame.px-box", null,
      pixelCover(e.cover, 120, e.title),
      h("span.chip.ep.px-box", null, `EP ${ep}`),
      h("div.play", null, h("span.px-box", null, sprite("play", 2.4))),
      done ? null : h("div.px-bar.progress", null, h("i", null, h("b", { style: { width: `${frac * 100}%` } })))),
    h("div.title", null, e.title || "Untitled"),
    h("div.sub", null, done ? "Up next" : `${Math.round(frac * 100)}% watched`));
}

// --- spotlight --------------------------------------------------------------------

export function heroSpotlight(animes) {
  const slides = animes.slice(0, 5);
  if (!slides.length) return h("div");
  let on = 0, timer = 0;
  const slideEls = slides.map((a, i) => {
    const title = titleOf(a);
    const blurb = plainText(a.description || "");
    const meta = metaLine(a);
    const canvas = h("canvas.drips");
    const el = h("div.hero-slide", { "aria-hidden": i ? "true" : "false" },
      h("div.backdrop", null, pixelCover(coverOf(a), 24)),
      h("div.shade"),
      canvas,
      h("div.hero-body", null,
        h("a.poster-art.px-box", { href: `/anime/${a.id}`, "aria-label": title }, pixelCover(coverOf(a), 90, title)),
        h("div.hero-info", null,
          h("span.chip.kicker.px-box", null, `#${i + 1} Spotlight`),
          h("h3", null, title),
          meta ? h("div.meta", null, meta) : null,
          blurb ? h("div.blurb", null, blurb) : null,
          h("div.actions", null,
            h("a.px-btn.px-box.bevel", { href: `/watch/${a.id}/1` }, sprite("play", 1.6), "Watch now"),
            h("a.px-btn.dark.px-box.bevel", { href: `/anime/${a.id}` }, "Details")))));
    el._drips = () => { if (!canvas._on) { canvas._on = true; drips(canvas, { count: 7, seed: title.length, cell: 3 }); } };
    return el;
  });
  const dots = slides.map((_, i) => h("button", { type: "button", "aria-label": `Slide ${i + 1}`, onclick: () => go(i, true) }));
  let first = true;
  const go = (i, user) => {
    const dir = i < on ? -1 : 1;
    on = (i + slides.length) % slides.length;
    slideEls.forEach((el, j) => {
      el.classList.toggle("on", j === on);
      el.classList.remove("enter-next", "enter-prev");
      el.setAttribute("aria-hidden", j === on ? "false" : "true");
    });
    if (!first) {
      void slideEls[on].offsetWidth;
      slideEls[on].classList.add(dir > 0 ? "enter-next" : "enter-prev");
      speedLines(stage, -dir);
    }
    first = false;
    dots.forEach((d, j) => d.classList.toggle("on", j === on));
    slideEls[on]._drips();
    if (user) restart();
  };
  const restart = () => {
    clearInterval(timer);
    timer = setInterval(() => { if (!document.hidden) go(on + 1); }, 7000);
  };
  const stage = h("div.hero-stage.px-box.rivets", null, slideEls,
    slides.length > 1 ? h("button.hero-arrow.prev.px-box", { type: "button", "aria-label": "Previous", onclick: () => go(on - 1, true) },
      h("span", { style: { transform: "scaleX(-1)", display: "grid" } }, sprite("chevron", 2))) : null,
    slides.length > 1 ? h("button.hero-arrow.next.px-box", { type: "button", "aria-label": "Next", onclick: () => go(on + 1, true) }, sprite("chevron", 2)) : null);
  // Swipe on touch screens.
  let x0 = null;
  stage.addEventListener("touchstart", (e) => { x0 = e.touches[0].clientX; }, { passive: true });
  stage.addEventListener("touchend", (e) => {
    if (x0 === null) return;
    const dx = e.changedTouches[0].clientX - x0;
    if (Math.abs(dx) > 40) go(on + (dx < 0 ? 1 : -1), true);
    x0 = null;
  });
  const root = h("section.hero.section", { "aria-label": "Spotlight" }, stage, slides.length > 1 ? h("div.hero-dots", null, dots) : null);
  queueMicrotask(() => { go(0); restart(); });
  return root;
}

export function heroSkeleton() {
  return h("section.hero.section", { "aria-hidden": "true" }, h("div.hero-stage.px-box.skel"));
}

export function metaLine(a) {
  const parts = [];
  const next = a.nextAiringEpisode;
  if (next && next.episode > 1) parts.push(`Ep ${next.episode - 1} out now`);
  else if (a.episodes) parts.push(a.episodes === 1 ? "1 episode" : `${a.episodes} episodes`);
  if (a.format) parts.push(String(a.format).replace("_", " "));
  if (a.averageScore) parts.push(`${a.averageScore}%`);
  return parts.join(" · ");
}

// --- the page shell -----------------------------------------------------------------

function headerSearch() {
  const input = document.getElementById("header-q");
  const box = document.getElementById("header-suggest");
  if (!input || !box) return;
  let timer = 0, seq = 0, items = [], active = -1;
  const close = () => { box.hidden = true; active = -1; };
  const highlight = () => items.forEach((a, i) => a.classList.toggle("active", i === active));
  input.addEventListener("input", () => {
    clearTimeout(timer);
    const q = input.value.trim();
    if (q.length < 2) { close(); return; }
    timer = setTimeout(async () => {
      const mine = ++seq;
      const results = (await api.search(q)).slice(0, 6);
      if (mine !== seq) return;
      clear(box);
      items = results.map((a) => h("a", { href: `/anime/${a.id}` },
        pixelCover(coverOf(a), 48, ""),
        h("div", null, h("div.s-title", null, titleOf(a)), h("div.s-meta", null, metaLine(a)))));
      if (!items.length) box.append(h("div.empty", null, "No matches"));
      else box.append(...items, h("a", { href: `/search?q=${encodeURIComponent(q)}` }, h("div.s-meta", null, "See all results")));
      box.hidden = false;
      active = -1;
    }, 280);
  });
  input.addEventListener("keydown", (e) => {
    if (box.hidden) return;
    if (e.key === "ArrowDown") { active = Math.min(items.length - 1, active + 1); highlight(); e.preventDefault(); }
    else if (e.key === "ArrowUp") { active = Math.max(-1, active - 1); highlight(); e.preventDefault(); }
    else if (e.key === "Escape") close();
    else if (e.key === "Enter" && active >= 0) { items[active].click(); e.preventDefault(); }
  });
  input.form?.addEventListener("submit", (e) => { if (!input.value.trim()) e.preventDefault(); });
  document.addEventListener("click", (e) => { if (!box.contains(e.target) && e.target !== input) close(); });
}

function accountNav() {
  const slot = document.getElementById("nav-account");
  if (!slot) return;
  const render = (user) => {
    const icon = slot.querySelector(".nav-icon");
    clear(icon);
    if (user) icon.append(h("span.avatar", null, (user.display_name || user.username || "?").trim().charAt(0).toUpperCase()));
    else icon.append(sprite("user", 2.2));
    slot.setAttribute("aria-label", user ? `Account: ${user.display_name || user.username}` : "Sign in");
    slot.querySelector(".nav-text").textContent = user ? "Account" : "Sign in";
  };
  render(auth.user);
  auth.onChange(render);
}

async function appPromo() {
  const slot = document.getElementById("app-promo");
  if (!slot) return;
  const rel = await api.appRelease();
  if (!rel || !rel.available) return;
  const mb = rel.size ? ` · ${(rel.size / 1048576).toFixed(0)} MB` : "";
  slot.append(h("div.app-promo.px-box", null,
    h("img.emblem", { src: emblemUrl() || "/static/pixel/img/logo.png", alt: "", width: 34, height: 30, style: { imageRendering: "pixelated" } }),
    h("div.txt", null, h("b", null, "AniVerse Pixel for Android"), h("span", null, `Version ${rel.versionName}${mb}`)),
    h("a.px-btn.px-box.bevel.small", { href: "/app/aniverse.apk", download: "AniVerse-Pixel.apk" }, sprite("download", 1.4), "Get the app")));
}

/** Same-site page links play the dissolve before leaving. */
function pageTransitions() {
  const root = document.documentElement;
  let switched = null;
  try { switched = sessionStorage.getItem("av.palette"); sessionStorage.removeItem("av.palette"); } catch { /* storage off */ }
  if (switched) {
    // Arriving from a palette switch: uncover in that palette's style.
    try { sessionStorage.removeItem("av.dissolve"); } catch { /* storage off */ }
    paletteSwitch(switched, "reveal");
    root.classList.remove("entering");
  } else if (root.classList.contains("entering")) {
    try { sessionStorage.removeItem("av.dissolve"); } catch { /* storage off */ }
    // The dissolve draws its first frame synchronously, so the page is still
    // covered when the CSS cover goes. (Not on a later frame: a background
    // tab may not get one until it is shown, and would sit there black.)
    dissolve("in", 220);
    root.classList.remove("entering");
  }
  document.addEventListener("click", (e) => {
    const a = e.target instanceof Element ? e.target.closest("a[href]") : null;
    if (!a || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if ((a.target && a.target !== "_self") || a.hasAttribute("download")) return;
    const url = new URL(a.href, location.href);
    if (url.origin !== location.origin || /^\/(app|static|api|proxy)\//.test(url.pathname)) return;
    if (url.pathname === location.pathname && url.search === location.search) return; // same page / anchor
    e.preventDefault();
    try { sessionStorage.setItem("av.dissolve", "1"); } catch { /* storage off */ }
    dissolve("out", 160).then(() => { location.href = url.href; });
  });
  // Back/forward restores the page as it was left: covered. Uncover it.
  addEventListener("pageshow", (e) => {
    if (e.persisted) document.querySelectorAll("canvas.dissolve").forEach((c) => c.remove());
  });
}

// --- new-episode alerts, sounds, achievements, offline install ---------------------

/** Followed shows with episodes out since you last looked: a dot on My List,
 *  a toast once per visit, and a system notification if you turned that on. */
async function checkAlerts() {
  if (!watchlist.all().length) return;
  const fresh = await watchlist.newEpisodes();
  document.querySelectorAll(".nav-mylist .alert-dot").forEach((d) => { d.hidden = !fresh.length; });
  if (!fresh.length) return;
  const key = fresh.map((f) => `${f.entry.anime_id}:${f.aired}`).join(",");
  let told = "";
  try { told = sessionStorage.getItem("av.alerted") || ""; sessionStorage.setItem("av.alerted", key); } catch { /* storage off */ }
  if (told === key) return;
  const first = fresh[0];
  const text = fresh.length === 1
    ? `New: ${first.entry.title} episode ${first.aired} is out`
    : `${fresh.length} shows on your list have new episodes`;
  toast(text, { action: { label: "Watch", run: () => { location.href = fresh.length === 1 ? `/watch/${first.entry.anime_id}/${first.aired}` : "/mylist"; } } });
  if (settings.get().alerts && "Notification" in window && Notification.permission === "granted") {
    try { new Notification("AniVerse", { body: text, icon: "/static/pixel/img/icon-192.png", tag: key }); } catch { /* not allowed here */ }
  }
}

function soundHooks() {
  document.addEventListener("pointerdown", (e) => {
    const el = e.target instanceof Element ? e.target.closest(".px-btn, .icon-btn, .ep-btn, .toggle, .poster, .px-switch") : null;
    if (!el || el.matches(":disabled")) return;
    sfx(el.matches(".px-btn:not(.dark):not(.bone), .big-play") ? "splat" : "click");
  });
}

function achievementToasts() {
  const show = () => {
    for (const b of newlyUnlocked()) {
      sfx("achieve");
      toast(`Achievement unlocked: ${b.name} — ${b.text}`, { ms: 7000, action: { label: "View", run: () => { location.href = "/account"; } } });
    }
  };
  show();
  history.onChange(show);
}

/** Everything every page needs once. */
// --- error reports (app/ops.py): crashes and episodes that would not play ---------------
let reportsLeft = 5;
const pageVersion = () => {
  const src = document.querySelector('script[type="module"][src*="?v="]')?.getAttribute("src") || "";
  return new URL(src, location.href).searchParams.get("v") || "";
};

/** Tells the server something went wrong here; never throws, at most a few per page. */
export function reportError({ kind = "error", message = "", stack = "", where = location.pathname } = {}) {
  if (reportsLeft <= 0 || !message) return;
  reportsLeft--;
  const body = JSON.stringify({ source: "web", version: pageVersion(), kind, message: String(message).slice(0, 2000),
    stack: String(stack || "").slice(0, 8000), where: String(where).slice(0, 200) });
  try {
    if (!navigator.sendBeacon?.("/api/client-errors", new Blob([body], { type: "application/json" }))) {
      fetch("/api/client-errors", { method: "POST", headers: { "Content-Type": "application/json" }, body, keepalive: true }).catch(() => {});
    }
  } catch { /* a report must never become an error itself */ }
}

function errorReports() {
  window.addEventListener("error", (e) => reportError({ message: e.message, stack: e.error?.stack || `${e.filename}:${e.lineno}` }));
  window.addEventListener("unhandledrejection", (e) => reportError({ message: String(e.reason?.message || e.reason), stack: e.reason?.stack }));
}

// --- arrow-key navigation, for TV browsers and remotes --------------------------------
// Arrow keys move focus to the nearest control in that direction. Inside the
// video player they are left alone: there they seek and change the volume.
const FOCUSABLE = 'a[href], button:not([disabled]), input:not([type="hidden"]), select, textarea, [tabindex]:not([tabindex="-1"])';

function spatialNav() {
  window.addEventListener("keydown", (e) => {
    const dir = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    if (!dir || e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
    const from = document.activeElement;
    const typing = from instanceof HTMLElement && from.closest('input:not([type="range"]), textarea, select, [contenteditable]');
    // Text boxes keep left/right for the cursor; up/down leave them.
    if (typing && dir[0] !== 0) return;
    const onPage = from && from !== document.body && from instanceof HTMLElement;
    if (onPage && from.closest(".player")) return;           // the player's own keys
    if (!onPage && document.querySelector(".player")) return; // nothing focused on the watch page: the player has them
    const rect = onPage ? from.getBoundingClientRect() : new DOMRect(0, 0, 0, 0);
    const cx = rect.left + rect.width / 2, cy = rect.top + rect.height / 2;
    let best = null, bestScore = Infinity;
    for (const el of document.querySelectorAll(FOCUSABLE)) {
      if (el === from || el.closest("[hidden], [inert]")) continue;
      const r = el.getBoundingClientRect();
      if (!r.width || !r.height) continue;
      const x = r.left + r.width / 2, y = r.top + r.height / 2;
      const along = (x - cx) * dir[0] + (y - cy) * dir[1];
      if (onPage && along <= 1) continue;
      const across = Math.abs((x - cx) * dir[1] + (y - cy) * dir[0]);
      const score = onPage ? along + across * 2 : y * 4 + x; // from nothing: the top-left-most
      if (score < bestScore) { bestScore = score; best = el; }
    }
    if (!best) return;
    e.preventDefault();
    best.focus({ preventScroll: true });
    best.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" });
  }, true);
}

export function initShell() {
  errorReports();
  spatialNav();
  // The header emblem in the palette's colours (Blood keeps the crimson PNG).
  const emblem = emblemUrl();
  document.querySelectorAll('img[src$="/pixel/img/logo.png"]').forEach((img) => {
    img.classList.add("emblem"); // so a palette switch can recolour it
    if (emblem) img.src = emblem;
  });
  hydrateSprites();
  const bg = document.querySelector("canvas.embers-bg");
  if (bg) embers(bg);
  pageTransitions();
  soundHooks();
  achievementToasts();
  // Secure origins only (the tunnel, or localhost): installable, and alerts by push.
  if ("serviceWorker" in navigator && isSecureContext) {
    navigator.serviceWorker.register("/sw.js").catch(() => { /* installable is a bonus */ });
  }
  auth.onChange((user) => { if (user) watchlist.sync({ full: true }).then(checkAlerts); });
  if (auth.token) watchlist.sync().then(checkAlerts); else checkAlerts();
  setInterval(checkAlerts, 30 * 60 * 1000);
  const logoDrips = document.querySelector(".logo canvas.drips");
  if (logoDrips) drips(logoDrips, { count: 4, seed: 3, cell: 2.4 });
  headerSearch();
  accountNav();
  appPromo();
  if (auth.token) { auth.refresh(); history.sync(); }
}
