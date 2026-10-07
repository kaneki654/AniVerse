part of 'logo_intro.dart';

/// Sakura: one petal drifts down through the dark and, where it lands, the
/// emblem blooms outward cell by cell with a ring of light. A gust throws
/// petals off it, ANIVERSE fades in letter by letter with a sparkle on each,
/// sparkles sweep the emblem, and a petal storm blows across and carries the
/// whole picture away onto the app.
class _SakuraScene extends _Scene {
  static const fallStart = 2, fallEnd = 16;
  static const bloomStart = 16;
  static const gust = 36;
  static const lettersStart = 40, letterEvery = 3;
  static const subAt = 62;
  static const shimmerStart = 64, shimmerEnd = 76;

  @override
  int get end => 92;
  @override
  int get exit => 78;

  @override
  Map<int, String> get sounds => {
        fallStart: 'select',
        bloomStart: 'skip',
        gust: 'achieve',
        for (var i = 0; i < _word.length; i++) lettersStart + i * letterEvery: 'click',
        subAt: 'start',
      };

  @override
  Map<int, int> get haptics => {bloomStart: 1, gust: 1};

  static const _centre = (17.0, 15.0);

  /// When each emblem cell blooms: by its distance from the centre, a little ragged.
  static final List<(int, int, String, int)> _cells = [
    for (final (i, (x, y, k)) in LogoSprite.cells().indexed)
      (
        x, y, k,
        bloomStart +
            (math.sqrt(math.pow(x - _centre.$1, 2) + math.pow(y - _centre.$2, 2)) * 0.7).round() +
            (pxRand(i * 7 + 3) * 3).round(),
      ),
  ];

  @override
  void paint(Canvas canvas, _Stage st, int f) {
    final pc = PixelCanvas(canvas, st.cell, glow: true);
    _drift(pc, st, f);
    _fallingPetal(pc, st, f);
    _ring(pc, st, f);
    _emblem(pc, st, f);
    _gust(pc, st, f);
    pc.commit();

    _wordmark(canvas, st, f);
    if (f == gust) _flash(canvas, st, 0.22);
    if (f >= exit) _storm(canvas, st, f);
  }

  /// A big petal: each cell of the sprite drawn two cells square.
  void _bigPetal(PixelCanvas pc, int x, int y, int frame, {double alpha = 1}) {
    for (final (dx, dy, shade) in petalFrames[frame & 3]) {
      pc.ghost(x + dx * 2, y + dy * 2, 2, 2, shade == 0 ? Px.bloodLight : Px.blood, alpha);
    }
  }

  /// Petals drifting down and across the whole time, and a few twinkles.
  void _drift(PixelCanvas pc, _Stage st, int f) {
    for (var i = 0; i < 18; i++) {
      final seed = i * 89 + 3;
      final fall = 0.25 + pxRand(seed) * 0.35;
      final span = st.gh + 8;
      final tt = f * fall + pxRand(seed + 2) * span;
      final y = (tt % span).floor() - 4;
      final x = ((pxRand(seed + 3) * st.gw + f * 0.2 + math.sin(tt * 0.2 + seed) * 2) % st.gw).floor();
      drawPetal(pc, x, y, (f ~/ 3 + i) & 3, alpha: 0.35 + 0.3 * pxRand(seed + 4));
    }
    for (var i = 0; i < 6; i++) {
      drawSparkle(pc, (pxRand(i * 53) * st.gw).floor(), (pxRand(i * 53 + 1) * st.gh).floor(), f ~/ 2 + i * 3, Px.gold, alpha: 0.6);
    }
  }

  /// The one petal that starts it, swaying down to the emblem's heart.
  void _fallingPetal(PixelCanvas pc, _Stage st, int f) {
    if (f < fallStart || f > fallEnd) return;
    double yAt(int g) => -6 + (st.cy + 6) * ((g - fallStart) / (fallEnd - fallStart));
    double xAt(int g) => st.cx + math.sin((g - fallStart) * 0.55) * 5;
    // A trail of see-through copies where it just was.
    for (final (back, alpha) in const [(2, 0.18), (1, 0.4)]) {
      final g = f - back;
      if (g < fallStart) continue;
      _bigPetal(pc, xAt(g).round(), yAt(g).round(), g ~/ 2, alpha: alpha);
    }
    _bigPetal(pc, xAt(f).round(), yAt(f).round(), f ~/ 2);
    drawSparkle(pc, xAt(f).round() + 3, yAt(f).round() - 2, f, Px.gold, alpha: 0.8);
  }

  /// The ring of light that spreads as the emblem blooms.
  void _ring(PixelCanvas pc, _Stage st, int f) {
    final t = f - bloomStart;
    if (t < 0 || t > 16) return;
    final r = t * 1.7;
    final alpha = 1 - t / 16;
    final reach = r.ceil() + 1;
    for (var dy = -reach; dy <= reach; dy++) {
      for (var dx = -reach; dx <= reach; dx++) {
        final d = math.sqrt(dx * dx + dy * dy);
        if ((d - r).abs() < 0.55) pc.ghost(st.cx + dx, st.cy + dy, 1, 1, Px.bloodLight, alpha * 0.8);
      }
    }
  }

