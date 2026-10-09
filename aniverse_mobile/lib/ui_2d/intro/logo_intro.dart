import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/native_bridge.dart';
import '../pixel/blood.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/theme_fx.dart';
import 'logo_sprite.dart';

part 'intro_blood.dart';
part 'intro_gameboy.dart';
part 'intro_neon.dart';
part 'intro_sakura.dart';
part 'intro_samurai.dart';

/// The intro that plays as the app opens: the AniVerse emblem, as pixel art,
/// brought into the world in the style of the palette picked in Settings.
///
///  - Blood (intro_blood.dart): a katana cuts the dark, the pixels fly in
///    white-hot, blood splatters, ANIVERSE is stamped in, blood drips.
///  - Neon cyber (intro_neon.dart): a CRT powers on, a boot log types out,
///    the emblem is scanned in line by line, a glitch hits with a colour
///    split and sparks, the sign flickers like neon, a scanline wipe out.
///  - Sakura (intro_sakura.dart): one petal falls, the emblem blooms out
///    from where it lands, a gust of petals, letters fade in with sparkles,
///    a petal storm sweeps it away.
///  - Game Boy (intro_gameboy.dart): the emblem scrolls down the LCD and
///    stops with a ding, ANIVERSE types in, blocks fall, the screen fades
///    through its greens and redraws onto the app.
///  - Gold samurai (intro_samurai.dart): a vermilion ensō brushed round, the
///    emblem gilded into it, a gong, gold leaf, a sword cut to open.
///
/// Everything is drawn one art cell at a time and moves in whole frames at
/// 24 fps, never interpolated, so it reads as sprite animation. Tap to skip.
class LogoIntro extends StatefulWidget {
  final VoidCallback onDone;
  const LogoIntro({super.key, required this.onDone});

  @override
  State<LogoIntro> createState() => _LogoIntroState();
}

const _fps = 24;

/// One palette's intro: how long it runs, what sounds when, how it looks.
abstract class _Scene {
  /// Frames in all.
  int get end;

  /// Where the way out (onto the app) starts; a tap skips to it.
  int get exit;

  /// Sound effects, by the frame they play on.
  Map<int, String> get sounds;

  /// Haptic bumps by frame: 1 light, 2 medium, 3 heavy.
  Map<int, int> get haptics;

  /// Draws frame [f]. The canvas is a layer over the app: painting it with
  /// BlendMode.clear shows the app through.
  void paint(Canvas canvas, _Stage st, int f);
}

_Scene _sceneFor(FxStyle style) => switch (style) {
      FxStyle.neon => _NeonScene(),
      FxStyle.sakura => _SakuraScene(),
      FxStyle.gameboy => _GameBoyScene(),
      FxStyle.samurai => _SamuraiScene(),
      FxStyle.blood => _BloodScene(),
    };

class _LogoIntroState extends State<LogoIntro> with SingleTickerProviderStateMixin {
  late final _Scene _scene = _sceneFor(fxStyle);
  late final AnimationController _c;
  int _frame = -1;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_scene.end * 1000 / _fps).round()),
    )
      ..addListener(_tick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _finish();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Reduced motion: no animation at all, straight to the app.
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return _finish();
      _c.forward();
    });
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  void _tick() {
    final f = (_c.value * _scene.end).floor().clamp(0, _scene.end - 1);
    if (f == _frame) return;
    final last = _frame;
    // Frames can be dropped under load; every cue between the last frame drawn
    // and this one still fires.
    for (final MapEntry(key: at, value: name) in _scene.sounds.entries) {
      if (last < at && f >= at) Sfx.play(name);
    }
    for (final MapEntry(key: at, value: kind) in _scene.haptics.entries) {
      if (last < at && f >= at) {
        switch (kind) {
          case 3:
            HapticFeedback.heavyImpact();
          case 2:
            HapticFeedback.mediumImpact();
          default:
            HapticFeedback.lightImpact();
        }
      }
    }
    setState(() => _frame = f);
  }

  void _skip() {
    if (_frame < _scene.exit) _c.forward(from: _scene.exit / _scene.end);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AniVerse. Tap to skip the intro.',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: SizedBox.expand(
          child: CustomPaint(painter: _ScenePainter(_scene, math.max(0, _frame))),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final _Scene scene;
  final int f;
  _ScenePainter(this.scene, this.f);

  @override
  void paint(Canvas canvas, Size size) {
    final st = _Stage(size);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = Px.black);
    scene.paint(canvas, st, f);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.f != f || old.scene != scene;
}

// --- shared by the scenes -----------------------------------------------------------------

/// Where things go: the art-cell size for this screen, the grid, and the
/// emblem's top-left cell (centred, a little above the middle).
class _Stage {
  final Size size;
  final double cell;
  final int gw, gh, ox, oy;

  _Stage._(this.size, this.cell, this.gw, this.gh, this.ox, this.oy);

  factory _Stage(Size size) {
    final cell = math
        .max(2.0, math.min(size.width * 0.56 / LogoSprite.width, size.height * 0.30 / LogoSprite.height))
        .floorToDouble();
    final gw = (size.width / cell).ceil(), gh = (size.height / cell).ceil();
    return _Stage._(size, cell, gw, gh, (gw - LogoSprite.width) ~/ 2, (gh * 0.36 - LogoSprite.height / 2).round());
  }

  /// The emblem's centre, in cells.
  int get cx => ox + LogoSprite.width ~/ 2;
  int get cy => oy + LogoSprite.height ~/ 2;

  /// Where the wordmark sits, and how big.
  double get wordTop => (oy + LogoSprite.height + 6) * cell;
  double get fontSize => (cell * 3.2).clamp(14.0, 34.0);

  /// The whole screen plus a margin, for flashes under a shake.
  Rect get bleed => Rect.fromLTWH(-4 * cell, -4 * cell, size.width + 8 * cell, size.height + 8 * cell);
}

TextPainter _text(String s, TextStyle style) =>
    TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();

void _flash(Canvas canvas, _Stage st, double alpha, [Color color = Colors.white]) =>
    canvas.drawRect(st.bleed, Paint()..color = color.withValues(alpha: alpha));

const _word = 'ANIVERSE';

/// Shows [LogoIntro] over the app the first time it is built this run, if the
/// intro is switched on. The app is built underneath as soon as [ready]
/// completes, so it loads while the intro plays; if the intro finishes first,
/// a loader holds the screen until it does.
class IntroGate extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Future<void>? ready;
  const IntroGate({super.key, required this.child, required this.enabled, this.ready});

  /// Once per launch: a palette change rebuilds the app, and must not replay it.
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
    return Stack(
      children: [
        if (_ready)
          widget.child
        else if (!_show)
          const ColoredBox(color: Px.black, child: Center(child: PixelSpinner())),
        if (_show) Positioned.fill(child: LogoIntro(onDone: () => setState(() => _show = false))),
      ],
    );
  }
}
