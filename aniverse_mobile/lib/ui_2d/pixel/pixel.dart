import 'package:flutter/material.dart';

/// The 2D UI's palette: blood reds on a near-black ground, bone-white text.
///
/// Kept to a small fixed set, like a console palette, so every sprite and
/// panel in the app draws from the same colours.
class Px {
  static const black = Color(0xFF050305);
  static const ink = Color(0xFF0D0709);
  static const panel = Color(0xFF1B1114);
  static const panelHigh = Color(0xFF2A1A1F);
  static const blood = Color(0xFFD10A1A);
  static const bloodDark = Color(0xFF7A0410);
  static const bloodDeep = Color(0xFF3D0107);
  static const bloodLight = Color(0xFFFF4D57);
  static const bone = Color(0xFFF2E8D5);
  static const ash = Color(0xFF9A918C);
  static const ashDark = Color(0xFF5A5250);
  static const steel = Color(0xFFD5DCE6);
  static const steelDark = Color(0xFF7D8796);
  static const gold = Color(0xFFE8B23A);
  static const goldDark = Color(0xFF9C6A14);
  static const googleBlue = Color(0xFF4285F4);

  /// Sprite palette keys. 'X' is special: it takes the sprite's tint colour,
  /// which is how one icon sprite serves in any colour.
  static const Map<String, Color> keys = {
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

  PixelCanvas(this.canvas, this.cell);

  void px(int x, int y, Color c) => rect(x, y, 1, 1, c);

  void rect(int x, int y, int w, int h, Color c) {
    if (w <= 0 || h <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(x * cell, y * cell, w * cell, h * cell),
      _paint..color = c,
    );
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
