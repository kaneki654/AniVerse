import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the saved server address before the first request goes out.
  await ApiService.load();
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
