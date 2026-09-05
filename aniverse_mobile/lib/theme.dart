import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One place for the AniVerse palette, so screens stop hard-coding hex values.
class AniVerseTheme {
  static const Color red = Color(0xFFE50914);
  static const Color redDark = Color(0xFF8E0610);
  static const Color bg = Color(0xFF0E0E0E);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceHigh = Color(0xFF242424);
  // Skeletons must sit clearly above the background or the loading state looks
  // like an empty screen.
  static const Color skeleton = Color(0xFF262626);
  static const Color skeletonHigh = Color(0xFF3D3D3D);
  static const Color textDim = Colors.white54;
  static const Color textFaint = Colors.white38;

  /// Scrim laid over poster art so titles stay readable on bright images.
  static const LinearGradient posterScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000)],
    stops: [0.45, 1.0],
  );

  static ThemeData build(BuildContext context) {
    final base = ThemeData(brightness: Brightness.dark);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      primaryColor: red,
      colorScheme: const ColorScheme.dark(
        primary: red,
        secondary: red,
        surface: surface,
      ),
      textTheme: GoogleFonts.orbitronTextTheme(
        base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: surface),
      snackBarTheme: const SnackBarThemeData(backgroundColor: surfaceHigh),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: red),
    );
  }
}

/// Section heading with the red accent bar used across the app.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;

  const SectionHeader({super.key, required this.title, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 22,
            decoration: BoxDecoration(
              color: AniVerseTheme.red,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              child: const Text('More', style: TextStyle(color: AniVerseTheme.red)),
            ),
        ],
      ),
    );
  }
}
