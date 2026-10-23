import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/native_bridge.dart';
import '../ink/ink_widgets.dart';
import '../ink/manga.dart';

/// The manga UI's opening, about four seconds, tap to skip:
///
/// 1. A blank page; three panel borders ink themselves in.
/// 2. The panels come alive -- speed lines racing through one, screentone
///    sweeping across another, ゴゴゴ rumbling in the third.
/// 3. An impact frame: the page flashes to negative.
/// 4. One big panel: focus lines converge and the AniVerse emblem is inked in
///    stage by stage (line art, screentone, red) as it lands with a ドン!
/// 5. ANIVERSE slams in letter by letter on a caption strip.
/// 6. The page turns over onto the app.
class MangaIntro extends StatefulWidget {
  final VoidCallback onDone;
  const MangaIntro({super.key, required this.onDone});

  @override
  State<MangaIntro> createState() => _MangaIntroState();
}

class _MangaIntroState extends State<MangaIntro> with SingleTickerProviderStateMixin {
  static const _ms = 4300;
  static const _still = 0.83; // where the finished logo stands, for "effects off"
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: _ms));
  bool _done = false;
  final Set<String> _played = {};

  @override
  void initState() {
    super.initState();
    _c.addListener(_cues);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    if (mangaFx == MangaFx.off) {
      _holdStill();
    } else {
      _c.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if ((MediaQuery.maybeDisableAnimationsOf(context) ?? false) && _c.isAnimating) _holdStill();
  }

  void _holdStill() {
    _c.stop();
    _c.value = _still;
    Future.delayed(const Duration(milliseconds: 900), _finish);
  }

  /// Sounds on their beats, once each.
  void _cues() {
    if (!_c.isAnimating) return;
    final t = _c.value * _ms;
    void at(double ms, String name) {
      if (t >= ms && _played.add('$name@$ms')) Sfx.play(name);
    }

    at(40, 'page');
    at(1480, 'hit');
    at(2050, 'don');
    at(2900, 'slash');
    at(3700, 'page');
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0..1 progress of a beat between [a] and [b] milliseconds.
  double _beat(double a, double b) => ((_c.value * _ms - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    // Material under it (lettering outside one gets Flutter's debug
    // underline), see-through: the page turn at the end shows the app.
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Semantics(
        label: 'AniVerse',
        button: true,
        onTap: _finish,
        excludeSemantics: true,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final ms = _c.value * _ms;
            final page = ms < 1450 ? _threePanels() : (ms < 1640 ? _impactFrame(ms) : _logoPanel(ms));
            // The page turns over at the end.
            final turn = Curves.easeInCubic.transform(_beat(3650, 4300));
            if (turn <= 0) return page;
            return Stack(fit: StackFit.expand, children: [
              ClipPath(clipper: _TurnClipper(turn), child: page),
              CustomPaint(painter: _TurnEdgePainter(turn)),
            ]);
          },
        ),
      ),
      ),
    );
  }

  // --- 1-2: three panels -------------------------------------------------------------------------

  Widget _threePanels() {
    final draw = Curves.easeOut.transform(_beat(80, 700));
    final life = _beat(600, 1450);
    return ColoredBox(
      color: Mg.paper,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest;
        final panels = _panelRects(s);
        return Stack(children: [
          // Panel 1: speed lines racing.
          if (life > 0)
            Positioned.fromRect(
              rect: panels[0],
              child: ClipRect(child: CustomPaint(painter: SpeedStreakPainter(phase: life * 1.6, angle: -0.08))),
            ),
          // Panel 2: screentone sweeping in from the left.
          if (life > 0)
            Positioned.fromRect(
              rect: panels[1],
              child: ClipPath(
                clipper: _Slanted(left: true),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: life,
                    heightFactor: 1,
                    child: const CustomPaint(painter: HalftonePainter(from: 0.7, to: 0.15, axis: Axis.horizontal)),
                  ),
                ),
              ),
            ),
          // Panel 3: ゴゴゴ.
          if (life > 0.1)
            Positioned.fromRect(
              rect: panels[2],
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.only(left: 18.0 * i),
                    child: SfxText('ゴ', size: s.shortestSide * 0.12, delay: Duration(milliseconds: 140 * i)),
                  ),
              ]),
            ),
          // The borders, inked in stroke by stroke.
          Positioned.fill(child: CustomPaint(painter: _BordersPainter(panels, draw))),
        ]);
      }),
    );
  }

  /// Three panels inside a page's margins: one wide on top, two below split
  /// by a slanted gutter.
  static List<Rect> _panelRects(Size s) {
    final m = s.width * 0.06;
    final top = s.height * 0.12;
    final split = s.height * 0.5;
    final bottom = s.height * 0.86;
    return [
      Rect.fromLTRB(m, top, s.width - m, split - m / 2),
      Rect.fromLTRB(m, split + m / 2, s.width * 0.56, bottom),
      Rect.fromLTRB(s.width * 0.44 + m, split + m / 2, s.width - m, bottom),
    ];
  }

  // --- 3: the impact frame -------------------------------------------------------------------

  Widget _impactFrame(double ms) {
    // Two drawings: negative (white lines on black), then a white flash.
    final negative = ms < 1560;
    return ColoredBox(
      color: negative ? Mg.ink : Mg.white,
      child: negative
          ? const CustomPaint(painter: FocusLinesPainter(seed: 9, count: 120, clear: 0.2, color: Mg.white))
          : null,
    );
  }

  // --- 4-5: the logo lands ----------------------------------------------------------------------

  Widget _logoPanel(double ms) {
    final lines = _beat(1640, 1950);
    final tone = _beat(1900, 2100);
    final red = _beat(2050, 2350);
    final word = _beat(2850, 3350);
    final underline = _beat(3300, 3550);
    final flicker = ((ms - 1640) / 70).floor();
    return ColoredBox(
      color: Mg.paper,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest;
        final size = s.shortestSide * 0.56;
        final land = Curves.elasticOut.transform(red);
        final shake = red > 0 && red < 0.6 ? 8 * (1 - red / 0.6) : 0.0;
        final emblem = SizedBox(
          width: size,
          height: size,
          child: Stack(fit: StackFit.expand, children: [
            if (red > 0)
              Transform.scale(
                scale: 1.35 - 0.35 * land,
                child: Opacity(opacity: red, child: Image.asset('assets/manga/logo_color.png')),
              ),
            Opacity(opacity: tone, child: Image.asset('assets/manga/logo_tone.png')),
            // Line art, drawn top to bottom.
            ClipRect(clipper: _Reveal(lines), child: Image.asset('assets/manga/logo_lines.png')),
          ]),
        );
        return Stack(children: [
          // Focus lines converging, redrawn every few frames like limited animation.
          Positioned.fill(
            child: CustomPaint(
              painter: FocusLinesPainter(
                center: const Alignment(0, -0.18),
                seed: ms < 2400 ? flicker : 3,
                count: 110,
                clear: 0.33,
                color: Mg.ink.withValues(alpha: ms < 2400 ? 1 : 0.85),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.18),
            child:
                Transform.translate(offset: Offset(wobble(flicker, shake), wobble(flicker + 7, shake)), child: emblem),
          ),
          if (red > 0.15)
            Align(
              alignment: const Alignment(0.82, -0.62),
              child: SfxText('ドン!', size: s.shortestSide * 0.15, color: Mg.red, angle: 0.18),
            ),
          if (word > 0)
            Align(
              alignment: const Alignment(0, 0.55),
              child: _Wordmark(progress: word, underline: underline, size: s.shortestSide * 0.12),
            ),
        ]);
      }),
    );
  }
}

