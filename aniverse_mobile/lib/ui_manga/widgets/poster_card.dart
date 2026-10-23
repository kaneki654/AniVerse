import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ink/ink_widgets.dart';
import '../ink/manga.dart';

/// The score as a red starburst sticker slapped on a cover's corner.
class ScoreBurst extends StatelessWidget {
  final Object score;
  final double size;
  const ScoreBurst(this.score, {super.key, this.size = 34});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: const _StarburstPainter(),
          child: Center(
            child: Text('$score', style: MgFont.heading(size * 0.36, color: Mg.white, height: 1)),
          ),
        ),
      );
}

class _StarburstPainter extends CustomPainter {
  const _StarburstPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const spikes = 12;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path();
    for (var i = 0; i < spikes * 2; i++) {
      final a = i / (spikes * 2) * 2 * math.pi - math.pi / 2;
      final d = i.isEven ? r : r * 0.74;
      final p = c + Offset(math.cos(a), math.sin(a)) * d;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Mg.red);
    canvas.drawPath(path, Paint()
      ..color = Mg.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _StarburstPainter oldDelegate) => false;
}

/// A poster in a manga panel: the cover inside a thick ink frame with a hard
/// shadow, the score as a starburst on its corner, the title lettered under
/// it.
class PosterCard extends StatelessWidget {
  final Map<String, dynamic> anime;
  final VoidCallback onTap;
  final double? width;
  final FocusNode? focusNode;

  const PosterCard({super.key, required this.anime, required this.onTap, this.width, this.focusNode});

  @override
  Widget build(BuildContext context) {
    final titles = (anime['title'] ?? {}) as Map<String, dynamic>;
    final title = (titles['english'] ?? titles['romaji'] ?? 'Unknown').toString();
    final poster = (((anime['coverImage'] ?? {}) as Map<String, dynamic>)['large'] ?? '').toString();
    final score = anime['averageScore'];
    final card = InkPress(
      focusNode: focusNode,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: PanelBox(shadow: 4, borderWidth: 2.5, child: InkCover(url: poster))),
              if (score != null) Positioned(top: -8, right: -6, child: ScoreBurst(score)),
            ]),
          ),
          const SizedBox(height: 8),
          // Two lines kept whatever the title's length, so rows stay even.
          SizedBox(
            height: 36,
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgFont.label(8.6, height: 1.15)),
          ),
        ],
      ),
    );
    return width == null
        ? card
        : SizedBox(width: width, child: Padding(padding: const EdgeInsets.only(right: 14, top: 8), child: card));
  }
}

/// An anime as a row -- small cover, title, score, episodes and status -- for
/// search results and the list view of genre results.
class AnimeListRow extends StatelessWidget {
  final Map<String, dynamic> anime;
  final VoidCallback onTap;

  const AnimeListRow({super.key, required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final titles = (anime['title'] ?? {}) as Map<String, dynamic>;
    final title = (titles['english'] ?? titles['romaji'] ?? 'Unknown').toString();
    final poster = (((anime['coverImage'] ?? {}) as Map<String, dynamic>)['large'] ?? '').toString();
    final score = anime['averageScore'];
    final episodes = anime['episodes'];
    final status = anime['status'];
    return InkPress(
      onTap: onTap,
      child: SizedBox(
        height: 96,
        child: PanelBox(
          child: Row(children: [
            Container(
              width: 64,
              decoration: const BoxDecoration(border: Border(right: BorderSide(color: Mg.ink, width: 2.5))),
              child: InkCover(url: poster, decodeWidth: 128),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgFont.heading(16, height: 1.1)),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (score != null) '★ $score',
                      if (episodes != null) '$episodes EPS',
                      if (status != null) status.toString().replaceAll('_', ' '),
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MgFont.label(7, color: Mg.gray),
                  ),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.only(right: 8), child: InkIcon(InkIcons.chevron, scale: 2.2)),
          ]),
        ),
      ),
    );
  }
}

/// Placeholder while a poster loads.
class PosterSkeleton extends StatelessWidget {
  const PosterSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const InkSkeleton();
}

/// Placeholder row shown while a home section is still loading.
class SectionSkeleton extends StatelessWidget {
  final double height;

  const SectionSkeleton({super.key, this.height = 214});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(right: 14, top: 8),
          child: SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: PanelBox(shadow: 4, child: InkSkeleton())),
                SizedBox(height: 8),
                InkSkeleton(width: 96, height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
