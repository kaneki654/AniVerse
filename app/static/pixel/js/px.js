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
const BLOOD = C.R, BLOOD_DARK = C.r, BLOOD_DEEP = C.d, BLOOD_LIGHT = C.H;

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
};

const SVG = "http://www.w3.org/2000/svg";

/** A sprite as an SVG: one rect per run of same-coloured cells. */
export function sprite(name, scale = 2, color) {
  const rows = SPRITES[name];
  const svg = document.createElementNS(SVG, "svg");
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
    this.ctx = canvas.getContext("2d");
  }
  clear() { this.ctx.clearRect(0, 0, this.c.width, this.c.height); }
  rect(x, y, w, h, color) {
    if (w <= 0 || h <= 0) return;
    this.ctx.fillStyle = color;
    this.ctx.fillRect(Math.round(x), Math.round(y), w, h);
  }
  px(x, y, color) { this.rect(x, y, 1, 1, color); }
}

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
          pc.rect(x, y, thick ? 2 : 1, 2, BLOOD);
          pc.px(x, y, BLOOD_LIGHT);
        }
      }
    }
  });
}

// --- splat -----------------------------------------------------------------------

/** A one-shot burst of blood where a blood button was hit -- the app's BloodSplat. */
export function splat(clientX, clientY) {
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;
  const cells = 44;
  const canvas = h("canvas.splat", { width: cells, height: cells });
  canvas.style.left = `${clientX - 66}px`;
  canvas.style.top = `${clientY - 66}px`;
  document.body.appendChild(canvas);
  const pc = new PixelCanvas(canvas);
  const seed = Math.floor(performance.now()) & 0xffff;
  const c = cells / 2;
  const t0 = performance.now();
  const step = () => {
    const frame = Math.floor((performance.now() - t0) / 40);
    if (frame >= 14) { canvas.remove(); return; }
    pc.clear();
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
      if (frame > 0 && frame < 9) {
        const f = frame - 1;
        pc.px(Math.round(c + Math.cos(a) * s * f), Math.round(c + Math.sin(a) * s * f + 0.21 * f * f), BLOOD_DARK);
      }
    }
    requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

/** Every .px-btn that is not .dark/.bone bursts blood where it is clicked. */
document.addEventListener("pointerdown", (e) => {
  const btn = e.target instanceof Element && e.target.closest(".px-btn:not(.dark):not(.bone):not(:disabled), .big-play");
  if (btn) splat(e.clientX, e.clientY);
});

// --- katana loader ----------------------------------------------------------------

/** The loading animation: a katana slashes, blood sprays and pools -- KatanaLoader. */
export function katana(width = 170) {
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
    for (const [bx, off] of [[9, 0], [15, 5], [20, 11], [12, 17]]) {
      const span = Math.floor(fill * 24);
      if (span < 4) continue;
      const y = innerBottom - 1 - ((frame + off) % span);
      if (y > surfaceAt(bx, -t, 1.3) + 1) pc.px(bx, y, BLOOD_LIGHT);
    }
    for (const [gx, gy] of [[9, 5], [8, 6], [7, 7], [6, 9]]) if (gy < surfaceAt(gx, -t, 1.3)) pc.px(gx, gy, C.g);
    if (fill > 0.3) {
      for (const [dx, off] of [[12, 0], [18, 4]]) {
        pc.px(dx, COLS - 1, BLOOD_DARK);
        const fall = (frame + off * 3) % 10;
        if (fall < 7) pc.rect(dx, COLS + fall, 1, 2, BLOOD);
      }
    }
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
      h("div.dialog.px-box", { role: "dialog", "aria-modal": "true", "aria-label": title },
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
