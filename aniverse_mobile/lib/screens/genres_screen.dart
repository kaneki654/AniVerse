import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/aniverse_logo.dart';
import 'genre_results_screen.dart';

/// Grid of genres to browse by.
class GenresScreen extends StatelessWidget {
  const GenresScreen({super.key});

  static const Color _accent = Color(0xFFE50914);

  /// A stable hue per genre so the grid reads as varied without being random
  /// between builds. Tinted toward the app's red rather than a rainbow.
  Color _tileColor(int index) {
    const palette = [
      Color(0xFF7F1220), Color(0xFF8E1B2E), Color(0xFF5C1020),
      Color(0xFF9B2226), Color(0xFF6A040F), Color(0xFF370617),
    ];
    return palette[index % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    const genres = ApiService.genres;

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        title: const Text(
          'GENRES',
          style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 16 / 9,
        ),
        itemCount: genres.length,
        itemBuilder: (context, i) {
          final genre = genres[i];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(
              context,
              FadeScaleRoute(page: GenreResultsScreen(genre: genre)),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_tileColor(i), const Color(0xFF141414)],
                ),
                border: Border.all(color: Colors.white10),
              ),
              padding: const EdgeInsets.all(12),
              alignment: Alignment.bottomLeft,
              child: Text(
                genre,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
