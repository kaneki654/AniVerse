//! Achievements and levels, worked out from watch history alone, so they are
//! the same on every device the history syncs to. The same rules as
//! lib/ui_manga/achievements.dart and the website's achievements.js.
use crate::models::HistoryEntry;
use chrono::{Datelike, Local, TimeZone, Timelike};
use std::collections::{HashMap, HashSet};

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Stats {
    pub finished: usize,
    pub anime: usize,
    pub streak: u32,
    pub best_day: u32,
    pub night_owl: bool,
    pub early_bird: bool,
    pub hours: f64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Level {
    pub xp: u32,
    pub level: u32,
    pub rank: &'static str,
    pub progress: f32,
    /// bronze | silver | gold | blood | legend, one step every 10 levels.
    pub frame: &'static str,
}

impl Level {
    pub fn to_next(&self) -> u32 {
        if self.level >= 99 { 0 } else { (40 * self.level * self.level).saturating_sub(self.xp) }
    }
}

pub struct BadgeDef {
    pub id: &'static str,
    pub name: &'static str,
    pub text: &'static str,
    /// An InkIcons name (ui/icons.slint).
    pub icon: &'static str,
    pub test: fn(&Stats) -> bool,
}

pub const BADGES: [BadgeDef; 17] = [
    BadgeDef { id: "first_blood", name: "First Blood", text: "Finish your first episode", icon: "blood-drop", test: |s| s.finished >= 1 },
    BadgeDef { id: "ten_slain", name: "Ten Slain", text: "Finish 10 episodes", icon: "skull-small", test: |s| s.finished >= 10 },
    BadgeDef { id: "hundred_slain", name: "100 Episodes Slain", text: "Finish 100 episodes", icon: "skull", test: |s| s.finished >= 100 },
    BadgeDef { id: "thousand_slain", name: "Demon Lord", text: "Finish 1,000 episodes", icon: "skull", test: |s| s.finished >= 1000 },
    BadgeDef { id: "collector", name: "Collector", text: "Watch 10 different anime", icon: "grid", test: |s| s.anime >= 10 },
    BadgeDef { id: "binge", name: "Binge", text: "6 episodes of one anime in a day", icon: "play", test: |s| s.best_day >= 6 },
    BadgeDef { id: "streak_3", name: "On a Roll", text: "Watch 3 days in a row", icon: "check", test: |s| s.streak >= 3 },
    BadgeDef { id: "streak_7", name: "Week of Blood", text: "Watch 7 days in a row", icon: "star", test: |s| s.streak >= 7 },
    BadgeDef { id: "streak_30", name: "Unstoppable", text: "Watch 30 days in a row", icon: "star", test: |s| s.streak >= 30 },
    BadgeDef { id: "night_owl", name: "Night Owl", text: "Finish an episode between 1 and 4 AM", icon: "clock", test: |s| s.night_owl },
    BadgeDef { id: "marathon", name: "Marathon", text: "Watch 24 hours in total", icon: "clock", test: |s| s.hours >= 24.0 },
    BadgeDef { id: "possessed", name: "Possessed", text: "10 episodes of one anime in a day", icon: "sword", test: |s| s.best_day >= 10 },
    BadgeDef { id: "archivist", name: "Archivist", text: "Watch 50 different anime", icon: "bookmark", test: |s| s.anime >= 50 },
    BadgeDef { id: "early_bird", name: "Early Bird", text: "Finish an episode between 5 and 7 AM", icon: "bell", test: |s| s.early_bird },
    BadgeDef { id: "legion", name: "Legion", text: "Finish 500 episodes", icon: "skull", test: |s| s.finished >= 500 },
    BadgeDef { id: "ascended", name: "Ascended", text: "Watch 100 hours in total", icon: "trophy", test: |s| s.hours >= 100.0 },
    BadgeDef { id: "streak_100", name: "Immortal", text: "Watch 100 days in a row", icon: "star", test: |s| s.streak >= 100 },
];

pub const RANKS: [&str; 8] = ["Peasant", "Ronin", "Samurai", "Hatamoto", "Daimyo", "Shogun", "Demon Hunter", "Demon Lord"];

fn day_of(millis: i64) -> (i32, u32, u32) {
    let t = Local.timestamp_millis_opt(millis).single().unwrap_or_else(Local::now);
    (t.year(), t.month(), t.day())
}

/// The stats over every episode watched (removed ones left out).
pub fn stats(entries: &[HistoryEntry]) -> Stats {
    let all: Vec<&HistoryEntry> = entries.iter().filter(|e| !e.deleted).collect();
    let done: Vec<&HistoryEntry> = all.iter().copied().filter(|e| e.finished()).collect();
    let days: HashSet<(i32, u32, u32)> = all.iter().map(|e| day_of(e.updated_at)).collect();
    // Streak: consecutive days with any watching, ending today or yesterday.
    let mut streak = 0;
    let today = Local::now().date_naive();
    let mut d = today;
    loop {
        let key = (d.year(), d.month(), d.day());
        if days.contains(&key) {
            streak += 1;
        } else if streak > 0 || d != today {
            break;
        }
        if streak > 400 {
            break;
        }
        match d.pred_opt() {
            Some(p) => d = p,
            None => break,
        }
    }
    let mut per_day: HashMap<(String, (i32, u32, u32)), u32> = HashMap::new();
    for e in &done {
        *per_day.entry((e.anime_id.clone(), day_of(e.updated_at))).or_default() += 1;
    }
    let hour = |e: &&HistoryEntry| Local.timestamp_millis_opt(e.updated_at).single().map(|t| t.hour()).unwrap_or(12);
    let ms: u64 = all.iter().map(|e| if e.finished() { e.duration_ms } else { e.position_ms }).sum();
    Stats {
        finished: done.len(),
        anime: all.iter().map(|e| e.anime_id.as_str()).collect::<HashSet<_>>().len(),
        streak,
        best_day: per_day.values().copied().max().unwrap_or(0),
        night_owl: done.iter().any(|e| (1..4).contains(&hour(e))),
        early_bird: done.iter().any(|e| (5..7).contains(&hour(e))),
        hours: ms as f64 / 3_600_000.0,
    }
}

pub fn level(s: &Stats) -> Level {
    let xp = (s.finished * 10 + s.anime * 25) as u32 + s.streak.min(60) * 15;
    let lvl = (((xp as f64) / 40.0).sqrt().floor() as u32 + 1).min(99);
    let floor = 40 * (lvl - 1) * (lvl - 1);
    let next = 40 * lvl * lvl;
    const FRAMES: [&str; 5] = ["bronze", "silver", "gold", "blood", "legend"];
    Level {
        xp,
        level: lvl,
        rank: RANKS[(((lvl - 1) / 6) as usize).min(RANKS.len() - 1)],
        progress: if lvl >= 99 { 1.0 } else { (xp - floor) as f32 / (next - floor) as f32 },
        frame: FRAMES[(((lvl - 1) / 10) as usize).min(4)],
    }
}

pub fn unlocked(s: &Stats) -> Vec<&'static str> {
    BADGES.iter().filter(|b| (b.test)(s)).map(|b| b.id).collect()
}

