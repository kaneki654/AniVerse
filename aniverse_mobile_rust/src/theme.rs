use serde::{Deserialize, Serialize};

/// The five palettes in Flutter's ui_2d/pixel/pixel.dart. Manga has its own
/// fixed paper/ink palette and keeps this choice for switching back to Pixel.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThemeId { Blood, Neon, Sakura, Gameboy, Samurai }

impl ThemeId {
    pub const ALL: [Self; 5] = [Self::Blood, Self::Neon, Self::Sakura, Self::Gameboy, Self::Samurai];
    pub fn parse(s: &str) -> Self {
        match s { "neon" => Self::Neon, "sakura" => Self::Sakura, "gameboy" => Self::Gameboy, "samurai" => Self::Samurai, _ => Self::Blood }
    }
    pub fn id(self) -> &'static str {
        match self { Self::Blood => "blood", Self::Neon => "neon", Self::Sakura => "sakura", Self::Gameboy => "gameboy", Self::Samurai => "samurai" }
    }
    pub fn name(self) -> &'static str {
        match self { Self::Blood => "Blood", Self::Neon => "Neon cyber", Self::Sakura => "Sakura", Self::Gameboy => "Game Boy", Self::Samurai => "Gold samurai" }
    }
    pub fn palette(self) -> Palette {
        let values = match self {
            Self::Blood => ["#0D0709", "#1B1114", "#2A1A1F", "#D10A1A", "#7A0410", "#3D0107", "#FF4D57", "#E8B23A", "#9C6A14"],
            Self::Neon => ["#070A12", "#10141F", "#1B2133", "#00D9FF", "#006B85", "#002A38", "#7FF3FF", "#FF3DF0", "#8A1F86"],
            Self::Sakura => ["#120A0F", "#21131B", "#321C29", "#FF5FA2", "#A3305F", "#4A1430", "#FFB3D1", "#FFD36B", "#A8801F"],
            Self::Gameboy => ["#0B1D0B", "#0F380F", "#1A4A1A", "#8BAC0F", "#306230", "#173D17", "#9BBC0F", "#C8E05A", "#5A7A1A"],
            Self::Samurai => ["#0B0907", "#17120C", "#261D12", "#D4A537", "#7A5A1C", "#2E220C", "#FFE08A", "#E8543A", "#8A2A18"],
        };
        Palette::new(values)
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Palette {
    pub ink: &'static str, pub panel: &'static str, pub panel_high: &'static str,
    pub accent: &'static str, pub accent_dark: &'static str, pub accent_deep: &'static str,
    pub accent_light: &'static str, pub gold: &'static str, pub gold_dark: &'static str,
}
impl Palette {
    const fn new(c: [&'static str; 9]) -> Self {
        Self { ink:c[0], panel:c[1], panel_high:c[2], accent:c[3], accent_dark:c[4], accent_deep:c[5], accent_light:c[6], gold:c[7], gold_dark:c[8] }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_flutter_palette_round_trips_through_settings() {
        for theme in ThemeId::ALL {
            assert_eq!(ThemeId::parse(theme.id()), theme);
            assert_eq!(serde_json::from_str::<ThemeId>(&serde_json::to_string(&theme).unwrap()).unwrap(), theme);
        }
        assert_eq!(ThemeId::parse("retired-palette"), ThemeId::Blood);
    }
}
