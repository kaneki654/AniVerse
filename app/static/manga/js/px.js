// Manga building blocks for the website, ported from the AniVerse app's manga
// UI (aniverse_mobile/lib/ui_manga): ink icons, cover art in panels, the ensō
// loader, the inked emblem filling with red ink, speech-bubble toasts, page
// turns, focus lines and impacts. The same exports as the pixel UI's px.js, so
// the page scripts work unchanged.

import { ICONS } from "./icons.js";
// The share card on the account page draws its badges from the pixel sprites.
export { SPRITES, PixelCanvas } from "/static/pixel/js/px.js";

const IMG = "/static/manga/img";

/** The ink and paper, by the pixel palette's keys (for code that reads them). */
export const C = {
  K: "#121010", k: "#f5f1e8", P: "#ffffff", p: "#eae4d8",
  R: "#e50914", r: "#9e0610", d: "#4a0308", H: "#ff5a64",
  W: "#ffffff", g: "#5c5852", G: "#9a948b",
  S: "#d6cfc2", s: "#9a948b", Y: "#e50914", y: "#9e0610",
};

/** One look, no palettes: nothing to pick up. */
export function refreshPalette() {}

export const fxStyle = () => "manga";
export const fxLevel = () => document.documentElement.dataset.fx || "full";
const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
const still = () => reducedMotion() || fxLevel() === "off";

// --- icons ----------------------------------------------------------------------------

/** An icon from the Material icon font (the app's glyphs), at the size a pixel
 *  sprite of [scale] had, so the page layouts keep their proportions. */
export function sprite(name, scale = 2, color) {
  const el = document.createElement("i");
  el.className = "mi sprite";
  el.setAttribute("aria-hidden", "true");
  el.textContent = String.fromCodePoint(ICONS[name] ?? ICONS.star);
  el.style.fontSize = `${Math.round(scale * 10)}px`;
  if (color) el.style.color = color;
  el.dataset.name = name;
  return el;
}

/** Replaces every <i data-sprite="name" data-scale="2"> with its icon. */
export function hydrateSprites(root = document) {
  root.querySelectorAll("i[data-sprite]").forEach((el) => {
    const s = sprite(el.dataset.sprite, Number(el.dataset.scale || 2), el.dataset.color);
    if (el.className) s.classList.add(...el.className.split(/\s+/).filter(Boolean));
    el.replaceWith(s);
  });
}

// --- safe element builder -----------------------------------------------------------

/**
 * h("a.poster#id", {href}, child, "text") -> element. Strings become text nodes,
 * never markup, so titles and descriptions from the API cannot inject HTML.
 */
export function h(tag, attrs, ...children) {
  const [selector, id] = tag.split("#");
  const [name, ...classes] = selector.split(".");
  const el = document.createElement(name || "div");
  if (classes.length) el.className = classes.join(" ");
  if (id) el.id = id;
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v === undefined || v === null || v === false) continue;
      if (k === "class") el.className += (el.className ? " " : "") + v;
      else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
      else if (k === "dataset") Object.assign(el.dataset, v);
      else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2), v);
      else if (v === true) el.setAttribute(k, "");
      else el.setAttribute(k, String(v));
    }
  }
  append(el, children);
  return el;
}

function append(el, children) {
  for (const c of children.flat(Infinity)) {
    if (c === null || c === undefined || c === false) continue;
    el.appendChild(c instanceof Node ? c : document.createTextNode(String(c)));
  }
}

export function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); return el; }

/** Plain text of an AniList description, which carries <br> and <i> markup. */
export function plainText(html) {
  if (!html) return "";
  const withBreaks = String(html).replace(/<br\s*\/?>/gi, "\n");
  const doc = new DOMParser().parseFromString(withBreaks, "text/html");
  return (doc.body.textContent || "").replace(/\n{3,}/g, "\n\n").trim();
}

// --- frame clock --------------------------------------------------------------------
// Limited animation: drawings change a dozen times a second, not every frame.
// Animations off screen or in a hidden tab are skipped.

