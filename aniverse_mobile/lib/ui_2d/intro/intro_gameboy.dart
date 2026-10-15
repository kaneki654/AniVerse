part of 'logo_intro.dart';

/// Game Boy: the screen lights up its darkest green, the emblem scrolls down
/// from the top of the screen and stops, a ding, a glint across it, ANIVERSE
/// types in, block pieces fall behind, and the screen fades through the
/// handheld's shades and redraws, row by row, onto the app.
class _GameBoyScene extends _Scene {
  static const scrollStart = 4, scrollEnd = 34;
  static const ding = 35;
  static const glintStart = 36, glintEnd = 44;
  static const lettersStart = 42, letterEvery = 2;
  static const subAt = 58;

  @override
  int get end => 86;
  @override
  int get exit => 72;

  @override
  Map<int, String> get sounds => {
        scrollStart: 'select',
        ding: 'achieve',
        for (var i = 0; i < _word.length; i++) lettersStart + i * letterEvery: 'click',
        subAt: 'start',
      };

  @override
  Map<int, int> get haptics => {ding: 1};

  @override
  void paint(Canvas canvas, _Stage st, int f) {
    canvas.drawRect(Offset.zero & st.size, Paint()..color = Px.ink);
    final pc = PixelCanvas(canvas, st.cell);
    // The LCD's dot matrix.
    for (var y = 1; y < st.gh; y += 3) {
      for (var x = 1; x < st.gw; x += 3) {
        pc.ghost(x, y, 1, 1, Px.bloodDark, 0.18);
      }
    }
    if (f >= 50) _pieces(pc, st, f);

    // The scroll: down a whole cell at a time, from off the top to its place.
    final travel = st.oy + LogoSprite.height + 2;
    final t = ((f - scrollStart) / (scrollEnd - scrollStart)).clamp(0.0, 1.0);
    final dy = f < scrollStart ? -travel : -(travel * (1 - t)).round();
    final colors = emblemPalette(FxStyle.gameboy);
    final glint = f >= glintStart && f <= glintEnd ? -10 + (f - glintStart) * 6 : null;
    for (final (x, y, k) in LogoSprite.cells()) {
      var c = colors[k]!;
      if (glint != null && k != 'A' && ((x + y * 0.5) - glint).abs() < 2) c = Px.bloodLight;
      pc.px(st.ox + x, st.oy + y + dy, c);
    }

    _wordmark(canvas, st, f);
    if (f >= exit) _fadeAndRedraw(canvas, st, f);
  }

  void _pieces(PixelCanvas pc, _Stage st, int f) {
    const shapes = [
      [(0, 0), (1, 0), (2, 0), (3, 0)],
      [(0, 0), (1, 0), (0, 1), (1, 1)],
      [(0, 0), (1, 0), (2, 0), (1, 1)],
      [(0, 0), (0, 1), (0, 2), (1, 2)],
    ];
    for (var i = 0; i < 6; i++) {
      final shape = shapes[i % shapes.length];
      final x = (pxRand(i * 7 + 3) * (st.gw - 6)).floor();
      final y = ((f - 50) ~/ 2 + (pxRand(i * 5) * st.gh * 0.6).floor()) - 6;
      for (final (dx, dy) in shape) {
        pc.ghost(x + dx, y + dy, 1, 1, Px.bloodDark, 0.7);
      }
    }
  }

  void _wordmark(Canvas canvas, _Stage st, int f) {
    final shown = f < lettersStart ? 0 : math.min(_word.length, (f - lettersStart) ~/ letterEvery + 1);
    if (shown == 0) return;
    final fs = st.fontSize;
    final style = PxFont.label(fs, color: Px.bloodLight, height: 1.2).copyWith(shadows: [
      Shadow(color: Px.bloodDeep, offset: Offset(fs / 8, fs / 8)),
    ]);
    final full = _text(_word, style);
    final left = (st.size.width - full.width) / 2;
    _text(_word.substring(0, shown), style).paint(canvas, Offset(left, st.wordTop));
    if (f >= subAt) {
      final sub = _text('P I X E L', PxFont.label(fs * 0.45, color: Px.gold));
      sub.paint(canvas, Offset((st.size.width - sub.width) / 2, st.wordTop + full.height + st.cell * 2));
    }
  }

  /// Out: the screen steps down through the shades, then redraws row by row onto the app.
  void _fadeAndRedraw(Canvas canvas, _Stage st, int f) {
    final t = f - exit;
    if (t < 6) {
      final shades = [Px.bloodDeep, Px.bloodDark, Px.ink, Px.ink, Px.black, Px.black];
      canvas.drawRect(st.bleed, Paint()..color = shades[t].withValues(alpha: 0.35 + t * 0.13));
      return;
    }
    canvas.drawRect(st.bleed, Paint()..color = Px.black);
    final q = (t - 5) / (end - exit - 5);
    final edge = st.size.height * q;
    canvas.drawRect(Rect.fromLTWH(0, 0, st.size.width, edge), Paint()..blendMode = BlendMode.clear);
    canvas.drawRect(Rect.fromLTWH(0, edge, st.size.width, st.cell / 2), Paint()..color = Px.bloodLight);
  }
}
