import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../intro/logo_sprite.dart';
import 'blood.dart';
import 'pixel.dart';

/// Each palette is a theme of its own, not just a recolour:
///
///  - Blood: embers, blood splats and drips, the katana.
///  - Neon cyber: digital rain over a synthwave grid, electric sparks, data
///    streams, a lightning bolt.
///  - Sakura: drifting petals and sparkles, petal bursts, petals falling, a
///    blossom.
///
/// Everything here is drawn in whole cells and moves in whole frames, like the
/// rest of the pixel UI.
enum FxStyle { blood, neon, sakura }

FxStyle get fxStyle => switch (Px.theme) {
      'neon' => FxStyle.neon,
      'sakura' => FxStyle.sakura,
      _ => FxStyle.blood,
    };

// --- marks and sprites ---------------------------------------------------------------

class ThemeSprites {
  static const bolt = Sprite([
    '...KKKK',
    '..KHHRK',
    '.KHRRK.',
    'KHRRRKK',
    'KRRRRRK',
    '.KKRRK.',
    '..KRK..',
    '.KRK...',
    '.KK....',
  ]);

  static const blossom = Sprite([
    '..K.K..',
    '.KHKHK.',
    'KHHRHHK',
    '.KRYRK.',
    'KHHRHHK',
    '.KHKHK.',
    '..K.K..',
  ]);

  /// The section-header mark: a blood drop, a bolt, a blossom.
  static Sprite mark(Sprite blood) => switch (fxStyle) {
        FxStyle.neon => bolt,
        FxStyle.sakura => blossom,
        FxStyle.blood => blood,
      };
}

/// A petal, in four flutter frames: (dx, dy, shade) cells, shade 0 light, 1 dark.
const petalFrames = [
  [(0, 0, 0), (1, 0, 0), (1, 1, 1)],
  [(0, 0, 0), (1, 0, 1)],
  [(0, 0, 0), (0, 1, 0), (1, 1, 1)],
  [(0, 0, 1), (1, 1, 0)],
];

void drawPetal(PixelCanvas pc, int x, int y, int frame, {double alpha = 1}) {
  for (final (dx, dy, shade) in petalFrames[frame & 3]) {
    final c = shade == 0 ? Px.bloodLight : Px.blood;
    pc.ghost(x + dx, y + dy, 1, 1, c, alpha);
  }
}

/// A twinkle: a dot that grows into a little cross and back.
void drawSparkle(PixelCanvas pc, int x, int y, int phase, Color c, {double alpha = 1}) {
  final p = phase % 8;
  if (p >= 6) return;
  pc.ghost(x, y, 1, 1, Colors.white, alpha);
  if (p >= 1 && p <= 4) {
    pc.ghost(x - 1, y, 1, 1, c, alpha);
    pc.ghost(x + 1, y, 1, 1, c, alpha);
    pc.ghost(x, y - 1, 1, 1, c, alpha);
    pc.ghost(x, y + 1, 1, 1, c, alpha);
  }
  if (p == 2 || p == 3) {
    pc.ghost(x - 2, y, 1, 1, c, alpha * 0.5);
    pc.ghost(x + 2, y, 1, 1, c, alpha * 0.5);
    pc.ghost(x, y - 2, 1, 1, c, alpha * 0.5);
    pc.ghost(x, y + 2, 1, 1, c, alpha * 0.5);
  }
}

// --- the emblem, in the theme's colours ----------------------------------------------------

/// The logo's colours for the current theme: its own crimson for Blood, the
/// palette's shades for the others.
Map<String, Color> emblemPalette([FxStyle? style]) {
  switch (style ?? fxStyle) {
    case FxStyle.blood:
      return LogoSprite.palette;
    case FxStyle.neon:
    case FxStyle.sakura:
      return {
        'A': Px.black,
        'B': Px.blood,
        'C': Color.lerp(Px.blood, Px.bloodDark, 0.45)!,
        'D': Px.bloodLight,
        'E': Px.bloodDark,
        'F': Px.bloodDeep,
      };
  }
}

/// The emblem drawn from its pixels, so it takes the theme's colours.
class EmblemSprite extends StatelessWidget {
  final double width;
  const EmblemSprite({super.key, required this.width});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: width * LogoSprite.height / LogoSprite.width,
        child: CustomPaint(painter: _EmblemPainter(Px.theme)),
      );
}

class _EmblemPainter extends CustomPainter {
  final String theme;
  _EmblemPainter(this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, size.width / LogoSprite.width);
    final colors = emblemPalette();
    for (final (x, y, k) in LogoSprite.cells()) {
      pc.px(x, y, colors[k]!);
    }
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter old) => old.theme != theme;
}

// --- ambient: digital rain, petals ------------------------------------------------------------