const anims = new Set();
let rafId = 0;
const visible = new WeakMap();
const io = "IntersectionObserver" in window
  ? new IntersectionObserver((entries) => { for (const e of entries) visible.set(e.target, e.isIntersecting); })
  : null;

function loop(now) {
  rafId = 0;
  for (const a of anims) {
    if (!a.el.isConnected) { anims.delete(a); io?.unobserve(a.el); continue; }
    if (visible.get(a.el) === false) continue;
    const frame = Math.floor(((now - a.t0) / 1000) * a.fps);
    if (frame !== a.last) {
      a.last = frame;
      a.draw(a.frames ? frame % a.frames : frame);
    }
  }
  if (anims.size && !document.hidden) rafId = requestAnimationFrame(loop);
}
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && anims.size && !rafId) rafId = requestAnimationFrame(loop);
});

/** Runs draw(frame) at fps for as long as el stays in the document. */
export function animate(el, fps, frames, draw) {
  const a = { el, fps, frames, draw, t0: performance.now(), last: -1 };
  anims.add(a);
  io?.observe(el);
  if (!rafId) rafId = requestAnimationFrame(loop);
  return () => { anims.delete(a); io?.unobserve(el); };
}

/** Stable pseudo-random value in [0, 1) for seed -- the same as the app's. */
export function pxRand(seed) {
  let x = (Math.imul(seed, 0x27d4eb2d) + 0x165667b1) & 0x7fffffff;
  x ^= x >> 15;
  x = Math.imul(x, 0x2c1b3c6d) & 0x7fffffff;
  x ^= x >> 12;
  return (x % 100000) / 100000;
}

// --- cover art ------------------------------------------------------------------------

/** Cover art in a panel: the picture as it is (covers should stay
 *  recognisable), screentone darkening its foot. Fills its positioned parent. */
export function pixelCover(url, decode = 96, label = "") {
  const box = h("div.px-cover.skel", label ? { role: "img", "aria-label": label } : { "aria-hidden": "true" });
  const noArt = () => {
    box.classList.remove("skel");
    clear(box).appendChild(h("div.noart", null, sprite("skull", 2.6)));
  };
  if (!url) { noArt(); return box; }
  const img = h("img", { alt: "", loading: "lazy", decoding: "async", referrerpolicy: "no-referrer" });
  img.onload = () => box.classList.remove("skel");
  img.onerror = noArt;
  img.src = url;
  box.append(img, h("i.tone"));
  return box;
}

/** The pixel UI's blood drips: manga pages have none. */
export function drips() {}

/** The pixel UI's ember backdrop: the manga page is plain paper. */
export function embers() {}

// --- impacts ----------------------------------------------------------------------------

/** A sound effect popping up at a point on the screen and gone a moment later. */
export function popSfx(x, y, text = "ドン!", color = "") {
  if (still()) return;
  const el = h("span.sfx-pop", { "aria-hidden": "true", style: { left: `${x}px`, top: `${y}px` } }, text);
  if (color) el.style.color = color;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 700);
}

/** Where the pixel UI splattered blood, the manga one lands a ドン. */
export function splat(x, y) { popSfx(x, y, "ドン!"); }

/** The page jolts, like a panel on an impact. */
export function shake() {
  if (still()) return;
  document.body.classList.remove("shake");
  void document.body.offsetWidth; // restart the animation
  document.body.classList.add("shake");
  setTimeout(() => document.body.classList.remove("shake"), 420);
}

// --- loader -------------------------------------------------------------------------------

/** Waiting: an ensō brush circle drawing itself round and round the inked emblem. */
export function katana(width = 170) {
  const s = Math.round(Math.min(width, 170) * 0.66);
  const el = h("div.enso", { style: { width: `${s}px`, height: `${s}px` } }, h("img", { src: `${IMG}/logo.png`, alt: "" }));
  el.insertAdjacentHTML("afterbegin",
    '<svg viewBox="0 0 100 100" aria-hidden="true"><circle class="stroke" cx="50" cy="50" r="42"/><circle class="dry" cx="50" cy="50" r="42"/></svg>');
  return el;
}

