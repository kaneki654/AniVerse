// Pixel-art building blocks for the website, ported from the AniVerse Pixel
// app (aniverse_mobile/lib/ui_2d/pixel): palette, sprites, cover art, and the
// blood effects. Everything is drawn one canvas pixel per art cell and scaled
// up by CSS with no smoothing, so edges stay hard at any size.

export const C = {
  K: "#050305", k: "#0d0709", P: "#1b1114", p: "#2a1a1f",
  R: "#d10a1a", r: "#7a0410", d: "#3d0107", H: "#ff4d57",
  W: "#f2e8d5", g: "#9a918c", G: "#5a5250",
  S: "#d5dce6", s: "#7d8796", Y: "#e8b23a", y: "#9c6a14",
};
let BLOOD = C.R, BLOOD_DARK = C.r, BLOOD_DEEP = C.d, BLOOD_LIGHT = C.H;

/**
 * Picks up the palette the page is themed with (Settings: Blood, Neon cyber,
 * Sakura): the CSS custom properties are the one source, so canvas effects
 * and sprites change colour together with everything else.
 */
export function refreshPalette() {
  const css = getComputedStyle(document.documentElement);
  const v = (name, fallback) => (css.getPropertyValue(name).trim() || fallback);
  C.R = v("--blood", C.R); C.r = v("--blood-dark", C.r); C.d = v("--blood-deep", C.d); C.H = v("--blood-light", C.H);
  C.Y = v("--gold", C.Y); C.y = v("--gold-dark", C.y);
  BLOOD = C.R; BLOOD_DARK = C.r; BLOOD_DEEP = C.d; BLOOD_LIGHT = C.H;
  RGB_BLOOD = hexToRgb(BLOOD);
}

function hexToRgb(hex) {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex.trim());
  return m ? `${parseInt(m[1], 16)},${parseInt(m[2], 16)},${parseInt(m[3], 16)}` : "209,10,26";
}

// --- sprites: rows of palette keys, 'X' takes the colour it is drawn in -----------
export const SPRITES = {
  play: ["XX.......", "XXXX.....", "XXXXXX...", "XXXXXXXX.", "XXXXXXXXX", "XXXXXXXX.", "XXXXXX...", "XXXX.....", "XX......."],
  pause: ["XXX...XXX", "XXX...XXX", "XXX...XXX", "XXX...XXX", "XXX...XXX", "XXX...XXX", "XXX...XXX", "XXX...XXX", "XXX...XXX"],
  back: ["....X....", "...XX....", "..XXX....", ".XXXXXXXX", "XXXXXXXXX", ".XXXXXXXX", "..XXX....", "...XX....", "....X...."],
  chevron: ["XX.....", "XXX....", ".XXX...", "..XXX..", "...XXX.", "..XXX..", ".XXX...", "XXX....", "XX....."],
  rewind: ["...X...X", "..XX..XX", ".XXX.XXX", "XXXXXXXX", ".XXX.XXX", "..XX..XX", "...X...X"],
  forward: ["X...X...", "XX..XX..", "XXX.XXX.", "XXXXXXXX", "XXX.XXX.", "XX..XX..", "X...X..."],
  skipNext: ["X......XX", "XXX....XX", "XXXXX..XX", "XXXXXXXXX", "XXXXX..XX", "XXX....XX", "X......XX"],
  search: ["..XXXX....", ".XX..XX...", "XX....XX..", "XX....XX..", "XX....XX..", ".XX..XX...", "..XXXXXX..", "......XXX.", ".......XXX", "........XX"],
  gear: ["....XXX....", ".XX.XXX.XX.", ".XXXXXXXXX.", "..XXXXXXX..", "XXXX...XXXX", "XXXX...XXXX", "XXXX...XXXX", "..XXXXXXX..", ".XXXXXXXXX.", ".XX.XXX.XX.", "....XXX...."],
  user: ["...XXX...", "..XXXXX..", "..XXXXX..", "..XXXXX..", "...XXX...", ".........", ".XXXXXXX.", "XXXXXXXXX", "XXXXXXXXX"],
  grid: ["XXXX.XXXX", "XXXX.XXXX", "XXXX.XXXX", "XXXX.XXXX", ".........", "XXXX.XXXX", "XXXX.XXXX", "XXXX.XXXX", "XXXX.XXXX"],
  clock: ["...XXXXX...", "..X.....X..", ".X...X...X.", "X....X....X", "X....X....X", "X....XXX..X", "X.........X", "X.........X", ".X.......X.", "..X.....X..", "...XXXXX..."],
  trash: ["...XXX...", "XXXXXXXXX", ".........", ".XXXXXXX.", ".X.X.X.X.", ".X.X.X.X.", ".X.X.X.X.", ".X.X.X.X.", ".XXXXXXX."],
  fullscreen: ["XXX...XXX", "X.......X", "X.......X", ".........", ".........", ".........", "X.......X", "X.......X", "XXX...XXX"],
  fullscreenExit: ["..X...X..", "..X...X..", "XXX...XXX", ".........", ".........", ".........", "XXX...XXX", "..X...X..", "..X...X.."],
  swap: ["......X..", "......XX.", "XXXXXXXXX", "......XX.", "..XX..X..", ".XX......", "XXXXXXXXX", ".XX......", "..X......"],
  refresh: ["..XXXX.X.", ".XX..XXX.", "XX...XXX.", "X........", "X.......X", "XX.....XX", ".XX...XX.", "..XXXXX.."],
  check: ["........X", ".......XX", "......XX.", "X....XX..", "XX..XX...", ".XXXX....", "..XX....."],
  close: ["XX...XX", "XXX.XXX", ".XXXXX.", "..XXX..", ".XXXXX.", "XXX.XXX", "XX...XX"],
  eye: ["...XXXXX...", ".XX.....XX.", "X....X....X", "X...XXX...X", "X....X....X", ".XX.....XX.", "...XXXXX..."],
  eyeOff: ["X..XXXXX...", ".XX.....XX.", "X.X..X....X", "X...XXX...X", "X....XXX..X", ".XX.....XX.", "...XXXXX.X."],
  lock: ["..XXXXX..", ".X.....X.", ".X.....X.", "XXXXXXXXX", "XXXX.XXXX", "XXX...XXX", "XXXX.XXXX", "XXXXXXXXX", "XXXXXXXXX"],
  logout: ["XXXXX....", "X...X....", "X...X.X..", "X...X.XX.", "X.XXXXXXX", "X...X.XX.", "X...X.X..", "X...X....", "XXXXX...."],
  floppy: ["XXXXXXXX.", "X.XXXX.XX", "X.XXXX..X", "X.......X", "X.XXXXX.X", "X.X...X.X", "X.X...X.X", "XXXXXXXXX"],
  star: ["....X....", "....X....", "...XXX...", "XXXXXXXXX", ".XXXXXXX.", "..XXXXX..", "..XX.XX..", ".XX...XX.", ".X.....X."],
  bloodDrop: ["...K...", "..KRK..", "..KRK..", ".KRRRK.", ".KHRRK.", "KRHRRRK", "KRRRRrK", "KRRRrrK", ".KrrrK.", "..KKK.."],
  skull: ["..KKKKKKK..", ".KWWWWWWWK.", "KWWWWWWWWWK", "KWRRWWWRRWK", "KWRRWWWRRWK", "KWRWWKWWRWK", ".KRWWWWWRK.", "..KWKWKWK..", "..KWKWKWK..", "...KKKKK..."],
  skullSmall: [".KKKKK.", "KWWWWWK", "KRWWWRK", "KWWKWWK", ".KWKWK.", "..KKK.."],
  // Web-only: speaker and captions, in the same style.
  volume: ["....X....", "...XX..X.", "XXXXX...X", "XXXXX.X.X", "XXXXX.X.X", "XXXXX...X", "...XX..X.", "....X...."],
  mute: ["....X....", "...XX....", "XXXXX.X.X", "XXXXX..X.", "XXXXX.X.X", "XXXXX....", "...XX....", "....X...."],
  download: ["...XXX...", "...XXX...", "...XXX...", "XXXXXXXXX", ".XXXXXXX.", "..XXXXX..", "...XXX...", ".........", "XXXXXXXXX"],
  home: ["....X....", "...XXX...", "..XXXXX..", ".XXXXXXX.", "XXXXXXXXX", ".XXX.XXX.", ".XXX.XXX.", ".XXX.XXX.", ".XXXXXXX."],
  // 1.9: schedule, My List, alerts, achievements, reports, parties, the boss fight.
  calendar: [".X.....X.", "XXXXXXXXX", "X.......X", "XXXXXXXXX", "X.X.X.X.X", "X.......X", "X.X.X.X.X", "X.......X", "XXXXXXXXX"],
  bookmark: ["XXXXXXX", "XXXXXXX", "XXXXXXX", "XXXXXXX", "XXXXXXX", "XXX.XXX", "XX...XX", "X.....X"],
  bookmarkOff: ["XXXXXXX", "X.....X", "X.....X", "X.....X", "X.....X", "X..X..X", "X.X.X.X", "XX...XX"],
  bell: ["....X....", "..XXXXX..", ".XXXXXXX.", ".XXXXXXX.", ".XXXXXXX.", "XXXXXXXXX", "XXXXXXXXX", ".........", "...XXX..."],
  trophy: ["XXXXXXXXX", "X.XXXXX.X", "X.XXXXX.X", ".XXXXXXX.", "..XXXXX..", "...XXX...", "....X....", "..XXXXX..", ".XXXXXXX."],
  flag: ["XXXXXXX..", "XXXXXXXX.", "XXXXXXX..", "XXXXXX...", "X........", "X........", "X........", "X........", "X........"],
  party: [".XX...XX.", "XXXX.XXXX", "XXXX.XXXX", ".XX...XX.", ".........", "XXXX.XXXX", "XXXXXXXXX", "XXXXXXXXX"],
  sword: ["........X", ".......XX", "......XX.", ".....XX..", ".X..XX...", "..XXX....", "..XX.....", ".X..X....", "X........"],
  pip: ["XXXXXXXXXXX", "X.........X", "X.........X", "X.........X", "X....XXXXXX", "X....XXXXXX", "X....XXXXXX", "XXXXXXXXXXX"],
  bolt: ["...KKKK", "..KHHRK", ".KHRRK.", "KHRRRKK", "KRRRRRK", ".KKRRK.", "..KRK..", ".KRK...", ".KK...."],
  blossom: ["..K.K..", ".KHKHK.", "KHHRHHK", ".KRYRK.", "KHHRHHK", ".KHKHK.", "..K.K.."],
  heart: [".KK.KK.", "KHRKRRK", "KRRRRRK", ".KRRRK.", "..KRK..", "...K..."],
  torii: ["KYYYYYYYK", ".YYYYYYY.", "..Y...Y..", ".YYYYYYY.", "..Y...Y..", "..Y...Y..", "..Y...Y..", ".KK...KK."],
  gauge: ["..XXXXX..", ".X.....X.", "X...X..XX", "X....X..X", "X....XX.X", "X.......X", ".XXXXXXX."],
};

