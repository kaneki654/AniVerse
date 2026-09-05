import 'package:flutter/material.dart';

import '../theme.dart';

/// The ANIVERSE wordmark with a soft red bloom behind it.
///
/// Plain red text on near-black reads flat; the glow is what makes it look lit
/// rather than printed, and it sets the tone the rest of the theme follows.
class AniVerseLogo extends StatelessWidget {
  final double fontSize;

  const AniVerseLogo({super.key, this.fontSize = 24});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Bloom layer: same glyphs, blurred, sitting behind the crisp text.
        Text(
          'ANIVERSE',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            foreground: Paint()
              ..color = AniVerseTheme.red
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
          ),
        ),
        Text(
          'ANIVERSE',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: AniVerseTheme.red,
            shadows: const [
              Shadow(color: Color(0x99E50914), blurRadius: 18),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fade-through page transition, so navigation feels deliberate instead of the
/// default platform slide.
class FadeScaleRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeScaleRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeIn,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// Scales a card down slightly while pressed, so taps feel physical.
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
      child: AnimatedScale(
        scale: _down ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
