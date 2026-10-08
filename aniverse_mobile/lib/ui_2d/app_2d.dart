import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../services/native_bridge.dart';
import '../services/watchlist_service.dart';
import 'achievements.dart';
import 'intro/logo_intro.dart';
import 'intro/palette_transition.dart';
import 'pixel/fx.dart';
import 'pixel/pixel.dart';
import 'pixel/pixel_widgets.dart';
import 'pixel/sprites.dart';
import 'pixel/theme_fx.dart';
import 'screens/detail_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mylist_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/search_screen.dart';
import 'theme_2d.dart';
import 'widgets/aniverse_logo.dart';
import 'widgets/pixel_extras.dart';

/// The 2D pixel-art UI. Everything it draws lives under lib/ui_2d; the
/// services (API, accounts, history, updates) are shared with the classic UI.
///
/// The palette (Settings) is applied by rebuilding the whole tree under a new
/// key: every widget then picks the new colours up from [Px].
class AniVerse2DApp extends StatelessWidget {
  /// Completes once the server address is settled and the account loaded;
  /// the screens are built after it, while the intro plays.
  final Future<void>? ready;

  const AniVerse2DApp({super.key, this.ready});

  // New keys for each palette: a kept Navigator would keep its screens, and
  // their unchanged widgets would never repaint in the new colours.
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static String? _builtTheme;

  @override
  Widget build(BuildContext context) {
    // The palette-switch animation sits above the whole app, outside
    // MaterialApp, so it carries on over the rebuild the switch causes.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListenableBuilder(
            listenable: Listenable.merge(
                [AppSettings.theme, AppSettings.effectsChanged]),
            builder: (context, _) {
              final theme = AppSettings.theme.value;
              Px.apply(theme);
              setFxLevel(AppSettings.effects);
              final look = '$theme/${AppSettings.effects}';
              if (_builtTheme != null && _builtTheme != look) {
                navigatorKey = GlobalKey<NavigatorState>();
                messengerKey = GlobalKey<ScaffoldMessengerState>();
              }
              _builtTheme = look;
              return MaterialApp(
                key: ValueKey(look),
                title: 'AniVerse Pixel',
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                scaffoldMessengerKey: messengerKey,
                theme: AniVerseTheme.build(context),
                home: IntroGate(
                    enabled: AppSettings.intro,
                    ready: ready,
                    child: const PixelBackdrop(child: MainShell())),
              );
            },
          ),
          const PaletteTransitionLayer(),
        ],
      ),
    );
  }
}

/// The five tabs and the pixel tab bar under them.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
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
    _alertTimer =
        Timer.periodic(const Duration(minutes: 30), (_) => _checkNew());
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

  void _openAnime(String id) {
    AniVerse2DApp.navigatorKey.currentState
        ?.push(FadeScaleRoute(page: DetailScreen(id: id)));
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
      AniVerse2DApp.messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text('Achievement unlocked: ${b.name} — ${b.text}'),
        duration: const Duration(seconds: 6),
        persist: false,
      ));
    }
  }

  void _select(int i) {
    if (_tab == i) return;
    Sfx.play('click');
    setState(() => _tab = i);
  }

  static const _tabs = [
    (Sprites.home, 'Home'),
    (Sprites.search, 'Search'),
    (Sprites.calendar, 'Airing'),
    (Sprites.bookmark, 'My List'),
    (Sprites.download, 'Saved'),
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
        decoration: BoxDecoration(
          color: Px.ink,
          border: Border(top: BorderSide(color: Px.blood, width: 2)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: PixelFocus(
                      onActivate: () => _select(i),
                      child: Semantics(
                        button: true,
                        selected: _tab == i,
                        label: _tabs[i].$2,
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _select(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  PixelSprite(_tabs[i].$1,
                                      scale: 2.2,
                                      color:
                                          _tab == i ? Px.bloodLight : Px.ash),
                                  if (i == 3)
                                    ValueListenableBuilder<int>(
                                      valueListenable: _fresh,
                                      builder: (_, n, __) => n == 0
                                          ? const SizedBox.shrink()
                                          : Positioned(
                                              right: -7,
                                              top: -5,
                                              child: PixelBox(
                                                fill: Px.blood,
                                                shadow: 0,
                                                borderWidth: 1,
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        3, 2, 2, 1),
                                                child: Text('$n',
                                                    style: PxFont.label(5,
                                                        height: 1.2)),
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(_tabs[i].$2.toUpperCase(),
                                  style: PxFont.label(6,
                                      color: _tab == i ? Px.bone : Px.ash,
                                      height: 1.2)),
                            ],
                          ),
                        ),
                      ),
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
