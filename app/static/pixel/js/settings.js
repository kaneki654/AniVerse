// Viewer settings for the website, kept in this browser: palette, sound,
// data saver, subtitle style and episode alerts. The theme is applied before
// first paint by a tiny script in base.html, so pages never flash the wrong one.

const KEY = "av.settings";
const DEFAULTS = {
  theme: "blood",      // blood | neon | sakura
  darkMode: true,      // independent of the accent palette
  sfx: true,           // 8-bit sound effects
  volume: 0.35,
  dataSaver: false,    // stay on the lowest quality
  subSize: "m",        // s | m | l | xl
  subBg: true,         // dark box behind subtitles
  subLang: "",         // preferred subtitle language; "" = the source's default
  alerts: false,       // system notifications for new episodes
};
export const THEMES = { blood: "Blood", neon: "Neon cyber", sakura: "Sakura" };

const listeners = new Set();
let current = { ...DEFAULTS };

function read() {
  try { current = { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") }; } catch { /* storage off: keep this visit's settings */ }
  return { ...current };
}

export const settings = {
  get: read,
  set(patch) {
    const next = { ...read(), ...patch };
    current = next;
    try { localStorage.setItem(KEY, JSON.stringify(next)); } catch { /* storage off */ }
    if (patch.theme) document.documentElement.dataset.theme = next.theme;
    if ("darkMode" in patch) document.documentElement.dataset.mode = next.darkMode ? "dark" : "light";
    listeners.forEach((fn) => fn(next));
    return next;
  },
  onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
};
