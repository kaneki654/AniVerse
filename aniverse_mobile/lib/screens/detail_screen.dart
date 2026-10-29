import '../classic_plus/classic_extras.dart';
import '../services/download_service.dart';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/history_service.dart';
import '../theme.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/continue_watching.dart';
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
        page: WatchScreen(
          animeId: widget.id,
          epNum: number,
          title: _title,
          cover: _cover,
        ),
      ),
    );
  }

  /// Long-press on an episode: save it to watch offline (classic_plus Downloads).
  void _download(int number) {
    final added = DownloadService.enqueue(
        animeId: widget.id, episode: number, category: 'sub', title: _title, cover: _cover ?? '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(added ? 'Downloading episode $number. It will be under Downloads.' : 'Episode $number is already saved or on its way.'),
    ));
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
            actions: [ClassicFollowButton(animeId: widget.id, anime: anime)],
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
                    "This anime hasn't been released yet",
                    style: TextStyle(color: AniVerseTheme.red, fontSize: 15),
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
                        onLongPress: () => _download(index + 1),
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
  const _EpisodeTile({required this.number, required this.onTap, this.onLongPress, this.progress});

  final int number;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// How far the user got, if they have started this episode.
  final HistoryEntry? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final finished = p?.finished ?? false;
    return Material(
      color: finished
          ? AniVerseTheme.redDark.withValues(alpha: 0.45)
          : AniVerseTheme.surfaceHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: AniVerseTheme.red.withValues(alpha: 0.25),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (finished) ...[
                    const Icon(Icons.check, size: 13, color: Colors.white70),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: finished ? Colors.white70 : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            if (p != null && !finished)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ProgressStrip(fraction: p.fraction, height: 3),
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
          child: Material(
            color: AniVerseTheme.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onOpen(next),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.play_circle_fill, color: AniVerseTheme.red, size: 34),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                last.finished ? 'Next: Episode $next' : 'Continue Episode $next',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Text(detail,
                                  style: const TextStyle(
                                      fontSize: 11, color: AniVerseTheme.textDim)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!last.finished) ProgressStrip(fraction: last.fraction),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
