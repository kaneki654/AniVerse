import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pixel.dart';

/// Stable pseudo-random value in [0, 1) for [seed]: every blood effect is
/// procedural but deterministic, so a given frame always draws the same.
double pxRand(int seed) {
  var x = (seed * 0x27d4eb2d + 0x165667b1) & 0x7fffffff;
  x ^= x >> 15;
  x = (x * 0x2c1b3c6d) & 0x7fffffff;
  x ^= x >> 12;
  return (x % 100000) / 100000.0;
}

Color _bloodAt(int age) => age < 3
    ? Px.bloodLight
    : age < 7
        ? Px.blood
        : age < 11
            ? Px.bloodDark
            : Px.bloodDeep;

// --- splat -----------------------------------------------------------------------

/// A one-shot burst of blood droplets, drawn above everything at a screen
/// position. Buttons fire it where they were hit.
class BloodSplat {
  static void show(BuildContext context, Offset globalPosition) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _SplatBurst(
        at: globalPosition,
        seed: DateTime.now().microsecondsSinceEpoch & 0xffff,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _SplatBurst extends StatefulWidget {
  final Offset at;
  final int seed;
  final VoidCallback onDone;

  const _SplatBurst({required this.at, required this.seed, required this.onDone});

  @override
  State<_SplatBurst> createState() => _SplatBurstState();
}

class _SplatBurstState extends State<_SplatBurst> with SingleTickerProviderStateMixin {
  static const _frames = 14;
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 560))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const box = 132.0;
    return Positioned(
      left: widget.at.dx - box / 2,
      top: widget.at.dy - box / 2,
      width: box,
      height: box,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _SplatPainter(
              (_c.value * _frames).floor().clamp(0, _frames - 1),
              widget.seed,
            ),
          ),
        ),
      ),
    );
  }
}

class _SplatPainter extends CustomPainter {
  final int frame;
  final int seed;
  _SplatPainter(this.frame, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 3.0;
    final pc = PixelCanvas(canvas, cell, glow: true);
    final c = (size.width / cell / 2).floor();

    // The hit itself: a blot that shrinks as the droplets leave it.
    final blot = 3 - frame ~/ 2;
    for (var dy = -blot; dy <= blot; dy++) {
      for (var dx = -blot; dx <= blot; dx++) {
        if (dx.abs() + dy.abs() <= blot) pc.px(c + dx, c + dy, _bloodAt(frame + 3));
      }
    }

    for (var i = 0; i < 13; i++) {
      final r1 = pxRand(seed + i * 7), r2 = pxRand(seed + i * 13 + 1);
      // Mostly up and out, a few low: blood thrown off an impact.
      final a = -math.pi * (0.05 + 0.9 * r1) + (i % 5 == 0 ? math.pi * 0.35 : 0);
      final s = 1.3 + 2.4 * r2;
      final f = frame.toDouble();
      final x = c + math.cos(a) * s * f;
      final y = c + math.sin(a) * s * f + 0.5 * 0.42 * f * f;
      final color = _bloodAt(frame + (i % 3));
      final big = i % 3 == 0 && frame < 8;
      pc.rect(x.round(), y.round(), big ? 2 : 1, big ? 2 : 1, color);
      // Trails behind fast drops: fading copies where they just were, which
      // reads as motion blur without a blurred pixel.
      for (final (back, alpha) in const [(1, 0.6), (2, 0.25)]) {
        final g = f - back;
        if (g < 0 || frame >= 10) continue;
        final px = c + math.cos(a) * s * g;
        final py = c + math.sin(a) * s * g + 0.5 * 0.42 * g * g;
        pc.ghost(px.round(), py.round(), 1, 1, Px.blood, alpha);
      }
    }
    pc.commit(strength: frame < 6 ? 1.2 : 0.8);
  }

  @override
  bool shouldRepaint(covariant _SplatPainter o) => o.frame != frame;
}

// --- drips -------------------------------------------------------------------------

/// Blood dripping off an edge: stems grow, a drop swells at the tip, lets go,
/// and falls. Place it directly under whatever it should drip from.
class BloodDrips extends StatelessWidget {
  /// Width of the edge; when null, whatever width the parent allows.
  final double? width;
  final double height;
  final int count;
  final int seed;
  final double cell;

  const BloodDrips({
    super.key,
    this.width,
    this.height = 40,
    this.count = 5,
    this.seed = 7,
    this.cell = 2.5,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: height,
        child: FrameClock(
          fps: 10,
          frames: 60,
          builder: (_, f) => CustomPaint(
            painter: _DripsPainter(f, count, seed, cell),
          ),
        ),
      ),
    );
  }
}