const SVG = "http://www.w3.org/2000/svg";

/** A sprite as an SVG: one rect per run of same-coloured cells. */
export function sprite(name, scale = 2, color) {
  const asked = name;
  // "mark" is the palette's own: a blood drop, a bolt, a blossom, a heart, a torii.
  if (name === "mark") name = { neon: "bolt", sakura: "blossom", gameboy: "heart", samurai: "torii" }[fxStyle()] || "bloodDrop";
  const rows = SPRITES[name];
  const svg = document.createElementNS(SVG, "svg");
  // Remembered so retheme() can draw it again in another palette.
  svg.dataset.name = asked;
  svg.dataset.scale = String(scale);
  if (color) svg.dataset.color = color;
  if (!rows) return svg;
  const w = rows[0].length, h = rows.length;
  svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
  svg.setAttribute("width", String(w * scale));
  svg.setAttribute("height", String(h * scale));
  svg.setAttribute("class", "sprite");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("shape-rendering", "crispEdges");
  if (color) svg.style.color = color;
  for (let y = 0; y < h; y++) {
    const row = rows[y];
    for (let x = 0; x < row.length;) {
      const ch = row[x];
      if (ch === ".") { x++; continue; }
      let end = x + 1;
      while (end < row.length && row[end] === ch) end++;
      const r = document.createElementNS(SVG, "rect");
      r.setAttribute("x", String(x));
      r.setAttribute("y", String(y));
      r.setAttribute("width", String(end - x));
      r.setAttribute("height", "1");
      r.setAttribute("fill", ch === "X" ? "currentColor" : (C[ch] || "currentColor"));
      svg.appendChild(r);
      x = end;
    }
  }
  return svg;
}

/** Replaces every <i data-sprite="name" data-scale="2"> with its sprite. */
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
// One requestAnimationFrame loop drives every pixel animation, each at its own
// frame rate and in whole frames, never interpolated: that is what makes motion
// read as sprite animation. Animations off screen or in a hidden tab are skipped.

const anims = new Set();
let rafId = 0;
const visible = new WeakMap();
const io = "IntersectionObserver" in window
  ? new IntersectionObserver((entries) => {
    for (const e of entries) visible.set(e.target, e.isIntersecting);
  })
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

/** Drawing on a canvas where one canvas pixel is one art cell. */
export class PixelCanvas {
  constructor(canvas) {
    this.c = canvas;
    // Bloom reads pixels back every frame, which is faster on a CPU-side canvas.
    this.ctx = canvas.getContext("2d", { willReadFrequently: true });
  }
  clear() { this.ctx.clearRect(0, 0, this.c.width, this.c.height); }
  rect(x, y, w, h, color) {
    if (w <= 0 || h <= 0) return;
    this.ctx.fillStyle = color;
    this.ctx.fillRect(Math.round(x), Math.round(y), w, h);
  }
  px(x, y, color) { this.rect(x, y, 1, 1, color); }

  /**
   * Pixel bloom: a stepped glow round every hot cell -- blood reds glow red,
   * bone and gold highlights glow warm -- painted into empty cells only, as two
   * rings with the outer one dithered. A blocky halo, never a blur.
   */
  bloom(strength = 1) {
    if (fxLevel() !== "full") return;
    const w = this.c.width, h = this.c.height;
    if (!w || !h) return;
    const img = this.ctx.getImageData(0, 0, w, h);
    const d = img.data;
    const glow = new Float32Array(w * h);
    const tone = new Uint8Array(w * h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4;
        if (d[i + 3] < 200) continue;
        const r = d[i], g = d[i + 1], b = d[i + 2];
        const bright = r > 220 && g > 170 && b < 200;
        const vivid = Math.max(r, g, b) > 170 && Math.max(r, g, b) - Math.min(r, g, b) > 120;
        const kind = bright ? 2 : vivid ? 1 : 0;
        if (!kind) continue;
        for (let dy = -2; dy <= 2; dy++) {
          for (let dx = -2; dx <= 2; dx++) {
            const qx = x + dx, qy = y + dy;
            if (qx < 0 || qy < 0 || qx >= w || qy >= h) continue;
            const ring = Math.max(Math.abs(dx), Math.abs(dy));
            if (!ring || (ring === 2 && ((qx + qy) & 1))) continue;
            const q = qy * w + qx;
            const a = (ring === 1 ? 0.42 : 0.17) * strength;
            if (a > glow[q]) { glow[q] = a; tone[q] = kind; }
          }
        }
      }
    }
    for (let q = 0; q < w * h; q++) {
      const i = q * 4;
      if (!glow[q] || d[i + 3] !== 0) continue;
      const warm = tone[q] === 2;
      const [gr, gg, gb] = warm ? [255, 196, 120] : RGB_LIGHT();
      d[i] = gr; d[i + 1] = gg; d[i + 2] = gb;
      d[i + 3] = Math.round(glow[q] * 255);
    }
    this.ctx.putImageData(img, 0, 0);
  }

  /** A see-through copy behind something moving: pixel art's motion blur. */
  ghost(x, y, w, h, rgb, alpha) { this.rect(x, y, w, h, `rgba(${rgb},${alpha})`); }
}

let RGB_BLOOD = "209,10,26";
const RGB_STEEL = "213,220,230";
const RGB_LIGHT = () => hexToRgb(BLOOD_LIGHT).split(",").map(Number);
refreshPalette();

/** Stable pseudo-random value in [0, 1) for seed -- same as the app's pxRand. */
export function pxRand(seed) {
  let x = (Math.imul(seed, 0x27d4eb2d) + 0x165667b1) & 0x7fffffff;
  x ^= x >> 15;
  x = Math.imul(x, 0x2c1b3c6d) & 0x7fffffff;
  x ^= x >> 12;
  return (x % 100000) / 100000;
}

const bloodAt = (age) => (age < 3 ? BLOOD_LIGHT : age < 7 ? BLOOD : age < 11 ? BLOOD_DARK : BLOOD_DEEP);

// --- cover art as pixel art -------------------------------------------------------

const lazyCovers = "IntersectionObserver" in window
  ? new IntersectionObserver((entries, obs) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      obs.unobserve(e.target);
      e.target._load?.();
    }
  }, { rootMargin: "300px" })
  : null;

/**
 * Cover art drawn at `decode` pixels across and scaled up with no smoothing, so
 * it reads as pixel art; the app does the same with memCacheWidth. Loads when
 * it nears the viewport. The element fills its (positioned) parent.
 */
export function pixelCover(url, decode = 96, label = "") {
  const box = h("div.px-cover.skel", label ? { role: "img", "aria-label": label } : { "aria-hidden": "true" });
  const noArt = () => {
    box.classList.remove("skel");
    clear(box).appendChild(h("div.noart", null, sprite("skull", 2.5)));
  };
  if (!url) { noArt(); return box; }

  box._load = () => {
    const img = new Image();
    img.decoding = "async";
    img.referrerPolicy = "no-referrer";
    img.onload = () => draw(img);
    img.onerror = noArt;
    img.src = url;
  };
  const draw = (img) => {
    const rect = box.getBoundingClientRect();
    const aspect = rect.width > 0 && rect.height > 0 ? rect.height / rect.width : img.naturalHeight / img.naturalWidth;
    const w = Math.max(4, decode), hgt = Math.max(4, Math.round(decode * aspect));
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = hgt;
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    // Cover-fit crop, like BoxFit.cover.
    const scale = Math.max(w / img.naturalWidth, hgt / img.naturalHeight);
    const sw = w / scale, sh = hgt / scale;
    ctx.drawImage(img, (img.naturalWidth - sw) / 2, (img.naturalHeight - sh) / 2, sw, sh, 0, 0, w, hgt);
    box.classList.remove("skel");
    clear(box).appendChild(canvas);
  };
  if (lazyCovers) lazyCovers.observe(box); else box._load();
  return box;
}

// --- blood drips ----------------------------------------------------------------

