// Viewer settings for the website, kept in this browser: palette, sound,
// data saver, subtitle style and episode alerts. The theme is applied before
// first paint by a tiny script in base.html, so pages never flash the wrong one.

const KEY = "av.settings";
const DEFAULTS = {
  theme: "blood",      // blood | neon | sakura
  sfx: true,           // 8-bit sound effects
  volume: 0.35,
  dataSaver: false,    // stay on the lowest quality
  subSize: "m",        // s | m | l | xl
  subBg: true,         // dark box behind subtitles
  subLang: "",         // preferred subtitle language; "" = the source's default
  alerts: false,       // system notifications for new episodes
  effects: "full",     // full | lite (fewer particles, no glow) | off
  contrast: false,     // brighter secondary text, for low vision
};
export const THEMES = { blood: "Blood", neon: "Neon cyber", sakura: "Sakura", gameboy: "Game Boy", samurai: "Gold samurai" };

const listeners = new Set();

function read() {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") }; } catch { return { ...DEFAULTS }; }
}

export const settings = {
  get: read,
  set(patch) {
    const next = { ...read(), ...patch };
    try { localStorage.setItem(KEY, JSON.stringify(next)); } catch { /* storage off */ }
    if (patch.theme) document.documentElement.dataset.theme = next.theme;
    if (patch.effects) document.documentElement.dataset.fx = next.effects;
    if ("contrast" in patch) document.documentElement.dataset.contrast = next.contrast ? "on" : "off";
    listeners.forEach((fn) => fn(next));
    return next;
  },
  onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
};
