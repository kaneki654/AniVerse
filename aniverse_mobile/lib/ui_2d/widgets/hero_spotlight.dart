import 'package:flutter/material.dart';

import '../pixel/blood.dart';
import '../pixel/fx.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import 'poster_card.dart';

/// Swipeable spotlight for the top trending shows, as a pixel-art panel: the
/// backdrop is the cover pixelated into big blocks (where the classic UI
/// blurred it), with blood dripping from the frame.
class HeroSpotlight extends StatefulWidget {
  const HeroSpotlight({super.key, required this.animes, required this.onTap});

  final List<dynamic> animes;
  final void Function(Map<String, dynamic> anime) onTap;

  @override
  State<HeroSpotlight> createState() => _HeroSpotlightState();
}

class _HeroSpotlightState extends State<HeroSpotlight> {
  static const int _maxSlides = 5;

  late final PageController _controller = PageController();
  int _page = 0;
  int _dir = 1;

  /// Bumped on every page change; the speed lines play when it does.
  final ValueNotifier<int> _swipes = ValueNotifier(0);

  List<Map<String, dynamic>> get _slides => widget.animes
      .whereType<Map<String, dynamic>>()
      .take(_maxSlides)
      .toList(growable: false);

  @override
  void dispose() {
    _controller.dispose();
    _swipes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    if (slides.isEmpty) return const SizedBox();

    return Column(
      children: [
        SizedBox(
          height: 232,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: slides.length,
                onPageChanged: (i) {
                  setState(() {
                    _dir = i > _page ? -1 : 1;
                    _page = i;
                  });
                  _swipes.value++;
                },
                itemBuilder: (context, i) => _Slide(
                  anime: slides[i],
                  onTap: () => widget.onTap(slides[i]),
                ),
              ),
              // Streaks across the card as it changes: pixel art's motion blur.
              Positioned.fill(child: SpeedLines(trigger: _swipes, direction: _dir)),
            ],
          ),
        ),
        if (slides.length > 1) ...[
          const SizedBox(height: 12),
          _PageDots(count: slides.length, active: _page),
        ],
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int active;
  const _PageDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active ? Px.blood : Px.panelHigh,
              border: Border.all(color: Px.black, width: 2),
            ),
          ),
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

  String get _cover {
    final c = anime['coverImage'];
    if (c is Map && c['large'] is String) return c['large'] as String;
    return '';
  }

  /// "Ep 5 out now" for an airing show, otherwise the episode count.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 6, 0),
      child: GestureDetector(
        onTap: onTap,
        child: PixelBox(
          fill: Px.black,
          border: Px.blood,
          borderWidth: 3,
          shadow: 4,
          rivets: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Backdrop: the cover crushed to a few dozen pixels across.
              PixelCover(url: _cover, decodeWidth: 22),
              const ColoredBox(color: Color(0xD90D0709)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: BloodDrips(height: 46, count: 7, seed: _title.length, cell: 3),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 116,
                      child: AspectRatio(
                        aspectRatio: 0.69,
                        child: PixelBox(
                          fill: Px.black,
                          shadow: 3,
                          child: PixelCover(url: _cover, decodeWidth: 80),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const PixelChip('Spotlight'),
                          const SizedBox(height: 10),
                          Text(
                            _title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: PxFont.label(10, height: 1.5)
                                .copyWith(shadows: PxFont.outline(1.2)),
                          ),
                          const SizedBox(height: 6),
                          Text(_meta, style: PxFont.text(13, color: Px.ash)),
                          const SizedBox(height: 12),
                          PixelButton(
                            label: 'Watch now',
                            icon: Sprites.play,
                            fontSize: 8,
                            onPressed: onTap,
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

/// Placeholder shaped like the spotlight while the home data loads.
class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(
          height: 232,
          child: PixelBox(
            fill: Px.black,
            border: Px.bloodDark,
            borderWidth: 3,
            shadow: 4,
            child: PixelSkeleton(),
          ),
        ),
        SizedBox(height: 12),
        _PageDots(count: 5, active: 0),
      ],
    );
  }
}
