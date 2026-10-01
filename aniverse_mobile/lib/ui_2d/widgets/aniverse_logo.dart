import 'package:flutter/material.dart';

import '../pixel/blood.dart';
import '../pixel/fx.dart';
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
    final step = fontSize / 4;
    final word = Text(
      'ANIVERSE',
      style: PxFont.label(fontSize, color: Px.blood, height: 1.2).copyWith(
        shadows: [
          ...PxFont.outline(fontSize / 9),
          // Hard drop shadow: offset, no blur.
          Shadow(color: Px.black, offset: Offset(fontSize / 6, fontSize / 6)),
          // Bloom: red copies a step out on each side -- a blocky glow.
          for (final o in [Offset(-step, 0), Offset(step, 0), Offset(0, -step), Offset(0, step)])
            Shadow(color: const Color(0x47D10A1A), offset: o),
        ],
      ),
    );
    // A light band sweeps across the letters every few seconds.
    final shiny = FrameClock(
      fps: 12,
      frames: 84,
      builder: (_, f) {
        final g = glintAt(f, frames: 84, sweep: 20);
        if (g < 0) return word;
        return Stack(
          children: [
            word,
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: const [Color(0x00FFFFFF), Color(0xD9FFECD2), Color(0xD9FFECD2), Color(0x00FFFFFF)],
                stops: [g - 0.08, g - 0.08, g, g].map((v) => v.clamp(0.0, 1.0)).toList(),
              ).createShader(r),
              child: Text('ANIVERSE', style: PxFont.label(fontSize, color: Colors.white, height: 1.2)),
            ),
          ],
        );
      },
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
                shiny,
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

/// Page transition as a Bayer-dither dissolve in five steps: the new screen
/// breaks out of square black cells (and back into them when it closes), the
/// way a 16-bit game swaps screens. The name is kept from the fade it replaced.
///
/// [backdrop] puts the screen on the ember backdrop; the player turns it off,
/// so nothing animates behind the video.
class FadeScaleRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadeScaleRoute({required this.page, bool backdrop = true})
      : super(
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (_, __, ___) => backdrop ? PixelBackdrop(child: page) : page,
          transitionsBuilder: (context, animation, __, child) {
            if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
            return AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (_, c) {
                final shown = ((animation.value * 5).floor() / 5).clamp(0.0, 1.0);
                if (shown >= 1) return c!;
                return Stack(
                  fit: StackFit.passthrough,
                  children: [
                    c!,
                    Positioned.fill(
                      child: IgnorePointer(child: CustomPaint(painter: DitherCover(1 - shown))),
                    ),
                  ],
                );
              },
            );
          },
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
