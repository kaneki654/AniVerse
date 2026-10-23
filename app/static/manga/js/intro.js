// The manga website's opening, the same as the app's (lib/ui_manga/intro):
// about four seconds, click or any key to skip, once per browser session.
//
//  1. A blank page; three panel borders ink themselves in.
//  2. The panels come alive: speed lines, screentone sweeping in, ゴゴゴ.
//  3. An impact frame: the page flashes to negative.
//  4. Focus lines converge and the AniVerse emblem is inked in stage by stage
//     (line art, screentone, red) as it lands with a ドン!
//  5. ANIVERSE slams in letter by letter on a caption strip.
//  6. The page turns over onto the site.
import { focusLines, pxRand } from "./px.js";
import { sfx } from "./sfx.js";
import { settings } from "./settings.js";

const MS = 4300;
const INK = "#121010", PAPER = "#f5f1e8", RED = "#e50914";
const IMG = "/static/manga/img";

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
const easeInCubic = (t) => t * t * t;
const easeOutBack = (t) => 1 + 2.70158 * Math.pow(t - 1, 3) + 1.70158 * Math.pow(t - 1, 2);
const elastic = (t) => (t === 0 || t === 1 ? t : Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * (2 * Math.PI) / 3) + 1);

function image(src) {
  return new Promise((resolve) => {
    const i = new Image();
    i.onload = () => resolve(i);
    i.onerror = () => resolve(null);
    i.src = src;
  });
}

