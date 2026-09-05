import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Branded loader: counter-rotating arcs around a pulsing core.
///
/// Replaces the stock CircularProgressIndicator so waiting still looks like
/// AniVerse. That matters more here than in most apps because a cold stream
/// resolve can take the better part of a minute.
class AniVerseLoader extends StatefulWidget {
  final double size;
  final String? label;

  const AniVerseLoader({super.key, this.size = 64, this.label});

  @override
  State<AniVerseLoader> createState() => _AniVerseLoaderState();
}

class _AniVerseLoaderState extends State<AniVerseLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _LoaderPainter(_c.value),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              // Gentle breathing rather than a hard blink.
              final t = (math.sin(_c.value * math.pi * 2) + 1) / 2;
              return Opacity(
                opacity: 0.45 + 0.45 * t,
                child: Text(
                  widget.label!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    letterSpacing: 2,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _LoaderPainter extends CustomPainter {
  final double t;

  _LoaderPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer arc, clockwise.
    _arc(canvas, center, radius - 2, t * 2 * math.pi, 2.2, AniVerseTheme.red, 3);
    // Middle arc, counter-clockwise and slower, for a bit of mechanical feel.
    _arc(canvas, center, radius - 11, -t * 2 * math.pi * 0.7 + 1.2, 1.6,
        AniVerseTheme.red.withValues(alpha: 0.65), 2.5);
    // Inner arc, fastest.
    _arc(canvas, center, radius - 19, t * 2 * math.pi * 1.6, 1.0,
        Colors.white.withValues(alpha: 0.5), 2);

    // Pulsing core.
    final pulse = (math.sin(t * math.pi * 2) + 1) / 2;
    canvas.drawCircle(
      center,
      3 + pulse * 2.5,
      Paint()
        ..color = AniVerseTheme.red
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, 2 + pulse * 1.5, Paint()..color = Colors.white);
  }

  void _arc(Canvas canvas, Offset center, double radius, double start,
      double sweep, Color color, double width) {
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LoaderPainter old) => old.t != t;
}

/// Full-screen loading state with the wordmark, used while a page has nothing
/// to show yet.
class AniVerseLoadingScreen extends StatelessWidget {
  final String? label;

  const AniVerseLoadingScreen({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(child: AniVerseLoader(size: 72, label: label));
  }
}
