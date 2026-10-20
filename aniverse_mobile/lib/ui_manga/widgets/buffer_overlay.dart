import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ink/ink_widgets.dart';
import '../ink/manga.dart';

/// The player's buffering state, inked: the AniVerse emblem as line art with
/// red ink rising inside it as the video downloads, ゴゴゴ (the manga rumble
/// of something about to happen) trembling at its sides, and the download
/// speed in a caption panel below.
///
/// Same inputs as the other UIs' overlays. [progress] is how full the buffer
/// is toward the point where playback resumes (0..1); null means unknown
/// (reconnecting), and the ink idles low instead of pretending to rise.
class BufferOverlay extends StatefulWidget {
  final double? progress;
  final double? mbps;
  final String label;
  final String? detail;
  final VoidCallback? onRetry;
  final double size;

  /// Where the ink starts, so an overlay that replaces another (loading stage
  /// to player) carries on at the same level.
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
  late final AnimationController _c;
  int _frame = 0;
  late double _level;

  @override
  void initState() {
    super.initState();
    _level = (widget.initialLevel ?? 0.08).clamp(0.0, 1.0);
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..addListener(_tick)
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Twelve drawings a second: the ink chases its target and the rumble
  /// trembles, like limited animation.
  void _tick() {
    final f = (_c.value * 48).floor();
    if (f == _frame) return;
    final p = widget.progress;
    final target = p != null ? p.clamp(0.0, 1.0) : 0.24 + 0.06 * math.sin(f / 48 * 2 * math.pi);
    _level += (target - _level) * (target > _level ? 0.3 : 0.12);
    setState(() => _frame = f);
  }

  static String _speedText(double? mbps) {
    if (mbps == null) return '--';
    if (mbps < 10) return mbps.toStringAsFixed(mbps < 1 ? 2 : 1);
    return mbps.toStringAsFixed(0);
  }

  Widget _rumble(int side) {
    final shake = mangaFx == MangaFx.full ? 2.5 : 0.0;
    return Transform.translate(
      offset: Offset(wobble(_frame * 3 + side, shake), wobble(_frame * 5 + side, shake)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(left: side == 0 ? i * 6.0 : 0, right: side == 1 ? i * 6.0 : 0),
            child: SfxText('ゴ', size: widget.size * 0.17, color: Mg.white, pop: false, angle: side == 0 ? -0.2 : 0.2),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.progress == null ? null : (widget.progress!.clamp(0.0, 1.0) * 100).round();
    final headline = percent == null ? widget.label : '${widget.label} $percent%';
    final speed = _speedText(widget.mbps);
    final s = widget.size;
    final emblem = SizedBox(
      width: s,
      height: s,
      child: Stack(fit: StackFit.expand, children: [
        // A paper disc behind, so the line art reads on the black video.
        Container(decoration: const BoxDecoration(color: Mg.paper, shape: BoxShape.circle)),
        Padding(
          padding: EdgeInsets.all(s * 0.08),
          child: Stack(fit: StackFit.expand, children: [
            ClipRect(
              clipper: _FromBottom(_level),
              child: Image.asset('assets/manga/logo_color.png', fit: BoxFit.contain),
            ),
            Image.asset('assets/manga/logo_tone.png', fit: BoxFit.contain),
            Image.asset('assets/manga/logo_lines.png', fit: BoxFit.contain),
          ]),
        ),
        CustomPaint(painter: _RingPainter(_level)),
      ]),
    );

    return Semantics(
      liveRegion: true,
      label: '$headline, ${widget.mbps == null ? 'speed unknown' : '$speed megabits per second'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _rumble(0),
            const SizedBox(width: 10),
            emblem,
            const SizedBox(width: 10),
            _rumble(1),
          ]),
          const SizedBox(height: 14),
          PanelBox(
            shadow: 3,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic, children: [
                Text(speed, style: MgFont.heading(22, color: Mg.red)),
                const SizedBox(width: 6),
                Text('MBPS', style: MgFont.label(7, color: Mg.gray)),
              ]),
              Text(headline.toUpperCase(), textAlign: TextAlign.center, style: MgFont.label(8.5)),
              if (widget.detail != null) ...[
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(widget.detail!, textAlign: TextAlign.center, style: MgFont.text(13, color: Mg.gray)),
                ),
              ],
            ]),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: 12),
            InkButton(label: 'Retry now', icon: InkIcons.refresh, fontSize: 8, onPressed: widget.onRetry),
          ],
        ],
      ),
    );
  }
}

/// Shows the bottom [level] of the child: the ink rising.
class _FromBottom extends CustomClipper<Rect> {
  final double level;
  _FromBottom(this.level);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, size.height * (1 - level.clamp(0.0, 1.0)), size.width, size.height);

  @override
  bool shouldReclip(covariant _FromBottom old) => old.level != level;
}

/// The disc's rim in ink, with a red arc for how far along the buffer is.
class _RingPainter extends CustomPainter {
  final double level;
  _RingPainter(this.level);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(0, 0, size.width, size.height).deflate(3);
    canvas.drawOval(r, Paint()
      ..color = Mg.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5);
    canvas.drawArc(r.deflate(5), -math.pi / 2, 2 * math.pi * level.clamp(0.0, 1.0), false, Paint()
      ..color = Mg.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.butt);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.level != level;
}
