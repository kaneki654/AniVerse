part of 'logo_intro.dart';

/// Neon cyber: a CRT powers on, a boot log types out over digital rain, the
/// emblem is scanned in line by line through a band of glitch noise, then a
/// glitch hits -- the image splits into magenta and cyan, slices tear sideways,
/// sparks fly. The sign flickers like neon warming up, ANIVERSE types in with
/// a block cursor and a colour fringe, and an interlaced scanline wipe opens
/// onto the app.
class _NeonScene extends _Scene {
  static const powerEnd = 10;
  static const bootStart = 10, bootEvery = 4;
  static const scanStart = 16, scanSpeed = 1.5;
  static const hit = 37, hitLength = 7;
  static const flickers = {44, 47, 48, 52};
  static const lettersStart = 46, letterEvery = 2;
  static const subAt = 64;
  static const boot = ['> ANIVERSE OS 1.9', '> LINK ........ OK', '> LOAD EMBLEM'];

  @override
  int get end => 92;
  @override
  int get exit => 80;

  @override
  Map<int, String> get sounds => {
        1: 'select',
        for (var i = 0; i < boot.length; i++) bootStart + i * bootEvery: 'click',
        scanStart: 'skip',
        hit: 'hit',
        hit + 2: 'error',
        for (var i = 0; i < _word.length; i++) lettersStart + i * letterEvery: 'click',
        subAt: 'start',
      };

  @override
  Map<int, int> get haptics => {hit: 2};

  @override
  void paint(Canvas canvas, _Stage st, int f) {
    if (f < powerEnd) return _powerOn(canvas, st, f);

    final pc = PixelCanvas(canvas, st.cell, glow: true);
    _rain(pc, st, f);
    _emblem(pc, st, f);
    final t = f - hit;
    if (t >= 0 && t < 12) paintSparkBurst(pc, st.cx, st.cy, t, 37);
    pc.commit();

    _bootLog(canvas, st, f);
    _wordmark(canvas, st, f);
    _scanlines(canvas, st);
    if (t == 0) _flash(canvas, st, 0.5, Px.bloodLight);
    if (t == 1) _flash(canvas, st, 0.12, Px.gold);
    // A tear across the screen now and then while it idles.
    if (f == 70 || f == 71) {
      canvas.drawRect(Rect.fromLTWH(0, st.size.height * 0.62, st.size.width, st.cell * 0.5),
          Paint()..color = Px.bloodLight.withValues(alpha: 0.5));
    }
    if (f >= exit) _wipe(canvas, st, f);
  }

  /// A CRT switching on: a dot, a line racing across, then the picture opening up.
  void _powerOn(Canvas canvas, _Stage st, int f) {
    final w = st.size.width, h = st.size.height, cy = h * 0.5;
    final p = Paint();
    if (f <= 1) {
      canvas.drawRect(Rect.fromCenter(center: Offset(w / 2, cy), width: st.cell * 3, height: st.cell), p..color = Colors.white);
      return;
    }
    if (f <= 4) {
      final lw = w * (f - 1) / 3;
      canvas.drawRect(Rect.fromCenter(center: Offset(w / 2, cy), width: lw, height: st.cell * 3), p..color = Px.bloodLight.withValues(alpha: 0.35));
      canvas.drawRect(Rect.fromCenter(center: Offset(w / 2, cy), width: lw, height: st.cell), p..color = Colors.white);
      return;
    }
    final k = (f - 4) / 5;
    final bh = h * k * k;
    canvas.drawRect(Rect.fromCenter(center: Offset(w / 2, cy), width: w, height: bh), p..color = Px.bloodDeep.withValues(alpha: 1 - k * 0.6));
    canvas.drawRect(Rect.fromLTWH(0, cy - bh / 2, w, st.cell), p..color = Colors.white.withValues(alpha: 0.8));
    canvas.drawRect(Rect.fromLTWH(0, cy + bh / 2 - st.cell, w, st.cell), p..color = Colors.white.withValues(alpha: 0.8));
  }

  void _rain(PixelCanvas pc, _Stage st, int f) {
    final n = st.gw ~/ 2;
    for (var i = 0; i < n; i++) {
      final seed = i * 71 + 5;
      final x = (pxRand(seed) * st.gw).floor();
      final speed = 0.6 + pxRand(seed + 1) * 1.1;
      final len = 4 + (pxRand(seed + 2) * 9).floor();
      final span = st.gh + len + 6;
      final head = ((f * speed + pxRand(seed + 3) * span) % span).floor() - len;
      for (var j = 0; j < len; j++) {
        final y = head - j;
        if (y < 0 || y >= st.gh) continue;
        if (j > 0 && pxRand(seed + y * 7 + (f ~/ 3)) < 0.35) continue;
        final c = j == 0 ? Px.bloodLight : (j < 3 ? Px.blood : Px.bloodDark);
        pc.ghost(x, y, 1, 1, c, (j == 0 ? 0.55 : 0.3) * (1 - j / len));
      }
    }
  }

  static const _noise = [0, 1, 2, 3];

