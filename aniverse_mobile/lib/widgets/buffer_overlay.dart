import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The player's "loading resources" circle: a glass orb that fills with water
/// as the video buffers, with the live download speed floating in the middle.
///
/// [progress] is how full the buffer is toward the point where playback
/// resumes (0..1). When it is null the amount is unknown -- e.g. while
/// reconnecting -- and the water idles at a low level instead of pretending to
/// make progress.
class BufferOverlay extends StatefulWidget {
  final double? progress;
  final double? mbps;
  final String label;
  final String? detail;
  final VoidCallback? onRetry;
  final double size;

  /// Where the water starts. The loading stage and the player each draw their
  /// own orb, so when one hands over to the other the new orb must pick up at
  /// the old one's level -- starting from empty looked like the load had
  /// suddenly drained away just as the video was about to play.
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

class _BufferOverlayState extends State<BufferOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  /// The level actually drawn. It chases the target rather than jumping, so the
  /// water visibly flows up as buffer arrives in chunks.
  late double _level;

  @override
  void initState() {
    super.initState();
    _level = (widget.initialLevel ?? 0.08).clamp(0.0, 1.0);
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )
      ..addListener(_chase)
      ..repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  double get _target {
    final p = widget.progress;
    if (p != null) return p.clamp(0.0, 1.0);
    // Unknown amount: a slow swell around a quarter full.
    return 0.24 + 0.06 * math.sin(_wave.value * 2 * math.pi);
  }

  void _chase() {
    // Rising fills quickly enough to track real progress; falling (a new
    // stall after a partial fill) drains more gently so it does not flicker.
    final target = _target;
    final rate = target > _level ? 0.09 : 0.04;
    _level += (target - _level) * rate;
  }

  static String _speedText(double? mbps) {
    if (mbps == null) return '—';
    if (mbps < 10) return mbps.toStringAsFixed(mbps < 1 ? 2 : 1);
    return mbps.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.progress == null
        ? null
        : (widget.progress!.clamp(0.0, 1.0) * 100).round();
    final headline =
        percent == null ? widget.label : '${widget.label} · $percent%';
    final speed = _speedText(widget.mbps);

    return Semantics(
      liveRegion: true,
      label: '$headline, ${widget.mbps == null ? 'speed unknown' : '$speed megabits per second'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: _wave,
              builder: (_, __) => CustomPaint(
                painter: _OrbPainter(phase: _wave.value, level: _level),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        speed,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.size * 0.22,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          shadows: const [
                            Shadow(color: Colors.black87, blurRadius: 8),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mbps',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: widget.size * 0.095,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          shadows: const [
                            Shadow(color: Colors.black87, blurRadius: 6),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black, blurRadius: 6)],
            ),
          ),
          if (widget.detail != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.detail!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)],
              ),
            ),
          ],
          if (widget.onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AniVerseTheme.red,
                backgroundColor: Colors.black45,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              ),
              child: const Text('Retry now'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double phase;
  final double level;

  _OrbPainter({required this.phase, required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ring = size.width * 0.035;
    final radius = size.width / 2 - ring;
    final orb = Rect.fromCircle(center: center, radius: radius);

    // Glow behind the orb so it reads over any video frame.
    canvas.drawCircle(
      center,
      radius + ring,
      Paint()
        ..color = AniVerseTheme.red.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.08),
    );

    // Glass.
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xCC0B0B0B));

    canvas.save();
    canvas.clipPath(Path()..addOval(orb));

    // Waves calm down as the orb nears empty or full, like a real container.
    final calm = 1 - (level - 0.5).abs() * 1.2;
    final amp = radius * 0.075 * calm.clamp(0.25, 1.0);
    // At 100% the crest must clear the top, so the surface overshoots a little.
    final surface = orb.bottom - (orb.height + amp * 2) * level.clamp(0.0, 1.0) + amp;

    final t = phase * 2 * math.pi;
    canvas.drawPath(
      _wavePath(orb, surface, amp * 0.85, orb.width * 1.35, t + math.pi * 0.8),
      Paint()..color = AniVerseTheme.redDark.withValues(alpha: 0.85),
    );
    canvas.drawPath(
      _wavePath(orb, surface + amp * 0.35, amp, orb.width, -t),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF3B45), AniVerseTheme.red, AniVerseTheme.redDark],
          stops: [0.0, 0.45, 1.0],
        ).createShader(orb),
    );

    // A few bubbles drifting up through the water.
    final bubble = Paint()..color = Colors.white.withValues(alpha: 0.22);
    for (var i = 0; i < 4; i++) {
      final life = (phase + i * 0.27) % 1.0;
      final x = orb.left + orb.width * (0.25 + 0.17 * i) +
          math.sin((life + i) * 2 * math.pi) * radius * 0.05;
      final y = orb.bottom - (orb.bottom - surface) * life;
      if (y > surface + amp) {
        canvas.drawCircle(Offset(x, y), radius * (0.025 + 0.012 * (i % 2)), bubble);
      }
    }
    canvas.restore();

    // Rim, and a highlight arc so it reads as glass rather than a flat disc.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AniVerseTheme.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.8),
      math.pi * 1.1,
      math.pi * 0.42,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring * 0.8
        ..strokeCap = StrokeCap.round,
    );
  }

  Path _wavePath(Rect box, double surface, double amp, double wavelength, double shift) {
    final path = Path()..moveTo(box.left, box.bottom);
    for (double x = box.left; x <= box.right + 2; x += 2) {
      final y = surface +
          math.sin((x - box.left) / wavelength * 2 * math.pi + shift) * amp;
      path.lineTo(x, y);
    }
    return path
      ..lineTo(box.right, box.bottom)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.phase != phase || old.level != level;
}
