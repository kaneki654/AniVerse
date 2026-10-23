import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/app_settings.dart';
import '../../services/download_service.dart';
import '../../services/history_service.dart';
import '../../services/native_bridge.dart';
import '../../services/watchlist_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../theme_2d.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/continue_watching.dart';
import '../widgets/pixel_extras.dart';
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

  /// Studio, season, trailer, characters, relations, recommendations.
  Map<String, dynamic> _extra = const {};

  /// Episode titles, synopses and screenshots, by number.
  Map<int, Map<String, dynamic>> _epInfo = const {};
  bool _listView = AppSettings.epView == 'list';

  /// The Tagalog dub, when this anime has one (app/tagalog.py).
  Map<String, dynamic>? _tagalog;

  /// Collapsed height of the header, measured from the top of the screen.
  static const double _expandedHeight = 330;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    ApiService.tagalog(widget.id).then((t) {
      if (mounted && t != null) setState(() => _tagalog = t);
    });
  }

  Future<void> _loadDetails() async {
    ApiService.extra(widget.id).then((x) {
      if (mounted) setState(() => _extra = x);
    });
    ApiService.episodes(widget.id).then((list) {
      if (mounted) setState(() => _epInfo = {for (final e in list) if (e['number'] is num) (e['number'] as num).toInt(): e});
    });
    final data = await ApiService.getAnimeDetails(widget.id);
    if (!mounted) return;
    setState(() {
      anime = data;
    });
  }

  int get _aired => airedEpisodes(anime);

  void _toggleFollow() {
    if (WatchlistService.has(widget.id)) {
      WatchlistService.unfollow(widget.id);
      pixelToast(context, 'Removed from My List.');
    } else {
      WatchlistService.follow(widget.id, title: _title, cover: _cover ?? '', seen: _aired);
      Sfx.play('achieve');
      pixelToast(context, AppSettings.alerts
          ? "On My List. You'll be told when new episodes air."
          : 'On My List. Turn on alerts in Settings to hear about new episodes.');
    }
  }

  void _download(int ep) {
    final ok = DownloadService.enqueue(animeId: widget.id, episode: ep, title: _title, cover: _cover ?? '');
    Sfx.play('select');
    pixelToast(context, ok ? 'Episode $ep is downloading. It will be under Saved.' : 'Episode $ep is already saved or on its way.');
  }

  /// Every aired episode not yet saved, after a confirmation with the count.
  Future<void> _downloadAll() async {
    final aired = _aired;
    final missing = [for (var ep = 1; ep <= aired; ep++) if (DownloadService.find(widget.id, ep) == null) ep].length;
    if (missing == 0) {
      pixelToast(context, 'Every aired episode is already saved or on its way.');
      return;
    }
    final go = await pickOption<bool>(context, 'Download $missing episode${missing == 1 ? '' : 's'}?', [
      (true, 'Download ${missing == aired ? 'all $aired' : 'the $missing not saved yet'}'),
      (false, 'Cancel'),
    ], null);
    if (go != true || !mounted) return;
    final n = DownloadService.enqueueSeason(animeId: widget.id, aired: aired, title: _title, cover: _cover ?? '');
    Sfx.play('select');
    pixelToast(context, '$n episode${n == 1 ? '' : 's'} queued. ${AppSettings.wifiOnly ? 'They download on Wi-Fi. ' : ''}They will be under Saved.');
  }

  /// Watch the Tagalog dub: from the episode last watched if it is dubbed,
  /// else the first dubbed one. The show then opens in Tagalog until the
  /// player is switched back to sub or dub.
  Widget _tagalogButton() {
    final dub = _tagalog!;
    final eps = (dub['episodes'] as Map).keys.map((k) => int.parse('$k')).toList()..sort();
    final last = HistoryService.episodesOf(widget.id).keys.fold<int>(0, (m, n) => n > m ? n : m);
    final start = eps.contains(last) ? last : eps.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: PixelButton(
        label: 'Tagalog dub · ${eps.length} EP${eps.length == 1 ? '' : 'S'}',
        icon: Sprites.play,
        fontSize: 8,
        onPressed: () {
          AppSettings.setTagalogFor(widget.id, true);
          Navigator.push(
            context,
            FadeScaleRoute(
              backdrop: false,
              page: WatchScreen(animeId: widget.id, epNum: start, category: 'tl', title: _title, cover: _cover),
            ),
          );
        },
      ),
    );
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
    final season = _extra['season'], year = _extra['seasonYear'];
    if (season is String && year != null) out.add('${season.toLowerCase()} $year');
    final studio = _extra['studio'];
    if (studio is String && studio.isNotEmpty) out.add(studio);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (anime == null) {
      return const Scaffold(body: AniVerseLoadingScreen(label: 'LOADING'));
    }

    final aired = _aired;
    final listed = anime!['episodes'] is num ? (anime!['episodes'] as num).toInt() : 0;
    final total = aired > listed ? aired : listed;
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
                  ValueListenableBuilder<int>(
                    valueListenable: WatchlistService.changes,
                    builder: (context, _, __) {
                      final on = WatchlistService.has(widget.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: PixelButton(
                          label: on ? 'On My List' : 'Add to My List',
                          icon: on ? Sprites.bookmark : Sprites.bookmarkOff,
                          kind: on ? PixelButtonKind.dark : PixelButtonKind.blood,
                          fontSize: 8,
                          onPressed: _toggleFollow,
                        ),
                      );
                    },
                  ),
                  if (_tagalog != null) _tagalogButton(),
                  if (released)
                    _ResumeBanner(
                      animeId: widget.id,
                      episodeCount: aired,
                      onOpen: _openEpisode,
                    ),
                  Row(
                    children: [
                      const Expanded(child: SectionHeader(title: 'Episodes')),
                      if (released && _aired > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14, left: 8),
                          child: PixelIconButton(
                            sprite: Sprites.download,
                            tooltip: 'Download every episode',
                            color: Px.ash,
                            framed: true,
                            onPressed: _downloadAll,
                          ),
                        ),
                      if (released)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14, left: 8),
                          child: PixelIconButton(
                            sprite: _listView ? Sprites.grid : Sprites.list,
                            tooltip: _listView ? 'Show as a grid' : 'Show as a list',
                            color: Px.ash,
                            framed: true,
                            onPressed: () {
                              Sfx.play('select');
                              setState(() => _listView = !_listView);
                              AppSettings.set('epView', _listView ? 'list' : 'grid');
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!released)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                child: Center(
                  child: Text(
                    "NOT RELEASED YET",
                    style: TextStyle(fontFamily: PxFont.display, color: AniVerseTheme.red, fontSize: 11),
                  ),
                ),
              ),
            )
          else if (_listView)
            ValueListenableBuilder<int>(
              valueListenable: HistoryService.changes,
              builder: (context, _, __) => ValueListenableBuilder<int>(
                valueListenable: DownloadService.changes,
                builder: (context, _, __) {
                  final watched = HistoryService.episodesOf(widget.id);
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    sliver: SliverList.separated(
                      itemCount: total,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _EpisodeRow(
                        number: i + 1,
                        info: _epInfo[i + 1],
                        cover: _cover ?? '',
                        future: i + 1 > aired,
                        progress: watched[i + 1],
                        download: DownloadService.find(widget.id, i + 1),
                        onTap: () => _openEpisode(i + 1),
                        onDownload: () => _download(i + 1),
                      ),
                    ),
                  );
                },
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
                      childCount: total,
                    ),
                  ),
                );
              },
            ),
          ..._extras(),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  static const _relation = {
    'PREQUEL': 'Prequel', 'SEQUEL': 'Sequel', 'SIDE_STORY': 'Side story', 'SPIN_OFF': 'Spin-off',
    'ALTERNATIVE': 'Alternative', 'PARENT': 'Main story', 'SUMMARY': 'Summary', 'COMPILATION': 'Compilation',
    'CHARACTER': 'Shared cast', 'OTHER': 'Related', 'CONTAINS': 'Contains', 'SOURCE': 'Source',
  };

  /// Trailer, characters, related seasons and recommendations, as they arrive.
  List<Widget> _extras() {
    final x = _extra;
    if (x.isEmpty) return const [];
    final out = <Widget>[];
    Widget section(String title, Widget child) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SectionHeader(title: title), child]),
          ),
        );

    final t = x['trailer'];
    if (t is Map && t['id'] != null && (t['site'] == 'youtube' || t['site'] == 'dailymotion')) {
      final url = t['site'] == 'youtube'
          ? 'https://www.youtube.com/watch?v=${t['id']}'
          : 'https://www.dailymotion.com/video/${t['id']}';
      out.add(section(
        'Trailer',
        PressableScale(
          onTap: () {
            Sfx.play('start');
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PixelBox(
              fill: Px.black,
              child: Stack(fit: StackFit.expand, children: [
                PixelCover(url: (t['thumbnail'] ?? x['bannerImage'] ?? _cover ?? '').toString(), decodeWidth: 120),
                Center(
                  child: PixelBox(
                    fill: Px.blood,
                    bevel: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: const PixelSprite(Sprites.play, scale: 3),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ));
    }

    final chars = [for (final c in (x['characters'] as List? ?? const [])) if (c is Map && c['name'] != null) c];
    if (chars.isNotEmpty) {
      out.add(section(
        'Characters',
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chars.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final c = chars[i];
              return SizedBox(
                width: 88,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 88,
                    height: 96,
                    child: PixelBox(fill: Px.black, shadow: 2, child: PixelCover(url: (c['image'] ?? '').toString(), decodeWidth: 56)),
                  ),
                  const SizedBox(height: 5),
                  Text(c['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: PxFont.text(12, height: 1.2)),
                  Text(
                    (c['voiceActor'] ?? (c['role'] == 'MAIN' ? 'Main' : 'Supporting')).toString().toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PxFont.label(5, color: Px.ash),
                  ),
                ]),
              );
            },
          ),
        ),
      ));
    }

    Widget shelf(List<Map> items, {bool relations = false}) => SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final a = Map<String, dynamic>.from(items[i]);
              final card = PosterCard(
                anime: a,
                width: 120,
                onTap: () => Navigator.push(context, FadeScaleRoute(page: DetailScreen(id: a['id'].toString()))),
              );
              if (!relations) return card;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: PixelChip((_relation[a['relation']] ?? 'Related').toUpperCase(), fontSize: 5),
                ),
                Expanded(child: card),
              ]);
            },
          ),
        );

    final related = [for (final r in (x['relations'] as List? ?? const [])) if (r is Map && r['id'] != null) r];
    if (related.isNotEmpty) out.add(section('Related', shelf(related, relations: true)));
    final recs = [for (final r in (x['recommendations'] as List? ?? const [])) if (r is Map && r['id'] != null) r];
    if (recs.isNotEmpty) out.add(section('You might also like', shelf(recs)));
    return out;
  }
}