/** Blood dripping off the top edge of the canvas's box -- the app's BloodDrips. */
export function drips(canvas, { count = 5, seed = 7, cell = 2.5 } = {}) {
  if (fxLevel() === "off") return;
  const pc = new PixelCanvas(canvas);
  const size = () => {
    const r = canvas.getBoundingClientRect();
    canvas.width = Math.max(1, Math.floor(r.width / cell));
    canvas.height = Math.max(1, Math.floor(r.height / cell));
  };
  size();
  canvas.style.imageRendering = "pixelated";
  if ("ResizeObserver" in window) new ResizeObserver(size).observe(canvas);

  animate(canvas, 10, 60, (frame) => {
    const cols = canvas.width, rows = canvas.height;
    pc.clear();
    const dripStyle = { neon: dataDrips, sakura: petalDrips, gameboy: blockDrips }[fxStyle()];
    if (dripStyle) {
      // Data streams for Neon cyber, petals for Sakura, blocks for Game Boy;
      // Gold samurai drips molten gold, below.
      dripStyle(pc, frame, count, seed, cols, rows);
      pc.bloom();
      return;
    }
    for (let i = 0; i < count; i++) {
      const r = pxRand(seed * 31 + i);
      const x = Math.round(cols * (i + 0.5) / count + (r - 0.5) * cols / count * 0.6);
      const maxLen = 2 + Math.round(pxRand(seed + i * 5) * 5);
      const thick = i % 2 === 0;
      const t = (frame + Math.floor(pxRand(seed + i * 11) * 60)) % 60;
      pc.rect(x - 1, 0, thick ? 4 : 3, 1, BLOOD_DARK);
      const len = t < 30 ? Math.round(t / 30 * maxLen) : Math.min(maxLen, Math.max(1, Math.round(maxLen - (t - 30) / 8)));
      pc.rect(x, 0, thick ? 2 : 1, len, BLOOD);
      if (thick) pc.rect(x + 1, 0, 1, len, BLOOD_DARK);
      if (t < 30) {
        const big = t > 18 ? 1 : 0;
        pc.rect(x - big, len, (thick ? 2 : 1) + big, 2, BLOOD);
        pc.px(x, len, BLOOD_LIGHT);
      } else {
        const ft = t - 30;
        const y = maxLen + 1 + Math.round(0.25 * ft * ft);
        if (y < rows) {
          // Motion blur, pixel style: fading copies where the drop just was.
          const fall = Math.max(1, Math.round(0.5 * ft));
          pc.ghost(x, y - fall, thick ? 2 : 1, fall, RGB_BLOOD, 0.45);
          pc.ghost(x, y - 2 * fall, thick ? 2 : 1, fall, RGB_BLOOD, 0.18);
          pc.rect(x, y, thick ? 2 : 1, 2, BLOOD);
          pc.px(x, y, BLOOD_LIGHT);
        }
      }
    }
    pc.bloom();
  });
}

// --- splat -----------------------------------------------------------------------