/// ANIVERSE on a black caption strip, the letters slamming down one after
/// another, then a red brush stroke underneath.
class _Wordmark extends StatelessWidget {
  final double progress;
  final double underline;
  final double size;
  const _Wordmark({required this.progress, required this.underline, required this.size});

  @override
  Widget build(BuildContext context) {
    const word = 'ANIVERSE';
    final letters = <Widget>[];
    for (var i = 0; i < word.length; i++) {
      final t = ((progress * (word.length + 3) - i) / 3).clamp(0.0, 1.0);
      final land = Curves.easeOutBack.transform(t);
      letters.add(Opacity(
        opacity: t > 0 ? 1 : 0,
        child: Transform.translate(
          offset: Offset(0, -size * 1.4 * (1 - land)),
          child: Transform.rotate(
            angle: (i.isEven ? -0.25 : 0.25) * (1 - land),
            child: Text(word[i], style: MgFont.heading(size, color: Mg.white, height: 1)),
          ),
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Transform(
        transform: Matrix4.skewX(-0.14),
        alignment: Alignment.center,
        child: Container(
          color: Mg.ink,
          padding: EdgeInsets.fromLTRB(size * 0.4, size * 0.12, size * 0.5, size * 0.12),
          child: Row(mainAxisSize: MainAxisSize.min, children: letters),
        ),
      ),
      SizedBox(height: size * 0.18),
      SizedBox(width: size * 6, height: size * 0.28, child: CustomPaint(painter: _UnderlinePainter(underline))),
    ]);
  }
}

/// A red brush stroke drawn left to right by [t]: thick, thinning at the end.
class _UnderlinePainter extends CustomPainter {
  final double t;
  _UnderlinePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final w = size.width * t;
    final h = size.height;
    canvas.drawPath(
        Path()
          ..moveTo(0, h * 0.25)
          ..quadraticBezierTo(w * 0.5, 0, w, h * 0.45)
          ..lineTo(w * 0.96, h * 0.6)
          ..quadraticBezierTo(w * 0.5, h * 0.75, 0, h * 0.85)
          ..close(),
        Paint()..color = Mg.red);
  }

  @override
  bool shouldRepaint(covariant _UnderlinePainter old) => old.t != t;
}

/// Panel borders inked in: each border's outline drawn along its length as
/// [t] runs 0..1, staggered so the strokes follow one another.
class _BordersPainter extends CustomPainter {
  final List<Rect> panels;
  final double t;
  _BordersPainter(this.panels, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Mg.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square;
    for (var i = 0; i < panels.length; i++) {
      final local = ((t * 1.6) - i * 0.3).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final path = i == 0 ? (Path()..addRect(panels[i])) : _Slanted.path(panels[i], left: i == 1);
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * local), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BordersPainter old) => old.t != t;
}

/// The lower panels share a slanted gutter: the left one's right edge and the
/// right one's left edge lean the same way.
class _Slanted extends CustomClipper<Path> {
  final bool left;
  _Slanted({required this.left});