// --- buffering ------------------------------------------------------------------------------

/**
 * The player's buffering state, inked: the emblem as line art with red ink
 * rising inside it as the video downloads, ゴゴゴ trembling at its sides and
 * the speed in a caption panel. Returns {el, set({progress, mbps}), level};
 * progress null means unknown, and the ink idles low instead of rising.
 */
export function orb(size = 136, initialLevel = 0.08) {
  const s = Math.round(size);
  const fill = h("div.fill", null, h("img", { src: `${IMG}/logo_color.png`, alt: "", style: { height: `${s * 0.84}px` } }));
  const ring = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  ring.setAttribute("viewBox", "0 0 100 100");
  ring.setAttribute("class", "ring");
  ring.innerHTML = '<circle class="rim" cx="50" cy="50" r="46"/><circle class="arc" cx="50" cy="50" r="41" pathLength="100"/>';
  const disc = h("div.disc", { style: { width: `${s}px`, height: `${s}px` } },
    fill,
    h("img.layer", { src: `${IMG}/logo_tone.png`, alt: "" }),
    h("img.layer", { src: `${IMG}/logo_lines.png`, alt: "" }),
    ring);
  const rumble = (side) => h(`div.rumble.${side}`, { "aria-hidden": "true" }, ["ゴ", "ゴ", "ゴ"].map((g) => h("span", null, g)));
  const speedB = h("b");
  const speed = h("div.speed", null, speedB, h("small", null, "MBPS"));
  const el = h("div.orb.ink", null, h("div.row", null, rumble("left"), disc, rumble("right")), speed);
  el.style.setProperty("--s", `${s}px`);

  let level = Math.min(1, Math.max(0, initialLevel));
  let progress = null;
  const arc = ring.querySelector(".arc");
  animate(disc, 12, 48, (frame) => {
    const target = progress !== null ? Math.min(1, Math.max(0, progress)) : 0.24 + 0.06 * Math.sin(frame / 48 * 2 * Math.PI);
    level += (target - level) * (target > level ? 0.3 : 0.12);
    fill.style.height = `${(level * 100).toFixed(1)}%`;
    arc.style.strokeDashoffset = String(100 - level * 100);
  });
  const set = ({ progress: p, mbps } = {}) => {
    if (p !== undefined) progress = p;
    if (mbps !== undefined) speedB.textContent = mbps == null ? "--" : mbps < 10 ? mbps.toFixed(mbps < 1 ? 2 : 1) : mbps.toFixed(0);
  };
  set({ mbps: null });
  return { el, set, level: () => level };
}

// --- toasts & dialogs ------------------------------------------------------------------

let toastHost;
/** A message in a speech bubble popping up from the foot of the page;
 *  optional {action: {label, run}}. */
export function toast(message, { action, ms = 5000 } = {}) {
  toastHost ??= document.body.appendChild(h("div.toasts", { role: "status", "aria-live": "polite" }));
  const t = h("div.toast.bubble", null, h("span.msg", null, message));
  if (action) t.appendChild(h("button.px-btn.small", { type: "button", onclick: () => { action.run(); t.remove(); } }, action.label));
  toastHost.appendChild(t);
  setTimeout(() => {
    t.classList.add("out");
    setTimeout(() => t.remove(), 260);
  }, ms);
  return t;
}

/** Resolves true/false. A panel slammed onto the page, its title in a caption box. */
export function confirmDialog(title, text, okLabel = "OK") {
  return new Promise((resolve) => {
    const done = (v) => { back.remove(); resolve(v); };
    const back = h("div.dialog-back", { onclick: (e) => { if (e.target === back) done(false); } },
      h("div.dialog.px-box", { role: "dialog", "aria-modal": "true", "aria-label": title },
        h("h3", null, title),
        h("p", null, text),
        h("div.row", null,
          h("button.px-btn.dark.px-box.small", { type: "button", onclick: () => done(false) }, "Cancel"),
          h("button.px-btn.px-box.small", { type: "button", onclick: () => done(true) }, okLabel))));
    document.body.appendChild(back);
    back.querySelector(".px-btn:last-child").focus();
    back.addEventListener("keydown", (e) => { if (e.key === "Escape") done(false); });
  });
}

