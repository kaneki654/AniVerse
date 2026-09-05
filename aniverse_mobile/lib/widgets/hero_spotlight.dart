import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme.dart';

/// Large featured banner at the top of the home screen.
///
/// The list endpoints only return `coverImage.large` -- there is no banner art
/// or synopsis in the payload -- so the backdrop is the same poster blurred and
/// over-scaled behind the sharp one. That keeps the hero to a single image
/// request per slide instead of a second round trip for artwork the API does
/// not expose.
class HeroSpotlight extends StatefulWidget {
  const HeroSpotlight({
    super.key,
    required this.animes,
    required this.onTap,
  });

  final List<dynamic> animes;
  final void Function(Map<String, dynamic> anime) onTap;

  @override
  State<HeroSpotlight> createState() => _HeroSpotlightState();
}

class _HeroSpotlightState extends State<HeroSpotlight> {
  static const int _maxSlides = 5;

  late final PageController _controller = PageController();
  int _page = 0;

  List<Map<String, dynamic>> get _slides => widget.animes
      .whereType<Map<String, dynamic>>()
      .take(_maxSlides)
      .toList(growable: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    if (slides.isEmpty) return const SizedBox();

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _Slide(
              anime: slides[i],
              onTap: () => widget.onTap(slides[i]),
            ),
          ),
        ),
        if (slides.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(slides.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 4,
                width: active ? 18 : 6,
                decoration: BoxDecoration(
                  color: active ? AniVerseTheme.red : Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.anime, required this.onTap});

  final Map<String, dynamic> anime;
  final VoidCallback onTap;

  String get _title {
    final t = anime['title'];
    if (t is Map) {
      final english = t['english'];
      final romaji = t['romaji'];
      if (english is String && english.isNotEmpty) return english;
      if (romaji is String && romaji.isNotEmpty) return romaji;
    }
    return 'Untitled';
  }

  String? get _cover {
    final c = anime['coverImage'];
    if (c is Map) {
      final large = c['large'];
      if (large is String && large.isNotEmpty) return large;
    }
    return null;
  }

  /// Episode count, or the latest aired episode while the show is still running.
  String get _meta {
    final next = anime['nextAiringEpisode'];
    if (next is Map && next['episode'] is num) {
      final aired = (next['episode'] as num).toInt() - 1;
      if (aired > 0) return 'Ep $aired out now';
    }
    final eps = anime['episodes'];
    if (eps is num && eps > 0) {
      final n = eps.toInt();
      return n == 1 ? '1 episode' : '$n episodes';
    }
    final status = anime['status'];
    return status is String ? status.toLowerCase() : '';
  }

  @override
  Widget build(BuildContext context) {
    final cover = _cover;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const ColoredBox(color: AniVerseTheme.surface),
                    errorWidget: (_, __, ___) =>
                        const ColoredBox(color: AniVerseTheme.surface),
                  ),
                )
              else
                Container(color: AniVerseTheme.surface),

              // Without this the blurred art washes the title out; the red tint
              // in the middle stop ties the hero back to the logo.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xF20E0E0E),
                      Color(0xCC160608),
                      Color(0x660E0E0E),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (cover != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: cover,
                          width: 118,
                          height: 172,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 118,
                            height: 172,
                            color: AniVerseTheme.skeleton,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 118,
                            height: 172,
                            color: AniVerseTheme.skeleton,
                          ),
                        ),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AniVerseTheme.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'SPOTLIGHT',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _meta,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AniVerseTheme.textDim,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: AniVerseTheme.red,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_arrow_rounded,
                                      size: 18, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'Watch now',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Placeholder occupying the hero's exact footprint while the home data loads,
/// so the list below does not jump once the real slides arrive.
class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Shimmer.fromColors(
          baseColor: AniVerseTheme.skeleton,
          highlightColor: AniVerseTheme.skeletonHigh,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              color: AniVerseTheme.skeleton,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 4,
              width: i == 0 ? 18 : 6,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
