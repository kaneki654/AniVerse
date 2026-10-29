// 8-bit sound effects, synthesised on the spot with WebAudio square and noise
// voices -- nothing to download, and they sound like a console because they
// are made the way one makes them. Off in Settings, quiet by default.
import { settings } from "./settings.js";

let ctx = null;
let noise = null;

function audio() {
  if (!ctx) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
    // One second of white noise, reused for hits and splats.
    noise = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
    const d = noise.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  }
  if (ctx.state === "suspended") ctx.resume().catch(() => {});
  return ctx;
}

// Each palette has its own voice: Blood as is, Neon cyber pitched up and
// bright, Sakura lower and softer -- the same as the app.
const voice = () => ({ neon: [1.3, 1], sakura: [0.82, 0.75], gameboy: [1.15, 0.9], samurai: [0.7, 0.95] })[document.documentElement.dataset.theme] || [1, 1];

function tone(c, { type = "square", from, to = from, at = 0, dur = 0.08, gain = 1 }) {
  const [rate, loud] = voice();
  from *= rate; to *= rate; gain *= loud;
  const t0 = c.currentTime + at;
  const osc = c.createOscillator();
  const g = c.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(from, t0);
  if (to !== from) osc.frequency.exponentialRampToValueAtTime(to, t0 + dur);
  // Stepped decay: a few hard levels instead of a smooth fade, like a sound chip.
  const v = settings.get().volume * 0.22 * gain;
  [1, 0.6, 0.3, 0].forEach((k, i) => g.gain.setValueAtTime(v * k, t0 + (dur * i) / 3));
  osc.connect(g).connect(c.destination);
  osc.start(t0);
  osc.stop(t0 + dur + 0.02);
}

function burst(c, { at = 0, dur = 0.12, cutoff = 1800, gain = 1 }) {
  const [rate, loud] = voice();
  cutoff *= rate; gain *= loud;
  const t0 = c.currentTime + at;
  const src = c.createBufferSource();
  src.buffer = noise;
  const f = c.createBiquadFilter();
  f.type = "lowpass";
  f.frequency.setValueAtTime(cutoff, t0);
  f.frequency.exponentialRampToValueAtTime(200, t0 + dur);
  const g = c.createGain();
  const v = settings.get().volume * 0.35 * gain;
  [1, 0.5, 0.2, 0].forEach((k, i) => g.gain.setValueAtTime(v * k, t0 + (dur * i) / 3));
  src.connect(f).connect(g).connect(c.destination);
  src.start(t0);
  src.stop(t0 + dur + 0.02);
}

const SOUNDS = {
  click: (c) => tone(c, { from: 880, dur: 0.04, gain: 0.6 }),
  select: (c) => { tone(c, { from: 660, dur: 0.05 }); tone(c, { from: 990, at: 0.05, dur: 0.06 }); },
  splat: (c) => { burst(c, { dur: 0.16, cutoff: 2400 }); tone(c, { type: "triangle", from: 220, to: 70, dur: 0.14, gain: 0.8 }); },
  slash: (c) => { burst(c, { dur: 0.09, cutoff: 6000, gain: 0.7 }); tone(c, { from: 1400, to: 300, dur: 0.09, gain: 0.5 }); },
  start: (c) => [523, 659, 784, 1047].forEach((f, i) => tone(c, { from: f, at: i * 0.07, dur: 0.07 })),
  skip: (c) => { tone(c, { from: 440, to: 1320, dur: 0.12 }); },
  error: (c) => { tone(c, { from: 196, dur: 0.12 }); tone(c, { from: 147, at: 0.13, dur: 0.22 }); },
  achieve: (c) => [784, 988, 1175, 1568, 1319, 1568].forEach((f, i) => tone(c, { from: f, at: i * 0.08, dur: 0.09 })),
  hit: (c) => { burst(c, { dur: 0.07, cutoff: 3200 }); tone(c, { from: 330, to: 110, dur: 0.07, gain: 0.7 }); },
  boss: (c) => [392, 311, 262, 196].forEach((f, i) => tone(c, { type: "sawtooth", from: f, at: i * 0.11, dur: 0.12, gain: 0.7 })),
};

/** Plays a named effect if sound is on. Safe to call before any user gesture:
 *  browsers keep audio locked until one, and this just stays quiet until then. */
export function sfx(name) {
  if (!settings.get().sfx) return;
  const c = audio();
  const play = SOUNDS[name];
  if (c && play) {
    try { play(c); } catch { /* audio refused */ }
  }
}
