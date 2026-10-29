// The manga look's sound effects: paper, ink and impacts -- taps, brush
// swishes, page turns, a speech bubble's pop and the heavy DON of an impact
// panel. The same recordings as the app (scripts/make_manga_sfx.py renders
// them; scripts/make_manga_web.py copies them here). Fetched and decoded the
// first time each plays; off in Settings, quiet by default.
import { settings } from "./settings.js";

let ctx = null;
const buffers = new Map();
const NAMES = new Set(["click", "select", "splat", "slash", "start", "skip", "error", "achieve", "hit", "boss", "page", "pop", "don"]);

function audio() {
  if (!ctx) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
  }
  if (ctx.state === "suspended") ctx.resume().catch(() => {});
  return ctx;
}

function load(c, name) {
  if (!buffers.has(name)) {
    buffers.set(name, fetch(`/static/manga/sfx/${name}.wav`)
      .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(String(r.status)))))
      .then((data) => c.decodeAudioData(data))
      .catch(() => null));
  }
  return buffers.get(name);
}

/** Plays a named effect if sound is on. Safe to call before any user gesture:
 *  browsers keep audio locked until one, and this just stays quiet until then. */
export function sfx(name) {
  if (!settings.get().sfx || !NAMES.has(name)) return;
  const c = audio();
  if (!c) return;
  load(c, name).then((buffer) => {
    if (!buffer) return;
    try {
      const src = c.createBufferSource();
      src.buffer = buffer;
      const g = c.createGain();
      g.gain.value = settings.get().volume;
      src.connect(g).connect(c.destination);
      src.start();
    } catch { /* audio refused */ }
  });
}
