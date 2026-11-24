//! The manga look's printed textures, after the painters in
//! lib/ui_manga/ink/ink_widgets.dart: screentone (HalftonePainter) drawn at
//! the screen's pixel density, focus lines (FocusLinesPainter) as vector path
//! strings, and the spotlight's cover cut on a slant.
use slint::{Image, Rgba8Pixel, SharedPixelBuffer};
use std::f32::consts::PI;
use std::fmt::Write as _;
use tiny_skia::{FillRule, Paint, PathBuilder, Pixmap, Transform};

pub const INK: [u8; 3] = [0x12, 0x10, 0x10];
pub const TONE: [u8; 3] = [0xD6, 0xCF, 0xC2];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Axis {
    Vertical,
    Horizontal,
}

/// Dots on a 45-degree grid. Density runs [from]..[to] along [axis] (flat
/// when [to] is None), as the area of each dot's cell that is inked.
#[derive(Clone, Copy, Debug)]
pub struct Tone {
    pub color: [u8; 3],
    pub spacing: f32,
    pub from: f32,
    pub to: Option<f32>,
    pub axis: Axis,
}

impl Tone {
    pub const fn flat(color: [u8; 3], spacing: f32, density: f32) -> Self {
        Self { color, spacing, from: density, to: None, axis: Axis::Vertical }
    }
    pub const fn fade(color: [u8; 3], spacing: f32, from: f32, to: f32, axis: Axis) -> Self {
        Self { color, spacing, from, to: Some(to), axis }
    }
}

/// Screentone for a [w] x [h] logical-pixel area, drawn [scale] times denser.
pub fn halftone(w: f32, h: f32, scale: f32, tone: Tone) -> Image {
    let scale = scale.clamp(1.0, 4.0);
    let pw = (w * scale).ceil().max(1.0) as u32;
    let ph = (h * scale).ceil().max(1.0) as u32;
    let Some(mut pixmap) = Pixmap::new(pw, ph) else { return Image::default() };
    let mut paint = Paint::default();
    paint.set_color_rgba8(tone.color[0], tone.color[1], tone.color[2], 255);
    paint.anti_alias = true;
    let s = tone.spacing;
    let row_step = s * 0.71;
    let mut builder = PathBuilder::new();
    let mut row = 0;
    let mut y = -s;
    while y < h + s {
        let mut x = if row % 2 == 1 { s / 2.0 } else { 0.0 } - s;
        while x < w + s {
            let t = match tone.axis {
                Axis::Vertical => y / h,
                Axis::Horizontal => x / w,
            };
            let d = match tone.to {
                None => tone.from,
                Some(to) => tone.from + (to - tone.from) * t.clamp(0.0, 1.0),
            };
            if d > 0.02 {
                let r = s * 0.5 * d.clamp(0.0, 1.0).sqrt();
                builder.push_circle(x * scale, y * scale, r * scale);
            }
            x += s;
        }
        y += row_step;
        row += 1;
    }
    if let Some(path) = builder.finish() {
        pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
    }
    let buffer = SharedPixelBuffer::<Rgba8Pixel>::clone_from_slice(pixmap.data(), pw, ph);
    Image::from_rgba8_premultiplied(buffer)
}

/// A small deterministic generator, so the same seed draws the same lines.
struct Rand(u64);
impl Rand {
    fn new(seed: u64) -> Self {
        Self(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ 0xD1B5_4A32_D192_ED03)
    }
    fn next(&mut self) -> f32 {
        // xorshift64*
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        let v = self.0.wrapping_mul(0x2545_F491_4F6C_DD1D);
        (v >> 40) as f32 / (1u64 << 24) as f32
    }
}

