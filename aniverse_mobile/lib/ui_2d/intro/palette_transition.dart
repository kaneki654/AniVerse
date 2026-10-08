import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/app_settings.dart';
import '../../services/native_bridge.dart';
import '../pixel/blood.dart';
import '../pixel/pixel.dart';

/// Switching palette is a scene change, in the style of the palette being
/// switched to. The new palette covers the screen its own way, its name shows
/// while the app rebuilds underneath in the new colours, and then it uncovers:
///
///  - Blood: a katana slash, a blood curtain pouring down; the curtain is cut
///    along the slash and the halves slide apart.
///  - Neon cyber: glitch scanlines closing in, interlaced; then the screen
///    opens from the middle like a CRT.
///  - Sakura: a petal storm sweeping in; then it blows on across and away.
///
/// About a second, at 24 fps in whole frames like everything else.
class PaletteTransition {
  static final ValueNotifier<String?> _request = ValueNotifier<String?>(null);

  /// Switch to [theme] with its transition.
  static void go(String theme) {
    if (theme == AppSettings.theme.value || _request.value != null) return;
    // Reduced motion, or effects off: switch straight away.
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations ||
        AppSettings.effects == 'off') {
      AppSettings.set('theme', theme);
      return;
    }
    _request.value = theme;
  }
}

/// Goes above the whole app (outside MaterialApp, so it survives the rebuild
/// the palette change causes) and plays the transition when one is asked for.
class PaletteTransitionLayer extends StatefulWidget {
  const PaletteTransitionLayer({super.key});

  @override
  State<PaletteTransitionLayer> createState() => _PaletteTransitionLayerState();
}

const _frames = 22, _swapAt = 10, _revealAt = 13;

class _PaletteTransitionLayerState extends State<PaletteTransitionLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: _frames * 1000 ~/ 24))
    ..addListener(_tick)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        PaletteTransition._request.value = null;
        setState(() => _theme = null);
      }
    });
  String? _theme;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    PaletteTransition._request.addListener(_start);
  }

  @override
  void dispose() {
    PaletteTransition._request.removeListener(_start);
    _c.dispose();
    super.dispose();
  }

  void _start() {
    final t = PaletteTransition._request.value;
    if (t == null || _theme != null) return;
    setState(() {
      _theme = t;
      _frame = 0;
    });
    Sfx.play(switch (t) { 'neon' => 'hit', 'sakura' => 'skip', 'gameboy' => 'select', 'samurai' => 'boss', _ => 'slash' });
    _c.forward(from: 0);
  }

  void _tick() {
    final f = (_c.value * _frames).floor().clamp(0, _frames - 1);
    if (f == _frame) return;
    // Fully covered: switch. The app rebuilds underneath in the new palette.
    if (_frame < _swapAt && f >= _swapAt) AppSettings.set('theme', _theme!);
    setState(() => _frame = f);
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    if (t == null) return const SizedBox.shrink();
    return Positioned.fill(
      // Touches stop here while it plays.
      child: AbsorbPointer(child: CustomPaint(painter: _SwitchPainter(t, _frame))),
    );
  }
}

