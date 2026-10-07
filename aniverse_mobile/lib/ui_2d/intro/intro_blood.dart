part of 'logo_intro.dart';

/// Blood: a katana cuts the dark, the emblem's pixels fly in from either side
/// of the cut and land white-hot, cooling to crimson; impact (a flash, a shake,
/// a burst of blood), ANIVERSE stamped in letter by letter, blood dripping off
/// the emblem, a glint, and a Bayer dither dissolve onto the app.
class _BloodScene extends _Scene {
  static const slashStart = 2, slashEnd = 10, slashGone = 16;
  static const firstArrival = 11, travel = 7;
  static const impact = 31;
  static const lettersStart = 36, letterEvery = 3;
  static const dripStart = 38;
  static const glintStart = 60, glintEnd = 72;

  @override
  int get end => 87;
  @override
  int get exit => 78;

  @override
  Map<int, String> get sounds => {
        slashStart: 'slash',
        impact: 'splat',
        for (var i = 0; i < _word.length; i++) lettersStart + i * letterEvery: 'click',
        glintStart: 'start',
      };

  @override
  Map<int, int> get haptics => {impact: 3};

  // The cut runs from below-left of the emblem to above-right, through its middle.
  static const _p0 = (-10.0, 36.0), _p1 = (44.0, -6.0);

  static final List<_Flight> _cells = _plan();

  static List<_Flight> _plan() {
    final dx = _p1.$1 - _p0.$1, dy = _p1.$2 - _p0.$2;
    final len = math.sqrt(dx * dx + dy * dy);
    final nx = -dy / len, ny = dx / len; // normal to the cut
    final tx = dx / len, ty = dy / len; // along the cut
    final out = <_Flight>[];
    var i = 0;
    for (final (x, y, k) in LogoSprite.cells()) {
      // Which side of the cut this pixel is on, and how far from it.
      final s = (x - _p0.$1) * nx + (y - _p0.$2) * ny;
      final side = s >= 0 ? 1.0 : -1.0;
      final mag = 14 + pxRand(i * 13 + 5) * 22;
      final along = (pxRand(i * 29 + 3) - 0.5) * 18;
      final lands = firstArrival + (s.abs() / 22 * 11).round() + (pxRand(i * 7 + 1) * 6).round();
      out.add(_Flight(
        x, y, k,
        x + nx * side * mag + tx * along,
        y + ny * side * mag + ty * along,
        math.min(lands, impact - 2),
      ));
      i++;
    }
    return out;
  }

  // Drips run from the bottom of the two legs and the slash's tip.
  static const _drips = [(4, 29), (6, 27), (27, 30), (31, 26)];

  @override
  void paint(Canvas canvas, _Stage st, int f) {
    // The screen shakes for a few frames on impact.
    const shake = [(2, -1), (-2, 1), (1, 1), (-1, 0), (1, -1)];
    final si = f - impact;
    if (si >= 0 && si < shake.length) canvas.translate(shake[si].$1 * st.cell, shake[si].$2 * st.cell);

    final pc = PixelCanvas(canvas, st.cell, glow: true);
    _embers(pc, st, f);
    _slash(pc, st, f);
    _emblem(pc, st, f);
    _splat(pc, st, f);
    _dripsAt(pc, st, f);
    pc.commit();

    _wordmark(canvas, st, f);
    if (f == impact || f == impact + 1) _flash(canvas, st, f == impact ? 0.7 : 0.3);

    // The dither dissolve onto the app: Bayer-ordered blocks punched out.
    if (f >= exit) {
      const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
      final q = (f - exit + 1) / (end - exit);
      final b = st.cell * 2;
      final clear = Paint()..blendMode = BlendMode.clear;
      for (var y = 0; y * b < st.size.height + b; y++) {
        for (var x = 0; x * b < st.size.width + b; x++) {
          if (bayer[(y % 4) * 4 + x % 4] / 16 < q) {
            canvas.drawRect(Rect.fromLTWH(x * b - 4 * st.cell, y * b - 4 * st.cell, b, b), clear);
          }
        }
      }
    }
  }

