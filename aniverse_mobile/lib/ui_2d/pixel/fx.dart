import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'blood.dart';
import 'pixel.dart';
import 'theme_fx.dart';

/// Ambient detail and motion effects for the 2D UI. All of it is pixel art:
/// glows are stepped halos, motion blur is ghost frames and speed lines, and
/// the vignette steps in bands -- nothing is smoothly blurred.

// --- backdrop: drifting embers, scanlines, a stepped vignette ----------------------

/// Puts drifting blood embers, faint scanlines and a stepped vignette behind
/// [child]. For the catalogue screens; the player stays plain black.
class PixelBackdrop extends StatelessWidget {
  final Widget child;
  const PixelBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final still = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) || fxLevel == FxLevel.off;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Px.ink),
        if (!still) const Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: EmberField()))),
        const Positioned.fill(
          child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _ScanlinePainter()))),
        ),
        child,
      ],
    );
  }
}

class EmberField extends StatelessWidget {
  const EmberField({super.key});

  @override
  Widget build(BuildContext context) {
    return FrameClock(
      fps: 12,
      frames: 7200,
      // Embers for Blood, digital rain for Neon cyber, petals for Sakura,
      // falling blocks for Game Boy, gold leaf for Gold samurai.
      builder: (_, f) => CustomPaint(
        painter: switch (fxStyle) {
          FxStyle.neon => DataRainPainter(f),
          FxStyle.sakura => PetalFieldPainter(f),
          FxStyle.gameboy => GameBoyFieldPainter(f),
          FxStyle.samurai => GoldLeafFieldPainter(f),
          FxStyle.blood => _EmberPainter(f),
        },
      ),
    );
  }
}

class _EmberPainter extends CustomPainter {
  final int frame;
  _EmberPainter(this.frame);

  static const _cell = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, _cell);
    final cols = (size.width / _cell).ceil();
    final rows = (size.height / _cell).ceil();
    final n = ((cols * rows * 0.0008).round().clamp(12, 48) * fxDensity).round();
    for (var i = 0; i < n; i++) {
      final seed = i * 97 + 13;
      // Each ember's place is a function of the frame, so the painter needs no
      // state: it rises at its own speed and wraps round from the bottom.
      final speed = 0.18 + pxRand(seed) * 0.45;
      final span = rows + 24;
      final y = (rows + 10 - ((frame * speed + pxRand(seed + 1) * span) % span)).round();
      final x = (pxRand(seed + 2) * cols + math.sin(frame * 0.05 + seed) * 2).round();
      final big = pxRand(seed + 3) < 0.22;
      final gold = pxRand(seed + 4) < 0.12;
      final lit = (frame + seed) % 9 < 7;
      final fade = (y / (rows * 0.35)).clamp(0.0, 1.0);
      final sz = big ? 2 : 1;
      final halo = gold ? Px.gold : Px.blood;
      final core = gold ? Px.gold : (lit ? Px.bloodLight : Px.blood);
      pc.ghost(x - 1, y - 1, sz + 2, sz + 2, halo, 0.14 * fade);
      pc.ghost(x, y + sz, sz, 2, halo, 0.16 * fade); // its trail
      pc.ghost(x, y, sz, sz, core, 0.9 * fade);
    }
  }

  @override
  bool shouldRepaint(covariant _EmberPainter o) => o.frame != frame;
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x33000000)
      ..isAntiAlias = false;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
    }
    // A vignette in hard bands rather than a smooth falloff.
    final r = size.longestSide * 0.62;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.4),
          r,
          const [Color(0x00050305), Color(0x00050305), Color(0x52050305), Color(0x52050305), Color(0x8C050305)],
          const [0.0, 0.58, 0.58, 0.8, 0.8],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- speed lines ---------------------------------------------------------------------

/// Streaks across the area for five frames each time [trigger] changes: how
/// pixel art draws a fast move. [direction] is 1 for rightward motion.
class SpeedLines extends StatefulWidget {
  final ValueListenable<int> trigger;
  final int direction;
  const SpeedLines({super.key, required this.trigger, this.direction = -1});

  @override
  State<SpeedLines> createState() => _SpeedLinesState();
}