  void _emblem(PixelCanvas pc, _Stage st, int f) {
    final colors = emblemPalette(FxStyle.sakura);
    final band = f >= shimmerStart && f <= shimmerEnd ? -10 + (f - shimmerStart) * 5 : null;
    for (final (x, y, k, at) in _cells) {
      if (f < at) continue;
      var c = colors[k]!;
      final outline = k == 'A';
      // Opening: a pale bud, then half-open, then its colour.
      if (f == at) {
        c = outline ? Px.bloodDark : Px.bloodLight;
      } else if (f == at + 1 && !outline) {
        c = Color.lerp(c, Colors.white, 0.45)!;
      }
      pc.rect(st.ox + x, st.oy + y, 1, 1, c);
      if (band != null && !outline && ((x + y * 0.5) - band).abs() < 1.5 && pxRand(x * 5 + y * 3 + f) < 0.35) {
        drawSparkle(pc, st.ox + x, st.oy + y, 2, Px.gold, alpha: 0.9);
      }
    }
  }

  /// The gust: petals thrown off the emblem, slowed by the air, drifting down.
  void _gust(PixelCanvas pc, _Stage st, int f) {
    final t = f - gust;
    if (t < 0) return;
    for (var i = 0; i < 44; i++) {
      final a = (i / 44) * math.pi * 2 + pxRand(i * 3) * 0.4;
      final s = 1.4 + pxRand(i * 7 + 1) * 2.2;
      final out = s * (1 - math.pow(0.86, t)) / 0.14;
      final x = st.cx + math.cos(a) * out + math.sin(t * 0.3 + i) * 1.5;
      final y = st.cy + math.sin(a) * out * 0.8 + 0.035 * t * t;
      final alpha = t < 30 ? 1.0 : math.max(0.0, 1 - (t - 30) / 20);
      if (alpha <= 0) continue;
      if (i % 3 == 0) {
        _bigPetal(pc, x.round(), y.round(), (t ~/ 2 + i) & 3, alpha: alpha);
      } else {
        drawPetal(pc, x.round(), y.round(), (t ~/ 2 + i) & 3, alpha: alpha);
      }
    }
  }

  void _wordmark(Canvas canvas, _Stage st, int f) {
    if (f < lettersStart) return;
    final fs = st.fontSize;
    TextStyle style(Color c) => PxFont.label(fs, color: c, height: 1.2).copyWith(shadows: [
          ...PxFont.outline(fs / 10),
          for (final o in [Offset(-fs / 5, 0), Offset(fs / 5, 0), Offset(0, -fs / 5), Offset(0, fs / 5)])
            Shadow(color: Px.bloodLight.withValues(alpha: 0.18), offset: o),
        ]);
    final full = _text(_word, style(Px.blood));
    final left = (st.size.width - full.width) / 2;
    final sparkles = PixelCanvas(canvas, st.cell);
    for (var i = 0; i < _word.length; i++) {
      final at = lettersStart + i * letterEvery;
      if (f < at) break;
      // Each letter fades in over three frames, in steps.
      final alpha = math.min(1.0, (f - at + 1) / 3);
      final x = left + _text(_word.substring(0, i), style(Px.blood)).width;
      _text(_word[i], style(Px.blood.withValues(alpha: alpha))).paint(canvas, Offset(x, st.wordTop));
      if (f - at < 6) {
        final letterW = _text(_word[i], style(Px.blood)).width;
        drawSparkle(sparkles, ((x + letterW / 2) / st.cell).round(), (st.wordTop / st.cell).round() - 1, f - at, Px.gold);
      }
    }
    if (f >= subAt) {
      final sub = _text('~ P I X E L ~', PxFont.label(fs * 0.45, color: Px.gold).copyWith(shadows: PxFont.outline(1.2)));
      sub.paint(canvas, Offset((st.size.width - sub.width) / 2, st.wordTop + full.height + st.cell * 2));
    }
  }

  /// Out: a petal storm blowing in from the left, the picture gone behind it.
  void _storm(Canvas canvas, _Stage st, int f) {
    final q = (f - exit + 1) / (end - exit);
    final front = q * (st.gw + 30) - 12; // in cells
    const b = 2;
    final clear = Paint()..blendMode = BlendMode.clear;
    for (var y = -2; y < st.gh + 4; y += b) {
      final ragged = (pxRand(y * 7 + 1) * 6).round();
      final edge = front - ragged;
      if (edge <= -2) continue;
      canvas.drawRect(Rect.fromLTWH(-2 * st.cell, y * st.cell, (edge + 2) * st.cell, b * st.cell), clear);
    }
    // The petals of the storm front, over the app as it is uncovered.
    final pc = PixelCanvas(canvas, st.cell);
    for (var i = 0; i < 70; i++) {
      final y = (pxRand(i * 3 + 7) * (st.gh + 4)).floor() - 2;
      final x = (front - pxRand(i * 5 + 2) * 14 + math.sin(f * 0.5 + i) * 1.5).round();
      _bigPetal(pc, x, y, (f + i) & 3, alpha: 0.95);
    }
  }
}
