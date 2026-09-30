import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/history_service.dart';
import 'ui_2d/app_2d.dart';

/// Which UI the app launches. The classic UI (lib/screens, lib/widgets,
/// lib/theme.dart) is kept unchanged; the 2D pixel-art UI lives in lib/ui_2d.
/// Set to false to ship the classic UI again -- and then, in
/// android/app/src/main/AndroidManifest.xml, set android:label back to
/// "AniVerse" and android:icon back to "@mipmap/ic_launcher", since the
/// launcher name ("AniVerse Pixel") and pixel icon belong to the 2D build.
const bool kUse2DUi = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the saved server address before the first request goes out.
  await ApiService.load();
  // Both are local reads, so "Continue Watching" and the signed-in avatar are
  // there on the first frame; the account check runs in the background.
  await HistoryService.load();
  await AuthService.load();
  runApp(kUse2DUi ? const AniVerse2DApp() : const AniVerseApp());
}

class AniVerseApp extends StatelessWidget {
  const AniVerseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniVerse',
      debugShowCheckedModeBanner: false,
      theme: AniVerseTheme.build(context),
      home: const HomeScreen(),
    );
  }
}