export function fmtTime(sec) {
  if (!Number.isFinite(sec) || sec < 0) sec = 0;
  sec = Math.floor(sec);
  const hgt = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  const ss = String(s).padStart(2, "0");
  return hgt ? `${hgt}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

// --- focus lines ------------------------------------------------------------------------

/** Draws focus lines (集中線): black wedges converging on (cx, cy), the middle left clear. */
export function focusLines(ctx, w, hgt, { cx = w / 2, cy = hgt / 2, seed = 0, count = 90, clear: gap = 0.42, color = "#121010" } = {}) {
  const reach = Math.max(w, hgt) * 1.2;
  ctx.fillStyle = color;
  for (let i = 0; i < count; i++) {
    const a = (i / count) * Math.PI * 2 + pxRand(seed * 131 + i) * 0.05;
    const inner = Math.min(w, hgt) * (gap + pxRand(seed * 17 + i * 7) * 0.22);
    const half = 0.006 + pxRand(seed * 29 + i * 3) * 0.016;
    ctx.beginPath();
    ctx.moveTo(cx + Math.cos(a) * inner, cy + Math.sin(a) * inner);
    ctx.lineTo(cx + Math.cos(a - half) * reach, cy + Math.sin(a - half) * reach);
    ctx.lineTo(cx + Math.cos(a + half) * reach, cy + Math.sin(a + half) * reach);
    ctx.fill();
  }
}

/** Focus lines flickering over [host] for a moment: a page of the spotlight landing. */
export function speedLines(host, dir = 1) {
  if (fxLevel() !== "full" || reducedMotion()) return;
  host.querySelectorAll("canvas.speedlines").forEach((c) => c.remove());
  const r = host.getBoundingClientRect();
  const canvas = h("canvas.speedlines", { width: Math.round(r.width), height: Math.round(r.height), "aria-hidden": "true" });
  host.appendChild(canvas);
  const ctx = canvas.getContext("2d");
  animate(canvas, 14, 0, (f) => {
    if (f > 6) { canvas.remove(); return; }
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const alpha = (0.55 * (1 - f / 7)).toFixed(2);
    focusLines(ctx, canvas.width, canvas.height, {
      cx: canvas.width * (dir > 0 ? 0.62 : 0.38), cy: canvas.height / 2, seed: f + 1, count: 70, clear: 0.5,
      color: `rgba(18,16,16,${alpha})`,
    });
  });
}

// --- page turns ---------------------------------------------------------------------------

/**
 * Pages change like turning a page: "out" sweeps a sheet of paper in from the
 * right along a slanted fold until it covers the page; "in" (the new page)
 * starts covered and the sheet sweeps on off to the left. A line of ink on the
 * fold, screentone shading just behind it.
 */
export function dissolve(mode, ms = 340) {
  return new Promise((resolve) => {
    if (still()) { resolve(); return; }
    const sheet = h(`div.pageturn.${mode}`, { "aria-hidden": "true" });
    sheet.style.setProperty("--dur", `${ms}ms`);
    document.body.appendChild(sheet);
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      if (mode === "in") sheet.remove();
      resolve();
    };
    sheet.addEventListener("animationend", finish, { once: true });
    setTimeout(finish, ms + 150);
  });
}

// --- the emblem ------------------------------------------------------------------------------

/** The inked emblem: one look, so always the same picture. */
export function emblemUrl() { return `${IMG}/logo.png`; }

/** Palettes are the pixel look's; the manga look has one. */
export function paletteSwitch() { return Promise.resolve(); }
export function retheme() {}