class _SpeedLinesState extends State<SpeedLines> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  int _seed = 0;

  @override
  void initState() {
    super.initState();
    widget.trigger.addListener(_play);
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_play);
    _c.dispose();
    super.dispose();
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _seed = widget.trigger.value * 31;
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => _c.isAnimating
            ? CustomPaint(
                painter: _SpeedPainter((_c.value * 5).floor().clamp(0, 4), _seed, widget.direction),
                size: Size.infinite,
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

class _SpeedPainter extends CustomPainter {
  final int frame;
  final int seed;
  final int dir;
  _SpeedPainter(this.frame, this.seed, this.dir);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 3.0;
    final pc = PixelCanvas(canvas, cell);
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    const alphas = [0.55, 0.7, 0.5, 0.3, 0.12];
    final n = math.max(8, rows ~/ 4);
    for (var i = 0; i < n; i++) {
      final y = (pxRand(seed + i * 3) * rows).floor();
      final len = 8 + (pxRand(seed + i * 3 + 1) * cols * 0.35).floor();
      final x = (pxRand(seed + i * 3 + 2) * cols + dir * frame * cols * 0.18).round();
      pc.ghost(x, y, len, 1, Px.bone, alphas[frame]);
      pc.ghost(x - dir * 3, y, 3, 1, Px.bloodLight, alphas[frame]);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedPainter o) => o.frame != frame || o.seed != seed;
}

// --- dither cover, for page transitions ----------------------------------------------------

const _bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

/// Covers [coverage] (0..1) of the area with black cells in a Bayer dither: a
/// page breaking into, or out of, square cells.
class DitherCover extends CustomPainter {
  final double coverage;
  DitherCover(this.coverage);

  @override
  void paint(Canvas canvas, Size size) {
    if (coverage <= 0) return;
    const cell = 6.0;
    final level = coverage * 16;
    final path = Path();
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        if (_bayer[(y & 3) * 4 + (x & 3)] < level) path.addRect(Rect.fromLTWH(x * cell, y * cell, cell, cell));
      }
    }
    canvas.drawPath(path, Paint()..color = Px.black..isAntiAlias = false);
  }

  @override
  bool shouldRepaint(covariant DitherCover o) => o.coverage != coverage;
}

// --- glint ------------------------------------------------------------------------------------

/// A hard-edged light band sweeping across, at [position] 0..1; nothing when
/// outside that range. Clipped to the painted area.
class GlintPainter extends CustomPainter {
  final double position;
  GlintPainter(this.position);

  @override
  void paint(Canvas canvas, Size size) {
    if (position < 0 || position > 1) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final x = -size.height + position * (size.width + size.height * 2);
    final band = Path()
      ..moveTo(x, size.height)
      ..lineTo(x + size.height * 0.6, 0)
      ..lineTo(x + size.height * 0.6 + 7, 0)
      ..lineTo(x + 7, size.height)
      ..close();
    final thin = band.shift(const Offset(12, 0));
    canvas.drawPath(band, Paint()..color = const Color(0x4DFFFFFF)..isAntiAlias = false);
    canvas.drawPath(thin, Paint()..color = const Color(0x26FFFFFF)..isAntiAlias = false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GlintPainter o) => o.position != position;
}

/// Where a glint is, for a [FrameClock] frame: idle for most of the loop, then
/// one sweep in whole steps.
double glintAt(int frame, {int frames = 60, int sweep = 16}) {
  final f = frame % frames;
  final start = frames - sweep;
  return f < start ? -1 : (f - start) / (sweep - 1);
}

// --- katana divider ---------------------------------------------------------------------------

/// A katana lying along a section header: wrapped handle, gold guard, steel
/// blade with a darker edge, and a bright point.
class KatanaDivider extends StatelessWidget {
  const KatanaDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 8, child: CustomPaint(painter: _KatanaDividerPainter(), size: Size.infinite));
}

class _KatanaDividerPainter extends CustomPainter {
  const _KatanaDividerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    final w = size.width;
    if (w < 40) return;
    canvas.saveLayer(Offset.zero & size, Paint()..color = const Color(0x8CFFFFFF));
    for (var x = 0.0; x < 20; x += 5) {
      canvas.drawRect(Rect.fromLTWH(x, 2, 3, 4), p..color = Px.bloodDark);
      canvas.drawRect(Rect.fromLTWH(x + 3, 2, 2, 4), p..color = Px.black);
    }
    canvas.drawRect(const Rect.fromLTWH(20, 0, 3, 8), p..color = Px.gold);
    canvas.drawRect(Rect.fromLTWH(23, 2, w - 29, 2), p..color = Px.steel);
    canvas.drawRect(Rect.fromLTWH(23, 4, w - 31, 1), p..color = Px.steelDark);
    canvas.drawRect(Rect.fromLTWH(w - 6, 3, 3, 1), p..color = Px.steel);
    canvas.drawRect(Rect.fromLTWH(w - 3, 3, 3, 1), p..color = Px.bone);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