/// Neon cyber's backdrop: streams of glyph pixels raining down, and a synthwave
/// grid rolling toward you along the bottom.
class DataRainPainter extends CustomPainter {
  final int frame;
  DataRainPainter(this.frame);

  static const _cell = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, _cell);
    final cols = (size.width / _cell).ceil();
    final rows = (size.height / _cell).ceil();

    // The grid: horizon two-thirds down, lines spaced wider as they come closer.
    final horizon = (rows * 0.7).round();
    final grid = Px.gold;
    for (var k = 0; k < 9; k++) {
      final t = ((k + (frame % 12) / 12) / 9);
      final y = horizon + (t * t * (rows - horizon)).round();
      pc.ghost(0, y, cols, 1, grid, 0.05 + 0.12 * t);
    }
    final cx = cols / 2;
    for (var k = -8; k <= 8; k++) {
      // Lines from the vanishing point out to the bottom edge, in steps.
      final xb = cx + k * cols / 7;
      for (var y = horizon; y < rows; y += 2) {
        final t = (y - horizon) / (rows - horizon);
        pc.ghost((cx + (xb - cx) * t).round(), y, 1, 1, grid, 0.05 + 0.1 * t);
      }
    }

    // The rain: a stream every few columns, each at its own speed, glyphs
    // flickering in its tail.
    final n = (cols / 5).round();
    for (var i = 0; i < n; i++) {
      final seed = i * 131 + 7;
      final x = (pxRand(seed) * cols).floor();
      final speed = 0.5 + pxRand(seed + 1) * 0.9;
      final len = 5 + (pxRand(seed + 2) * 12).floor();
      final span = rows + len + 10;
      final head = ((frame * speed + pxRand(seed + 3) * span) % span).floor() - len;
      for (var j = 0; j < len; j++) {
        final y = head - j;
        if (y < 0 || y >= rows) continue;
        // Glyph flicker: cells of the tail switch on and off as it falls.
        if (j > 0 && pxRand(seed + y * 7 + (frame ~/ 3)) < 0.3) continue;
        final fade = 1 - j / len;
        final c = j == 0 ? Px.bloodLight : (j < 3 ? Px.blood : Px.bloodDark);
        pc.ghost(x, y, 1, 1, c, (j == 0 ? 0.8 : 0.5) * fade);
      }
    }

    // Now and then a glitch: a bright line tearing across for two frames.
    if (frame % 97 < 2) {
      final y = (pxRand(frame ~/ 97 + 5) * rows * 0.7).floor();
      pc.ghost(0, y, cols, 1, Px.bloodLight, 0.25);
      pc.ghost((pxRand(frame ~/ 97) * cols * 0.5).floor(), y + 1, cols ~/ 3, 1, Px.gold, 0.3);
    }
  }

  @override
  bool shouldRepaint(covariant DataRainPainter o) => o.frame != frame;
}

/// Sakura's backdrop: petals drifting down and across, swaying and
/// fluttering, with sparkles twinkling here and there.
class PetalFieldPainter extends CustomPainter {
  final int frame;
  PetalFieldPainter(this.frame);

  static const _cell = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, _cell);
    final cols = (size.width / _cell).ceil();
    final rows = (size.height / _cell).ceil();
    final n = (cols * rows * 0.0006).round().clamp(10, 36);
    for (var i = 0; i < n; i++) {
      final seed = i * 89 + 3;
      final fall = 0.16 + pxRand(seed) * 0.28;
      final drift = 0.08 + pxRand(seed + 1) * 0.16;
      final span = rows + 12;
      final t = frame * fall + pxRand(seed + 2) * span;
      final y = (t % span).floor() - 6;
      final x = ((pxRand(seed + 3) * (cols + 20) + frame * drift + math.sin(t * 0.18 + seed) * 3) % (cols + 20)).floor() - 10;
      final fade = 0.45 + 0.4 * pxRand(seed + 4);
      drawPetal(pc, x, y, (frame ~/ 4 + i) & 3, alpha: fade);
    }
    for (var i = 0; i < 7; i++) {
      final seed = i * 53 + 11;
      final x = (pxRand(seed) * cols).floor(), y = (pxRand(seed + 1) * rows).floor();
      drawSparkle(pc, x, y, frame ~/ 2 + i * 5, Px.gold, alpha: 0.55);
    }
  }

  @override
  bool shouldRepaint(covariant PetalFieldPainter o) => o.frame != frame;
}

// --- taps: sparks, petals ------------------------------------------------------------------------