class _SwitchPainter extends CustomPainter {
  final String theme;
  final int f;
  _SwitchPainter(this.theme, this.f);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Px.colorsOf(theme);
    final cell = (size.shortestSide / 64).clamp(4.0, 10.0).floorToDouble();
    final gw = (size.width / cell).ceil() + 1, gh = (size.height / cell).ceil() + 1;
    final pc = PixelCanvas(canvas, cell);
    switch (theme) {
      case 'neon':
        _neon(canvas, size, pc, c, cell, gw, gh);
      case 'sakura':
        _sakura(canvas, size, pc, c, cell, gw, gh);
      case 'gameboy':
        _gameboy(canvas, size, pc, c, cell, gw, gh);
      case 'samurai':
        _samurai(canvas, size, pc, c, cell, gw, gh);
      default:
        _blood(canvas, size, pc, c, cell, gw, gh);
    }
    if (f >= _swapAt - 1 && f < _revealAt) _label(canvas, size, c);
  }

  /// The palette's name while it is fully covered.
  void _label(Canvas canvas, Size size, ({Color ink, Color blood, Color bloodDark, Color bloodDeep, Color bloodLight, Color gold}) c) {
    final name = (Px.themes[theme] ?? theme).toUpperCase();
    final fs = (size.width / 16).clamp(14.0, 26.0);
    final style = PxFont.label(fs, color: c.bloodLight).copyWith(shadows: PxFont.outline(fs / 10));
    TextPainter tp(String s, TextStyle st) => TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout();
    final main = tp(name, style);
    final at = Offset((size.width - main.width) / 2, (size.height - main.height) / 2);
    if (theme == 'neon') {
      // A colour fringe, magenta and cyan.
      tp(name, style.copyWith(color: c.gold.withValues(alpha: 0.8), shadows: [])).paint(canvas, at - Offset(fs / 8, 0));
      tp(name, style.copyWith(color: c.blood.withValues(alpha: 0.8), shadows: [])).paint(canvas, at + Offset(fs / 8, 0));
    }
    main.paint(canvas, at);
  }

  // --- Blood ---------------------------------------------------------------------------

  void _blood(Canvas canvas, Size size, PixelCanvas pc, ({Color ink, Color blood, Color bloodDark, Color bloodDeep, Color bloodLight, Color gold}) c, double cell, int gw, int gh) {
    final w = size.width, h = size.height;
    if (f < _revealAt) {
      // The curtain: every column pours down at its own speed, a drop at its tip.
      for (var x = 0; x < gw; x++) {
        final speed = 1.0 + pxRand(x * 7 + 3) * 0.7;
        final len = ((f - 1) * speed * gh / 7.5 + pxRand(x * 13) * 3).round();
        if (len <= 0) continue;
        pc.rect(x, 0, 1, math.min(len, gh), c.bloodDeep);
        if (len < gh) {
          pc.rect(x, len - 1, 1, 1, c.blood);
          if (x.isEven) pc.rect(x, len, 1, 1, c.bloodLight);
        }
      }
      // The katana slash across it, first.
      if (f <= 4) {
        final p = math.min(1.0, (f + 1) / 4);
        final paint = Paint()
          ..color = Colors.white
          ..strokeWidth = cell * 1.5
          ..isAntiAlias = false;
        canvas.drawLine(Offset(0, h), Offset(w * p, h - h * p), paint);
      }
      return;
    }
    // Cut along the diagonal, the two halves slide apart.
    final p = (f - _revealAt) / (_frames - 1 - _revealAt);
    final e = p * p * 1.2;
    final fill = Paint()..color = c.bloodDeep;
    final a = Path()..moveTo(0, 0)..lineTo(w, 0)..lineTo(0, h)..close();
    final b = Path()..moveTo(w, 0)..lineTo(w, h)..lineTo(0, h)..close();
    canvas.save();
    canvas.translate(-w * e * 0.6, -h * e * 0.6);
    canvas.drawPath(a, fill);
    canvas.restore();
    canvas.save();
    canvas.translate(w * e * 0.6, h * e * 0.6);
    canvas.drawPath(b, fill);
    canvas.restore();
    if (f <= _revealAt + 1) {
      canvas.drawLine(Offset(0, h), Offset(w, 0), Paint()..color = c.bloodLight..strokeWidth = cell);
    }
  }

  // --- Neon cyber ------------------------------------------------------------------------

  void _neon(Canvas canvas, Size size, PixelCanvas pc, ({Color ink, Color blood, Color bloodDark, Color bloodDeep, Color bloodLight, Color gold}) c, double cell, int gw, int gh) {
    final w = size.width, h = size.height;
    if (f < _revealAt) {
      // Interlaced lines closing in: every fourth first, then those between.
      final q = math.min(1.0, (f + 1) / _swapAt);
      const band = 2;
      final rows = (gh / band).ceil();
      for (var r = 0; r < rows; r++) {
        final key = (r % 4) * 0.25 + (r ~/ 4) / rows;
        if (key < q) {
          pc.rect(0, r * band, gw, band, c.ink);
        } else if (key < q + 0.05) {
          pc.rect(0, r * band, gw, 1, c.bloodLight);
        }
      }
      // Glitch blocks, thinning out as it closes.
      for (var i = 0; i < 14; i++) {
        if (pxRand(i * 5 + f * 17) > 1 - q * 0.3 - 0.3) continue;
        final x = (pxRand(i * 3 + f) * gw).floor(), y = (pxRand(i * 7 + f * 3) * gh).floor();
        pc.rect(x, y, 3 + (pxRand(i + f) * 10).floor(), 1, i.isEven ? c.gold : c.blood);
      }
      if (f >= _swapAt - 1) {
        // Covered: the synthwave grid along the bottom.
        final horizon = (gh * 0.68).round();
        for (var k = 0; k < 7; k++) {
          final t = k / 7;
          pc.ghost(0, horizon + (t * t * (gh - horizon)).round(), gw, 1, c.gold, 0.3);
        }
      }
      return;
    }
    // Open like a CRT: top and bottom panels pull back from a bright middle line.
    final p = (f - _revealAt) / (_frames - 1 - _revealAt);
    final e = 1 - math.pow(1 - p, 2).toDouble();
    final half = h / 2 * (1 - e);
    final fill = Paint()..color = c.ink;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, half), fill);
    canvas.drawRect(Rect.fromLTWH(0, h - half, w, half), fill);
    final edge = Paint()..color = c.bloodLight;
    canvas.drawRect(Rect.fromLTWH(0, half - cell / 2, w, cell / 2), edge);
    canvas.drawRect(Rect.fromLTWH(0, h - half, w, cell / 2), edge);
    if (f == _revealAt) canvas.drawRect(Rect.fromLTWH(0, h / 2 - cell / 2, w, cell), Paint()..color = Colors.white);
  }

  // --- Sakura ----------------------------------------------------------------------------

  void _petal(PixelCanvas pc, int x, int y, int frame, Color light, Color dark) {
    const shapes = [
      [(0, 0, 0), (1, 0, 0), (1, 1, 1)],
      [(0, 0, 0), (1, 0, 1)],
      [(0, 0, 0), (0, 1, 0), (1, 1, 1)],
      [(0, 0, 1), (1, 1, 0)],
    ];
    for (final (dx, dy, shade) in shapes[frame & 3]) {
      pc.rect(x + dx * 2, y + dy * 2, 2, 2, shade == 0 ? light : dark);
    }
  }

  void _sakura(Canvas canvas, Size size, PixelCanvas pc, ({Color ink, Color blood, Color bloodDark, Color bloodDeep, Color bloodLight, Color gold}) c, double cell, int gw, int gh) {
    final cover = Color.lerp(c.ink, c.bloodDeep, 0.5)!;
    final covering = f < _revealAt;
    // The storm front: in from the left to cover, on out to the right to uncover.
    final q = covering ? math.min(1.0, (f + 1) / _swapAt) : (f - _revealAt + 1) / (_frames - _revealAt);
    final front = q * (gw + 24) - 12;
    for (var y = 0; y < gh; y += 2) {
      final edge = (front - (pxRand(y * 7 + 1) * 6).round()).round();
      if (covering) {
        if (edge > 0) pc.rect(0, y, edge, 2, cover);
      } else if (edge < gw) {
        pc.rect(math.max(0, edge), y, gw - math.max(0, edge), 2, cover);
      }
    }
    for (var i = 0; i < 60; i++) {
      final y = (pxRand(i * 3 + 7) * gh).floor();
      final x = (front - pxRand(i * 5 + 2) * 14 + math.sin(f * 0.6 + i) * 1.5).round();
      _petal(pc, x, y, (f + i) & 3, c.bloodLight, c.blood);
    }
    if (f >= _swapAt - 1 && f < _revealAt) {
      // Covered: sparkles twinkling round the name.
      for (var i = 0; i < 10; i++) {
        final x = (gw * (0.2 + 0.6 * pxRand(i * 11))).floor(), y = (gh * (0.35 + 0.3 * pxRand(i * 13))).floor();
        if ((f + i).isEven) {
          pc.rect(x, y, 1, 1, Colors.white);
          pc.rect(x - 1, y, 1, 1, c.gold);
          pc.rect(x + 1, y, 1, 1, c.gold);
          pc.rect(x, y - 1, 1, 1, c.gold);
          pc.rect(x, y + 1, 1, 1, c.gold);
        }
      }
    }
  }

  // --- Game Boy ----------------------------------------------------------------------------

  void _gameboy(Canvas canvas, Size size, PixelCanvas pc, ({Color ink, Color blood, Color bloodDark, Color bloodDeep, Color bloodLight, Color gold}) c, double cell, int gw, int gh) {
    final w = size.width, h = size.height;
    if (f < _revealAt) {
      // Fading through the handheld's greens to its darkest, in four steps.
      final shades = [c.bloodLight, c.blood, c.bloodDark, c.ink];
      final step = math.min(3, f * 4 ~/ _swapAt);
      canvas.drawRect(Offset.zero & size, Paint()..color = shades[step].withValues(alpha: math.min(1.0, (f + 1) / 4)));
      // The LCD's dot matrix over it.
      for (var y = 1; y < gh; y += 3) {
        for (var x = 1; x < gw; x += 3) {
          pc.ghost(x, y, 1, 1, c.bloodDark, 0.25);
        }
      }
      return;
    }
    // The screen redraws from the top, a band at a time, onto the new look.
    final q = (f - _revealAt + 1) / (_frames - _revealAt);
    final edge = h * q;
    canvas.drawRect(Rect.fromLTWH(0, edge, w, h - edge), Paint()..color = c.ink);
    canvas.drawRect(Rect.fromLTWH(0, edge, w, cell / 2), Paint()..color = c.bloodLight);
  }

  // --- Gold samurai ------------------------------------------------------------------------

  void _samurai(Canvas canvas, Size size, PixelCanvas pc, ({Color ink, Color blood, Color bloodDark, Color bloodDeep, Color bloodLight, Color gold}) c, double cell, int gw, int gh) {
    final w = size.width, h = size.height;
    if (f < _revealAt) {
      // Brush strokes of lacquer, band after band, alternating direction,
      // each with a ragged vermilion edge where the brush leaves it.
      const bands = 6;
      final bh = (gh / bands).ceil();
      final progress = math.min(1.0, (f + 1) / _swapAt) * bands;
      for (var b = 0; b < bands; b++) {
        final p = (progress - b).clamp(0.0, 1.0);
        if (p <= 0) continue;
        final len = (gw * p).round();
        final fromLeft = b.isEven;
        for (var y = b * bh; y < (b + 1) * bh && y < gh; y++) {
          final ragged = (pxRand(y * 13 + b) * 3).round();
          final l = math.max(0, len - ragged);
          final x0 = fromLeft ? 0 : gw - l;
          pc.rect(x0, y, l, 1, c.ink);
          if (p < 1) pc.rect(fromLeft ? x0 + l : x0 - 1, y, 1, 1, c.gold);
        }
      }
      if (f >= _swapAt - 1) {
        // Covered: gold leaf drifting over the lacquer.
        for (var i = 0; i < 16; i++) {
          final x = (pxRand(i * 9) * gw).floor(), y = (pxRand(i * 9 + 1) * gh + f).floor() % gh;
          pc.rect(x, y, 1, 1, i.isEven ? c.blood : c.bloodLight);
        }
      }
      return;
    }
    // A sword cut across the middle, and the halves slide apart.
    final p = (f - _revealAt) / (_frames - 1 - _revealAt);
    final shift = h / 2 * p * p * 1.2;
    final fill = Paint()..color = c.ink;
    canvas.drawRect(Rect.fromLTWH(0, -shift, w, h / 2), fill);
    canvas.drawRect(Rect.fromLTWH(0, h / 2 + shift, w, h / 2), fill);
    if (f <= _revealAt + 1) canvas.drawRect(Rect.fromLTWH(0, h / 2 - cell / 2, w, cell), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SwitchPainter old) => old.f != f || old.theme != theme;
}
