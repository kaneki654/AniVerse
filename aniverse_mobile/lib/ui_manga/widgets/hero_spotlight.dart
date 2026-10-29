import 'package:flutter/material.dart';

import '../../services/native_bridge.dart';
import '../ink/ink_widgets.dart';
import '../ink/manga.dart';

/// Swipeable spotlight for the top trending shows, as a manga spread: the
/// cover cut into a slanted panel, the title lettered over screentone with
/// focus lines behind it, the episode news in a speech bubble. Turning to the
/// next show flashes the focus lines and jolts the panel; the page number
/// sits under it like a manga page's folio.
class HeroSpotlight extends StatefulWidget {
  const HeroSpotlight({super.key, required this.animes, required this.onTap});

  final List<dynamic> animes;
  final void Function(Map<String, dynamic> anime) onTap;

  @override
  State<HeroSpotlight> createState() => _HeroSpotlightState();
}

class _HeroSpotlightState extends State<HeroSpotlight> {
  static const int _maxSlides = 5;
  late final PageController _controller = PageController();
  int _page = 0;

  List<Map<String, dynamic>> get _slides =>
      widget.animes.whereType<Map<String, dynamic>>().take(_maxSlides).toList(growable: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    if (slides.isEmpty) return const SizedBox();
    return Column(children: [
      SizedBox(
        height: 236,
        child: ImpactShake(
          trigger: _page,
          strength: 4,
          child: PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) {
              Sfx.play('slash');
              setState(() => _page = i);
            },
            itemBuilder: (context, i) => _Slide(
              anime: slides[i],
              flash: i == _page,
              onTap: () => widget.onTap(slides[i]),
            ),
          ),
        ),
      ),
      if (slides.length > 1) ...[
        const SizedBox(height: 10),
        Text('—  ${_page + 1} / ${slides.length}  —', style: MgFont.label(8, color: Mg.gray)),
      ],
    ]);
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.anime, required this.onTap, required this.flash});

  final Map<String, dynamic> anime;
  final VoidCallback onTap;
  final bool flash;

  String get _title {
    final t = anime['title'];
    if (t is Map) {
      for (final k in const ['english', 'romaji']) {
        final v = t[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return 'Untitled';
  }

  String get _cover {
    final c = anime['coverImage'];
    if (c is Map && c['large'] is String) return c['large'] as String;
    return '';
  }

  /// "Ep 5 out now" for an airing show, otherwise the episode count.
  String get _meta {
    final next = anime['nextAiringEpisode'];
    if (next is Map && next['episode'] is num) {
      final aired = (next['episode'] as num).toInt() - 1;
      if (aired > 0) return 'Ep $aired out now!';
    }
    final eps = anime['episodes'];
    if (eps is num && eps > 0) return eps == 1 ? '1 episode' : '${eps.toInt()} episodes';
    final status = anime['status'];
    return status is String ? status.toLowerCase().replaceAll('_', ' ') : '';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 8, 6),
      child: InkPress(
        onTap: onTap,
        child: PanelBox(
          borderWidth: 3,
          shadow: 5,
          child: Stack(fit: StackFit.expand, children: [
            // Screentone ground, and focus lines that flicker as the page lands.
            const CustomPaint(painter: HalftonePainter(from: 0.05, to: 0.3, axis: Axis.horizontal, color: Mg.tone)),
            if (flash && mangaFx != MangaFx.off)
              _FlashLines(key: ValueKey(_title))
            else
              const CustomPaint(painter: FocusLinesPainter(center: Alignment(0.45, 0), seed: 3, count: 60, clear: 0.5,
                  color: Color(0x22121010))),
            // The cover, cut on a slant.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 150,
              child: ClipPath(
                clipper: const _SlantClipper(),
                child: InkCover(url: _cover, decodeWidth: 320),
              ),
            ),
            const Positioned(left: 0, top: 0, bottom: 0, width: 150, child: CustomPaint(painter: _SlantEdgePainter())),
            Positioned(
              left: 144,
              right: 12,
              top: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.rotate(
                    angle: -0.05,
                    child: Container(
                      color: Mg.red,
                      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                      child: Text('SPOTLIGHT', style: MgFont.label(7, color: Mg.white)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: MgFont.heading(19, height: 1.05).copyWith(shadows: MgFont.outline(2, color: Mg.white)),
                  ),
                  const SizedBox(height: 4),
                  if (_meta.isNotEmpty)
                    SpeechBubble(
                      tail: const Alignment(-0.6, 1),
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                      child: Text(_meta, style: MgFont.text(13)),
                    ),
                  const SizedBox(height: 6),
                  InkButton(label: 'Watch now', icon: InkIcons.play, fontSize: 8, onPressed: onTap),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Focus lines that flicker for a moment as a page lands, then fade to a
/// faint pattern.
class _FlashLines extends StatefulWidget {
  const _FlashLines({super.key});

  @override
  State<_FlashLines> createState() => _FlashLinesState();
}

class _FlashLinesState extends State<_FlashLines> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final alpha = (0x22 + (0x99 - 0x22) * (1 - t)).round();
          return CustomPaint(
            painter: FocusLinesPainter(
              center: const Alignment(0.45, 0),
              seed: t < 1 ? (t * 10).floor() : 3,
              count: 60,
              clear: 0.5,
              color: Color.fromARGB(alpha, 0x12, 0x10, 0x10),
            ),
          );
        },
      );
}

/// The cover's panel: straight on the left, its right edge on a slant.
class _SlantClipper extends CustomClipper<Path> {
  const _SlantClipper();

  @override
  Path getClip(Size s) => Path()
    ..lineTo(s.width, 0)
    ..lineTo(s.width - 28, s.height)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _SlantEdgePainter extends CustomPainter {
  const _SlantEdgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - 28, size.height), Paint()
      ..color = Mg.ink
      ..strokeWidth = 3.5);
  }

  @override
  bool shouldRepaint(covariant _SlantEdgePainter oldDelegate) => false;
}

/// Placeholder shaped like the spotlight while the home data loads.
class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const SizedBox(height: 236, child: PanelBox(borderWidth: 3, shadow: 5, child: InkSkeleton())),
        const SizedBox(height: 10),
        Text('—  1 / 5  —', style: MgFont.label(8, color: Mg.grayLight)),
      ]);
}
