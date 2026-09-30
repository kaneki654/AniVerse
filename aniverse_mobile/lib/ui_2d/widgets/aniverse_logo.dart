import 'package:flutter/material.dart';

import '../pixel/blood.dart';
import '../pixel/pixel.dart';

/// The ANIVERSE wordmark as sprite text -- arcade face, hard black outline, the
/// pixel-art logo beside it -- with blood dripping off the letters.
class AniVerseLogo extends StatelessWidget {
  final double fontSize;

  /// Blood running off the wordmark. Off where the logo is small or static.
  final bool drips;

  const AniVerseLogo({super.key, this.fontSize = 14, this.drips = true});

  @override
  Widget build(BuildContext context) {
    final word = Text(
      'ANIVERSE',
      style: PxFont.label(fontSize, color: Px.blood, height: 1.2).copyWith(
        shadows: [
          ...PxFont.outline(fontSize / 9),
          // Hard drop shadow: offset, no blur.
          Shadow(color: Px.black, offset: Offset(fontSize / 6, fontSize / 6)),
        ],
      ),
    );
    return Semantics(
      label: 'AniVerse',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The real logo as pixel art, drawn with no smoothing so its
            // pixels stay square at any size.
            Image.asset(
              'assets/icon/aniverse_icon_pixel.png',
              width: 34 * fontSize / 16,
              height: 30 * fontSize / 16,
              filterQuality: FilterQuality.none,
              isAntiAlias: false,
            ),
            SizedBox(width: fontSize * 0.5),
            Stack(
              clipBehavior: Clip.none,
              children: [
                word,
                if (drips)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: fontSize * 1.05,
                    child: BloodDrips(
                      height: fontSize * 1.6,
                      count: 4,
                      seed: 3,
                      cell: (fontSize / 6).clamp(1.5, 4.0),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Page transition in four hard steps instead of a smooth fade: the way a
/// 2D game swaps screens.
class FadeScaleRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeScaleRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) => AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (_, c) => Opacity(
              opacity: ((animation.value * 4).floor() / 4).clamp(0.0, 1.0),
              child: c,
            ),
          ),
        );
}

/// Presses a card down onto its shadow while held, instead of scaling it.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const PressableScale({super.key, required this.child, required this.onTap});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: Transform.translate(
        offset: _down ? const Offset(2, 2) : Offset.zero,
        child: widget.child,
      ),
    );
  }
}
