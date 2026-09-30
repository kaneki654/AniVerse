import 'package:flutter/material.dart';
import '../../services/api_service.dart';
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
import 'search_screen.dart';

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
            child: const Text('Update', style: TextStyle(color: Color(0xFFE50914))),
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

  /// Lets the tunnel URL be changed on the device. A free trycloudflare address
  /// is reissued whenever the tunnel restarts, and without this the app would
  /// need rebuilding and reinstalling every time.
  Future<void> _editServer() async {
    final controller = TextEditingController(text: ApiService.host);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Server address', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'https://xxxx.trycloudflare.com',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save', style: TextStyle(color: Color(0xFFE50914))),
          ),
        ],
      ),
    );

    if (saved == null || saved.trim().isEmpty) return;
    await ApiService.setHost(saved);
    if (!mounted) return;
    setState(() => homeData = null);
    _loadData();
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
            sprite: Sprites.search,
            tooltip: 'Search',
            color: Px.ash,
            onPressed: () => Navigator.push(
              context,
              FadeScaleRoute(page: const SearchScreen()),
            ),
          ),
          PixelIconButton(
            sprite: Sprites.gear,
            tooltip: 'Server address',
            color: Px.ash,
            onPressed: _editServer,
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
                const SizedBox(height: 24),
                _buildSection('Trending Now', homeData!['trending']),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: animes.length,
            itemBuilder: (context, index) {
              return PosterCard(
                anime: animes[index] as Map<String, dynamic>,
                width: 130,
                onTap: () => Navigator.push(
                  context,
                  FadeScaleRoute(page: DetailScreen(id: animes[index]['id'].toString()),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
