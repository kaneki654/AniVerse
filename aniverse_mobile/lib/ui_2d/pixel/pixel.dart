import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The 2D UI's palette: blood reds on a near-black ground, bone-white text.
///
/// Kept to a small fixed set, like a console palette, so every sprite and
/// panel in the app draws from the same colours. The ground, panels, the blood
/// family and the gold accents change with the palette picked in Settings
/// (Blood, Neon cyber, Sakura) -- the same three the website has -- so they
/// are set at start-up by [apply] rather than being compile-time constants.
class Px {
  static const black = Color(0xFF050305);
  static Color ink = const Color(0xFF0D0709);
  static Color panel = const Color(0xFF1B1114);
  static Color panelHigh = const Color(0xFF2A1A1F);
  static Color blood = const Color(0xFFD10A1A);
  static Color bloodDark = const Color(0xFF7A0410);
  static Color bloodDeep = const Color(0xFF3D0107);
  static Color bloodLight = const Color(0xFFFF4D57);
  static const bone = Color(0xFFF2E8D5);
  static const ash = Color(0xFF9A918C);
  static const ashDark = Color(0xFF5A5250);
  static const steel = Color(0xFFD5DCE6);
  static const steelDark = Color(0xFF7D8796);
  static Color gold = const Color(0xFFE8B23A);
  static Color goldDark = const Color(0xFF9C6A14);
  static const googleBlue = Color(0xFF4285F4);

  /// Palette ids and their names, as on the website's Settings page.
  static const themes = {
    'blood': 'Blood',
    'neon': 'Neon cyber',
    'sakura': 'Sakura',
    'gameboy': 'Game Boy',
    'samurai': 'Gold samurai',
  };
  static String theme = 'blood';

  // ink, panel, panelHigh, blood, bloodDark, bloodDeep, bloodLight, gold, goldDark
  static const _palettes = <String, List<int>>{
    'blood': [0xFF0D0709, 0xFF1B1114, 0xFF2A1A1F, 0xFFD10A1A, 0xFF7A0410, 0xFF3D0107, 0xFFFF4D57, 0xFFE8B23A, 0xFF9C6A14],
    'neon': [0xFF070A12, 0xFF10141F, 0xFF1B2133, 0xFF00D9FF, 0xFF006B85, 0xFF002A38, 0xFF7FF3FF, 0xFFFF3DF0, 0xFF8A1F86],
    'sakura': [0xFF120A0F, 0xFF21131B, 0xFF321C29, 0xFFFF5FA2, 0xFFA3305F, 0xFF4A1430, 0xFFFFB3D1, 0xFFFFD36B, 0xFFA8801F],
    // The handheld's four greens, darkest to lightest, plus a brighter lime.
    'gameboy': [0xFF0B1D0B, 0xFF0F380F, 0xFF1A4A1A, 0xFF8BAC0F, 0xFF306230, 0xFF173D17, 0xFF9BBC0F, 0xFFC8E05A, 0xFF5A7A1A],
    // Lacquer black, gold leaf, and vermilion for the accents.
    'samurai': [0xFF0B0907, 0xFF17120C, 0xFF261D12, 0xFFD4A537, 0xFF7A5A1C, 0xFF2E220C, 0xFFFFE08A, 0xFFE8543A, 0xFF8A2A18],
  };

  /// A palette's colours without switching to it: what the switch animation
  /// draws its way in with.
  static ({Color ink, Color blood, Color bloodDark, Color bloodDeep, Color bloodLight, Color gold}) colorsOf(String name) {
    final p = _palettes[name] ?? _palettes['blood']!;
    return (
      ink: Color(p[0]),
      blood: Color(p[3]),
      bloodDark: Color(p[4]),
      bloodDeep: Color(p[5]),
      bloodLight: Color(p[6]),
      gold: Color(p[7]),
    );
  }

