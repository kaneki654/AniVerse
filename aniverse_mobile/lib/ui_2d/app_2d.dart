import 'package:flutter/material.dart';

import 'pixel/fx.dart';
import 'screens/home_screen.dart';
import 'theme_2d.dart';

/// The 2D pixel-art UI. Everything it draws lives under lib/ui_2d; the
/// services (API, accounts, history, updates) are shared with the classic UI.
class AniVerse2DApp extends StatelessWidget {
  const AniVerse2DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniVerse Pixel',
      debugShowCheckedModeBanner: false,
      theme: AniVerseTheme.build(context),
      home: const PixelBackdrop(child: HomeScreen()),
    );
  }
}
