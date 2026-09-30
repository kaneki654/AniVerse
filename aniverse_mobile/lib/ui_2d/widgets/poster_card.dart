import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import 'aniverse_logo.dart';

/// Width, in image pixels, that cover art is decoded at before being scaled up
/// with no smoothing. Low enough that posters read as pixel art, high enough
/// that the show is still recognisable. Raise it for sharper covers.
const int kPixelArtWidth = 96;

/// Cover art as a sprite: decoded small, drawn with nearest-neighbour scaling
/// so its pixels stay square instead of being blurred back into a photo.
class PixelCover extends StatelessWidget {
  final String url;
  final int decodeWidth;

  const PixelCover({super.key, required this.url, this.decodeWidth = kPixelArtWidth});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _NoArt();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: decodeWidth,
      filterQuality: FilterQuality.none,
      placeholder: (_, __) => const PixelSkeleton(),
      errorWidget: (_, __, ___) => const _NoArt(),
    );
  }
}

class _NoArt extends StatelessWidget {
  const _NoArt();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Px.panelHigh,
        child: Center(child: PixelSprite(Sprites.skull, scale: 2.5)),
      );
}

/// Poster tile shared by the home rows, search and genre grids: the cover in a
/// hard pixel frame with a drop shadow, the score as a badge.
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
    final poster = (((anime['coverImage'] ?? {}) as Map<String, dynamic>)['large'] ?? '').toString();
    final score = anime['averageScore'];

    final card = PressableScale(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PixelBox(
              fill: Px.black,
              shadow: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PixelCover(url: poster),
                  if (score != null)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: PixelBox(
                        fill: Px.blood,
                        shadow: 0,
                        padding: const EdgeInsets.fromLTRB(3, 3, 4, 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const PixelSprite(Sprites.star, scale: 1, color: Px.gold),
                            const SizedBox(width: 3),
                            Text('$score', style: PxFont.label(7, height: 1.2)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Two lines reserved whatever the title length, so rows stay even.
          SizedBox(
            height: 34,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PxFont.text(13, height: 1.25),
            ),
          ),
        ],
      ),
    );

    return width == null
        ? card
        : SizedBox(
            width: width,
            child: Padding(padding: const EdgeInsets.only(right: 12), child: card),
          );
  }
}

/// Placeholder while a poster loads.
class PosterSkeleton extends StatelessWidget {
  const PosterSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const PixelSkeleton();
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
          padding: EdgeInsets.only(right: 12),
          child: SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: PixelBox(fill: Px.black, child: PixelSkeleton())),
                SizedBox(height: 8),
                PixelSkeleton(width: 96, height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