  void _embers(PixelCanvas pc, _Stage st, int f) {
    for (var i = 0; i < 22; i++) {
      final x = (pxRand(i * 3 + 1) * st.gw).floor() + ((f + i * 5) ~/ 9 % 3) - 1;
      final speed = 0.18 + pxRand(i * 7 + 2) * 0.4;
      final y = st.gh - ((f * speed + pxRand(i * 11 + 3) * st.gh) % (st.gh + 4)).floor();
      final c = i % 4 == 0 ? Px.gold : Px.bloodLight;
      pc.rect(x, y, 1, 1, c.withValues(alpha: 0.35 + pxRand(i) * 0.4));
    }
  }

  static (int, int) _onCut(double t) => (
        (_p0.$1 + (_p1.$1 - _p0.$1) * t).round(),
        (_p0.$2 + (_p1.$2 - _p0.$2) * t).round(),
      );

  void _slash(PixelCanvas pc, _Stage st, int f) {
    if (f < slashStart || f >= slashGone) return;
    final ox = st.ox, oy = st.oy;
    if (f <= slashEnd) {
      final p = (f - slashStart) / (slashEnd - slashStart);
      final head = 1 - math.pow(1 - p, 3).toDouble();
      final tail = math.max(0.0, head - 0.4);
      final (ax, ay) = _onCut(0);
      final (tx, ty) = _onCut(tail);
      final (hx, hy) = _onCut(head);
      // Motion blur, pixel style: a see-through streak behind the blade.
      _thick(pc, ox + ax, oy + ay, ox + tx, oy + ty, Px.bloodLight.withValues(alpha: 0.28), 1);
      _thick(pc, ox + tx, oy + ty, ox + hx, oy + hy, Px.bone, 2);
      pc.rect(ox + hx - 1, oy + hy - 1, 3, 3, Colors.white);
      return;
    }
    // The cut glows, cools and goes.
    final cool = [Px.bone, Px.bloodLight, Px.blood, Px.bloodDark, Px.bloodDeep, Px.bloodDeep];
    final (ax, ay) = _onCut(0);
    final (bx, by) = _onCut(1);
    _thick(pc, ox + ax, oy + ay, ox + bx, oy + by, cool[(f - slashEnd - 1).clamp(0, 5)], 1);
  }

  void _thick(PixelCanvas pc, int x0, int y0, int x1, int y1, Color c, int w) {
    for (var i = 0; i < w; i++) {
      pc.line(x0, y0 + i, x1, y1 + i, c);
    }
  }

  void _emblem(PixelCanvas pc, _Stage st, int f) {
    final glint = f >= glintStart && f <= glintEnd ? -12 + (f - glintStart) * 5 : null;
    final colors = emblemPalette(FxStyle.blood);
    for (final c in _cells) {
      final outline = c.key == 'A';
      final start = c.lands - travel;
      if (f < start) continue;
      if (f < c.lands) {
        // In flight: eased in whole cells, white-hot, with a ghost one step behind.
        double at(int frame) => 1 - math.pow(1 - (frame - start) / travel, 3).toDouble();
        final t = at(f), tp = at(math.max(start, f - 1));
        final x = (c.sx + (c.x - c.sx) * t).round(), y = (c.sy + (c.y - c.sy) * t).round();
        final px = (c.sx + (c.x - c.sx) * tp).round(), py = (c.sy + (c.y - c.sy) * tp).round();
        if (px != x || py != y) pc.ghost(st.ox + px, st.oy + py, 1, 1, Px.bloodLight, 0.35);
        pc.rect(st.ox + x, st.oy + y, 1, 1, outline ? Px.bloodLight : Px.bone);
        continue;
      }
      var color = colors[c.key]!;
      // Landed: a frame white-hot, a frame cooling, then its own colour.
      if (f == c.lands) {
        color = outline ? Px.bloodLight : Px.bone;
      } else if (f == c.lands + 1 && !outline) {
        color = Color.lerp(color, Colors.white, 0.5)!;
      }
      if (glint != null && !outline && ((c.x + c.y * 0.5) - glint).abs() < 2.2) {
        color = Color.lerp(color, Colors.white, 0.6)!;
      }
      pc.rect(st.ox + c.x, st.oy + c.y, 1, 1, color);
    }
  }

