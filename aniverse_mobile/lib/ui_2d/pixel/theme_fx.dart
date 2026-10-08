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
enum FxStyle { blood, neon, sakura, gameboy, samurai }

/// How much ambient animation the viewer wants (Settings > Effects).
enum FxLevel { full, lite, off }

FxLevel fxLevel = FxLevel.full;

/// Called when the setting changes (and at start).
void setFxLevel(String level) {
  fxLevel = switch (level) { 'lite' => FxLevel.lite, 'off' => FxLevel.off, _ => FxLevel.full };
  PixelCanvas.bloomEnabled = fxLevel == FxLevel.full;
}

/// Particle counts are scaled by this: half for Lite.
double get fxDensity => fxLevel == FxLevel.lite ? 0.5 : 1.0;

FxStyle get fxStyle => switch (Px.theme) {
      'neon' => FxStyle.neon,
      'sakura' => FxStyle.sakura,
      'gameboy' => FxStyle.gameboy,
      'samurai' => FxStyle.samurai,
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

  static const heart = Sprite([
    '.KK.KK.',
    'KHRKRRK',
    'KRRRRRK',
    '.KRRRK.',
    '..KRK..',
    '...K...',
  ]);

  static const torii = Sprite([
    'KYYYYYYYK',
    '.YYYYYYY.',
    '..Y...Y..',
    '.YYYYYYY.',
    '..Y...Y..',
    '..Y...Y..',
    '..Y...Y..',
    '.KK...KK.',
  ]);

  /// The section-header mark: a blood drop, a bolt, a blossom, a heart, a torii.
  static Sprite mark(Sprite blood) => switch (fxStyle) {
        FxStyle.neon => bolt,
        FxStyle.sakura => blossom,
        FxStyle.gameboy => heart,
        FxStyle.samurai => torii,
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
    case FxStyle.gameboy:
    case FxStyle.samurai:
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
    final n = (cols / 5 * fxDensity).round();
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
    final n = ((cols * rows * 0.0006).round().clamp(10, 36) * fxDensity).round();
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


// --- the boss of the failure screen, per palette ----------------------------------------------

class ThemeBosses {
  /// Neon cyber: a glitch virus.
  static const virus = [
    '..K..........K..',
    '...K........K...',
    '....KKKKKKKK....',
    '...KRRRRRRRRK...',
    '..KRHHRRRRRRRK..',
    '.KRHRRRRRRRRRRK.',
    'KRRRWWRRRRWWRRRK',
    'KRRWYYWRRWYYWRRK',
    'KRRRWWRRRRWWRRRK',
    'KRRRRRRRRRRRRRRK',
    '.KRrRKRKKRKRrRK.',
    '.KrrKWKWWKWKrrK.',
    'KK.KrrrrrrrrK.KK',
    'K..KKrKKKKrKK..K',
    'K...K.K..K.K...K',
    '...K..K..K..K...',
  ];

  /// Sakura: an oni mask.
  static const oni = [
    '.K............K.',
    'KHK..........KHK',
    'KRHK.KKKKKK.KHRK',
    '.KRHKRRRRRRKHRK.',
    '..KRRRRRRRRRRK..',
    '.KRRRHRRRRHRRRK.',
    'KRRWWKRRRRKWWRRK',
    'KRWYYWKRRKWYYWRK',
    'KRRWWRRRRRRWWRRK',
    'KRRRRRRKKRRRRRRK',
    '.KRRRRRRRRRRRRK.',
    '.KRKWKWKKWKWKRK.',
    '..KRKWWWWWWKRK..',
    '...KRKKKKKKRK...',
    '....KKRRRRKK....',
    '......KKKK......',
  ];

  /// Game Boy: a space invader.
  static const invader = [
    '................',
    '...K........K...',
    '....K......K....',
    '...KKKKKKKKKK...',
    '..KRRRRRRRRRRK..',
    '.KRRWWRRRRWWRRK.',
    '.KRRWYRRRRWYRRK.',
    'KRRRRRRRRRRRRRRK',
    'KRHRRRRRRRRRRHRK',
    'KRKRRRRRRRRRRKRK',
    'KRKKRRRRRRRRKKRK',
    'KK.KRRRKKRRRK.KK',
    '...KRRK..KRRK...',
    '..KRRK....KRRK..',
    '..KKK......KKK..',
    '................',
  ];

  /// Gold samurai: a kabuto helmet and war mask.
  static const kabuto = [
    '.Y....YYYY....Y.',
    '.YY..YYYYYY..YY.',
    '..YYKKKKKKKKYY..',
    '...KRRRRRRRRK...',
    '..KRRRRRRRRRRK..',
    '.KRRRRRRRRRRRRK.',
    'KKKKKKKKKKKKKKKK',
    'KrrKWWKrrKWWKrrK',
    'KrKWYYWKKWYYWKrK',
    'KrrKWWKrrKWWKrrK',
    '.KrrrrrKKrrrrrK.',
    '.KrrKWKWWKWKrrK.',
    '..KrrrrrrrrrrK..',
    '..KRKRKRRKRKRK..',
    '...KRKRKKRKRK...',
    '....KKKKKKKK....',
  ];

  /// The boss for the current palette, or null for Blood's own glitch demon.
  static List<String>? current() => switch (fxStyle) {
        FxStyle.neon => virus,
        FxStyle.sakura => oni,
        FxStyle.gameboy => invader,
        FxStyle.samurai => kabuto,
        FxStyle.blood => null,
      };
}

// --- loaders, per palette (Blood's is the katana in blood.dart) -----------------------------------

/// Neon cyber's loader: a square ring with a light running round it, a core of
/// data flickering inside, and a scan line passing down. 50 x 36 cells.
class NeonLoaderPainter extends CustomPainter {
  final int frame;
  NeonLoaderPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, size.width / 50, glow: true);
    const x0 = 17, y0 = 10, side = 16;
    final ring = <(int, int)>[
      for (var i = 0; i < side; i++) (x0 + i, y0),
      for (var i = 0; i < side; i++) (x0 + side, y0 + i),
      for (var i = side; i > 0; i--) (x0 + i, y0 + side),
      for (var i = side; i > 0; i--) (x0, y0 + i),
    ];
    for (final (x, y) in ring) {
      pc.px(x, y, Px.bloodDeep);
    }
    final head = (frame / 28 * ring.length).floor();
    for (var k = 0; k < 14; k++) {
      final (x, y) = ring[(head - k) % ring.length];
      pc.px(x, y, k == 0 ? Colors.white : (k < 4 ? Px.bloodLight : (k < 9 ? Px.blood : Px.bloodDark)));
    }
    // Corner brackets.
    for (final (cx, cy, dx, dy) in [(x0 - 2, y0 - 2, 1, 1), (x0 + side + 2, y0 - 2, -1, 1), (x0 - 2, y0 + side + 2, 1, -1), (x0 + side + 2, y0 + side + 2, -1, -1)]) {
      pc.px(cx, cy, Px.gold);
      pc.px(cx + dx, cy, Px.gold);
      pc.px(cx, cy + dy, Px.gold);
    }
    // The data core.
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 6; x++) {
        if (pxRand(x * 7 + y * 13 + (frame ~/ 2) * 31) < 0.45) {
          pc.px(x0 + 5 + x, y0 + 5 + y, pxRand(x + y + frame) < 0.2 ? Px.gold : Px.blood);
        }
      }
    }
    final scan = y0 + 1 + frame % (side - 1);
    pc.ghost(x0 + 1, scan, side - 1, 1, Px.bloodLight, 0.45);
    for (var x = 4; x < 46; x += 3) {
      pc.px(x, 33, Px.bloodDark);
    }
    pc.commit();
  }

  @override
  bool shouldRepaint(covariant NeonLoaderPainter o) => o.frame != frame;
}