/// Focus lines (集中線): black wedges converging on ([cx], [cy]), leaving a
/// clear middle [clear] of the short side across. As an SVG path in the
/// area's own logical pixels.
pub fn focus_lines(w: f32, h: f32, cx: f32, cy: f32, seed: u64, count: usize, clear: f32) -> String {
    let reach = w.max(h) * 1.2;
    let short = w.min(h);
    let mut rnd = Rand::new(seed);
    let mut path = String::with_capacity(count * 64);
    for i in 0..count {
        let a = (i as f32 / count as f32) * 2.0 * PI + rnd.next() * 0.05;
        let inner = short * (clear + rnd.next() * 0.22);
        let half = 0.006 + rnd.next() * 0.016;
        let tip = (cx + a.cos() * inner, cy + a.sin() * inner);
        let l = (cx + (a - half).cos() * reach, cy + (a - half).sin() * reach);
        let r = (cx + (a + half).cos() * reach, cy + (a + half).sin() * reach);
        let _ = write!(path, "M{:.1} {:.1}L{:.1} {:.1}L{:.1} {:.1}Z", tip.0, tip.1, l.0, l.1, r.0, r.1);
    }
    path
}

/// The spotlight's cover: fitted to [w] x [h] logical pixels (cropped like
/// BoxFit.cover), its right edge cut on a slant [cut] pixels wide at the foot.
pub fn slant_cover(source: &image::RgbaImage, w: f32, h: f32, cut: f32, scale: f32) -> SharedPixelBuffer<Rgba8Pixel> {
    let scale = scale.clamp(1.0, 3.0);
    let pw = (w * scale).round().max(1.0) as u32;
    let ph = (h * scale).round().max(1.0) as u32;
    let fitted = cover_fit(source, pw, ph);
    let mut buffer = SharedPixelBuffer::<Rgba8Pixel>::new(pw, ph);
    let pixels = buffer.make_mut_slice();
    let cut = cut * scale;
    for y in 0..ph {
        // the slanted edge runs from (pw, 0) to (pw - cut, ph)
        let edge = pw as f32 - cut * (y as f32 + 0.5) / ph as f32;
        for x in 0..pw {
            let coverage = (edge - x as f32).clamp(0.0, 1.0);
            let p = fitted.get_pixel(x, y).0;
            pixels[(y * pw + x) as usize] = Rgba8Pixel { r: p[0], g: p[1], b: p[2], a: (p[3] as f32 * coverage) as u8 };
        }
    }
    buffer
}

/// Scale and centre-crop [source] to exactly [w] x [h] pixels.
pub fn cover_fit(source: &image::RgbaImage, w: u32, h: u32) -> image::RgbaImage {
    let (sw, sh) = (source.width().max(1), source.height().max(1));
    let k = (w as f32 / sw as f32).max(h as f32 / sh as f32);
    let (cw, ch) = ((w as f32 / k).round().max(1.0) as u32, (h as f32 / k).round().max(1.0) as u32);
    let (cx, cy) = ((sw.saturating_sub(cw)) / 2, (sh.saturating_sub(ch)) / 2);
    let crop = image::imageops::crop_imm(source, cx, cy, cw.min(sw), ch.min(sh)).to_image();
    image::imageops::resize(&crop, w, h, image::imageops::FilterType::Triangle)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn focus_lines_are_closed_wedges_and_repeat_for_a_seed() {
        let a = focus_lines(300.0, 200.0, 150.0, 100.0, 3, 60, 0.5);
        assert_eq!(a.matches('Z').count(), 60);
        assert_eq!(a, focus_lines(300.0, 200.0, 150.0, 100.0, 3, 60, 0.5));
        assert_ne!(a, focus_lines(300.0, 200.0, 150.0, 100.0, 4, 60, 0.5));
    }

    #[test]
    fn slant_cover_clears_the_corner_past_the_cut() {
        let source = image::RgbaImage::from_pixel(40, 60, image::Rgba([200, 10, 10, 255]));
        let out = slant_cover(&source, 150.0, 221.0, 28.0, 1.0);
        let px = out.as_slice();
        // top right is kept, bottom right is cut away, bottom left is kept
        assert!(px[148].a > 200);
        assert_eq!(px[(220 * 150 + 149) as usize].a, 0);
        assert_eq!(px[(220 * 150) as usize].a, 255);
    }
}
