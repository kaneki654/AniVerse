import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'services/api_service.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'services/download_service.dart';
import 'services/error_reporter.dart';
import 'services/history_service.dart';
import 'services/native_bridge.dart';
import 'services/watchlist_service.dart';
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
  // Crashes reach the server's /status page (POST /api/client-errors).
  ErrorReporter.install();
  if (kUse2DUi) {
    // The 2D app's own state: settings (and with them the palette), history,
    // My List, saved episodes, and the line to the Android side -- all local.
    await AppSettings.load();
    await HistoryService.load();
    await WatchlistService.load();
    await DownloadService.load();
    NativeBridge.init();
    await NativeBridge.detectTv();
    // The server address is checked while the logo intro plays: ruling out a
    // dead saved address can take seconds, and used to be a black screen.
    final ready = ApiService.load().then((_) => AuthService.load());
    runApp(AniVerse2DApp(ready: ready));
    return;
  }
  // Load the saved server address before the first request goes out.
  await ApiService.load();
  // Both are local reads, so "Continue Watching" and the signed-in avatar are
  // there on the first frame; the account check runs in the background.
  await HistoryService.load();
  await AuthService.load();
  // Shared with the 2D UI: settings, My List, saved episodes, the Android side
  // (lib/classic_plus has the classic screens for them).
  await AppSettings.load();
  await WatchlistService.load();
  await DownloadService.load();
  NativeBridge.init();
  runApp(const AniVerseApp());
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
