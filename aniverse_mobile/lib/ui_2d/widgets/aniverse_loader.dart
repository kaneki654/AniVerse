import 'package:flutter/material.dart';

import '../pixel/blood.dart';

/// The 2D loader: the katana slash sprite animation (see [KatanaLoader]).
///
/// Kept under the classic loader's name so every screen that waits on the
/// server shows it without further changes.
class AniVerseLoader extends StatelessWidget {
  final double size;
  final String? label;

  const AniVerseLoader({super.key, this.size = 64, this.label});

  @override
  Widget build(BuildContext context) {
    // The classic loader was a 64-72px ring; the sprite needs room for the
    // swing and the blood, so it is drawn at about twice that.
    return KatanaLoader(size: (size * 2.1).clamp(110.0, 170.0), label: label);
  }
}

/// Full-screen loading state.
class AniVerseLoadingScreen extends StatelessWidget {
  final String? label;

  const AniVerseLoadingScreen({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(child: AniVerseLoader(size: 72, label: label));
  }
}