/** Plays the intro over the page if it has not played this session. */
export async function playIntro() {
  try { if (sessionStorage.getItem("av.intro")) return; sessionStorage.setItem("av.intro", "1"); } catch { return; }
  if (settings.get().intro === false || document.documentElement.dataset.fx === "off" ||
      matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const canvas = document.createElement("canvas");
  canvas.className = "intro";
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", "AniVerse");
  document.body.appendChild(canvas);
  const ctx = canvas.getContext("2d");
  const dpr = Math.min(2, devicePixelRatio || 1);
  let W = 0, H = 0;
  const size = () => {
    W = innerWidth; H = innerHeight;
    canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  };
  size();
  addEventListener("resize", size);

  // Cover the page at once; the art arrives in a moment.
  ctx.fillStyle = PAPER;
  ctx.fillRect(0, 0, W, H);
  const [lines, tone, color] = await Promise.all(["logo_lines", "logo_tone", "logo_color"].map((n) => image(`${IMG}/${n}.png`)));
  try { await document.fonts.load('italic 40px "MangaTitle"'); await document.fonts.load('700 40px "MangaSfx"'); } catch { /* fallback faces */ }

  let done = false, t0 = performance.now();
  const played = new Set();
  const finish = () => {
    if (done) return;
    done = true;
    removeEventListener("resize", size);
    removeEventListener("keydown", finish);
    canvas.remove();
  };
  canvas.addEventListener("click", finish);
  addEventListener("keydown", finish);

  const beat = (ms, a, b) => clamp01((ms - a) / (b - a));
  const cue = (ms, at, name) => { if (ms >= at && !played.has(at)) { played.add(at); sfx(name); } };

  function frame(now) {
    if (done) return;
    const ms = now - t0;
    if (ms >= MS) { finish(); return; }
    cue(ms, 40, "page"); cue(ms, 1480, "hit"); cue(ms, 2050, "don"); cue(ms, 2900, "slash"); cue(ms, 3700, "page");

    ctx.save();
    const turn = easeInCubic(beat(ms, 3650, MS));
    if (turn > 0) {
      // The page turning over: only the part not yet turned is drawn.
      ctx.clearRect(0, 0, W, H);
      const slant = W * 0.4, x = W + slant - turn * (W + 2 * slant);
      ctx.beginPath();
      ctx.moveTo(0, 0); ctx.lineTo(Math.max(0, x + slant), 0); ctx.lineTo(Math.max(0, x), H); ctx.lineTo(0, H);
      ctx.closePath();
      ctx.clip();
    }
    if (ms < 1450) threePanels(ms);
    else if (ms < 1640) impact(ms);
    else logoPanel(ms);
    ctx.restore();
    if (turn > 0) foldEdge(turn);
    requestAnimationFrame(frame);
  }

  // --- 1-2: three panels ------------------------------------------------------------------------

  function panelRects() {
    const m = W * 0.06, top = H * 0.12, split = H * 0.5, bottom = H * 0.86;
    return [
      [[m, top], [W - m, top], [W - m, split - m / 2], [m, split - m / 2]],
      [[m, split + m / 2], [W * 0.56, split + m / 2], [W * 0.56 - 40, bottom], [m, bottom]],
      [[W * 0.44 + m, split + m / 2], [W - m, split + m / 2], [W - m, bottom], [W * 0.44 + m - 40, bottom]],
    ];
  }

  function polygon(pts) {
    ctx.beginPath();
    pts.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
    ctx.closePath();
  }

  /** The outline of pts drawn along its length up to t. */
  function partialOutline(pts, t) {
    const ring = [...pts, pts[0]];
    let total = 0;
    for (let i = 1; i < ring.length; i++) total += Math.hypot(ring[i][0] - ring[i - 1][0], ring[i][1] - ring[i - 1][1]);
    let left = total * t;
    ctx.beginPath();
    ctx.moveTo(ring[0][0], ring[0][1]);
    for (let i = 1; i < ring.length && left > 0; i++) {
      const [ax, ay] = ring[i - 1], [bx, by] = ring[i];
      const len = Math.hypot(bx - ax, by - ay);
      const k = Math.min(1, left / len);
      ctx.lineTo(ax + (bx - ax) * k, ay + (by - ay) * k);
      left -= len;
    }
    ctx.stroke();
  }

  function halftone(x0, y0, w, hgt, from, to, spacing = 7) {
    ctx.fillStyle = INK;
    let row = 0;
    for (let y = y0 - spacing; y < y0 + hgt + spacing; y += spacing * 0.71, row++) {
      for (let x = x0 + (row % 2 ? spacing / 2 : 0) - spacing; x < x0 + w + spacing; x += spacing) {
        const d = from + (to - from) * clamp01((x - x0) / Math.max(1, w));
        if (d <= 0.02) continue;
        ctx.beginPath();
        ctx.arc(x, y, spacing * 0.5 * Math.sqrt(d), 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  function sfxText(text, x, y, sizePx, colorFill, angle, scale = 1) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(angle);
    ctx.scale(scale, scale);
    ctx.font = `700 ${sizePx}px "MangaSfx", sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.lineJoin = "round";
    ctx.strokeStyle = INK; ctx.lineWidth = sizePx / 4.5; ctx.strokeText(text, 0, 0);
    ctx.strokeStyle = "#fff"; ctx.lineWidth = sizePx / 8; ctx.strokeText(text, 0, 0);
    ctx.fillStyle = colorFill; ctx.fillText(text, 0, 0);
    ctx.restore();
  }

  function threePanels(ms) {
    ctx.fillStyle = PAPER;
    ctx.fillRect(0, 0, W, H);
    const panels = panelRects();
    const draw = easeOut(beat(ms, 80, 700));
    const life = beat(ms, 600, 1450);
    if (life > 0) {
      // Panel 1: speed lines racing across.
      ctx.save(); polygon(panels[0]); ctx.clip();
      const [[x0, y0], [x1], , [, y3]] = panels[0];
      ctx.strokeStyle = INK; ctx.lineCap = "round";
      for (let i = 0; i < 40; i++) {
        const y = y0 + pxRand(i * 3 + 1) * (y3 - y0);
        const len = (x1 - x0) * (0.15 + pxRand(i * 7) * 0.4);
        const x = x0 - len + ((pxRand(i * 11) + life * 1.6 * (0.8 + pxRand(i * 13))) % 1) * (x1 - x0 + len);
        ctx.lineWidth = 0.8 + pxRand(i * 5) * 2.2;
        ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + len, y - len * 0.08); ctx.stroke();
      }
      ctx.restore();
      // Panel 2: screentone sweeping in from the left.
      ctx.save(); polygon(panels[1]); ctx.clip();
      const [[ax, ay], [bx], , [, dy]] = panels[1];
      halftone(ax, ay, (bx - ax) * life, dy - ay, 0.7, 0.15);
      ctx.restore();
      // Panel 3: ゴゴゴ, one after another.
      const [[cx0, cy0], [cx1], , [, cy3]] = panels[2];
      const sizePx = Math.min(W, H) * 0.12;
      for (let i = 0; i < 3; i++) {
        const t = clamp01((ms - 700 - i * 140) / 420);
        if (t <= 0) continue;
        sfxText("ゴ", cx0 + (cx1 - cx0) * 0.4 + i * 18, cy0 + (cy3 - cy0) * (0.25 + i * 0.25), sizePx, INK,
          -0.12 * (2 - elastic(t)), 2.2 - 1.2 * elastic(t));
      }
    }
    // The borders, inked in one after another.
    ctx.strokeStyle = INK; ctx.lineWidth = 5; ctx.lineCap = "square";
    panels.forEach((p, i) => {
      const local = clamp01(draw * 1.6 - i * 0.3);
      if (local > 0) partialOutline(p, local);
    });
  }

  // --- 3: impact frame -------------------------------------------------------------------------

  function impact(ms) {
    if (ms < 1560) {
      ctx.fillStyle = INK; ctx.fillRect(0, 0, W, H);
      focusLines(ctx, W, H, { seed: 9, count: 120, clear: 0.2, color: "#fff" });
    } else {
      ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, W, H);
    }
  }

  // --- 4-5: the logo lands ----------------------------------------------------------------------

  function logoPanel(ms) {
    ctx.fillStyle = PAPER;
    ctx.fillRect(0, 0, W, H);
    const flicker = Math.floor((ms - 1640) / 70);
    const cy = H * 0.41;
    focusLines(ctx, W, H, { cx: W / 2, cy, seed: ms < 2400 ? flicker : 3, count: 110, clear: 0.33,
      color: ms < 2400 ? INK : "rgba(18,16,16,0.85)" });
    const lineT = beat(ms, 1640, 1950), toneT = beat(ms, 1900, 2100), redT = beat(ms, 2050, 2350);
    const s = Math.min(W, H) * 0.56;
    const shake = redT > 0 && redT < 0.6 ? 8 * (1 - redT / 0.6) : 0;
    const ox = W / 2 - s / 2 + (pxRand(flicker * 7) - 0.5) * 2 * shake;
    const oy = cy - s / 2 + (pxRand(flicker * 13 + 5) - 0.5) * 2 * shake;
    if (color && redT > 0) {
      const k = 1.35 - 0.35 * elastic(redT);
      ctx.globalAlpha = redT;
      ctx.drawImage(color, W / 2 - (s * k) / 2, cy - (s * k) / 2, s * k, s * k);
      ctx.globalAlpha = 1;
    }
    if (tone && toneT > 0) { ctx.globalAlpha = toneT; ctx.drawImage(tone, ox, oy, s, s); ctx.globalAlpha = 1; }
    if (lines && lineT > 0) {
      // Line art drawn from the top down.
      ctx.save(); ctx.beginPath(); ctx.rect(ox, oy, s, s * lineT); ctx.clip();
      ctx.drawImage(lines, ox, oy, s, s);
      ctx.restore();
    }
    if (redT > 0.15) {
      const t = clamp01((ms - 2100) / 520);
      sfxText("ドン!", W * 0.5 + Math.min(W, H) * 0.36, H * 0.19, Math.min(W, H) * 0.15, RED,
        0.18 * (2 - elastic(t)), 2.2 - 1.2 * elastic(t));
    }
    const word = beat(ms, 2850, 3350);
    if (word > 0) wordmark(word, beat(ms, 3300, 3550), H * 0.775, Math.min(W, H) * 0.12);
  }

  function wordmark(progress, underline, y, sizePx) {
    const word = "ANIVERSE";
    ctx.font = `italic ${sizePx}px "MangaTitle", sans-serif`;
    const widths = [...word].map((c) => ctx.measureText(c).width);
    const total = widths.reduce((a, b) => a + b, 0);
    const padX = sizePx * 0.45, padY = sizePx * 0.14;
    // The caption strip, skewed.
    ctx.save();
    ctx.translate(W / 2, y);
    ctx.transform(1, 0, -0.14, 1, 0, 0);
    ctx.fillStyle = INK;
    ctx.fillRect(-total / 2 - padX, -sizePx / 2 - padY, total + padX * 2, sizePx + padY * 2);
    ctx.restore();
    ctx.fillStyle = "#fff";
    ctx.textBaseline = "middle";
    ctx.textAlign = "center";
    let x = W / 2 - total / 2;
    [...word].forEach((c, i) => {
      const t = clamp01((progress * (word.length + 3) - i) / 3);
      if (t > 0) {
        const land = easeOutBack(t);
        ctx.save();
        ctx.translate(x + widths[i] / 2, y - sizePx * 1.4 * (1 - land));
        ctx.rotate((i % 2 ? 0.25 : -0.25) * (1 - land));
        ctx.fillText(c, 0, 0);
        ctx.restore();
      }
      x += widths[i];
    });
    if (underline > 0) {
      const full = total + padX * 2, w = full * underline, ux = W / 2 - full / 2, uy = y + sizePx * 0.75, uh = sizePx * 0.28;
      ctx.fillStyle = RED;
      ctx.beginPath();
      ctx.moveTo(ux, uy + uh * 0.25);
      ctx.quadraticCurveTo(ux + w * 0.5, uy, ux + w, uy + uh * 0.45);
      ctx.lineTo(ux + w * 0.96, uy + uh * 0.6);
      ctx.quadraticCurveTo(ux + w * 0.5, uy + uh * 0.75, ux, uy + uh * 0.85);
      ctx.closePath();
      ctx.fill();
    }
  }

  /** The turning page's underside along the fold: white, screentoned, inked. */
  function foldEdge(t) {
    const slant = W * 0.4, x = W + slant - t * (W + 2 * slant);
    const top = [x + slant, 0], bottom = [x, H];
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(top[0], 0); ctx.lineTo(top[0] + 60, 0); ctx.lineTo(bottom[0] + 60, H); ctx.lineTo(bottom[0], H);
    ctx.closePath();
    ctx.clip();
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, W, H);
    halftone(bottom[0], 0, slant + 60, H, 0.4, 0.4, 6);
    ctx.restore();
    ctx.strokeStyle = INK; ctx.lineWidth = 4;
    ctx.beginPath(); ctx.moveTo(top[0], top[1]); ctx.lineTo(bottom[0], bottom[1]); ctx.stroke();
  }

  t0 = performance.now();
  requestAnimationFrame(frame);
}