  /// Switches the palette. Widgets built before the switch keep their old
  /// colours, so the app rebuilds its whole tree after calling this.
  static void apply(String name) {
    final p = _palettes[name] ?? _palettes['blood']!;
    theme = _palettes.containsKey(name) ? name : 'blood';
    ink = Color(p[0]);
    panel = Color(p[1]);
    panelHigh = Color(p[2]);
    blood = Color(p[3]);
    bloodDark = Color(p[4]);
    bloodDeep = Color(p[5]);
    bloodLight = Color(p[6]);
    gold = Color(p[7]);
    goldDark = Color(p[8]);
    keys
      ..['k'] = ink
      ..['P'] = panel
      ..['R'] = blood
      ..['r'] = bloodDark
      ..['d'] = bloodDeep
      ..['H'] = bloodLight
      ..['Y'] = gold
      ..['y'] = goldDark;
  }

  /// The swatch shown for a palette in Settings.
  static Color swatch(String name) => Color((_palettes[name] ?? _palettes['blood']!)[3]);

  /// Sprite palette keys. 'X' is special: it takes the sprite's tint colour,
  /// which is how one icon sprite serves in any colour.
  static final Map<String, Color> keys = {
    'K': black,
    'k': ink,
    'P': panel,
    'R': blood,
    'r': bloodDark,
    'd': bloodDeep,
    'H': bloodLight,
    'W': bone,
    'g': ash,
    'G': ashDark,
    'S': steel,
    's': steelDark,
    'Y': gold,
    'y': goldDark,
    'B': googleBlue,
  };
}

/// Pixel fonts. PressStart2P is the 8-bit arcade face for headings, buttons
/// and labels; DotGothic16 is a dot-matrix face that stays readable at body
/// sizes and also covers the Japanese in anime titles.
class PxFont {
  static const display = 'PressStart2P';
  static const body = 'DotGothic16';

  static TextStyle label(double size, {Color color = Px.bone, double height = 1.5}) =>
      TextStyle(fontFamily: display, fontSize: size, color: color, height: height);

  static TextStyle text(double size, {Color color = Px.bone, double height = 1.35}) =>
      TextStyle(fontFamily: body, fontSize: size, color: color, height: height);

  /// A hard 1-cell outline around display text, the way sprite text is drawn
  /// in games -- shadows with no blur, one per direction.
  static List<Shadow> outline(double w, {Color color = Px.black}) => [
        for (final o in const [
          Offset(-1, 0), Offset(1, 0), Offset(0, -1), Offset(0, 1),
          Offset(-1, -1), Offset(1, -1), Offset(-1, 1), Offset(1, 1),
        ])
          Shadow(color: color, offset: o * w),
      ];
}

/// A sprite: rows of palette keys, one character per pixel ('.' is clear).
class Sprite {
  final List<String> rows;
  const Sprite(this.rows);

  int get w => rows.first.length;
  int get h => rows.length;
}

/// Draws on a grid of square cells with anti-aliasing off, so everything
/// painted through it has the hard edges of pixel art at any screen density.
class PixelCanvas {
  final Canvas canvas;
  final double cell;
  final Paint _paint = Paint()..isAntiAlias = false;

  /// With [glow] on, cells are collected and drawn by [commit], which first
  /// paints a bloom under the hot ones: blood reds and bright highlights get a
  /// stepped halo -- one solid ring and a dithered outer one, into empty cells
  /// only -- so effects glow without a single blurred pixel.
  final bool glow;
  final List<(int, int, int, int, Color)> _ops = [];

  PixelCanvas(this.canvas, this.cell, {bool glow = false}) : glow = glow && bloomEnabled;

  /// Off with the Lite and Off effects settings: no bloom halos anywhere.
  static bool bloomEnabled = true;

  void px(int x, int y, Color c) => rect(x, y, 1, 1, c);

  void rect(int x, int y, int w, int h, Color c) {
    if (w <= 0 || h <= 0) return;
    if (glow) {
      _ops.add((x, y, w, h, c));
      return;
    }
    _draw(x, y, w, h, c);
  }

  void _draw(int x, int y, int w, int h, Color c) {
    canvas.drawRect(
      Rect.fromLTWH(x * cell, y * cell, w * cell, h * cell),
      _paint..color = c,
    );
  }

  /// A see-through copy behind something moving: pixel art's motion blur.
  void ghost(int x, int y, int w, int h, Color c, double alpha) =>
      rect(x, y, w, h, c.withValues(alpha: alpha));

  static const _warm = Color(0xFFFFC478);

  static Color? _glowOf(Color c) {
    if (c.a < 0.8) return null;
    if (c == Px.blood || c == Px.bloodLight) return Px.bloodLight;
    if (c == Px.bone || c == Px.gold) return _warm;
    return null;
  }