  static Path path(Rect r, {required bool left}) {
    const lean = 40.0;
    return left
        ? (Path()
          ..moveTo(r.left, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right - lean, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close())
        : (Path()
          ..moveTo(r.left, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left - lean, r.bottom)
          ..close());
  }

  @override
  Path getClip(Size s) => path(Offset.zero & s, left: left);

  @override
  bool shouldReclip(covariant _Slanted old) => false;
}

/// Shows the top [t] of the child: line art being drawn downwards.
class _Reveal extends CustomClipper<Rect> {
  final double t;
  _Reveal(this.t);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height * t);

  @override
  bool shouldReclip(covariant _Reveal old) => old.t != t;
}

/// Where the turning fold is: off the right edge at t = 0, past the left at 1.
(Offset, Offset) _fold(Size s, double t) {
  final slant = s.width * 0.4;
  final x = s.width + slant - t * (s.width + 2 * slant);
  return (Offset(x + slant, 0), Offset(x, s.height));
}

/// The page turning over at the end: what is left of the intro page, on the
/// near side of a slanted fold sweeping right to left.
class _TurnClipper extends CustomClipper<Path> {
  final double t;
  _TurnClipper(this.t);

  @override
  Path getClip(Size s) {
    final (top, bottom) = _fold(s, t);
    return Path()
      ..moveTo(0, 0)
      ..lineTo(math.max(0, top.dx), 0)
      ..lineTo(math.max(0, bottom.dx), s.height)
      ..lineTo(0, s.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _TurnClipper old) => old.t != t;
}

class _TurnEdgePainter extends CustomPainter {
  final double t;
  _TurnEdgePainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final (top, bottom) = _fold(s, t);
    // The underside of the turning page: a band of white with screentone.
    canvas.save();
    canvas.clipPath(Path()
      ..moveTo(top.dx, 0)
      ..lineTo(top.dx + 60, 0)
      ..lineTo(bottom.dx + 60, s.height)
      ..lineTo(bottom.dx, s.height)
      ..close());
    canvas.drawRect(Offset.zero & s, Paint()..color = Mg.white);
    const HalftonePainter(from: 0.4, spacing: 6).paint(canvas, s);
    canvas.restore();
    canvas.drawLine(top, bottom, Paint()
      ..color = Mg.ink
      ..strokeWidth = 4);
  }

  @override
  bool shouldRepaint(covariant _TurnEdgePainter old) => old.t != t;
}

/// Shows the intro once per launch over the app while the server address is
/// checked ([ready]), then the app. Without the intro, a brush circle waits.
class IntroGate extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Future<void>? ready;
  const IntroGate({super.key, required this.child, required this.enabled, this.ready});

  /// Once per launch: switching looks rebuilds the app, and must not replay it.
  static bool _played = false;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  late bool _show;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _show = widget.enabled && !IntroGate._played;
    IntroGate._played = true;
    final r = widget.ready;
    if (r == null) {
      _ready = true;
    } else {
      // A failure to load is still "ready": the screens handle an unreachable server.
      r.whenComplete(() {
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      if (_ready)
        widget.child
      else if (!_show)
        const ColoredBox(color: Mg.paper, child: Center(child: SizedBox(width: 64, height: 64, child: InkSpinner()))),
      if (_show) Positioned.fill(child: MangaIntro(onDone: () => setState(() => _show = false))),
    ]);
  }
}
