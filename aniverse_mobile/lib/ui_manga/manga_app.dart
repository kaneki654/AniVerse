import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../services/native_bridge.dart';
import '../services/watchlist_service.dart';
import 'achievements.dart';
import 'ink/ink_widgets.dart';
import 'ink/manga.dart';
import 'intro/manga_intro.dart';
import 'manga_theme.dart';
import 'screens/detail_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mylist_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/search_screen.dart';
import 'screens/watch_screen.dart';
import 'widgets/manga_extras.dart';

/// The manga UI. Everything it draws lives under lib/ui_manga; the services
/// (API, accounts, history, downloads, updates) are shared with the other UIs.
class AniVerseMangaApp extends StatelessWidget {
  /// Completes once the server address is settled and the account loaded;
  /// the screens are built after it, while the intro plays.
  final Future<void>? ready;

  const AniVerseMangaApp({super.key, this.ready});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.effectsChanged,
      builder: (context, _) {
        final scale = AppSettings.textScale;
        return MaterialApp(
          title: 'AniVerse',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          theme: MangaTheme.build(context),
          // Text size from Settings, on top of the system's own.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: _Scaled(mq.textScaler, scale)),
              child: child ?? const SizedBox(),
            );
          },
          home: IntroGate(
            enabled: AppSettings.intro,
            ready: ready,
            child: const PaperBackdrop(child: MangaShell()),
          ),
        );
      },
    );
  }
}

/// The five tabs, and the tab bar under them: a paper strip ruled off in ink,
/// the open tab lettered white on a black caption box that slides over.
class MangaShell extends StatefulWidget {
  const MangaShell({super.key});

  @override
  State<MangaShell> createState() => _MangaShellState();
}

class _MangaShellState extends State<MangaShell> {
  int _tab = 0;

  /// Followed shows with episodes out since they were last looked at.
  final ValueNotifier<int> _fresh = ValueNotifier<int>(0);
  Timer? _alertTimer;

  @override
  void initState() {
    super.initState();
    NativeBridge.onOpenAnime = _openAnime;
    NativeBridge.takeLaunchAnime().then((id) {
      if (id != null && id.isNotEmpty) _openAnime(id);
    });
    // Keep the scheduled check in line with the setting (it is lost on reinstall).
    NativeBridge.scheduleAlerts(AppSettings.alerts);
    HistoryService.changes.addListener(_achievementToasts);
    AuthService.user.addListener(_onAuth);
    if (AuthService.signedIn) WatchlistService.sync();
    Future.delayed(const Duration(seconds: 3), _checkNew);
    _alertTimer = Timer.periodic(const Duration(minutes: 30), (_) => _checkNew());
    WatchlistService.changes.addListener(_recount);
  }

  @override
  void dispose() {
    _alertTimer?.cancel();
    HistoryService.changes.removeListener(_achievementToasts);
    AuthService.user.removeListener(_onAuth);
    WatchlistService.changes.removeListener(_recount);
    super.dispose();
  }

  void _onAuth() {
    if (AuthService.signedIn) WatchlistService.sync(full: true);
  }

  /// A tapped alert: "animeId:episode" plays the new episode, a bare id
  /// (older alerts) opens the show.
  void _openAnime(String alert) {
    final parts = alert.split(':');
    final ep = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final nav = AniVerseMangaApp.navigatorKey.currentState;
    if (ep == null) {
      nav?.push(PageTurnRoute(page: DetailScreen(id: parts[0])));
      return;
    }
    final e = WatchlistService.entry(parts[0]);
    nav?.push(PageTurnRoute(
      backdrop: false,
      page: WatchScreen(animeId: parts[0], epNum: ep, title: e?.title, cover: e?.cover),
    ));
  }

  // The aired counts last fetched, so My List edits recount without refetching.
  final Map<String, int> _aired = {};

  Future<void> _checkNew() async {
    for (final e in WatchlistService.all().take(30)) {
      final info = await ApiService.getAnimeDetails(e.animeId);
      if (info != null) _aired[e.animeId] = airedEpisodes(info);
    }
    _recount();
  }

  void _recount() {
    var n = 0;
    for (final e in WatchlistService.all()) {
      final aired = _aired[e.animeId];
      if (aired != null && e.seenEpisode > 0 && aired > e.seenEpisode) n++;
    }
    _fresh.value = n;
  }

  Future<void> _achievementToasts() async {
    for (final b in await Achievements.newlyUnlocked()) {
      Sfx.play('achieve');
      final ctx = AniVerseMangaApp.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) mangaToast(ctx, 'Achievement unlocked! ${b.name} — ${b.text}');
    }
  }

  void _select(int i) {
    if (_tab == i) return;
    Sfx.play('page');
    setState(() => _tab = i);
  }

  static const _tabs = [
    (InkIcons.home, 'Home'),
    (InkIcons.search, 'Search'),
    (InkIcons.calendar, 'Airing'),
    (InkIcons.bookmark, 'My List'),
    (InkIcons.download, 'Saved'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          HomeScreen(),
          SearchScreen(autofocus: false),
          ScheduleScreen(),
          MyListScreen(),
          DownloadsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Mg.panel,
          border: Border(top: BorderSide(color: Mg.ink, width: 3)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth / _tabs.length;
              return Stack(children: [
                // The caption box marking the open tab, sliding across.
                AnimatedPositioned(
                  duration: Duration(milliseconds: mangaFx == MangaFx.off ? 0 : 240),
                  curve: Curves.easeOutBack,
                  left: w * _tab + 6,
                  top: 7,
                  width: w - 12,
                  height: 50,
                  child: Transform(
                    transform: Matrix4.skewX(-0.12),
                    alignment: Alignment.center,
                    child: const ColoredBox(color: Mg.ink),
                  ),
                ),
                Row(children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: InkFocus(
                        onActivate: () => _select(i),
                        child: Semantics(
                          button: true,
                          selected: _tab == i,
                          label: _tabs[i].$2,
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _select(i),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Stack(clipBehavior: Clip.none, children: [
                                InkIcon(_tabs[i].$1, scale: 2.5, color: _tab == i ? Mg.white : Mg.gray),
                                if (i == 3)
                                  ValueListenableBuilder<int>(
                                    valueListenable: _fresh,
                                    builder: (_, n, __) => n == 0
                                        ? const SizedBox.shrink()
                                        : Positioned(
                                            right: -10,
                                            top: -8,
                                            child: Container(
                                              padding: const EdgeInsets.fromLTRB(5, 1, 5, 1),
                                              decoration: BoxDecoration(
                                                color: Mg.red,
                                                border: Border.all(color: Mg.ink, width: 1.5),
                                              ),
                                              child: Text('$n', style: MgFont.label(6, color: Mg.white, height: 1.2)),
                                            ),
                                          ),
                                  ),
                              ]),
                              const SizedBox(height: 3),
                              Text(_tabs[i].$2.toUpperCase(),
                                  style: MgFont.label(6, color: _tab == i ? Mg.white : Mg.gray, height: 1.1)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

/// The system's text scaling times the app's own (Settings, Text size).
class _Scaled extends TextScaler {
  final TextScaler base;
  final double factor;
  const _Scaled(this.base, this.factor);

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is _Scaled && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