  /// Paints the bloom, then every collected cell over it.
  void commit({double strength = 1}) {
    if (!glow) return;
    final filled = <int>{};
    int key(int x, int y) => (y + 4096) * 8192 + (x + 4096);
    for (final (x, y, w, h, _) in _ops) {
      for (var j = 0; j < h; j++) {
        for (var i = 0; i < w; i++) {
          filled.add(key(x + i, y + j));
        }
      }
    }
    final halo = <int, (double, Color)>{};
    for (final (x, y, w, h, c) in _ops) {
      final g = _glowOf(c);
      if (g == null) continue;
      for (var j = -2; j < h + 2; j++) {
        for (var i = -2; i < w + 2; i++) {
          final ring = math.max(
            i < 0 ? -i : (i >= w ? i - w + 1 : 0),
            j < 0 ? -j : (j >= h ? j - h + 1 : 0),
          );
          if (ring == 0) continue;
          final cx = x + i, cy = y + j;
          if (ring == 2 && (cx + cy).isOdd) continue;
          final k = key(cx, cy);
          if (filled.contains(k)) continue;
          final a = (ring == 1 ? 0.4 : 0.16) * strength;
          final old = halo[k];
          if (old == null || old.$1 < a) halo[k] = (a, g);
        }
      }
    }
    halo.forEach((k, v) {
      _draw(k % 8192 - 4096, k ~/ 8192 - 4096, 1, 1, v.$2.withValues(alpha: v.$1));
    });
    for (final (x, y, w, h, c) in _ops) {
      _draw(x, y, w, h, c);
    }
    _ops.clear();
  }

  /// Bresenham: an aliased line, stepping one cell at a time.
  void line(int x0, int y0, int x1, int y1, Color c) {
    final dx = (x1 - x0).abs(), sx = x0 < x1 ? 1 : -1;
    final dy = -(y1 - y0).abs(), sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    while (true) {
      px(x0, y0, c);
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x0 += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y0 += sy;
      }
    }
  }

  void sprite(Sprite s, int ox, int oy, {Color tint = Px.bone}) {
    for (var y = 0; y < s.h; y++) {
      final row = s.rows[y];
      var x = 0;
      while (x < row.length) {
        final ch = row[x];
        if (ch == '.') {
          x++;
          continue;
        }
        // Merge a run of the same colour into one rect: fewer draws, and no
        // hairline seams between neighbouring cells.
        var end = x + 1;
        while (end < row.length && row[end] == ch) {
          end++;
        }
        final color = ch == 'X' ? tint : (Px.keys[ch] ?? tint);
        rect(ox + x, oy + y, end - x, 1, color);
        x = end;
      }
    }
  }
}

class _SpritePainter extends CustomPainter {
  final Sprite sprite;
  final Color tint;

  _SpritePainter(this.sprite, this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    PixelCanvas(canvas, size.width / sprite.w).sprite(sprite, 0, 0, tint: tint);
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) =>
      old.sprite != sprite || old.tint != tint;
}

/// A sprite at [scale] logical pixels per art pixel.
class PixelSprite extends StatelessWidget {
  final Sprite sprite;
  final double scale;
  final Color color;

  const PixelSprite(this.sprite, {super.key, this.scale = 2, this.color = Px.bone});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: sprite.w * scale,
      height: sprite.h * scale,
      child: CustomPaint(painter: _SpritePainter(sprite, color)),
    );
  }
}

/// Frame counter for sprite animations: whole frames at a fixed rate, never
/// interpolated, which is what makes motion read as 2D sprite animation.
class FrameClock extends StatefulWidget {
  final int fps;
  final int frames;
  final Widget Function(BuildContext context, int frame) builder;

  const FrameClock({
    super.key,
    required this.fps,
    required this.frames,
    required this.builder,
  });

  @override
  State<FrameClock> createState() => _FrameClockState();
}

class _FrameClockState extends State<FrameClock> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (1000 * widget.frames / widget.fps).round()),
    )
      ..addListener(() {
        final f = (_c.value * widget.frames).floor() % widget.frames;
        // Only rebuild when the frame actually changes.
        if (f != _frame) setState(() => _frame = f);
      })
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _frame);
}
