import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ink/ink_widgets.dart';
import '../ink/manga.dart';

/// The AniVerse emblem, inked: the same "A", orbit and play mark as the app
/// icon, redrawn as manga art -- ink lines, screentone shadows, red fill
/// (scripts/make_manga_assets.py renders the layers).
class MangaEmblem extends StatelessWidget {
  final double size;
  const MangaEmblem({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/manga/logo.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

/// The wordmark: the inked emblem, then ANIVERSE in heavy italic red with an
/// ink outline and a paper one outside it, like a title on a manga cover.
/// Every few seconds a sparkle flicks off the emblem.
class AniVerseLogo extends StatelessWidget {
  final double fontSize;

  /// Kept from the pixel logo (its blood drips); here it allows the sparkle.
  final bool drips;

  const AniVerseLogo({super.key, this.fontSize = 14, this.drips = true});

  @override
  Widget build(BuildContext context) {
    final s = fontSize * 1.55;
    final word = Text(
      'ANIVERSE',
      style: MgFont.heading(s, color: Mg.red).copyWith(shadows: [
        ...MgFont.outline(s / 16),
        ...MgFont.outline(s / 9, color: Mg.white),
        Shadow(color: Mg.ink, offset: Offset(s / 10, s / 10)),
      ]),
    );
    final emblem = SizedBox(
      width: s * 1.7,
      height: s * 1.7,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: MangaEmblem(size: s * 1.7)),
        if (drips && mangaFx == MangaFx.full)
          Positioned(right: -s * 0.35, top: -s * 0.35, child: _Sparkle(size: s * 0.8)),
      ]),
    );
    return Semantics(
      label: 'AniVerse',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [emblem, SizedBox(width: s * 0.25), word]),
      ),
    );
  }
}

/// A four-point sparkle that flashes now and then: a few frames of glint every
/// six seconds, like a highlight on a manga cover.
class _Sparkle extends StatelessWidget {
  final double size;
  const _Sparkle({required this.size});

  @override
  Widget build(BuildContext context) => MangaClock(
        fps: 12,
        frames: 72,
        builder: (_, f) {
          if (f < 60 || f >= 66) return SizedBox(width: size, height: size);
          final k = 1 - (f - 62.5).abs() / 3;
          return SizedBox(width: size, height: size, child: CustomPaint(painter: _SparklePainter(0.5 + 0.5 * k)));
        },
      );
}

class _SparklePainter extends CustomPainter {
  final double k;
  const _SparklePainter(this.k);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * k;
    final star = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final p = c + Offset(math.cos(a), math.sin(a)) * (i.isEven ? r : r * 0.18);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = Mg.white);
    canvas.drawPath(star, Paint()
      ..color = Mg.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.k != k;
}

/// Waiting on the server: an ensō brush circle drawing itself round the inked
/// emblem, with a caption box under it (and 読込中, "loading").
class AniVerseLoader extends StatelessWidget {
  final double size;
  final String? label;

  const AniVerseLoader({super.key, this.size = 64, this.label});

  @override
  Widget build(BuildContext context) {
    final s = size.clamp(22.0, 160.0);
    final ring = SizedBox(
      width: s * 1.5,
      height: s * 1.5,
      child: Stack(alignment: Alignment.center, children: [
        const Positioned.fill(child: InkSpinner()),
        if (s >= 40) MangaEmblem(size: s * 0.8),
      ]),
    );
    if (label == null || s < 40) return ring;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ring,
      const SizedBox(height: 14),
      PanelBox(
        shadow: 2,
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label!.toUpperCase(), style: MgFont.label(8)),
          const SizedBox(width: 8),
          Text('読込中', style: MgFont.sfx(12, color: Mg.red)),
        ]),
      ),
    ]);
  }
}

/// Full-screen loading state.
class AniVerseLoadingScreen extends StatelessWidget {
  final String? label;
  const AniVerseLoadingScreen({super.key, this.label});

  @override
  Widget build(BuildContext context) => Center(child: AniVerseLoader(size: 72, label: label));
}