/// Sakura's loader: petals circling a blossom, sparkles winking round them.
/// 50 x 36 cells.
class SakuraLoaderPainter extends CustomPainter {
  final int frame;
  SakuraLoaderPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, size.width / 50, glow: true);
    const cx = 25.0, cy = 17.0;
    pc.sprite(ThemeSprites.blossom, 22, 14);
    for (var i = 0; i < 8; i++) {
      final a = frame / 28 * math.pi * 2 + i * math.pi / 4;
      final x = (cx + math.cos(a) * 13).round(), y = (cy + math.sin(a) * 10).round();
      // A fading copy where each petal just was: its motion blur.
      final pa = a - math.pi * 2 / 28;
      drawPetal(pc, (cx + math.cos(pa) * 13).round(), (cy + math.sin(pa) * 10).round(), (frame + i) & 3, alpha: 0.3);
      drawPetal(pc, x, y, (frame ~/ 2 + i) & 3);
    }
    for (var i = 0; i < 4; i++) {
      drawSparkle(pc, (6 + pxRand(i * 3) * 38).round(), (3 + pxRand(i * 7) * 28).round(), frame + i * 4, Px.gold, alpha: 0.8);
    }
    pc.commit();
  }

  @override
  bool shouldRepaint(covariant SakuraLoaderPainter o) => o.frame != frame;
}