class _DripsPainter extends CustomPainter {
  final int frame;
  final int count;
  final int seed;
  final double cell;

  _DripsPainter(this.frame, this.count, this.seed, this.cell);

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, cell, glow: true);
    final cols = (size.width / cell).floor();
    final rows = (size.height / cell).floor();

    for (var i = 0; i < count; i++) {
      final r = pxRand(seed * 31 + i);
      final x = ((cols * (i + 0.5) / count) + (r - 0.5) * cols / count * 0.6).round();
      final maxLen = 2 + (pxRand(seed + i * 5) * 5).round();
      final thick = i % 2 == 0;
      final t = (frame + (pxRand(seed + i * 11) * 60).floor()) % 60;

      // Anchor: blood clinging along the edge.
      pc.rect(x - 1, 0, thick ? 4 : 3, 1, Px.bloodDark);

      int len;
      if (t < 30) {
        len = (t / 30 * maxLen).round();
      } else {
        len = (maxLen - (t - 30) / 8).round().clamp(1, maxLen);
      }
      pc.rect(x, 0, thick ? 2 : 1, len, Px.blood);
      if (thick) pc.rect(x + 1, 0, 1, len, Px.bloodDark);

      if (t < 30) {
        // The drop swelling at the tip.
        pc.rect(x - (t > 18 ? 1 : 0), len, thick ? 2 + (t > 18 ? 1 : 0) : 1 + (t > 18 ? 1 : 0), 2, Px.blood);
        pc.px(x, len, Px.bloodLight);
      } else {
        // Let go: falls under gravity, in whole cells.
        final ft = (t - 30).toDouble();
        final y = maxLen + 1 + (0.5 * 0.5 * ft * ft).round();
        if (y < rows) {
          // Motion blur, pixel style: fading copies where the drop just was.
          final fall = math.max(1, (0.5 * ft).round());
          pc.ghost(x, y - fall, thick ? 2 : 1, fall, Px.blood, 0.45);
          pc.ghost(x, y - 2 * fall, thick ? 2 : 1, fall, Px.blood, 0.18);
          pc.rect(x, y, thick ? 2 : 1, 2, Px.blood);
          pc.px(x, y, Px.bloodLight);
        }
      }
    }
    pc.commit();
  }

  @override
  bool shouldRepaint(covariant _DripsPainter o) => o.frame != frame;
}

// --- katana loader -------------------------------------------------------------------

/// The loading animation: a katana slashes, blood sprays off the cut and
/// pools on the ground, the blade comes back bloodied, and it goes again.
class KatanaLoader extends StatelessWidget {
  final double size;
  final String? label;

  const KatanaLoader({super.key, this.size = 150, this.label});

  static const frames = 28;

  @override
  Widget build(BuildContext context) {
    return FrameClock(
      fps: 12,
      frames: frames,
      builder: (_, f) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size * 0.72,
            child: CustomPaint(painter: _KatanaPainter(f)),
          ),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(
              // Dots count up in whole steps, like a console loading screen.
              '${label!}${'.' * ((f ~/ 4) % 4)}'.padRight(label!.length + 3),
              style: PxFont.label(9, color: Px.bone).copyWith(shadows: PxFont.outline(1.5)),
            ),
          ],
        ],
      ),
    );
  }
}

class _KatanaPainter extends CustomPainter {
  final int frame;
  _KatanaPainter(this.frame);

  static const _w = 50;
  static const _pivot = (13, 31);
  static const _len = 27;
  static const _start = -115.0, _end = 12.0;
  static const _ground = 34;

  /// Blade angle per frame: wind-up, a four-frame slash, hold, then a slower
  /// recovery back to the guard.
  static double angle(int f) {
    if (f < 3) return _start;
    if (f < 7) return _start + (_end - _start) * (f - 2) / 4;
    if (f < 21) return _end;
    return _end + (_start - _end) * math.min(1, (f - 20) / 6);
  }

  (int, int) _at(double deg, double t) {
    final a = deg * math.pi / 180;
    return ((_pivot.$1 + math.cos(a) * t).round(), (_pivot.$2 + math.sin(a) * t).round());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, size.width / _w, glow: true);

    // Ground line, dithered.
    for (var x = 2; x < _w - 2; x += 2) {
      pc.px(x, _ground + 1, Px.ashDark);
    }

