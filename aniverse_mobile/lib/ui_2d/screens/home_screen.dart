import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/native_bridge.dart';
import '../../services/history_service.dart';
import '../../services/auth_service.dart';
import '../../services/update_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../theme_2d.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/continue_watching.dart';
import '../widgets/hero_spotlight.dart';
import '../widgets/poster_card.dart';
import 'account_screen.dart';
import 'detail_screen.dart';
import 'genres_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? homeData;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkForUpdate();
  }

  /// Offers the newer build published by the server, so a change does not mean
  /// sideloading the APK again.
  Future<void> _checkForUpdate() async {
    final update = await UpdateService.check();
    if (update == null || !mounted) return;

    final sizeMb = ((update['size'] as num?) ?? 0) / (1024 * 1024);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('UPDATE AVAILABLE'),
        content: Text(
          'AniVerse Pixel ${update['versionName']} (build ${update['versionCode']})'
          '${sizeMb > 0 ? ' — ${sizeMb.toStringAsFixed(1)} MB' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Update', style: TextStyle(color: Px.bloodLight)),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await _runUpdate();
  }

  Future<void> _runUpdate() async {
    final progress = ValueNotifier<double?>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Downloading', style: TextStyle(color: Colors.white)),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelBar(fraction: value ?? 0, height: 14),
              const SizedBox(height: 12),
              Text(
                value == null ? '' : '${(value * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    );

    final error = await UpdateService.downloadAndInstall(
      onProgress: (p) => progress.value = p,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _openHistory() => Navigator.push(
        context,
        FadeScaleRoute(page: const HistoryScreen()),
      );

  Future<void> _loadData() async {
    final data = await ApiService.getHomeData();
    setState(() {
      homeData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AniVerseLogo(fontSize: 16),
        centerTitle: true,
        toolbarHeight: 64,
        leading: ValueListenableBuilder<AuthUser?>(
          valueListenable: AuthService.user,
          builder: (context, user, _) {
            void open() => Navigator.push(
                  context,
                  FadeScaleRoute(page: const AccountScreen()),
                );
            if (user == null) {
              return PixelIconButton(
                sprite: Sprites.user,
                tooltip: 'Sign in',
                color: Px.ash,
                onPressed: open,
              );
            }
            return Semantics(
              button: true,
              label: 'Account',
              child: GestureDetector(
                onTap: open,
                child: Center(child: UserAvatar(user: user, size: 30)),
              ),
            );
          },
        ),
        actions: [
          PixelIconButton(
            sprite: Sprites.grid,
            tooltip: 'Genres',
            color: Px.ash,
            onPressed: () => Navigator.push(
              context,
              FadeScaleRoute(page: const GenresScreen()),
            ),
          ),
          PixelIconButton(
            sprite: Sprites.gear,
            tooltip: 'Settings',
            color: Px.ash,
            onPressed: () => Navigator.push(
              context,
              FadeScaleRoute(page: const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: homeData == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // History is local, so it can show while the server answers.
                ContinueWatchingRow(onSeeAll: _openHistory),
                const HeroSkeleton(),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Trending Now'),
                const SectionSkeleton(),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Popular'),
                const SectionSkeleton(),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Latest Episodes'),
                const SectionSkeleton(),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ContinueWatchingRow(onSeeAll: _openHistory),
                HeroSpotlight(
                  animes: (homeData!['trending'] as List<dynamic>?) ?? const [],
                  onTap: (anime) => Navigator.push(
                    context,
                    FadeScaleRoute(
                      page: DetailScreen(id: anime['id'].toString()),
                    ),
                  ),
                ),
                const _BecauseYouWatched(),
                const SizedBox(height: 24),
                _buildSection('Trending Now', homeData!['trending']),
                const _TagalogRow(),
                const SizedBox(height: 24),
                _buildSection('Popular', homeData!['popular']),
                const SizedBox(height: 24),
                _buildSection('Latest Episodes', homeData!['latest']),
              ],
            ),
    );
  }

  Widget _buildSection(String title, List<dynamic>? animes) {
    if (animes == null || animes.isEmpty) return const SizedBox();
    return PosterRow(title: title, animes: animes);
  }
}


/// A titled row of posters. On a TV the posters are bigger, and coming back
/// to the row with the remote lands on the poster last left, not whichever
/// sits nearest the focus coming in.
class PosterRow extends StatefulWidget {
  final String title;
  final List<dynamic> animes;
  const PosterRow({super.key, required this.title, required this.animes});

  @override
  State<PosterRow> createState() => _PosterRowState();
}

class _PosterRowState extends State<PosterRow> {
  final _nodes = <int, FocusNode>{};
  int? _last;

  FocusNode _node(int i) => _nodes.putIfAbsent(i, () {
        final n = FocusNode(debugLabel: '${widget.title} $i');
        n.addListener(() {
          if (n.hasFocus) _last = i;
        });
        return n;
      });

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// The poster focus was on when it last left this row.
  int? _remembered;

  /// Focus came into the row from outside: go to where it was last time.
  void _cameBack() {
    final want = _remembered;
    final target = want == null ? null : _nodes[want];
    final landed = _nodes.entries.where((e) => e.value.hasPrimaryFocus).map((e) => e.key).firstOrNull;
    if (target == null || landed == null || landed == want) return;
    target.requestFocus();
    final ctx = target.context;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 150));
  }

  @override
  Widget build(BuildContext context) {
    final tv = NativeBridge.isTv;
    final width = tv ? 180.0 : 130.0;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        if (has) {
          _cameBack();
        } else {
          _remembered = _last;
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: widget.title),
          SizedBox(
            height: tv ? 290 : 210,
            // Not built lazily: a row is at most a couple of dozen posters, and
            // the remembered one must exist to take focus.
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < widget.animes.length; i++)
                  PosterCard(
                    anime: widget.animes[i] as Map<String, dynamic>,
                    width: width,
                    focusNode: _node(i),
                    onTap: () => Navigator.push(
                      context,
                      FadeScaleRoute(page: DetailScreen(id: widget.animes[i]['id'].toString())),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Because you watched …": AniList's recommendations for the two shows
/// watched most recently, leaving out ones already in the history.
class _BecauseYouWatched extends StatefulWidget {
  const _BecauseYouWatched();

  @override
  State<_BecauseYouWatched> createState() => _BecauseYouWatchedState();
}

class _BecauseYouWatchedState extends State<_BecauseYouWatched> {
  final _rows = <(String, List<dynamic>)>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final recent = HistoryService.latestPerAnime();
    final seen = {for (final e in recent) e.animeId};
    for (final e in recent.take(2)) {
      final x = await ApiService.extra(e.animeId);
      final recs = [
        for (final r in (x['recommendations'] as List? ?? const []))
          if (r is Map && r['id'] != null && !seen.contains(r['id'].toString())) r,
      ];
      if (!mounted) return;
      if (recs.length >= 3) setState(() => _rows.add((e.title.isEmpty ? 'a show' : e.title, recs)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (final (title, recs) in _rows) ...[
        const SizedBox(height: 24),
        PosterRow(title: 'Because you watched $title', animes: recs),
      ],
    ]);
  }
}


/// Tagalog-dubbed anime (app/tagalog.py on the web server).
class _TagalogRow extends StatefulWidget {
  const _TagalogRow();

  @override
  State<_TagalogRow> createState() => _TagalogRowState();
}

class _TagalogRowState extends State<_TagalogRow> {
  List<Map<String, dynamic>> _shows = const [];

  @override
  void initState() {
    super.initState();
    ApiService.tagalogShows().then((s) {
      if (mounted) setState(() => _shows = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_shows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: PosterRow(title: 'Tagalog Dub', animes: _shows),
    );
  }
}