// --- Game Boy ---------------------------------------------------------------------------------

/// Block pieces (I, O, T, L, S), in cells two-square.
const _pieces = [
  [(0, 0), (1, 0), (2, 0), (3, 0)],
  [(0, 0), (1, 0), (0, 1), (1, 1)],
  [(0, 0), (1, 0), (2, 0), (1, 1)],
  [(0, 0), (0, 1), (0, 2), (1, 2)],
  [(1, 0), (2, 0), (0, 1), (1, 1)],
];

void _block(PixelCanvas pc, int x, int y, double alpha) {
  // A bevelled square: light corner, dark edge -- the handheld's block look.
  pc.ghost(x, y, 2, 2, Px.blood, alpha);
  pc.ghost(x, y, 1, 1, Px.bloodLight, alpha);
  pc.ghost(x + 1, y + 1, 1, 1, Px.bloodDark, alpha);
}

/// Game Boy's backdrop: the LCD's dot matrix, and block pieces stepping down.
class GameBoyFieldPainter extends CustomPainter {
  final int frame;
  GameBoyFieldPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 3.0;
    final pc = PixelCanvas(canvas, cell);
    final cols = (size.width / cell).ceil(), rows = (size.height / cell).ceil();
    for (var y = 1; y < rows; y += 4) {
      for (var x = 1; x < cols; x += 4) {
        pc.ghost(x, y, 1, 1, Px.bloodDark, 0.12);
      }
    }
    final n = (10 * fxDensity).round();
    for (var i = 0; i < n; i++) {
      final seed = i * 61 + 9;
      final shape = _pieces[(pxRand(seed) * _pieces.length).floor() % _pieces.length];
      final x = (pxRand(seed + 1) * (cols - 8)).floor();
      final span = rows + 12;
      // Down a whole step at a time, every few frames, like a falling piece.
      final y = ((frame ~/ 3) * 2 + (pxRand(seed + 2) * span).floor()) % span - 8;
      for (final (dx, dy) in shape) {
        _block(pc, x + dx * 2, y + dy * 2, 0.22 + 0.25 * pxRand(seed + 3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant GameBoyFieldPainter o) => o.frame != frame;
}

/// Game Boy's tap: stepped diamonds ringing out, and four blocks flying off.
void paintPixelPop(PixelCanvas pc, int cx, int cy, int frame, int seed) {
  final shades = [Px.bloodLight, Px.blood, Px.bloodDark, Px.bloodDeep];
  if (frame < 8) {
    final r = 1 + frame;
    final c = shades[(frame ~/ 2).clamp(0, 3)];
    for (var d = 0; d <= r; d++) {
      pc.px(cx + d, cy - (r - d), c);
      pc.px(cx - d, cy - (r - d), c);
      pc.px(cx + d, cy + (r - d), c);
      pc.px(cx - d, cy + (r - d), c);
    }
  }
  if (frame < 2) pc.rect(cx - 1, cy - 1, 3, 3, Px.bloodLight);
  for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
    final d = 2 + frame * 2;
    if (frame < 11) pc.rect(cx + dx * d - 1, cy + dy * d - 1, 2, 2, shades[(frame ~/ 3).clamp(0, 3)]);
  }
}

/// Game Boy's drips: blocks dropping off the edge a step at a time.
void paintBlockDrips(PixelCanvas pc, int frame, int count, int seed, int cols, int rows) {
  for (var i = 0; i < count; i++) {
    final x = ((cols * (i + 0.5) / count) + (pxRand(seed * 31 + i) - 0.5) * cols / count * 0.6).round();
    pc.rect(x - 1, 0, 3, 1, Px.bloodDark);
    final period = rows + 4;
    final y = (((frame ~/ 2) * 2 + (pxRand(seed + i * 11) * period).floor()) % period);
    if (y > 1 && y < rows - 1) _block(pc, x - 1, y, 1);
  }
}

/// Game Boy's loader: a bar of blocks filling up, and a cursor blinking at its end.
class GameBoyLoaderPainter extends CustomPainter {
  final int frame;
  GameBoyLoaderPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, size.width / 50);
    const x0 = 9, y0 = 15, segs = 8;
    pc.rect(x0 - 2, y0 - 2, segs * 4 + 3, 7, Px.bloodDark);
    pc.rect(x0 - 1, y0 - 1, segs * 4 + 1, 5, Px.ink);
    final filled = (frame ~/ 3) % (segs + 2);
    for (var i = 0; i < math.min(filled, segs); i++) {
      _block(pc, x0 + i * 4, y0, 1);
      _block(pc, x0 + i * 4 + 2, y0, 1);
      _block(pc, x0 + i * 4, y0 + 1, 1);
    }
    if ((frame ~/ 4).isEven) pc.rect(x0 + math.min(filled, segs) * 4, y0 + 3, 3, 1, Px.bloodLight);
    // A little blob hopping along the top as it loads.
    final hop = (frame % 8) < 4 ? 0 : -2;
    final bx = x0 + (frame ~/ 3) % (segs * 4);
    pc.rect(bx, y0 - 6 + hop, 3, 3, Px.blood);
    pc.px(bx + 1, y0 - 5 + hop, Px.bloodLight);
  }

