import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/aniverse_logo.dart';
import '../theme.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/poster_card.dart';
import 'detail_screen.dart';

/// Paged poster grid for one genre, loading more as you reach the bottom.
class GenreResultsScreen extends StatefulWidget {
  final String genre;

  const GenreResultsScreen({super.key, required this.genre});

  @override
  State<GenreResultsScreen> createState() => _GenreResultsScreenState();
}

class _GenreResultsScreenState extends State<GenreResultsScreen> {
  static const int _perPage = 24;

  final ScrollController _scroll = ScrollController();
  final List<dynamic> _items = [];
  final Set<int> _seenIds = {};

  int _page = 1;
  bool _loading = false;
  bool _end = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _end) return;
    // Start the next page before the user actually hits the bottom.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _end) return;
    setState(() => _loading = true);

    final batch = await ApiService.byGenre(widget.genre, page: _page, perPage: _perPage);
    if (!mounted) return;

    // The API can repeat entries across pages; a duplicate id would trip
    // Flutter's key handling and show the same poster twice.
    final fresh = <dynamic>[];
    for (final item in batch) {
      final id = (item is Map && item['id'] is num) ? (item['id'] as num).toInt() : null;
      if (id == null || _seenIds.contains(id)) continue;
      _seenIds.add(id);
      fresh.add(item);
    }

    setState(() {
      _items.addAll(fresh);
      _loading = false;
      _page += 1;
      // A short page means the source is exhausted.
      if (batch.length < _perPage) _end = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AniVerseTheme.bg,
      appBar: AppBar(
        title: Text(
          widget.genre.toUpperCase(),
          style: const TextStyle(color: AniVerseTheme.red, fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: _items.isEmpty && _loading
          ? const AniVerseLoadingScreen(label: 'LOADING')
          : _items.isEmpty
              ? const Center(
                  child: Text('Nothing found', style: TextStyle(color: AniVerseTheme.textFaint)))
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.58,
                  ),
                  // One extra cell carries the "loading more" spinner.
                  itemCount: _items.length + (_loading ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _items.length) {
                      return const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: AniVerseLoader(size: 24),
                        ),
                      );
                    }

                    final anime = _items[i] as Map<String, dynamic>;
                    return PosterCard(
                      anime: anime,
                      onTap: () => Navigator.push(
                        context,
                        FadeScaleRoute(page: DetailScreen(id: anime['id'].toString()),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
