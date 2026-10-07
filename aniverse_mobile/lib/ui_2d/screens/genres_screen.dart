import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/poster_card.dart';
import 'genre_results_screen.dart';

/// Grid of genres to browse by. Each tile's background is the top-rated anime
/// in that genre, pixelated like the rest of the 2D UI.
class GenresScreen extends StatefulWidget {
  const GenresScreen({super.key});

  @override
  State<GenresScreen> createState() => _GenresScreenState();
}

class _GenresScreenState extends State<GenresScreen> {
  /// Tile colours when there is no art: a stable shade per genre from the
  /// blood palette. Also what shows through before the art arrives.
  static List<Color> get _fills => [Px.bloodDark, Px.panelHigh, Px.blood, Px.bloodDeep, Px.panel];

  /// null while loading; empty when the server had no art to give.
  Map<String, Map<String, dynamic>>? _art;

  @override
  void initState() {
    super.initState();
    ApiService.genreArt().then((art) {
      if (mounted) setState(() => _art = art);
    });
  }

  @override
  Widget build(BuildContext context) {
    const genres = ApiService.genres;

    return Scaffold(
      appBar: AppBar(title: const Text('GENRES')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 16 / 9,
        ),
        itemCount: genres.length,
        itemBuilder: (context, i) {
          final genre = genres[i];
          return _GenreTile(
            genre: genre,
            fill: _fills[i % _fills.length],
            loading: _art == null,
            art: _art?[genre],
            onTap: () => Navigator.push(
              context,
              FadeScaleRoute(page: GenreResultsScreen(genre: genre)),
            ),
          );
        },
      ),
    );
  }
}

class _GenreTile extends StatelessWidget {
  final String genre;
  final Color fill;
  final bool loading;
  final Map<String, dynamic>? art;
  final VoidCallback onTap;

  const _GenreTile({
    required this.genre,
    required this.fill,
    required this.loading,
    required this.art,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = art;
    // Banners are wide like the tile; the portrait cover only when a show has
    // no banner.
    final banner = (a?['banner'] ?? '').toString();
    final url = banner.isNotEmpty ? banner : (a?['cover'] ?? '').toString();
    // A banner is about 4.75:1, so a 16:9 tile shows only its middle third:
    // decode it wide enough that the visible part is still ~65 pixels across
    // -- chunky pixel art, but the show stays recognisable.
    final decodeWidth = banner.isNotEmpty ? 180 : 72;
    final title = (a?['title'] ?? '').toString();
    final score = a?['score'];

    return Semantics(
      button: true,
      label: title.isEmpty ? genre : '$genre. Top rated: $title',
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: PixelBox(
          fill: fill,
          bevel: url.isEmpty,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url.isNotEmpty)
                PixelCover(url: url, decodeWidth: decodeWidth)
              else if (loading)
                const PixelSkeleton(),
              if (url.isNotEmpty)
                // Hard bands, darkest at the bottom where the label sits.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x33050305), Color(0x33050305),
                        Color(0x8C050305), Color(0x8C050305),
                        Color(0xE6050305), Color(0xE6050305),
                      ],
                      stops: [0.0, 0.3, 0.3, 0.58, 0.58, 1.0],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      genre.toUpperCase(),
                      style: PxFont.label(9, height: 1.4).copyWith(shadows: PxFont.outline(1.2)),
                    ),
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          PixelSprite(Sprites.star, scale: 0.9, color: Px.gold),
                          const SizedBox(width: 3),
                          if (score != null)
                            Text('$score ', style: PxFont.label(6, color: Px.gold, height: 1.2)),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PxFont.text(11, color: Px.bone, height: 1.1)
                                  .copyWith(shadows: PxFont.outline(1)),
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
      ),
    );
  }
}