  @override
  bool shouldRepaint(covariant GameBoyLoaderPainter o) => o.frame != frame;
}

// --- Gold samurai -----------------------------------------------------------------------------

/// A flake of gold leaf, in four turning frames.
void drawFlake(PixelCanvas pc, int x, int y, int frame, {double alpha = 1}) {
  switch (frame & 3) {
    case 0:
      pc.ghost(x, y, 2, 1, Px.bloodLight, alpha);
      pc.ghost(x + 1, y + 1, 1, 1, Px.blood, alpha);
    case 1:
      pc.ghost(x, y, 1, 2, Px.blood, alpha);
    case 2:
      pc.ghost(x, y, 1, 1, Px.blood, alpha);
      pc.ghost(x + 1, y + 1, 2, 1, Px.bloodLight, alpha);
    default:
      pc.ghost(x, y, 1, 1, Px.bloodLight, alpha);
  }
}

/// Gold samurai's backdrop: gold leaf drifting down, turning in the air, and
/// the odd vermilion spark.
class GoldLeafFieldPainter extends CustomPainter {
  final int frame;
  GoldLeafFieldPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 3.0;
    final pc = PixelCanvas(canvas, cell);
    final cols = (size.width / cell).ceil(), rows = (size.height / cell).ceil();
    final n = ((cols * rows * 0.0006).round().clamp(10, 34) * fxDensity).round();
    for (var i = 0; i < n; i++) {
      final seed = i * 73 + 17;
      final fall = 0.12 + pxRand(seed) * 0.22;
      final span = rows + 10;
      final t = frame * fall + pxRand(seed + 1) * span;
      final y = (t % span).floor() - 5;
      final x = ((pxRand(seed + 2) * cols + math.sin(t * 0.15 + seed) * 4) % cols).floor();
      drawFlake(pc, x, y, (frame ~/ 3 + i) & 3, alpha: 0.4 + 0.4 * pxRand(seed + 3));
    }
    for (var i = 0; i < 4; i++) {
      drawSparkle(pc, (pxRand(i * 41) * cols).floor(), (pxRand(i * 41 + 1) * rows).floor(), frame ~/ 2 + i * 7, Px.gold, alpha: 0.5);
    }
  }

  @override
  bool shouldRepaint(covariant GoldLeafFieldPainter o) => o.frame != frame;
}

/// Gold samurai's tap: gold leaf thrown out and fluttering down, a vermilion spark.
void paintGoldBurst(PixelCanvas pc, int cx, int cy, int frame, int seed) {
  if (frame < 6) drawSparkle(pc, cx, cy, frame, Px.gold);
  for (var i = 0; i < 12; i++) {
    final a = (i / 12) * math.pi * 2 + pxRand(seed + i) * 0.4;
    final s = 1.3 + 1.5 * pxRand(seed + i * 7);
    final out = s * (1 - math.pow(0.8, frame)) / 0.2;
    final x = cx + math.cos(a) * out + math.sin(frame * 0.5 + i) * 1.0;
    final y = cy + math.sin(a) * out + 0.06 * frame * frame;
    drawFlake(pc, x.round(), y.round(), (frame ~/ 2 + i) & 3, alpha: frame < 10 ? 1 : 0.5);
  }
}
