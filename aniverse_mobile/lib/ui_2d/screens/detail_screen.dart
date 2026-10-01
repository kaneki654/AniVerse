import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/history_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../theme_2d.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/continue_watching.dart';
import '../widgets/poster_card.dart';
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

  void _openEpisode(int number) {
    Navigator.push(
      context,
      FadeScaleRoute(
        backdrop: false,
        page: WatchScreen(
          animeId: widget.id,
          epNum: number,
          title: _title,
          cover: _cover,
        ),
      ),
    );
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
                    Text(_synopsis, style: PxFont.text(15, color: Px.ash, height: 1.5)),
                    const SizedBox(height: 24),
                  ],
                  if (released)
                    _ResumeBanner(
                      animeId: widget.id,
                      episodeCount: epCount is num ? epCount.toInt() : 12,
                      onOpen: _openEpisode,
                    ),
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
                    "NOT RELEASED YET",
                    style: TextStyle(fontFamily: PxFont.display, color: AniVerseTheme.red, fontSize: 11),
                  ),
                ),
              ),
            )
          else
            // Rebuilt from history so tiles pick up progress made in the
            // player the moment the user comes back to this screen.
            ValueListenableBuilder<int>(
              valueListenable: HistoryService.changes,
              builder: (context, _, __) {
                final watched = HistoryService.episodesOf(widget.id);
                return SliverPadding(
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
                        progress: watched[index + 1],
                        onTap: () => _openEpisode(index + 1),
                      ),
                      childCount: epCount is num ? epCount.toInt() : 12,
                    ),
                  ),
                );
              },
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
      title.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PxFont.label(10).copyWith(shadows: PxFont.outline(1.2)),
    );
  }
}

/// Expanded header: the art crushed into big pixels as a backdrop, stepped
/// down into the page in hard bands, and the framed poster in front.
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
          PixelCover(url: banner!, decodeWidth: banner == cover ? 18 : 64)
        else
          const ColoredBox(color: Px.panel),
        // Hard bands instead of a smooth fade into the page.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x99050305), Color(0x99050305),
                Color(0xCC0D0709), Color(0xCC0D0709),
                Px.ink, Px.ink,
              ],
              stops: [0.0, 0.45, 0.45, 0.78, 0.78, 1.0],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 84, 16, 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (cover != null)
                SizedBox(
                  width: 128,
                  height: 188,
                  child: PixelBox(
                    fill: Px.black,
                    border: Px.blood,
                    borderWidth: 3,
                    shadow: 4,
                    child: PixelCover(url: cover!, decodeWidth: 100),
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: PxFont.label(12, height: 1.5)
                          .copyWith(shadows: PxFont.outline(1.5)),
                    ),
                    if (genres.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 8,
                        children: [for (final g in genres.take(3)) PixelChip(g, fontSize: 6)],
                      ),
                    ],
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 8,
                        children: [
                          for (final f in facts)
                            PixelChip(f, fill: Px.panelHigh, color: Px.ash, fontSize: 6),
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
  const _EpisodeTile({required this.number, required this.onTap, this.progress});

  final int number;
  final VoidCallback onTap;

  /// How far the user got, if they have started this episode.
  final HistoryEntry? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final finished = p?.finished ?? false;
    return PressableScale(
      onTap: onTap,
      child: PixelBox(
        fill: finished ? Px.bloodDeep : Px.panelHigh,
        border: finished ? Px.bloodDark : Px.black,
        shadow: 2,
        bevel: !finished,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (finished) ...[
                    const PixelSprite(Sprites.skullSmall, scale: 1.4),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    '$number',
                    style: PxFont.label(10, color: finished ? Px.ash : Px.bone, height: 1.2),
                  ),
                ],
              ),
            ),
            if (p != null && !finished)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PixelBar(fraction: p.fraction, height: 5),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Continue EP 5 · 12:30 left" above the episode grid when the user has
/// started this anime -- or "Next: EP 6" once the last one they watched is done.
class _ResumeBanner extends StatelessWidget {
  final String animeId;
  final int episodeCount;
  final void Function(int episode) onOpen;

  const _ResumeBanner({
    required this.animeId,
    required this.episodeCount,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HistoryService.changes,
      builder: (context, _, __) {
        final eps = HistoryService.episodesOf(animeId).values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (eps.isEmpty) return const SizedBox.shrink();
        final last = eps.first;
        final next = last.finished ? last.episode + 1 : last.episode;
        // Finished the final episode: there is nothing to continue.
        if (next > episodeCount) return const SizedBox.shrink();
        final String detail;
        if (last.finished) {
          detail = 'You finished episode ${last.episode}';
        } else if (last.durationMs > 0) {
          final left = last.duration - last.position;
          detail = '${left.inMinutes} min left';
        } else {
          detail = 'Pick up where you stopped';
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: PressableScale(
            onTap: () => onOpen(next),
            child: PixelBox(
              fill: Px.panel,
              border: Px.bloodDark,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      const PixelBox(
                        fill: Px.blood,
                        shadow: 2,
                        bevel: true,
                        padding: EdgeInsets.fromLTRB(9, 7, 7, 7),
                        child: PixelSprite(Sprites.play, scale: 2),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              last.finished ? 'NEXT: EPISODE $next' : 'CONTINUE EP $next',
                              style: PxFont.label(9),
                            ),
                            const SizedBox(height: 5),
                            Text(detail, style: PxFont.text(13, color: Px.ash)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!last.finished) ...[
                    const SizedBox(height: 10),
                    ProgressStrip(fraction: last.fraction, height: 8),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