/// The avatar frame's colour.
pub fn frame_color(frame: &str) -> slint::Color {
    match frame {
        "silver" => slint::Color::from_rgb_u8(0xC9, 0xD2, 0xDE),
        "gold" => slint::Color::from_rgb_u8(0xE5, 0x09, 0x14),
        "blood" => slint::Color::from_rgb_u8(0xFF, 0x5A, 0x64),
        "legend" => slint::Color::from_rgb_u8(0xB4, 0x8C, 0xFF),
        _ => slint::Color::from_rgb_u8(0xB0, 0x6A, 0x2C),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn watched(anime: &str, episode: u32, at: i64) -> HistoryEntry {
        HistoryEntry { anime_id: anime.into(), episode, position_ms: 1_000, duration_ms: 1_000, updated_at: at, ..Default::default() }
    }

    #[test]
    fn levels_follow_the_flutter_curve() {
        let lv = level(&Stats { finished: 2, anime: 7, ..Default::default() });
        // 2*10 + 7*25 = 195 XP: level 3, 165 to level 4, as on the Flutter screen
        assert_eq!((lv.xp, lv.level, lv.rank, lv.to_next()), (195, 3, "Peasant", 165));
        assert_eq!(level(&Stats::default()).level, 1);
    }

    #[test]
    fn finished_episodes_unlock_badges_and_today_counts_for_the_streak() {
        let now = Local::now().timestamp_millis();
        let s = stats(&[watched("1", 1, now), watched("1", 2, now), watched("2", 1, now - 86_400_000)]);
        assert_eq!((s.finished, s.anime, s.streak), (3, 2, 2));
        assert!(unlocked(&s).contains(&"first_blood"));
        assert!(!unlocked(&s).contains(&"ten_slain"));
    }
}