  void _emblem(PixelCanvas pc, _Stage st, int f) {
    if (f < scanStart) return;
    final colors = emblemPalette(FxStyle.neon);
    final scan = (f - scanStart) * scanSpeed; // the row being scanned
    final t = f - hit;
    final tearing = t >= 0 && t < hitLength;
    final dim = flickers.contains(f);

    void cellAt(int x, int y, Color c, {int dx = 0, double alpha = 1}) {
      if (alpha >= 1) {
        pc.rect(st.ox + x + dx, st.oy + y, 1, 1, c);
      } else {
        pc.ghost(st.ox + x + dx, st.oy + y, 1, 1, c, alpha);
      }
    }

    int sliceShift(int y) => tearing && t < 5 ? ((pxRand((y ~/ 3) * 5 + f) - 0.5) * 7).round() : 0;

    // The colour split: magenta and cyan copies pulled apart behind the image.
    if (tearing) {
      final split = t < 4 ? 2 : 1;
      for (final (x, y, k) in LogoSprite.cells()) {
        if (k == 'A') continue;
        cellAt(x, y, Px.gold, dx: sliceShift(y) - split, alpha: 0.6);
        cellAt(x, y, Px.bloodLight, dx: sliceShift(y) + split, alpha: 0.6);
      }
    }

    for (final (x, y, k) in LogoSprite.cells()) {
      if (y > scan) continue; // not scanned yet
      if (y > scan - 3 && f < scanStart + (LogoSprite.height + 3) / scanSpeed) {
        // Just under the scan: unresolved noise.
        if (pxRand(x * 7 + y * 13 + f) < 0.3) continue;
        final pick = _noise[(pxRand(x * 3 + y * 5 + f * 11) * 4).floor() % 4];
        cellAt(x, y, [Px.blood, Px.gold, Colors.white, Px.bloodLight][pick]);
        continue;
      }
      var c = colors[k]!;
      if (dim && k != 'A') c = Color.lerp(c, Px.black, 0.75)!;
      cellAt(x, y, c, dx: sliceShift(y));
    }

    // The scan line itself, running past the emblem's edges.
    if (scan <= LogoSprite.height + 1) {
      final y = scan.floor();
      pc.ghost(st.ox - 4, st.oy + y, LogoSprite.width + 8, 1, Px.bloodLight, 0.55);
      pc.rect(st.ox, st.oy + y, LogoSprite.width, 1, Colors.white);
    }
  }

  void _bootLog(Canvas canvas, _Stage st, int f) {
    if (f < bootStart) return;
    final fs = (st.cell * 1.9).clamp(10.0, 15.0);
    final fade = f >= hit ? 0.35 : 1.0;
    for (var i = 0; i < boot.length; i++) {
      final start = bootStart + i * bootEvery;
      if (f < start) continue;
      final chars = math.min(boot[i].length, (f - start + 1) * 3);
      var s = boot[i].substring(0, chars);
      if (i == boot.length - 1 && f < hit && (f ~/ 3).isEven) s += '_';
      _text(s, PxFont.label(fs, color: Px.blood.withValues(alpha: fade), height: 1.2))
          .paint(canvas, Offset(st.cell * 3, st.cell * 6 + i * fs * 1.9));
    }
  }

  void _wordmark(Canvas canvas, _Stage st, int f) {
    final shown = f < lettersStart ? 0 : math.min(_word.length, (f - lettersStart) ~/ letterEvery + 1);
    if (shown == 0) return;
    final fs = st.fontSize;
    TextStyle style(Color c) => PxFont.label(fs, color: c, height: 1.2);
    final full = _text(_word, style(Px.bloodLight));
    final left = (st.size.width - full.width) / 2;
    final s = _word.substring(0, shown);
    // A colour fringe: magenta left, cyan right, then the letters on top.
    final fringe = fs / 8;
    _text(s, style(Px.gold.withValues(alpha: 0.75))).paint(canvas, Offset(left - fringe, st.wordTop));
    _text(s, style(Px.blood.withValues(alpha: 0.75))).paint(canvas, Offset(left + fringe, st.wordTop));
    _text(s, style(Colors.white).copyWith(shadows: PxFont.outline(fs / 12))).paint(canvas, Offset(left, st.wordTop));
    // The block cursor, blinking, until the word is done.
    final done = shown == _word.length && f > lettersStart + _word.length * letterEvery + 8;
    if (!done && (f ~/ 3).isEven) {
      final w = _text(s, style(Colors.white)).width;
      canvas.drawRect(Rect.fromLTWH(left + w + fs * 0.15, st.wordTop + fs * 0.1, fs * 0.7, fs), Paint()..color = Px.bloodLight);
    }
    if (f >= subAt) {
      final sub = _text('< P I X E L >', PxFont.label(fs * 0.45, color: Px.gold).copyWith(shadows: PxFont.outline(1.2)));
      sub.paint(canvas, Offset((st.size.width - sub.width) / 2, st.wordTop + full.height + st.cell * 2));
    }
  }

  /// CRT lines over the whole picture.
  void _scanlines(Canvas canvas, _Stage st) {
    final p = Paint()..color = const Color(0x40000000);
    for (var y = 0.0; y < st.size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, st.size.width, 1), p);
    }
  }

  /// Out: an interlaced wipe, every fourth line first, then the ones between.
  void _wipe(Canvas canvas, _Stage st, int f) {
    final q = (f - exit + 1) / (end - exit);
    final b = st.cell * 2;
    final rows = (st.size.height / b).ceil() + 4;
    final clear = Paint()..blendMode = BlendMode.clear;
    final edge = Paint()..color = Px.bloodLight.withValues(alpha: 0.6);
    for (var r = 0; r < rows; r++) {
      final key = (r % 4) * 0.25 + (r ~/ 4) / rows;
      final y = r * b - 2 * b;
      if (key < q) {
        canvas.drawRect(Rect.fromLTWH(-b, y, st.size.width + 2 * b, b), clear);
      } else if (key < q + 0.04) {
        canvas.drawRect(Rect.fromLTWH(0, y, st.size.width, st.cell * 0.5), edge);
      }
    }
  }
}
