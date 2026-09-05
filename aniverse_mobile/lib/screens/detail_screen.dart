import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/aniverse_logo.dart';
import 'watch_screen.dart';

class DetailScreen extends StatefulWidget {
  final String id;
  const DetailScreen({super.key, required this.id});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Map<String, dynamic>? anime;

  /// Collapsed height of the header, measured from the top of the screen.
  static const double _expandedHeight = 330;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final data = await ApiService.getAnimeDetails(widget.id);
    if (!mounted) return;
    setState(() {
      anime = data;
    });
  }

  String get _title {
    final t = anime!['title'];
    if (t is Map) {
      final english = t['english'];
      final romaji = t['romaji'];
      if (english is String && english.isNotEmpty) return english;
      if (romaji is String && romaji.isNotEmpty) return romaji;
    }
    return 'Untitled';
  }

  String? get _cover {
    final c = anime!['coverImage'];
    if (c is Map) {
      final large = c['large'];
      if (large is String && large.isNotEmpty) return large;
    }
    return null;
  }

  /// Wide banner art, which the detail payload carries but the list endpoints
  /// do not. Falls back to the cover so the header still fills when a title has
  /// no banner on AniList.
  String? get _banner {
    final b = anime!['bannerImage'];
    if (b is String && b.isNotEmpty) return b;
    return _cover;
  }

  List<String> get _genres {
    final g = anime!['genres'];
    if (g is List) return g.whereType<String>().take(4).toList();
    return const [];
  }

  String get _synopsis {
    final d = anime!['description'];
    if (d is! String) return '';
    // The API returns HTML; <br> becomes a newline so paragraphs survive, and
    // every other tag is dropped.
    return d
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  /// Short facts line under the title: episode count, status, year.
  List<String> get _facts {
    final out = <String>[];
    final eps = anime!['episodes'];
    if (eps is num && eps > 0) {
      out.add(eps.toInt() == 1 ? '1 episode' : '${eps.toInt()} episodes');
    }
    final status = anime!['status'];
    if (status is String && status.isNotEmpty) {
      out.add(status.replaceAll('_', ' ').toLowerCase());
    }
    final score = anime!['averageScore'];
    if (score is num && score > 0) out.add('${score.toInt()}%');
    final mins = anime!['duration'];
    if (mins is num && mins > 0) out.add('${mins.toInt()}m');
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (anime == null) {
      return const Scaffold(body: AniVerseLoadingScreen(label: 'LOADING'));
    }

    final epCount = anime!['episodes'] ?? 12;
    final released = anime!['status'] != 'NOT_YET_RELEASED';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: _expandedHeight,
            backgroundColor: AniVerseTheme.bg,
            // FlexibleSpaceBar parks its title at the bottom of the expanded
            // area until the bar collapses, which drew the title a second time
            // underneath the one in the header. Fade it in only once the bar is
            // actually collapsed, so exactly one title is visible at any point.
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final collapsedAt = kToolbarHeight +
                    MediaQuery.of(context).padding.top +
                    12;
                final collapsed = constraints.biggest.height <= collapsedAt;
                return FlexibleSpaceBar(
                  title: AnimatedOpacity(
                    opacity: collapsed ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: _CollapsedTitle(title: _title),
                  ),
                  titlePadding: const EdgeInsetsDirectional.only(
                      start: 52, bottom: 16, end: 16),
                  background: _Header(
                    title: _title,
                    cover: _cover,
                    banner: _banner,
                    facts: _facts,
                    genres: _genres,
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_synopsis.isNotEmpty) ...[
                    Text(
                      _synopsis,
                      style: const TextStyle(
                        color: AniVerseTheme.textDim,
                        height: 1.45,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const SectionHeader(title: 'Episodes'),
                ],
              ),
            ),
          ),
          if (!released)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                child: Center(
                  child: Text(
                    "This anime hasn't been released yet",
                    style: TextStyle(color: AniVerseTheme.red, fontSize: 15),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _EpisodeTile(
                    number: index + 1,
                    onTap: () => Navigator.push(
                      context,
                      FadeScaleRoute(
                        page: WatchScreen(
                          animeId: widget.id,
                          epNum: index + 1,
                        ),
                      ),
                    ),
                  ),
                  childCount: epCount is num ? epCount.toInt() : 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
  }
}

/// Expanded header: blurred cover as backdrop, sharp poster in front.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.cover,
    required this.banner,
    required this.facts,
    required this.genres,
  });

  final String title;
  final String? cover;
  final String? banner;
  final List<String> facts;
  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (banner != null)
          ImageFiltered(
            // Real banner art is already the right shape, so it only needs
            // enough blur to keep the title legible; an over-scaled portrait
            // cover standing in for one needs much more.
            imageFilter: banner == cover
                ? ImageFilter.blur(sigmaX: 22, sigmaY: 22)
                : ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: CachedNetworkImage(
              imageUrl: banner!,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  const ColoredBox(color: AniVerseTheme.surface),
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: AniVerseTheme.surface),
            ),
          )
        else
          const ColoredBox(color: AniVerseTheme.surface),

        // Fades the backdrop into the page background so the header has no
        // visible seam where the episode grid begins.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x99000000),
                Color(0xB3160608),
                AniVerseTheme.bg,
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 78, 16, 46),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (cover != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: cover!,
                    width: 130,
                    height: 190,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 130,
                      height: 190,
                      color: AniVerseTheme.skeleton,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 130,
                      height: 190,
                      color: AniVerseTheme.skeleton,
                    ),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (genres.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        genres.join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AniVerseTheme.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final f in facts)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                f,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.number, required this.onTap});

  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AniVerseTheme.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: AniVerseTheme.red.withValues(alpha: 0.25),
        child: Center(
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