    // Slash trail: an arc swept by the tip, bright then broken up as it fades.
    if (frame >= 3 && frame <= 9) {
      final upto = angle(math.min(frame, 6));
      final fade = frame - 6;
      for (var d = _start; d <= upto; d += 3) {
        final (x, y) = _at(d, _len - 1);
        if (fade > 0 && ((x + y + frame) % (fade + 1)) != 0) continue;
        pc.px(x, y, fade > 1 ? Px.ash : Px.bone);
        final (x2, y2) = _at(d, _len - 3);
        if (fade <= 0) pc.px(x2, y2, Px.steelDark);
      }
    }

    // Blood from the cut: thrown off at the impact point, falling in whole
    // cells, then lying on the ground as a pool until the loop resets.
    const hitFrame = 5;
    final (hx, hy) = _at(-45, _len - 4);
    final pool = <int>{};
    for (var i = 0; i < 16; i++) {
      final r1 = pxRand(i * 3 + 1), r2 = pxRand(i * 5 + 2);
      final vx = -0.4 + r1 * 2.4;
      final vy = -2.6 + r2 * 2.2;
      const g = 0.38;
      // Where it lands, found analytically so every frame agrees.
      final disc = vy * vy + 2 * g * (_ground - hy);
      final tLand = (-vy + math.sqrt(disc)) / g;
      final landX = (hx + vx * tLand).round();
      if (frame >= hitFrame && frame < 24) {
        final t = (frame - hitFrame).toDouble();
        if (t < tLand) {
          final x = (hx + vx * t).round(), y = (hy + vy * t + 0.5 * g * t * t).round();
          pc.px(x, y, _bloodAt((t * 1.5).round()));
          if (i % 4 == 0) pc.px(x, y + 1, Px.bloodDark);
        } else {
          pool.add(landX);
        }
      }
    }
    // The pool spreads a cell either side of each landed drop.
    for (final x in pool) {
      for (var dx = -1; dx <= 1; dx++) {
        pc.px(x + dx, _ground, dx == 0 ? Px.blood : Px.bloodDark);
      }
    }
    if (frame >= 24) {
      // Draining away before the next cut.
      for (final x in [30, 33, 36]) {
        if ((x + frame).isEven) pc.px(x, _ground, Px.bloodDeep);
      }
    }

    // The katana itself, rasterised at its current angle: wrapped handle,
    // gold guard, steel blade with a darker edge, bloodied after the cut.
    final deg = angle(frame);
    final bloodied = frame >= hitFrame && frame < 26;
    // The swing is four frames; copies of the blade at the two angles before
    // this one smear it across the arc -- motion blur in whole cells.
    if (frame >= 4 && frame <= 7) {
      for (final (back, alpha) in const [(1, 0.42), (2, 0.18)]) {
        final ghostDeg = angle(frame - back);
        for (var t = 8; t <= _len; t++) {
          final (x, y) = _at(ghostDeg, t.toDouble());
          pc.ghost(x, y, 1, 1, Px.steel, alpha);
        }
      }
    }
    for (var t = 0; t <= _len; t++) {
      final (x, y) = _at(deg, t.toDouble());
      if (t < 7) {
        pc.px(x, y, t.isEven ? Px.bloodDark : Px.black);
      } else if (t == 7) {
        final a = (deg + 90) * math.pi / 180;
        for (var k = -2; k <= 2; k++) {
          pc.px((x + math.cos(a) * k).round(), (y + math.sin(a) * k).round(),
              k.abs() == 2 ? Px.goldDark : Px.gold);
        }
      } else {
        final a = (deg + 90) * math.pi / 180;
        final ex = (x + math.cos(a)).round(), ey = (y + math.sin(a)).round();
        final red = bloodied && t > _len - 9;
        pc.px(ex, ey, red ? Px.bloodDark : Px.steelDark);
        pc.px(x, y, t == _len ? Px.bone : (red ? Px.blood : Px.steel));
      }
    }
    // A glint travelling up the blade during the wind-up.
    if (frame < 3) {
      final (gx, gy) = _at(deg, 10 + frame * 6.0);
      pc.px(gx, gy, Px.bone);
    }
    // Blood running off the tip while it is held out after the cut.
    if (frame >= 8 && frame < 21) {
      final (tx, ty) = _at(deg, _len - 2.0);
      final drop = (frame - 8) % 5;
      pc.px(tx, ty + 1 + drop, Px.blood);
    }
    pc.commit();
  }

  @override
  bool shouldRepaint(covariant _KatanaPainter o) => o.frame != frame;
}