/// One episode in the list view: screenshot, number, title, air date, a line
/// of synopsis, progress, and the download button.
class _EpisodeRow extends StatelessWidget {
  final int number;
  final Map<String, dynamic>? info;
  final String cover;
  final bool future;
  final HistoryEntry? progress;
  final DownloadItem? download;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const _EpisodeRow({
    required this.number,
    required this.info,
    required this.cover,
    required this.future,
    required this.progress,
    required this.download,
    required this.onTap,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final i = info;
    final title = (i?['title'] ?? '').toString().isNotEmpty ? i!['title'].toString() : 'Episode $number';
    final done = progress?.finished ?? false;
    final air = DateTime.tryParse((i?['airDate'] ?? '').toString());
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final meta = [
      if (air != null) '${air.day} ${months[air.month - 1]} ${air.year}',
      if (i?['runtime'] is num) '${(i!['runtime'] as num).toInt()}m',
      if (future) 'Not aired yet' else if (done) 'Watched',
    ].join(' · ');
    final d = download;
    final image = (i?['image'] ?? '').toString();

    return Opacity(
      opacity: future ? 0.45 : 1,
      child: PressableScale(
        onTap: future ? () {} : onTap,
        child: PixelBox(
          border: done ? Px.bloodDark : Px.black,
          padding: const EdgeInsets.all(6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                height: 68,
                child: Stack(fit: StackFit.expand, children: [
                  PixelCover(url: image.isNotEmpty ? image : cover, decodeWidth: image.isNotEmpty ? 96 : 40),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Px.black,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
                        child: Text('EP $number', style: PxFont.label(6, height: 1.2)),
                      ),
                    ),
                  ),
                  if (done) const Positioned(right: 3, top: 3, child: PixelSprite(Sprites.skullSmall, scale: 1.6)),
                  if (progress != null && !done)
                    Positioned(left: 0, right: 0, bottom: 0, child: PixelBar(fraction: progress!.fraction, height: 4)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: PxFont.text(14, color: done ? Px.ash : Px.bone, height: 1.2)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(meta.toUpperCase(), style: PxFont.label(5, color: Px.ashDark)),
                  ],
                  if ((i?['overview'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(i!['overview'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: PxFont.text(11, color: Px.ash, height: 1.25)),
                  ],
                ]),
              ),
              if (!future)
                d == null || d.status == 'failed'
                    ? PixelIconButton(sprite: Sprites.download, tooltip: 'Download episode $number', color: Px.ash, scale: 1.8, size: 40, onPressed: onDownload)
                    : SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: d.done
                              ? PixelSprite(Sprites.check, scale: 1.8, color: Px.bloodLight)
                              : Text('${(d.progress * 100).toStringAsFixed(0)}%', style: PxFont.label(6, color: Px.ash)),
                        ),
                      ),
            ],
          ),
        ),
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
          ColoredBox(color: Px.panel),
        // Hard bands instead of a smooth fade into the page.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0x99050305), const Color(0x99050305),
                const Color(0xCC0D0709), const Color(0xCC0D0709),
                Px.ink, Px.ink,
              ],
              stops: const [0.0, 0.45, 0.45, 0.78, 0.78, 1.0],
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
                      PixelBox(
                        fill: Px.blood,
                        shadow: 2,
                        bevel: true,
                        padding: const EdgeInsets.fromLTRB(9, 7, 7, 7),
                        child: const PixelSprite(Sprites.play, scale: 2),
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
