import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/hero_spotlight.dart';
import '../widgets/poster_card.dart';
import 'detail_screen.dart';
import 'genres_screen.dart';
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
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Update available', style: TextStyle(color: Colors.white)),
        content: Text(
          'Version ${update['versionName']} (build ${update['versionCode']})'
          '${sizeMb > 0 ? ' — ${sizeMb.toStringAsFixed(1)} MB' : ''}',
          style: const TextStyle(color: Colors.white70),
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
              LinearProgressIndicator(
                value: value,
                color: AniVerseTheme.red,
                backgroundColor: Colors.white12,
              ),
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
        title: const AniVerseLogo(fontSize: 22),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined, color: Colors.white70),
            tooltip: 'Genres',
            onPressed: () => Navigator.push(
              context,
              FadeScaleRoute(page: const GenresScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white70),
            tooltip: 'Search',
            onPressed: () => Navigator.push(
              context,
              FadeScaleRoute(page: const SearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            tooltip: 'Server address',
            onPressed: _editServer,
          ),
        ],
      ),
      body: homeData == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                HeroSkeleton(),
                SizedBox(height: 24),
                SectionHeader(title: 'Trending Now'),
                SectionSkeleton(),
                SizedBox(height: 24),
                SectionHeader(title: 'Popular'),
                SectionSkeleton(),
                SizedBox(height: 24),
                SectionHeader(title: 'Latest Episodes'),
                SectionSkeleton(),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