/// Neon cyber's tap: a square shockwave and jagged sparks flying straight out
/// from ([cx], [cy]).
void paintSparkBurst(PixelCanvas pc, int cx, int cy, int frame, int seed) {
  // The shockwave: a square ring growing and cooling.
  final r = 1 + (frame * 1.6).round();
  final ring = frame < 3 ? Px.bloodLight : (frame < 7 ? Px.blood : Px.bloodDark);
  if (frame < 10) {
    for (var d = -r; d <= r; d += 1) {
      if ((d + frame).isOdd) continue; // dashed, like an electric arc
      pc.px(cx + d, cy - r, ring);
      pc.px(cx + d, cy + r, ring);
      pc.px(cx - r, cy + d, ring);
      pc.px(cx + r, cy + d, ring);
    }
  }
  if (frame < 2) {
    pc.rect(cx - 2, cy, 5, 1, Colors.white);
    pc.rect(cx, cy - 2, 1, 5, Colors.white);
  }
  // Sparks: straight out, with a kink or two, magenta and cyan.
  for (var i = 0; i < 10; i++) {
    final a = (i / 10) * math.pi * 2 + pxRand(seed + i) * 0.5;
    final s = 1.6 + pxRand(seed + i * 3) * 1.6;
    final kink = (pxRand(seed + i * 5) - 0.5) * 2;
    final color = i.isEven ? Px.bloodLight : Px.gold;
    for (var back = 0; back < 3; back++) {
      final f = frame - back;
      if (f < 0 || frame > 11) continue;
      final x = cx + math.cos(a) * s * f + (f > 4 ? kink * (f - 4) : 0);
      final y = cy + math.sin(a) * s * f;
      if (back == 0) {
        pc.px(x.round(), y.round(), color);
      } else {
        pc.ghost(x.round(), y.round(), 1, 1, color, back == 1 ? 0.5 : 0.2);
      }
    }
  }
}

/// Sakura's tap: petals pop out and float down, swaying, with a sparkle.
void paintPetalBurst(PixelCanvas pc, int c, int frame, int seed) {
  if (frame < 8) drawSparkle(pc, c, c, frame, Px.gold);
  for (var i = 0; i < 12; i++) {
    final a = -math.pi * (0.1 + 0.8 * pxRand(seed + i * 7)) + (i % 4 == 0 ? math.pi * 0.4 : 0);
    final s = 1.2 + 1.6 * pxRand(seed + i * 13);
    final f = frame.toDouble();
    // Fast out, then caught by the air: speed decays, a slow fall takes over.
    final out = s * (1 - math.pow(0.78, f)) / 0.22;
    final x = c + math.cos(a) * out + math.sin(f * 0.6 + i) * 1.2;
    final y = c + math.sin(a) * out + 0.05 * f * f;
    drawPetal(pc, x.round(), y.round(), (frame ~/ 2 + i) & 3, alpha: frame < 10 ? 1 : 0.5);
  }
}

// --- drips: data, petals ------------------------------------------------------------------------

/// Neon cyber's drips: thin data streams running down off the edge.
void paintDataDrips(PixelCanvas pc, int frame, int count, int seed, int cols, int rows) {
  for (var i = 0; i < count; i++) {
    final x = ((cols * (i + 0.5) / count) + (pxRand(seed * 31 + i) - 0.5) * cols / count * 0.6).round();
    pc.rect(x - 1, 0, 3, 1, Px.bloodDark);
    final speed = 1 + (i % 2);
    final period = rows + 6;
    final head = ((frame * speed + pxRand(seed + i * 11) * period) % period).floor();
    for (var j = 0; j < 4; j++) {
      final y = head - j;
      if (y < 1 || y >= rows) continue;
      final c = j == 0 ? Px.bloodLight : (j == 1 ? Px.blood : Px.bloodDark);
      if (j > 1 && (frame + y + i).isOdd) continue; // flicker
      pc.px(x, y, c);
    }
  }
}

/// Sakura's drips: petals letting go of the edge and drifting down.
void paintPetalDrips(PixelCanvas pc, int frame, int count, int seed, int cols, int rows) {
  for (var i = 0; i < count; i++) {
    final x0 = ((cols * (i + 0.5) / count) + (pxRand(seed * 31 + i) - 0.5) * cols / count * 0.6).round();
    // A little cluster of blossom clinging to the edge.
    pc.px(x0 - 1, 0, Px.bloodLight);
    pc.px(x0, 0, Px.blood);
    pc.px(x0 + 1, 0, Px.bloodLight);
    final t = (frame + (pxRand(seed + i * 11) * 60).floor()) % 60;
    final y = (t * 0.45).floor() + 1;
    if (y >= rows) continue;
    final x = x0 + (math.sin(t * 0.25 + i) * 2).round();
    drawPetal(pc, x, y, (t ~/ 3) & 3, alpha: (1 - t / 60).clamp(0.3, 1.0));
  }
}
