import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pixel/pixel.dart';
import '../pixel/theme_fx.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';

/// The player's buffering circle, as pixel art: a stepped glass orb that fills
/// with blood as the video downloads, with the live download speed in the
/// middle. Drops fall from its base once it is filling.
///
/// Same inputs as the classic overlay. [progress] is how full the buffer is
/// toward the point where playback resumes (0..1); null means the amount is
/// unknown (e.g. reconnecting), and the blood idles low instead of pretending
/// to make progress.
class BufferOverlay extends StatefulWidget {
  final double? progress;
  final double? mbps;
  final String label;
  final String? detail;
  final VoidCallback? onRetry;
  final double size;

  /// Where the blood starts, so an orb that replaces another (loading stage to
  /// player) carries on at the same level instead of draining to empty.
  final double? initialLevel;

  const BufferOverlay({
    super.key,
    required this.label,
    this.progress,
    this.mbps,
    this.detail,
    this.onRetry,
    this.size = 136,
    this.initialLevel,
  });

  @override
  State<BufferOverlay> createState() => _BufferOverlayState();
}

class _BufferOverlayState extends State<BufferOverlay> with SingleTickerProviderStateMixin {
  static const _frames = 40;
  late final AnimationController _c;
  int _frame = 0;
  late double _level;

  @override
  void initState() {
    super.initState();
    _level = (widget.initialLevel ?? 0.08).clamp(0.0, 1.0);
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4000))
      ..addListener(_tick)
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Advances in whole frames (10 fps). The level chases its target a step at
  /// a time, so blood visibly climbs cell by cell as the buffer fills.
  void _tick() {
    final f = (_c.value * _frames).floor() % _frames;
    if (f == _frame) return;
    final p = widget.progress;
    final target = p != null
        ? p.clamp(0.0, 1.0)
        : 0.24 + 0.06 * math.sin(f / _frames * 2 * math.pi);
    _level += (target - _level) * (target > _level ? 0.35 : 0.15);
    setState(() => _frame = f);
  }

  static String _speedText(double? mbps) {
    if (mbps == null) return '--';
    if (mbps < 10) return mbps.toStringAsFixed(mbps < 1 ? 2 : 1);
    return mbps.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.progress == null
        ? null
        : (widget.progress!.clamp(0.0, 1.0) * 100).round();
    final headline = percent == null ? widget.label : '${widget.label} $percent%';
    final speed = _speedText(widget.mbps);
    final s = widget.size;

    return Semantics(
      liveRegion: true,
      label: '$headline, ${widget.mbps == null ? 'speed unknown' : '$speed megabits per second'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: s,
            height: s * _OrbPainter.rows / _OrbPainter.cols,
            child: CustomPaint(
              painter: _OrbPainter(frame: _frame, level: _level),
              child: SizedBox(
                height: s,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: s * 0.04),
                    Text(
                      speed,
                      style: PxFont.label(s * 0.14, height: 1.1)
                          .copyWith(shadows: PxFont.outline(s * 0.014)),
                    ),
                    SizedBox(height: s * 0.04),
                    Text(
                      'MBPS',
                      style: PxFont.label(s * 0.062, height: 1.1)
                          .copyWith(shadows: PxFont.outline(s * 0.01)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            headline.toUpperCase(),
            textAlign: TextAlign.center,
            style: PxFont.label(9).copyWith(shadows: PxFont.outline(1.5)),
          ),
          if (widget.detail != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.detail!,
              textAlign: TextAlign.center,
              style: PxFont.text(14, color: Px.bone)
                  .copyWith(shadows: PxFont.outline(1.2)),
            ),
          ],
          if (widget.onRetry != null) ...[
            const SizedBox(height: 12),
            PixelButton(
              label: 'Retry now',
              icon: Sprites.refresh,
              fontSize: 8,
              onPressed: widget.onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  static const cols = 30;
  // Extra rows under the orb for the falling drops.
  static const rows = 37;

  final int frame;
  final double level;

  _OrbPainter({required this.frame, required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final pc = PixelCanvas(canvas, size.width / cols, glow: true);
    const c = 15.0, r = 15.0;
    const innerTop = 2.0, innerBottom = 28.0;
    final fill = level.clamp(0.0, 1.0);
    final t = frame / 40 * 2 * math.pi;

    int surfaceAt(int x, double phase, double amp) {
      // Waves settle as the orb nears empty or full.
      final calm = (1 - (fill - 0.5).abs() * 1.4).clamp(0.3, 1.0);
      final wave = (math.sin(x * 0.55 + phase) * amp * calm).round();
      return (innerBottom - fill * (innerBottom - innerTop + 1) + wave).round();
    }

    for (var y = 0; y < cols; y++) {
      for (var x = 0; x < cols; x++) {
        final d = math.sqrt(math.pow(x + 0.5 - c, 2) + math.pow(y + 0.5 - c, 2));
        if (d > r) continue;
        if (d > r - 1.3) {
          pc.px(x, y, Px.black);
          continue;
        }
        if (d > r - 2.5) {
          // Rim, lit on the upper left like a 16-bit sphere.
          pc.px(x, y, x + y < 22 ? Px.bloodLight : (x + y > 36 ? Px.bloodDark : Px.blood));
          continue;
        }
        final surf = surfaceAt(x, -t, 1.3);
        final back = surfaceAt(x, t * 0.8 + 1.7, 1.1);
        Color col;
        if (y > surf) {
          final depth = innerBottom - y;
          col = y == surf + 1
              ? (math.sin(x * 0.55 - t) > 0.35 ? Px.bloodLight : Px.blood)
              : depth < 2
                  ? Px.bloodDeep
                  : depth < 6
                      ? Px.bloodDark
                      : Px.blood;
        } else if (y > back) {
          col = Px.bloodDeep;
        } else {
          col = Px.ink;
        }
        pc.px(x, y, col);
      }
    }

    // Rising through the liquid: bubbles for Blood, bits of data for Neon
    // cyber, petals for Sakura -- one cell at a time.
    for (final (bx, off) in const [(9, 0), (15, 5), (20, 11), (12, 17)]) {
      final depthSpan = (fill * 24).floor();
      if (depthSpan < 4) continue;
      final y = (innerBottom - 1 - ((frame + off) % depthSpan)).round();
      if (y <= surfaceAt(bx, -t, 1.3) + 1) continue;
      switch (fxStyle) {
        case FxStyle.neon:
          pc.px(bx, y, (frame + off).isEven ? Px.bloodLight : Px.gold);
          pc.px(bx + 1, y, Px.bloodLight);
        case FxStyle.sakura:
          drawPetal(pc, bx, y, (frame ~/ 3 + off) & 3);
        case FxStyle.samurai:
          drawFlake(pc, bx, y, (frame ~/ 3 + off) & 3);
        case FxStyle.gameboy:
        case FxStyle.blood:
          pc.px(bx, y, Px.bloodLight);
      }
    }
    if (fxStyle == FxStyle.neon) {
      // Scanlines across the liquid, and HUD brackets round the orb.
      for (var y = 4; y < innerBottom; y += 3) {
        pc.ghost(4, y, 22, 1, Px.black, 0.25);
      }
      for (final (bx, by, dx, dy) in const [(0, 0, 1, 1), (29, 0, -1, 1), (0, 29, 1, -1), (29, 29, -1, -1)]) {
        pc.px(bx, by, Px.gold);
        pc.px(bx + dx, by, Px.gold);
        pc.px(bx, by + dy, Px.gold);
      }
    } else if (fxStyle == FxStyle.sakura) {
      // A blossom resting on top of the orb.
      pc.sprite(ThemeSprites.blossom, 12, -3);
    }

    // Glass glint, top left.
    for (final (gx, gy) in const [(9, 5), (8, 6), (7, 7), (6, 9)]) {
      if (gy < surfaceAt(gx, -t, 1.3)) pc.px(gx, gy, Px.ash);
    }

    // Drops falling from the base once there is blood to spare.
    if (fill > 0.3) {
      for (final (dx, off) in const [(12, 0), (18, 4)]) {
        pc.px(dx, cols - 1, Px.bloodDark);
        final fall = (frame + off * 3) % 10;
        if (fall < 7) {
          if (fall > 0) pc.ghost(dx, cols + fall - 1, 1, 1, Px.blood, 0.4);
          pc.rect(dx, cols + fall, 1, 2, Px.blood);
        }
      }
    }
    pc.commit(strength: 0.8);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter o) => o.frame != frame || o.level != level;
}
