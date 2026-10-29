// Achievements and levels, worked out from watch history alone, so they are
// the same on every device the history syncs to. The app has the same rules
// in lib/ui_2d/achievements.dart; change both together.
import { history } from "./api.js";

const DAY = 86400000;

export const BADGES = [
  { id: "first_blood", name: "First Blood", text: "Finish your first episode", sprite: "bloodDrop", test: (s) => s.finished >= 1 },
  { id: "ten_slain", name: "Ten Slain", text: "Finish 10 episodes", sprite: "skullSmall", test: (s) => s.finished >= 10 },
  { id: "hundred_slain", name: "100 Episodes Slain", text: "Finish 100 episodes", sprite: "skull", test: (s) => s.finished >= 100 },
  { id: "thousand_slain", name: "Demon Lord", text: "Finish 1,000 episodes", sprite: "skull", test: (s) => s.finished >= 1000 },
  { id: "collector", name: "Collector", text: "Watch 10 different anime", sprite: "grid", test: (s) => s.anime >= 10 },
  { id: "binge", name: "Binge", text: "6 episodes of one anime in a day", sprite: "play", test: (s) => s.bestDay >= 6 },
  { id: "streak_3", name: "On a Roll", text: "Watch 3 days in a row", sprite: "check", test: (s) => s.streak >= 3 },
  { id: "streak_7", name: "Week of Blood", text: "Watch 7 days in a row", sprite: "star", test: (s) => s.streak >= 7 },
  { id: "streak_30", name: "Unstoppable", text: "Watch 30 days in a row", sprite: "star", test: (s) => s.streak >= 30 },
  { id: "night_owl", name: "Night Owl", text: "Finish an episode between 1 and 4 AM", sprite: "clock", test: (s) => s.nightOwl },
  { id: "marathon", name: "Marathon", text: "Watch 24 hours in total", sprite: "clock", test: (s) => s.hours >= 24 },
  { id: "possessed", name: "Possessed", text: "10 episodes of one anime in a day", sprite: "sword", test: (s) => s.bestDay >= 10 },
  { id: "archivist", name: "Archivist", text: "Watch 50 different anime", sprite: "bookmark", test: (s) => s.anime >= 50 },
  { id: "early_bird", name: "Early Bird", text: "Finish an episode between 5 and 7 AM", sprite: "bell", test: (s) => s.earlyBird },
  { id: "legion", name: "Legion", text: "Finish 500 episodes", sprite: "skull", test: (s) => s.finished >= 500 },
  { id: "ascended", name: "Ascended", text: "Watch 100 hours in total", sprite: "trophy", test: (s) => s.hours >= 100 },
  { id: "streak_100", name: "Immortal", text: "Watch 100 days in a row", sprite: "star", test: (s) => s.streak >= 100 },
];

export const RANKS = ["Peasant", "Ronin", "Samurai", "Hatamoto", "Daimyo", "Shogun", "Demon Hunter", "Demon Lord"];

const finishedEntry = (e) => e.duration_ms > 0 && e.position_ms >= e.duration_ms * 0.9;

export function stats(entries = history.all()) {
  const done = entries.filter(finishedEntry);
  const days = new Set(entries.map((e) => new Date(e.updated_at).toDateString()));
  // Streak: consecutive days with any watching, ending today or yesterday.
  let streak = 0;
  for (let d = new Date(); ; d = new Date(d.getTime() - DAY)) {
    if (days.has(d.toDateString())) streak++;
    else if (streak > 0 || d.toDateString() !== new Date().toDateString()) break;
    if (streak > 400) break;
  }
  const perDay = new Map();
  for (const e of done) {
    const k = `${e.anime_id}|${new Date(e.updated_at).toDateString()}`;
    perDay.set(k, (perDay.get(k) || 0) + 1);
  }
  const ms = entries.reduce((sum, e) => sum + (finishedEntry(e) ? e.duration_ms : e.position_ms), 0);
  return {
    finished: done.length,
    anime: new Set(entries.map((e) => e.anime_id)).size,
    streak,
    bestDay: Math.max(0, ...perDay.values()),
    nightOwl: done.some((e) => { const h = new Date(e.updated_at).getHours(); return h >= 1 && h < 4; }),
    earlyBird: done.some((e) => { const h = new Date(e.updated_at).getHours(); return h >= 5 && h < 7; }),
    hours: ms / 3600000,
  };
}

/** XP, level (1-99), rank title and progress to the next level. */
export function level(s = stats()) {
  const xp = s.finished * 10 + s.anime * 25 + Math.min(s.streak, 60) * 15;
  const lvl = Math.min(99, Math.floor(Math.sqrt(xp / 40)) + 1);
  const floor = 40 * (lvl - 1) ** 2, next = 40 * lvl ** 2;
  return {
    xp, level: lvl,
    rank: RANKS[Math.min(RANKS.length - 1, Math.floor((lvl - 1) / 6))],
    progress: lvl >= 99 ? 1 : (xp - floor) / (next - floor),
    // The avatar frame steps up every 10 levels: bronze, silver, gold, blood, legend.
    frame: ["bronze", "silver", "gold", "blood", "legend"][Math.min(4, Math.floor((lvl - 1) / 10))],
  };
}

export function unlocked(s = stats()) {
  return BADGES.filter((b) => b.test(s)).map((b) => b.id);
}

const SEEN = "av.badges";

/** Badges newly earned since the last call, remembered so each shows once. */
export function newlyUnlocked() {
  const now = unlocked();
  let seen;
  try { seen = JSON.parse(localStorage.getItem(SEEN) || "null"); } catch { seen = null; }
  try { localStorage.setItem(SEEN, JSON.stringify(now)); } catch { /* storage off */ }
  // First run on this browser: everything is "already seen", no burst of toasts.
  if (!Array.isArray(seen)) return [];
  return BADGES.filter((b) => now.includes(b.id) && !seen.includes(b.id));
}