  void _splat(PixelCanvas pc, _Stage st, int f) {
    final t = f - impact;
    if (t < 0) return;
    // Blood bursts off the emblem and falls away out of the picture.
    for (var i = 0; i < 30; i++) {
      final x0 = st.ox + 6 + pxRand(i * 5 + 9) * 24;
      final y0 = st.oy + 14 + pxRand(i * 3 + 4) * 10;
      final vx = (pxRand(i * 17 + 2) - 0.5) * 3.4;
      final vy = -(0.8 + pxRand(i * 19 + 6) * 2.2);
      final x = x0 + vx * t;
      final y = y0 + vy * t + 0.11 * t * t;
      final c = i % 3 == 0 ? Px.bloodLight : Px.blood;
      final s = i % 4 == 0 ? 2 : 1;
      // A see-through copy a step back: the drop's motion blur.
      final px = x0 + vx * (t - 1), py = y0 + vy * (t - 1) + 0.11 * (t - 1) * (t - 1);
      if (t > 0) pc.ghost(px.round(), py.round(), s, s, Px.bloodDark, 0.4);
      pc.rect(x.round(), y.round(), s, s, c);
    }
  }

  void _dripsAt(PixelCanvas pc, _Stage st, int f) {
    for (var i = 0; i < _drips.length; i++) {
      final t = f - dripStart - i * 4;
      if (t < 0) continue;
      final (dx, dy) = _drips[i];
      final len = math.min(2 + i % 2 * 2, t ~/ 3 + 1);
      pc.rect(st.ox + dx, st.oy + dy, 1, len, Px.blood);
      pc.rect(st.ox + dx, st.oy + dy + len - 1, 1, 1, Px.bloodLight);
      // Once full, drops fall from the tip.
      if (t > 10) {
        final fall = (t - 10) % 9;
        pc.rect(st.ox + dx, st.oy + dy + len + fall * 2, 1, 1, Px.blood);
      }
    }
  }

  void _wordmark(Canvas canvas, _Stage st, int f) {
    final shown = f < lettersStart ? 0 : math.min(_word.length, (f - lettersStart) ~/ letterEvery + 1);
    if (shown == 0) return;
    final fs = st.fontSize;
    TextStyle style(Color c) => PxFont.label(fs, color: c, height: 1.2).copyWith(shadows: [
          ...PxFont.outline(fs / 9),
          Shadow(color: Px.black, offset: Offset(fs / 6, fs / 6)),
          for (final o in [Offset(-fs / 4, 0), Offset(fs / 4, 0), Offset(0, -fs / 4), Offset(0, fs / 4)])
            Shadow(color: Px.blood.withValues(alpha: 0.28), offset: o),
        ]);
    final full = _text(_word, style(Px.blood));
    final left = (st.size.width - full.width) / 2;
    _text(_word.substring(0, shown), style(Px.blood)).paint(canvas, Offset(left, st.wordTop));
    // The newest letter lands white-hot for a frame.
    final step = f - lettersStart;
    if (step % letterEvery == 0 && step ~/ letterEvery < _word.length) {
      final before = _text(_word.substring(0, shown - 1), style(Px.blood)).width;
      _text(_word[shown - 1], style(Px.bone)).paint(canvas, Offset(left + before, st.wordTop));
    }
    if (f >= glintStart) {
      final sub = _text('P I X E L', PxFont.label(fs * 0.45, color: Px.gold).copyWith(shadows: PxFont.outline(1.2)));
      sub.paint(canvas, Offset((st.size.width - sub.width) / 2, st.wordTop + full.height + st.cell * 2));
    }
  }
}

/// One emblem pixel's flight: where it lands, its colour key, where it
/// starts, and the frame it lands on.
class _Flight {
  final int x, y;
  final String key;
  final double sx, sy;
  final int lands;
  const _Flight(this.x, this.y, this.key, this.sx, this.sy, this.lands);
}