/** A one-shot burst of blood where a blood button was hit -- the app's BloodSplat. */
export function splat(clientX, clientY) {
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches || fxLevel() === "off") return;
  const cells = 44;
  const canvas = h("canvas.splat", { width: cells, height: cells });
  canvas.style.left = `${clientX - 66}px`;
  canvas.style.top = `${clientY - 66}px`;
  document.body.appendChild(canvas);
  const pc = new PixelCanvas(canvas);
  const seed = Math.floor(performance.now()) & 0xffff;
  const c = cells / 2;
  const style = fxStyle();
  const t0 = performance.now();
  const step = () => {
    const frame = Math.floor((performance.now() - t0) / 40);
    if (frame >= 14) { canvas.remove(); return; }
    pc.clear();
    if (style !== "blood") {
      // Sparks for Neon cyber, a burst of petals for Sakura.
      ({ neon: sparkBurst, sakura: petalBurst, gameboy: pixelPop, samurai: goldBurst }[style] || petalBurst)(pc, c, frame, seed);
      pc.bloom(frame < 6 ? 1.2 : 0.8);
      requestAnimationFrame(step);
      return;
    }
    const blot = 3 - (frame >> 1);
    for (let dy = -blot; dy <= blot; dy++) {
      for (let dx = -blot; dx <= blot; dx++) {
        if (Math.abs(dx) + Math.abs(dy) <= blot) pc.px(c + dx, c + dy, bloodAt(frame + 3));
      }
    }
    for (let i = 0; i < 13; i++) {
      const r1 = pxRand(seed + i * 7), r2 = pxRand(seed + i * 13 + 1);
      const a = -Math.PI * (0.05 + 0.9 * r1) + (i % 5 === 0 ? Math.PI * 0.35 : 0);
      const s = 1.3 + 2.4 * r2;
      const x = c + Math.cos(a) * s * frame;
      const y = c + Math.sin(a) * s * frame + 0.21 * frame * frame;
      const big = i % 3 === 0 && frame < 8;
      pc.rect(Math.round(x), Math.round(y), big ? 2 : 1, big ? 2 : 1, bloodAt(frame + (i % 3)));
      for (const [back, alpha] of [[1, 0.6], [2, 0.25]]) {
        const f = frame - back;
        if (f < 0 || frame >= 10) continue;
        pc.ghost(Math.round(c + Math.cos(a) * s * f), Math.round(c + Math.sin(a) * s * f + 0.21 * f * f), 1, 1, RGB_BLOOD, alpha);
      }
    }
    pc.bloom(frame < 6 ? 1.2 : 0.8);
    requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

/** Every .px-btn that is not .dark/.bone bursts blood where it is clicked. */
document.addEventListener("pointerdown", (e) => {
  const btn = e.target instanceof Element && e.target.closest(".px-btn:not(.dark):not(.bone):not(:disabled), .big-play");
  if (btn) {
    splat(e.clientX, e.clientY);
    shake();
  }
});

const reducedMotion = () => !!window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

/** Three frames of a 2px screen shake: the hit landing. */
export function shake() {
  if (reducedMotion()) return;
  document.body.classList.remove("shake");
  void document.body.offsetWidth; // restart the animation
  document.body.classList.add("shake");
  setTimeout(() => document.body.classList.remove("shake"), 200);
}

// --- katana loader ----------------------------------------------------------------

/** The loading animation: a katana slashes, blood sprays and pools -- KatanaLoader. */
export function katana(width = 170) {
  // Each palette loads its own way; Blood's is the katana below.
  if (fxStyle() !== "blood" && fxStyle() !== "samurai") return themedLoader(width, fxStyle());
  const W = 50, H = 36, ground = 34, len = 27, start = -115, end = 12;
  const pivot = [13, 31];
  const canvas = h("canvas", { width: W, height: H });
  canvas.style.width = `${width}px`;
  canvas.style.height = `${width * H / W}px`;
  const wrap = h("div.katana", null, canvas);
  const pc = new PixelCanvas(canvas);
  const angle = (f) => (f < 3 ? start : f < 7 ? start + (end - start) * (f - 2) / 4 : f < 21 ? end : end + (start - end) * Math.min(1, (f - 20) / 6));
  const at = (deg, t) => {
    const a = deg * Math.PI / 180;
    return [Math.round(pivot[0] + Math.cos(a) * t), Math.round(pivot[1] + Math.sin(a) * t)];
  };
  animate(canvas, 12, 28, (frame) => {
    pc.clear();
    for (let x = 2; x < W - 2; x += 2) pc.px(x, ground + 1, C.G);
    if (frame >= 3 && frame <= 9) {
      const upto = angle(Math.min(frame, 6));
      const fade = frame - 6;
      for (let d = start; d <= upto; d += 3) {
        const [x, y] = at(d, len - 1);
        if (fade > 0 && (x + y + frame) % (fade + 1) !== 0) continue;
        pc.px(x, y, fade > 1 ? C.g : C.W);
        const [x2, y2] = at(d, len - 3);
        if (fade <= 0) pc.px(x2, y2, C.s);
      }
    }
    const hitFrame = 5;
    const [hx, hy] = at(-45, len - 4);
    const pool = new Set();
    for (let i = 0; i < 16; i++) {
      const vx = -0.4 + pxRand(i * 3 + 1) * 2.4, vy = -2.6 + pxRand(i * 5 + 2) * 2.2, g = 0.38;
      const tLand = (-vy + Math.sqrt(vy * vy + 2 * g * (ground - hy))) / g;
      if (frame >= hitFrame && frame < 24) {
        const t = frame - hitFrame;
        if (t < tLand) {
          const x = Math.round(hx + vx * t), y = Math.round(hy + vy * t + 0.5 * g * t * t);
          pc.px(x, y, bloodAt(Math.round(t * 1.5)));
          if (i % 4 === 0) pc.px(x, y + 1, BLOOD_DARK);
        } else {
          pool.add(Math.round(hx + vx * tLand));
        }
      }
    }
    for (const x of pool) for (let dx = -1; dx <= 1; dx++) pc.px(x + dx, ground, dx === 0 ? BLOOD : BLOOD_DARK);
    if (frame >= 24) for (const x of [30, 33, 36]) if ((x + frame) % 2 === 0) pc.px(x, ground, BLOOD_DEEP);
    const deg = angle(frame);
    const bloodied = frame >= hitFrame && frame < 26;
    // The swing is four frames; copies of the blade at the two angles before
    // this one smear it across the arc -- motion blur in whole cells.
    if (frame >= 4 && frame <= 7) {
      for (const [back, alpha] of [[1, 0.42], [2, 0.18]]) {
        const ghostDeg = angle(frame - back);
        for (let t = 8; t <= len; t++) {
          const [x, y] = at(ghostDeg, t);
          pc.ghost(x, y, 1, 1, RGB_STEEL, alpha);
        }
      }
    }
    for (let t = 0; t <= len; t++) {
      const [x, y] = at(deg, t);
      const a = (deg + 90) * Math.PI / 180;
      if (t < 7) pc.px(x, y, t % 2 === 0 ? BLOOD_DARK : C.K);
      else if (t === 7) {
        for (let k = -2; k <= 2; k++) pc.px(Math.round(x + Math.cos(a) * k), Math.round(y + Math.sin(a) * k), Math.abs(k) === 2 ? C.y : C.Y);
      } else {
        const red = bloodied && t > len - 9;
        pc.px(Math.round(x + Math.cos(a)), Math.round(y + Math.sin(a)), red ? BLOOD_DARK : C.s);
        pc.px(x, y, t === len ? C.W : (red ? BLOOD : C.S));
      }
    }
    if (frame < 3) { const [gx, gy] = at(deg, 10 + frame * 6); pc.px(gx, gy, C.W); }
    if (frame >= 8 && frame < 21) { const [tx, ty] = at(deg, len - 2); pc.px(tx, ty + 1 + ((frame - 8) % 5), BLOOD); }
    pc.bloom();
  });
  return wrap;
}

// --- buffering orb ------------------------------------------------------------------

/**
 * The player's buffering circle: a glass orb filling with blood as the video
 * downloads, the live speed in the middle -- the app's BufferOverlay.
 * Returns {el, set({progress, mbps})}; progress null means "unknown" and the
 * blood idles low instead of pretending to move.
 */
export function orb(size = 136, initialLevel = 0.08) {
  const COLS = 30, ROWS = 37;
  const canvas = h("canvas", { width: COLS, height: ROWS });
  const speedB = h("b");
  const speedS = h("small", null, "MBPS");
  const speed = h("div.speed", null, speedB, speedS);
  const el = h("div.orb", null, canvas, speed);
  el.style.width = `${size}px`;
  el.style.height = `${size * ROWS / COLS}px`;
  speed.style.height = `${size}px`;
  speedB.style.fontSize = `${Math.round(size * 0.14)}px`;
  speedS.style.fontSize = `${Math.max(7, Math.round(size * 0.062))}px`;
  const pc = new PixelCanvas(canvas);
  let level = Math.min(1, Math.max(0, initialLevel));
  let progress = null;

  animate(canvas, 10, 40, (frame) => {
    const target = progress !== null ? Math.min(1, Math.max(0, progress)) : 0.24 + 0.06 * Math.sin(frame / 40 * 2 * Math.PI);
    level += (target - level) * (target > level ? 0.35 : 0.15);
    const c = 15, r = 15, innerTop = 2, innerBottom = 28;
    const fill = level, t = frame / 40 * 2 * Math.PI;
    const surfaceAt = (x, phase, amp) => {
      const calm = Math.min(1, Math.max(0.3, 1 - Math.abs(fill - 0.5) * 1.4));
      const wave = Math.round(Math.sin(x * 0.55 + phase) * amp * calm);
      return Math.round(innerBottom - fill * (innerBottom - innerTop + 1) + wave);
    };
    pc.clear();
    for (let y = 0; y < COLS; y++) {
      for (let x = 0; x < COLS; x++) {
        const d = Math.hypot(x + 0.5 - c, y + 0.5 - c);
        if (d > r) continue;
        if (d > r - 1.3) { pc.px(x, y, C.K); continue; }
        if (d > r - 2.5) { pc.px(x, y, x + y < 22 ? BLOOD_LIGHT : x + y > 36 ? BLOOD_DARK : BLOOD); continue; }
        const surf = surfaceAt(x, -t, 1.3), back = surfaceAt(x, t * 0.8 + 1.7, 1.1);
        let col;
        if (y > surf) {
          const depth = innerBottom - y;
          col = y === surf + 1 ? (Math.sin(x * 0.55 - t) > 0.35 ? BLOOD_LIGHT : BLOOD) : depth < 2 ? BLOOD_DEEP : depth < 6 ? BLOOD_DARK : BLOOD;
        } else if (y > back) col = BLOOD_DEEP;
        else col = C.k;
        pc.px(x, y, col);
      }
    }
    // Rising through the liquid: bubbles for Blood, bits of data for Neon
    // cyber, petals for Sakura.
    const style = fxStyle();
    for (const [bx, off] of [[9, 0], [15, 5], [20, 11], [12, 17]]) {
      const span = Math.floor(fill * 24);
      if (span < 4) continue;
      const y = innerBottom - 1 - ((frame + off) % span);
      if (y <= surfaceAt(bx, -t, 1.3) + 1) continue;
      if (style === "neon") { pc.px(bx, y, (frame + off) % 2 ? C.Y : BLOOD_LIGHT); pc.px(bx + 1, y, BLOOD_LIGHT); }
      else if (style === "sakura") petal(pc, bx, y, (Math.floor(frame / 3) + off) & 3);
      else if (style === "samurai") flake(pc, bx, y, (Math.floor(frame / 3) + off) & 3);
      else pc.px(bx, y, BLOOD_LIGHT);
    }
    if (style === "neon") {
      for (let y = 4; y < innerBottom; y += 3) pc.ghost(4, y, 22, 1, "5,3,5", 0.25);
      for (const [x, y, dx, dy] of [[0, 0, 1, 1], [29, 0, -1, 1], [0, 29, 1, -1], [29, 29, -1, -1]]) { pc.px(x, y, C.Y); pc.px(x + dx, y, C.Y); pc.px(x, y + dy, C.Y); }
    }
    for (const [gx, gy] of [[9, 5], [8, 6], [7, 7], [6, 9]]) if (gy < surfaceAt(gx, -t, 1.3)) pc.px(gx, gy, C.g);
    if (fill > 0.3) {
      for (const [dx, off] of [[12, 0], [18, 4]]) {
        pc.px(dx, COLS - 1, BLOOD_DARK);
        const fall = (frame + off * 3) % 10;
        if (fall < 7) {
          if (fall > 0) pc.ghost(dx, COLS + fall - 1, 1, 1, RGB_BLOOD, 0.4);
          pc.rect(dx, COLS + fall, 1, 2, BLOOD);
        }
      }
    }
    pc.bloom(0.8);
  });

  const set = ({ progress: p, mbps } = {}) => {
    if (p !== undefined) progress = p;
    if (mbps !== undefined) {
      speedB.textContent = mbps == null ? "--" : mbps < 10 ? mbps.toFixed(mbps < 1 ? 2 : 1) : mbps.toFixed(0);
    }
  };
  set({ mbps: null });
  return { el, set, level: () => level };
}

// --- toasts & dialogs ------------------------------------------------------------------

let toastHost;
/** A pixel snack bar at the bottom; optional {action: {label, run}}. */
export function toast(message, { action, ms = 5000 } = {}) {
  toastHost ??= document.body.appendChild(h("div.toasts", { role: "status", "aria-live": "polite" }));
  const t = h("div.toast.px-box", null, h("span.msg", null, message));
  if (action) t.appendChild(h("button", { type: "button", onclick: () => { action.run(); t.remove(); } }, action.label));
  toastHost.appendChild(t);
  setTimeout(() => t.remove(), ms);
  return t;
}

/** Resolves true/false. */
export function confirmDialog(title, text, okLabel = "OK") {
  return new Promise((resolve) => {
    const done = (v) => { back.remove(); resolve(v); };
    const back = h("div.dialog-back", { onclick: (e) => { if (e.target === back) done(false); } },
      h("div.dialog.px-box.rivets", { role: "dialog", "aria-modal": "true", "aria-label": title },
        h("h3", null, title),
        h("p", null, text),
        h("div.row", null,
          h("button.px-btn.dark.px-box.bevel.small", { type: "button", onclick: () => done(false) }, "Cancel"),
          h("button.px-btn.px-box.bevel.small", { type: "button", onclick: () => done(true) }, okLabel))));
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

// --- ambient embers ----------------------------------------------------------------

/**
 * Blood embers drifting up behind the page: a low-resolution canvas fixed
 * behind everything, each ember a cell or two with its own stepped glow, a
 * slow sway and a flicker. Off when the viewer asks for reduced motion.
 */
export function embers(canvas, { cell = 3, density = 0.00009 } = {}) {
  if (reducedMotion() || fxLevel() === "off") return;
  density *= fxDensity();
  const pc = new PixelCanvas(canvas);
  let parts = [];
  const spawn = (w, h, anywhere) => ({
    x: Math.random() * w,
    y: anywhere ? Math.random() * h : h + Math.random() * 20,
    v: 0.18 + Math.random() * 0.45,
    sway: Math.random() * Math.PI * 2,
    big: Math.random() < 0.22,
    gold: Math.random() < 0.12,
    life: 0,
  });
  const size = () => {
    canvas.width = Math.max(1, Math.ceil(innerWidth / cell));
    canvas.height = Math.max(1, Math.ceil(innerHeight / cell));
    const n = Math.round(canvas.width * canvas.height * cell * cell * density);
    parts = Array.from({ length: Math.min(70, Math.max(14, n)) }, () => spawn(canvas.width, canvas.height, true));
  };
  size();
  addEventListener("resize", size);
  animate(canvas, 12, 0, (frame) => {
    const w = canvas.width, h = canvas.height;
    pc.clear();
    // Chosen every frame, so a palette switch changes it on the spot: digital
    // rain for Neon cyber, petals for Sakura, falling blocks for Game Boy,
    // gold leaf for Gold samurai, embers for Blood.
    const themed = { neon: rainFrame, sakura: petalFrame, gameboy: blocksFrame, samurai: leafFrame }[fxStyle()];
    if (themed) { themed(pc, frame, w, h); return; }
    for (const p of parts) {
      p.y -= p.v;
      p.life++;
      const x = Math.round(p.x + Math.sin(p.sway + p.life * 0.05) * 2);
      const y = Math.round(p.y);
      if (y < -4) Object.assign(p, spawn(w, h, false));
      // Flicker in whole steps; fade near the top.
      const lit = (frame + Math.floor(p.sway * 7)) % 9 < 7;
      const fade = Math.min(1, y / (h * 0.35));
      const gold = hexToRgb(C.Y), light = hexToRgb(BLOOD_LIGHT);
      const core = p.gold ? gold : lit ? light : RGB_BLOOD;
      const halo = p.gold ? gold : RGB_BLOOD;
      const sz = p.big ? 2 : 1;
      pc.ghost(x - 1, y - 1, sz + 2, sz + 2, halo, 0.14 * fade);
      pc.ghost(x, y + sz, sz, 2, halo, 0.16 * fade); // its trail
      pc.ghost(x, y, sz, sz, core, 0.9 * fade);
    }
  });
}

// --- speed lines ----------------------------------------------------------------------

/**
 * Horizontal streaks across `host` for a few frames: how pixel art draws a
 * fast move. dir is 1 (moving right) or -1.
 */
export function speedLines(host, dir = 1) {
  if (reducedMotion()) return;
  const cell = 3;
  const r = host.getBoundingClientRect();
  const canvas = h("canvas.speedlines", { width: Math.ceil(r.width / cell), height: Math.ceil(r.height / cell) });
  host.appendChild(canvas);
  const pc = new PixelCanvas(canvas);
  const W = canvas.width, H = canvas.height;
  const lines = Array.from({ length: Math.max(8, Math.round(H / 4)) }, () => ({
    y: Math.floor(Math.random() * H), len: 8 + Math.floor(Math.random() * W * 0.35), x: Math.random() * W,
  }));
  let frame = 0;
  const step = () => {
    if (frame >= 5) { canvas.remove(); return; }
    pc.clear();
    const alpha = [0.55, 0.7, 0.5, 0.3, 0.12][frame];
    for (const l of lines) {
      const x = Math.round(l.x + dir * frame * W * 0.18);
      pc.ghost(x, l.y, l.len, 1, "242,232,213", alpha);
      pc.ghost(x - dir * 3, l.y, 3, 1, hexToRgb(BLOOD_LIGHT), alpha);
    }
    frame++;
    setTimeout(() => requestAnimationFrame(step), 45);
  };
  step();
}

// --- page transition --------------------------------------------------------------------
// A Bayer-dither dissolve: the page breaks into, or out of, square cells in
// five steps, the way 16-bit games change screens.

const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

export function dissolve(mode, ms = 200) {
  return new Promise((resolve) => {
    if (reducedMotion()) { resolve(); return; }
    const cell = 6;
    const canvas = h("canvas.dissolve", { width: Math.ceil(innerWidth / cell), height: Math.ceil(innerHeight / cell) });
    document.body.appendChild(canvas);
    const ctx = canvas.getContext("2d");
    const W = canvas.width, H = canvas.height;
    const steps = 5;
    let i = 0;
    const draw = () => {
      // "out" covers the page as it leaves; "in" uncovers the new one.
      const t = mode === "out" ? (i + 1) / steps : 1 - (i + 1) / steps;
      ctx.clearRect(0, 0, W, H);
      ctx.fillStyle = "#050305";
      const level = t * 16;
      for (let y = 0; y < H; y++) {
        for (let x = 0; x < W; x++) if (BAYER[(y & 3) * 4 + (x & 3)] < level) ctx.fillRect(x, y, 1, 1);
      }
      i++;
      if (i < steps) setTimeout(draw, ms / steps);
      else {
        if (mode === "in") canvas.remove();
        resolve();
      }
    };
    draw();
  });
}

// --- per-palette effects -------------------------------------------------------------
// Each palette is a theme of its own, not a recolour: embers, blood and drips
// for Blood; digital rain over a synthwave grid, sparks and data streams for
// Neon cyber; drifting petals, sparkles and petal bursts for Sakura. The app has
// the same set (aniverse_mobile/lib/ui_2d/pixel/theme_fx.dart).

export const fxStyle = () => document.documentElement.dataset.theme || "blood";

/** Settings > Effects: "full", "lite" (fewer particles, no glow) or "off". */
export const fxLevel = () => document.documentElement.dataset.fx || "full";
const fxDensity = () => (fxLevel() === "lite" ? 0.5 : 1);

const PETAL = [
  [[0, 0, 0], [1, 0, 0], [1, 1, 1]],
  [[0, 0, 0], [1, 0, 1]],
  [[0, 0, 0], [0, 1, 0], [1, 1, 1]],
  [[0, 0, 1], [1, 1, 0]],
];
function petal(pc, x, y, frame, alpha = 1) {
  for (const [dx, dy, shade] of PETAL[frame & 3]) pc.ghost(x + dx, y + dy, 1, 1, hexToRgb(shade ? BLOOD : BLOOD_LIGHT), alpha);
}
function sparkle(pc, x, y, phase, alpha = 1) {
  const p = ((phase % 8) + 8) % 8;
  if (p >= 6) return;
  const gold = hexToRgb(C.Y);
  pc.ghost(x, y, 1, 1, "255,255,255", alpha);
  if (p >= 1 && p <= 4) for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) pc.ghost(x + dx, y + dy, 1, 1, gold, alpha);
  if (p === 2 || p === 3) for (const [dx, dy] of [[-2, 0], [2, 0], [0, -2], [0, 2]]) pc.ghost(x + dx, y + dy, 1, 1, gold, alpha * 0.5);
}

function rainFrame(pc, frame, cols, rows) {
  const grid = hexToRgb(C.Y);
  const horizon = Math.round(rows * 0.7);
  for (let k = 0; k < 9; k++) {
    const t = (k + (frame % 12) / 12) / 9;
    pc.ghost(0, horizon + Math.round(t * t * (rows - horizon)), cols, 1, grid, 0.05 + 0.12 * t);
  }
  const cx = cols / 2;
  for (let k = -8; k <= 8; k++) {
    const xb = cx + k * cols / 7;
    for (let y = horizon; y < rows; y += 2) {
      const t = (y - horizon) / (rows - horizon);
      pc.ghost(Math.round(cx + (xb - cx) * t), y, 1, 1, grid, 0.05 + 0.1 * t);
    }
  }
  const n = Math.round(cols / 5 * fxDensity());
  for (let i = 0; i < n; i++) {
    const seed = i * 131 + 7;
    const x = Math.floor(pxRand(seed) * cols);
    const speed = 0.5 + pxRand(seed + 1) * 0.9;
    const len = 5 + Math.floor(pxRand(seed + 2) * 12);
    const span = rows + len + 10;
    const head = Math.floor((frame * speed + pxRand(seed + 3) * span) % span) - len;
    for (let j = 0; j < len; j++) {
      const y = head - j;
      if (y < 0 || y >= rows) continue;
      if (j > 0 && pxRand(seed + y * 7 + Math.floor(frame / 3)) < 0.3) continue;
      const c = j === 0 ? BLOOD_LIGHT : j < 3 ? BLOOD : BLOOD_DARK;
      pc.ghost(x, y, 1, 1, hexToRgb(c), (j === 0 ? 0.8 : 0.5) * (1 - j / len));
    }
  }
  if (frame % 97 < 2) {
    const y = Math.floor(pxRand(Math.floor(frame / 97) + 5) * rows * 0.7);
    pc.ghost(0, y, cols, 1, hexToRgb(BLOOD_LIGHT), 0.25);
  }
}

function petalFrame(pc, frame, cols, rows) {
  const n = Math.round(Math.min(36, Math.max(10, Math.round(cols * rows * 0.0006))) * fxDensity());
  for (let i = 0; i < n; i++) {
    const seed = i * 89 + 3;
    const fall = 0.16 + pxRand(seed) * 0.28, drift = 0.08 + pxRand(seed + 1) * 0.16;
    const span = rows + 12;
    const t = frame * fall + pxRand(seed + 2) * span;
    const y = Math.floor(t % span) - 6;
    const x = Math.floor((pxRand(seed + 3) * (cols + 20) + frame * drift + Math.sin(t * 0.18 + seed) * 3) % (cols + 20)) - 10;
    petal(pc, x, y, (Math.floor(frame / 4) + i) & 3, 0.45 + 0.4 * pxRand(seed + 4));
  }
  for (let i = 0; i < 7; i++) {
    const seed = i * 53 + 11;
    sparkle(pc, Math.floor(pxRand(seed) * cols), Math.floor(pxRand(seed + 1) * rows), Math.floor(frame / 2) + i * 5, 0.55);
  }
}

function sparkBurst(pc, c, frame, seed) {
  const r = 1 + Math.round(frame * 1.6);
  const ring = frame < 3 ? BLOOD_LIGHT : frame < 7 ? BLOOD : BLOOD_DARK;
  if (frame < 10) {
    for (let d = -r; d <= r; d++) {
      if ((d + frame) & 1) continue; // dashed, like an electric arc
      pc.px(c + d, c - r, ring); pc.px(c + d, c + r, ring); pc.px(c - r, c + d, ring); pc.px(c + r, c + d, ring);
    }
  }
  if (frame < 2) { pc.rect(c - 2, c, 5, 1, "#fff"); pc.rect(c, c - 2, 1, 5, "#fff"); }
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2 + pxRand(seed + i) * 0.5;
    const sp = 1.6 + pxRand(seed + i * 3) * 1.6;
    const kink = (pxRand(seed + i * 5) - 0.5) * 2;
    const color = i % 2 ? C.Y : BLOOD_LIGHT;
    for (let back = 0; back < 3; back++) {
      const f = frame - back;
      if (f < 0 || frame > 11) continue;
      const x = Math.round(c + Math.cos(a) * sp * f + (f > 4 ? kink * (f - 4) : 0));
      const y = Math.round(c + Math.sin(a) * sp * f);
      if (back === 0) pc.px(x, y, color); else pc.ghost(x, y, 1, 1, hexToRgb(color), back === 1 ? 0.5 : 0.2);
    }
  }
}

function petalBurst(pc, c, frame, seed) {
  if (frame < 8) sparkle(pc, c, c, frame);
  for (let i = 0; i < 12; i++) {
    const a = -Math.PI * (0.1 + 0.8 * pxRand(seed + i * 7)) + (i % 4 === 0 ? Math.PI * 0.4 : 0);
    const sp = 1.2 + 1.6 * pxRand(seed + i * 13);
    const out = sp * (1 - Math.pow(0.78, frame)) / 0.22;
    const x = c + Math.cos(a) * out + Math.sin(frame * 0.6 + i) * 1.2;
    const y = c + Math.sin(a) * out + 0.05 * frame * frame;
    petal(pc, Math.round(x), Math.round(y), (Math.floor(frame / 2) + i) & 3, frame < 10 ? 1 : 0.5);
  }
}

function dataDrips(pc, frame, count, seed, cols, rows) {
  for (let i = 0; i < count; i++) {
    const x = Math.round(cols * (i + 0.5) / count + (pxRand(seed * 31 + i) - 0.5) * cols / count * 0.6);
    pc.rect(x - 1, 0, 3, 1, BLOOD_DARK);
    const speed = 1 + (i % 2), period = rows + 6;
    const head = Math.floor((frame * speed + pxRand(seed + i * 11) * period) % period);
    for (let j = 0; j < 4; j++) {
      const y = head - j;
      if (y < 1 || y >= rows) continue;
      if (j > 1 && (frame + y + i) & 1) continue;
      pc.px(x, y, j === 0 ? BLOOD_LIGHT : j === 1 ? BLOOD : BLOOD_DARK);
    }
  }
}

function petalDrips(pc, frame, count, seed, cols, rows) {
  for (let i = 0; i < count; i++) {
    const x0 = Math.round(cols * (i + 0.5) / count + (pxRand(seed * 31 + i) - 0.5) * cols / count * 0.6);
    pc.px(x0 - 1, 0, BLOOD_LIGHT); pc.px(x0, 0, BLOOD); pc.px(x0 + 1, 0, BLOOD_LIGHT);
    const t = (frame + Math.floor(pxRand(seed + i * 11) * 60)) % 60;
    const y = Math.floor(t * 0.45) + 1;
    if (y >= rows) continue;
    petal(pc, x0 + Math.round(Math.sin(t * 0.25 + i) * 2), y, (t / 3) & 3, Math.max(0.3, 1 - t / 60));
  }
}

// --- the emblem in the palette's colours ------------------------------------------------
// The logo's pixels (static/pixel/img/logo.png, 34x30), so Neon cyber and Sakura
// can draw it in their own colours; Blood keeps the crimson image.
const EMBLEM = [
  "..............A...A...............", ".............ABAAACA..............", ".............ABBBBCCA.............",
  "............ADDBBBCEA.............", "............ADBBBCCECA......AAA...", "...........ABBBBBCCCCA...AAADEEAA.",
  "...........ABBBBBCCCCCA.AEEEEEEBBA", "..........ABBBBBFECCCCBA.AAAAEEBBA", "..........ABBBBEFECCCCBA....AEEBBA",
  ".........ABBBBEEAACCCCBBA...ABBBA.", "........ABBBBBEEAACCCBBBA..ABBBBA.", "........ABBBBEEAA.ACBBCCBAACCCBA..",
  ".......ABBBBBEEEBAACCCCCBACCCCA...", ".......ABBBBEEAEBBAACCCCCCCECA....", "......ABBBBBEAAEBBBACCCCCCEEA.....",
  "......ABBBBEEAAEEEA.AECCCEEA......", ".....ABBBBEEA..AAAAABBBCEEBA......", "...A.ABBBBEEAAAAAABBBBFFEBBBA.....",
  "..ABABBBBEEEEEEBBBBBFFFFCBBBA.....", ".ABBBBBBBEEEEBBBBEEFFFFCCBBBDA....", ".ABEBBBBEEBBBBBFFFEEEEEEBBBBDA....",
  "ABBEEECBBBBBBAAAAAAAAAEEBBBBBDA...", ".ABBBBCCFFFAA.........AFFBBBBDA...", ".ACEEEEEFFA............AFFBBBBBA..",
  ".ACCCCCEEA.............AFFBBBBBA..", "ACCCCCEEA...............AEBBBBBBA.", ".ACCCCEA................AEEBBBBA..",
  "..AACCA..................AEEEAA...", "....AA....................AEA.....", "...........................A......",
];

/** The emblem as a data URL in the palette's colours, or null for Blood (the PNG). */
export function emblemUrl() {
  if (fxStyle() === "blood") return null;
  const cv = document.createElement("canvas");
  cv.width = 34; cv.height = 30;
  const ctx = cv.getContext("2d");
  const mix = (a, b, t) => {
    const [r1, g1, b1] = hexToRgb(a).split(",").map(Number), [r2, g2, b2] = hexToRgb(b).split(",").map(Number);
    return `rgb(${Math.round(r1 + (r2 - r1) * t)},${Math.round(g1 + (g2 - g1) * t)},${Math.round(b1 + (b2 - b1) * t)})`;
  };
  const pal = { A: C.K, B: BLOOD, C: mix(BLOOD, BLOOD_DARK, 0.45), D: BLOOD_LIGHT, E: BLOOD_DARK, F: BLOOD_DEEP };
  EMBLEM.forEach((row, y) => [...row].forEach((k, x) => {
    if (k === ".") return;
    ctx.fillStyle = pal[k];
    ctx.fillRect(x, y, 1, 1);
  }));
  return cv.toDataURL();
}

// --- switching palette: a scene change in the new palette's style ------------------------
// Blood: a katana slash and a blood curtain, then the curtain cut along the slash
// and slid apart. Neon cyber: glitch scanlines closing in, then the screen opening
// from the middle like a CRT. Sakura: a petal storm in, and on out. The app plays
// the same (lib/ui_2d/intro/palette_transition.dart). "cover" runs to fully
// covered with the palette's name showing; "reveal" uncovers the reloaded page.

const SWITCH = {
  blood: { ink: "#0d0709", blood: "#d10a1a", dark: "#7a0410", deep: "#3d0107", light: "#ff4d57", gold: "#e8b23a", name: "BLOOD" },
  neon: { ink: "#070a12", blood: "#00d9ff", dark: "#006b85", deep: "#002a38", light: "#7ff3ff", gold: "#ff3df0", name: "NEON CYBER" },
  sakura: { ink: "#120a0f", blood: "#ff5fa2", dark: "#a3305f", deep: "#4a1430", light: "#ffb3d1", gold: "#ffd36b", name: "SAKURA" },
  gameboy: { ink: "#0b1d0b", blood: "#8bac0f", dark: "#306230", deep: "#173d17", light: "#9bbc0f", gold: "#c8e05a", name: "GAME BOY" },
  samurai: { ink: "#0b0907", blood: "#d4a537", dark: "#7a5a1c", deep: "#2e220c", light: "#ffe08a", gold: "#e8543a", name: "GOLD SAMURAI" },
};
const SW_FRAMES = 22, SW_SWAP = 10, SW_REVEAL = 13;

export function paletteSwitch(theme, phase) {
  return new Promise((resolve) => {
    if (reducedMotion() || fxLevel() === "off") { resolve(); return; }
    const c = SWITCH[theme] || SWITCH.blood;
    const cell = Math.max(4, Math.min(10, Math.floor(Math.min(innerWidth, innerHeight) / 64)));
    const canvas = h("canvas.dissolve.palette-fx", { width: Math.ceil(innerWidth / cell) + 1, height: Math.ceil(innerHeight / cell) + 1 });
    canvas.style.zIndex = "310";
    document.body.appendChild(canvas);
    const ctx = canvas.getContext("2d");
    const gw = canvas.width, gh = canvas.height;
    const rect = (x, y, w, hh, col) => { if (w > 0 && hh > 0) { ctx.fillStyle = col; ctx.fillRect(x, y, w, hh); } };
    // A reveal opens on the covered frame, name and all, so the reload is seamless.
    const first = phase === "reveal" ? SW_SWAP : 0, last = phase === "reveal" ? SW_FRAMES : SW_REVEAL;
    const label = (f) => {
      if (f < SW_SWAP - 1 || f >= SW_REVEAL) return;
      // The name is drawn in page pixels, over the canvas, so it stays sharp.
      let el = document.querySelector(".palette-fx-label");
      if (!el) {
        el = h("div.palette-fx-label", { style: { position: "fixed", inset: "0", zIndex: "311", display: "grid", placeItems: "center", pointerEvents: "none",
          font: `${Math.max(14, Math.min(26, innerWidth / 16))}px/1 var(--display)`, color: c.light,
          textShadow: theme === "neon" ? `-3px 0 ${c.gold}, 3px 0 ${c.blood}` : "2px 2px 0 #050305, -2px -2px 0 #050305" } }, c.name);
        document.body.appendChild(el);
      }
    };
    const drawBlood = (f) => {
      if (f < SW_REVEAL) {
        for (let x = 0; x < gw; x++) {
          const len = Math.round((f - 1) * (1 + pxRand(x * 7 + 3) * 0.7) * gh / 7.5 + pxRand(x * 13) * 3);
          if (len <= 0) continue;
          rect(x, 0, 1, Math.min(len, gh), c.deep);
          if (len < gh) { rect(x, len - 1, 1, 1, c.blood); if (!(x & 1)) rect(x, len, 1, 1, c.light); }
        }
        if (f <= 4) {
          const p = Math.min(1, (f + 1) / 4);
          ctx.strokeStyle = "#fff"; ctx.lineWidth = 1.5;
          ctx.beginPath(); ctx.moveTo(0, gh); ctx.lineTo(gw * p, gh - gh * p); ctx.stroke();
        }
        return;
      }
      const p = (f - SW_REVEAL) / (SW_FRAMES - 1 - SW_REVEAL), e = p * p * 1.2;
      ctx.fillStyle = c.deep;
      ctx.save(); ctx.translate(-gw * e * 0.6, -gh * e * 0.6);
      ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(gw, 0); ctx.lineTo(0, gh); ctx.closePath(); ctx.fill(); ctx.restore();
      ctx.save(); ctx.translate(gw * e * 0.6, gh * e * 0.6);
      ctx.beginPath(); ctx.moveTo(gw, 0); ctx.lineTo(gw, gh); ctx.lineTo(0, gh); ctx.closePath(); ctx.fill(); ctx.restore();
      if (f <= SW_REVEAL + 1) { ctx.strokeStyle = c.light; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(0, gh); ctx.lineTo(gw, 0); ctx.stroke(); }
    };
    const drawNeon = (f) => {
      if (f < SW_REVEAL) {
        const q = Math.min(1, (f + 1) / SW_SWAP), rows = Math.ceil(gh / 2);
        for (let r = 0; r < rows; r++) {
          const key = (r % 4) * 0.25 + Math.floor(r / 4) / rows;
          if (key < q) rect(0, r * 2, gw, 2, c.ink);
          else if (key < q + 0.05) rect(0, r * 2, gw, 1, c.light);
        }
        for (let i = 0; i < 14; i++) {
          if (pxRand(i * 5 + f * 17) > 1 - q * 0.3 - 0.3) continue;
          rect(Math.floor(pxRand(i * 3 + f) * gw), Math.floor(pxRand(i * 7 + f * 3) * gh), 3 + Math.floor(pxRand(i + f) * 10), 1, i % 2 ? c.blood : c.gold);
        }
        if (f >= SW_SWAP - 1) {
          const horizon = Math.round(gh * 0.68);
          ctx.globalAlpha = 0.3;
          for (let k = 0; k < 7; k++) { const t = k / 7; rect(0, horizon + Math.round(t * t * (gh - horizon)), gw, 1, c.gold); }
          ctx.globalAlpha = 1;
        }
        return;
      }
      const p = (f - SW_REVEAL) / (SW_FRAMES - 1 - SW_REVEAL), e = 1 - (1 - p) * (1 - p);
      const half = Math.round(gh / 2 * (1 - e));
      rect(0, 0, gw, half, c.ink); rect(0, gh - half, gw, half, c.ink);
      rect(0, half - 1, gw, 1, c.light); rect(0, gh - half, gw, 1, c.light);
      if (f === SW_REVEAL) rect(0, Math.floor(gh / 2) - 1, gw, 2, "#fff");
    };
    const drawSakura = (f) => {
      const cover = c.deep;
      const covering = f < SW_REVEAL;
      const q = covering ? Math.min(1, (f + 1) / SW_SWAP) : (f - SW_REVEAL + 1) / (SW_FRAMES - SW_REVEAL);
      const front = q * (gw + 24) - 12;
      for (let y = 0; y < gh; y += 2) {
        const edge = Math.round(front - Math.round(pxRand(y * 7 + 1) * 6));
        if (covering) rect(0, y, edge, 2, cover);
        else rect(Math.max(0, edge), y, gw - Math.max(0, edge), 2, cover);
      }
      for (let i = 0; i < 60; i++) {
        const y = Math.floor(pxRand(i * 3 + 7) * gh);
        const x = Math.round(front - pxRand(i * 5 + 2) * 14 + Math.sin(f * 0.6 + i) * 1.5);
        for (const [dx, dy, shade] of PETAL[(f + i) & 3]) rect(x + dx * 2, y + dy * 2, 2, 2, shade ? c.blood : c.light);
      }
      if (f >= SW_SWAP - 1 && f < SW_REVEAL) {
        for (let i = 0; i < 10; i++) {
          if ((f + i) & 1) continue;
          const x = Math.floor(gw * (0.2 + 0.6 * pxRand(i * 11))), y = Math.floor(gh * (0.35 + 0.3 * pxRand(i * 13)));
          rect(x, y, 1, 1, "#fff"); rect(x - 1, y, 1, 1, c.gold); rect(x + 1, y, 1, 1, c.gold); rect(x, y - 1, 1, 1, c.gold); rect(x, y + 1, 1, 1, c.gold);
        }
      }
    };
    const drawGameBoy = (f) => {
      if (f < SW_REVEAL) {
        const shades = [c.light, c.blood, c.dark, c.ink];
        ctx.globalAlpha = Math.min(1, (f + 1) / 4);
        rect(0, 0, gw, gh, shades[Math.min(3, Math.floor(f * 4 / SW_SWAP))]);
        ctx.globalAlpha = 0.25;
        for (let y = 1; y < gh; y += 3) for (let x = 1; x < gw; x += 3) rect(x, y, 1, 1, c.dark);
        ctx.globalAlpha = 1;
        return;
      }
      const edge = Math.round(gh * (f - SW_REVEAL + 1) / (SW_FRAMES - SW_REVEAL));
      rect(0, edge, gw, gh - edge, c.ink);
      rect(0, edge, gw, 1, c.light);
    };
    const drawSamurai = (f) => {
      if (f < SW_REVEAL) {
        const bands = 6, bh = Math.ceil(gh / bands), progress = Math.min(1, (f + 1) / SW_SWAP) * bands;
        for (let b = 0; b < bands; b++) {
          const p = Math.max(0, Math.min(1, progress - b));
          if (p <= 0) continue;
          const len = Math.round(gw * p), fromLeft = b % 2 === 0;
          for (let y = b * bh; y < (b + 1) * bh && y < gh; y++) {
            const l = Math.max(0, len - Math.round(pxRand(y * 13 + b) * 3));
            const x0 = fromLeft ? 0 : gw - l;
            rect(x0, y, l, 1, c.ink);
            if (p < 1) rect(fromLeft ? x0 + l : x0 - 1, y, 1, 1, c.gold);
          }
        }
        if (f >= SW_SWAP - 1) for (let i = 0; i < 16; i++) rect(Math.floor(pxRand(i * 9) * gw), Math.floor(pxRand(i * 9 + 1) * gh + f) % gh, 1, 1, i % 2 ? c.light : c.blood);
        return;
      }
      const p = (f - SW_REVEAL) / (SW_FRAMES - 1 - SW_REVEAL), shift = Math.round(gh / 2 * p * p * 1.2);
      rect(0, -shift, gw, Math.ceil(gh / 2), c.ink);
      rect(0, Math.floor(gh / 2) + shift, gw, Math.ceil(gh / 2), c.ink);
      if (f <= SW_REVEAL + 1) rect(0, Math.floor(gh / 2), gw, 1, "#fff");
    };
    const draw = { neon: drawNeon, sakura: drawSakura, gameboy: drawGameBoy, samurai: drawSamurai }[theme] || drawBlood;
    let f = first;
    const t0 = performance.now();
    const frame = () => {
      ctx.clearRect(0, 0, gw, gh);
      draw(f);
      label(f);
      if (f >= SW_REVEAL) document.querySelector(".palette-fx-label")?.remove();
      const next = first + Math.floor((performance.now() - t0) / (1000 / 24)) + 1;
      if (next >= last) {
        // A cover stays up (the page is about to reload under it); a reveal goes.
        if (phase === "reveal") canvas.remove();
        resolve();
        return;
      }
      f = next;
      // Timers, not animation frames: a hidden tab gets no frames, and the
      // switch must still finish (and reload) there.
      setTimeout(frame, 1000 / 24);
    };
    frame();
  });
}


/** Neon cyber's loader (a square ring with a running light, a flickering data
 *  core, a scan line) and Sakura's (petals circling a blossom). 50 x 36 cells. */
function themedLoader(width, style) {
  const W = 50, H = 36;
  const canvas = h("canvas", { width: W, height: H });
  canvas.style.width = `${width}px`;
  canvas.style.height = `${width * H / W}px`;
  const wrap = h("div.katana", null, canvas);
  const pc = new PixelCanvas(canvas);
  animate(canvas, 12, 28, (frame) => {
    pc.clear();
    if (style === "gameboy") {
      const x0 = 9, y0 = 15, segs = 8;
      pc.rect(x0 - 2, y0 - 2, segs * 4 + 3, 7, BLOOD_DARK);
      pc.rect(x0 - 1, y0 - 1, segs * 4 + 1, 5, C.k);
      const filled = Math.floor(frame / 3) % (segs + 2);
      for (let i = 0; i < Math.min(filled, segs); i++) { block(pc, x0 + i * 4, y0); block(pc, x0 + i * 4 + 2, y0); block(pc, x0 + i * 4, y0 + 1); }
      if (Math.floor(frame / 4) % 2 === 0) pc.rect(x0 + Math.min(filled, segs) * 4, y0 + 3, 3, 1, BLOOD_LIGHT);
      const hop = frame % 8 < 4 ? 0 : -2, bx = x0 + Math.floor(frame / 3) % (segs * 4);
      pc.rect(bx, y0 - 6 + hop, 3, 3, BLOOD); pc.px(bx + 1, y0 - 5 + hop, BLOOD_LIGHT);
    } else if (style === "neon") {
      const x0 = 17, y0 = 10, side = 16, ring = [];
      for (let i = 0; i < side; i++) ring.push([x0 + i, y0]);
      for (let i = 0; i < side; i++) ring.push([x0 + side, y0 + i]);
      for (let i = side; i > 0; i--) ring.push([x0 + i, y0 + side]);
      for (let i = side; i > 0; i--) ring.push([x0, y0 + i]);
      for (const [x, y] of ring) pc.px(x, y, BLOOD_DEEP);
      const head = Math.floor(frame / 28 * ring.length);
      for (let k = 0; k < 14; k++) {
        const [x, y] = ring[((head - k) % ring.length + ring.length) % ring.length];
        pc.px(x, y, k === 0 ? "#fff" : k < 4 ? BLOOD_LIGHT : k < 9 ? BLOOD : BLOOD_DARK);
      }
      for (const [cx, cy, dx, dy] of [[x0 - 2, y0 - 2, 1, 1], [x0 + side + 2, y0 - 2, -1, 1], [x0 - 2, y0 + side + 2, 1, -1], [x0 + side + 2, y0 + side + 2, -1, -1]]) {
        pc.px(cx, cy, C.Y); pc.px(cx + dx, cy, C.Y); pc.px(cx, cy + dy, C.Y);
      }
      for (let y = 0; y < 6; y++) for (let x = 0; x < 6; x++) {
        if (pxRand(x * 7 + y * 13 + Math.floor(frame / 2) * 31) < 0.45) pc.px(x0 + 5 + x, y0 + 5 + y, pxRand(x + y + frame) < 0.2 ? C.Y : BLOOD);
      }
      pc.ghost(x0 + 1, y0 + 1 + (frame % (side - 1)), side - 1, 1, hexToRgb(BLOOD_LIGHT), 0.45);
      for (let x = 4; x < 46; x += 3) pc.px(x, 33, BLOOD_DARK);
    } else {
      const rows = SPRITES.blossom;
      rows.forEach((row, y) => [...row].forEach((ch, x) => { if (ch !== ".") pc.px(22 + x, 14 + y, C[ch] || BLOOD); }));
      for (let i = 0; i < 8; i++) {
        const a = frame / 28 * Math.PI * 2 + i * Math.PI / 4, pa = a - Math.PI * 2 / 28;
        petal(pc, Math.round(25 + Math.cos(pa) * 13), Math.round(17 + Math.sin(pa) * 10), (frame + i) & 3, 0.3);
        petal(pc, Math.round(25 + Math.cos(a) * 13), Math.round(17 + Math.sin(a) * 10), (Math.floor(frame / 2) + i) & 3);
      }
      for (let i = 0; i < 4; i++) sparkle(pc, Math.round(6 + pxRand(i * 3) * 38), Math.round(3 + pxRand(i * 7) * 28), frame + i * 4, 0.8);
    }
    pc.bloom();
  });
  return wrap;
}


// --- Game Boy and Gold samurai -------------------------------------------------------------

const PIECES = [[[0, 0], [1, 0], [2, 0], [3, 0]], [[0, 0], [1, 0], [0, 1], [1, 1]], [[0, 0], [1, 0], [2, 0], [1, 1]],
  [[0, 0], [0, 1], [0, 2], [1, 2]], [[1, 0], [2, 0], [0, 1], [1, 1]]];

function block(pc, x, y, alpha = 1) {
  // A bevelled square: light corner, dark edge.
  pc.ghost(x, y, 2, 2, hexToRgb(BLOOD), alpha);
  pc.ghost(x, y, 1, 1, hexToRgb(BLOOD_LIGHT), alpha);
  pc.ghost(x + 1, y + 1, 1, 1, hexToRgb(BLOOD_DARK), alpha);
}

function blocksFrame(pc, frame, cols, rows) {
  for (let y = 1; y < rows; y += 4) for (let x = 1; x < cols; x += 4) pc.ghost(x, y, 1, 1, hexToRgb(BLOOD_DARK), 0.12);
  const n = Math.round(10 * fxDensity());
  for (let i = 0; i < n; i++) {
    const seed = i * 61 + 9;
    const shape = PIECES[Math.floor(pxRand(seed) * PIECES.length) % PIECES.length];
    const x = Math.floor(pxRand(seed + 1) * (cols - 8));
    const span = rows + 12;
    const y = (Math.floor(frame / 3) * 2 + Math.floor(pxRand(seed + 2) * span)) % span - 8;
    for (const [dx, dy] of shape) block(pc, x + dx * 2, y + dy * 2, 0.22 + 0.25 * pxRand(seed + 3));
  }
}

function pixelPop(pc, c, frame) {
  const shades = [BLOOD_LIGHT, BLOOD, BLOOD_DARK, BLOOD_DEEP];
  if (frame < 8) {
    const r = 1 + frame, col = shades[Math.min(3, frame >> 1)];
    for (let d = 0; d <= r; d++) { pc.px(c + d, c - (r - d), col); pc.px(c - d, c - (r - d), col); pc.px(c + d, c + (r - d), col); pc.px(c - d, c + (r - d), col); }
  }
  if (frame < 2) pc.rect(c - 1, c - 1, 3, 3, BLOOD_LIGHT);
  for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
    const d = 2 + frame * 2;
    if (frame < 11) pc.rect(c + dx * d - 1, c + dy * d - 1, 2, 2, shades[Math.min(3, Math.floor(frame / 3))]);
  }
}

function blockDrips(pc, frame, count, seed, cols, rows) {
  for (let i = 0; i < count; i++) {
    const x = Math.round(cols * (i + 0.5) / count + (pxRand(seed * 31 + i) - 0.5) * cols / count * 0.6);
    pc.rect(x - 1, 0, 3, 1, BLOOD_DARK);
    const period = rows + 4;
    const y = (Math.floor(frame / 2) * 2 + Math.floor(pxRand(seed + i * 11) * period)) % period;
    if (y > 1 && y < rows - 1) block(pc, x - 1, y);
  }
}

function flake(pc, x, y, frame, alpha = 1) {
  const g = hexToRgb(BLOOD), l = hexToRgb(BLOOD_LIGHT);
  switch (frame & 3) {
    case 0: pc.ghost(x, y, 2, 1, l, alpha); pc.ghost(x + 1, y + 1, 1, 1, g, alpha); break;
    case 1: pc.ghost(x, y, 1, 2, g, alpha); break;
    case 2: pc.ghost(x, y, 1, 1, g, alpha); pc.ghost(x + 1, y + 1, 2, 1, l, alpha); break;
    default: pc.ghost(x, y, 1, 1, l, alpha);
  }
}

function leafFrame(pc, frame, cols, rows) {
  const n = Math.round(Math.min(34, Math.max(10, Math.round(cols * rows * 0.0006))) * fxDensity());
  for (let i = 0; i < n; i++) {
    const seed = i * 73 + 17;
    const fall = 0.12 + pxRand(seed) * 0.22, span = rows + 10;
    const t = frame * fall + pxRand(seed + 1) * span;
    const y = Math.floor(t % span) - 5;
    const x = Math.floor((pxRand(seed + 2) * cols + Math.sin(t * 0.15 + seed) * 4 + cols) % cols);
    flake(pc, x, y, (Math.floor(frame / 3) + i) & 3, 0.4 + 0.4 * pxRand(seed + 3));
  }
  for (let i = 0; i < 4; i++) sparkle(pc, Math.floor(pxRand(i * 41) * cols), Math.floor(pxRand(i * 41 + 1) * rows), Math.floor(frame / 2) + i * 7, 0.5);
}

function goldBurst(pc, c, frame, seed) {
  if (frame < 6) sparkle(pc, c, c, frame);
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2 + pxRand(seed + i) * 0.4;
    const sp = 1.3 + 1.5 * pxRand(seed + i * 7);
    const out = sp * (1 - Math.pow(0.8, frame)) / 0.2;
    flake(pc, Math.round(c + Math.cos(a) * out + Math.sin(frame * 0.5 + i)), Math.round(c + Math.sin(a) * out + 0.06 * frame * frame), (Math.floor(frame / 2) + i) & 3, frame < 10 ? 1 : 0.5);
  }
}


/** A palette switch without a reload: new colours for the canvases, every
 *  sprite drawn again (marks change shape too), and the emblem recoloured.
 *  CSS follows data-theme on its own, and the animations pick their style
 *  every frame. */
export function retheme() {
  refreshPalette();
  document.querySelectorAll("svg.sprite[data-name]").forEach((old) => {
    const fresh = sprite(old.dataset.name, Number(old.dataset.scale) || 2, old.dataset.color);
    fresh.setAttribute("class", old.getAttribute("class") || "sprite");
    old.replaceWith(fresh);
  });
  document.querySelectorAll("img.emblem").forEach((img) => { img.src = emblemUrl() || "/static/pixel/img/logo.png"; });
}
