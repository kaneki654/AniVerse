import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme.dart';
import 'aniverse_logo.dart';

/// Poster tile shared by the home rows, search and genre grids, so a change to
/// card styling lands everywhere instead of in one screen at a time.
class PosterCard extends StatelessWidget {
  final Map<String, dynamic> anime;
  final VoidCallback onTap;
  final double? width;

  const PosterCard({
    super.key,
    required this.anime,
    required this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final titles = (anime['title'] ?? {}) as Map<String, dynamic>;
    final title = (titles['english'] ?? titles['romaji'] ?? 'Unknown').toString();
    final poster = ((anime['coverImage'] ?? {}) as Map<String, dynamic>)['large'] ?? '';
    final score = anime['averageScore'];

    final card = PressableScale(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster.toString().isEmpty)
                    const ColoredBox(color: AniVerseTheme.surfaceHigh)
                  else
                    CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const PosterSkeleton(),
                      errorWidget: (_, __, ___) =>
                          const ColoredBox(color: AniVerseTheme.surfaceHigh),
                    ),
                  // Keeps the title legible where the art is bright.
                  const DecoratedBox(
                    decoration: BoxDecoration(gradient: AniVerseTheme.posterScrim),
                  ),
                  if (score != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AniVerseTheme.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Reserve two lines whatever the title length: with a flexible title
          // the Expanded poster above it changed height per card, so rows came
          // out ragged.
          SizedBox(
            // 32, not 30: two lines at 12px x 1.2 leading is 28.8px, which only
            // just fits, so any device text scaling above 1.0 clipped the
            // descenders on the second line.
            height: 32,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ),
        ],
      ),
    );

    return width == null
        ? card
        : SizedBox(width: width, child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: card,
          ));
  }
}

/// Shimmer block used while a poster loads.
class PosterSkeleton extends StatelessWidget {
  const PosterSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AniVerseTheme.skeleton,
      highlightColor: AniVerseTheme.skeletonHigh,
      child: const ColoredBox(color: AniVerseTheme.skeleton),
    );
  }
}

/// Placeholder row shown while a home section is still loading. Standing in for
/// the real layout reads better than a lone spinner, which matters here because
/// a cold resolve can take a while.
class SectionSkeleton extends StatelessWidget {
  final double height;

  const SectionSkeleton({super.key, this.height = 210});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: const PosterSkeleton(),
                  ),
                ),
                const SizedBox(height: 6),
                Shimmer.fromColors(
                  baseColor: AniVerseTheme.skeleton,
                  highlightColor: AniVerseTheme.skeletonHigh,
                  child: Container(
                    height: 10,
                    width: 90,
                    color: AniVerseTheme.skeleton,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
