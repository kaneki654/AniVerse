part of 'logo_intro.dart';

/// Gold samurai: a vermilion ensō is brushed round in one stroke, the emblem
/// is gilded into it -- gold leaf sweeping across, dull bronze turning bright
/// -- a gong rings out in waves, gold leaf drifts down, ANIVERSE settles in
/// letter by letter over a brush stroke, and a sword cut splits the picture,
/// top and bottom sliding apart onto the app.
class _SamuraiScene extends _Scene {
  static const ensoStart = 2, ensoEnd = 16;
  static const gildStart = 14;
  static const gong = 32;
  static const lettersStart = 40, letterEvery = 3;
  static const underlineStart = 62, underlineEnd = 68;

  @override
  int get end => 94;
  @override
  int get exit => 80;

  @override
  Map<int, String> get sounds => {
        ensoStart: 'slash',
        gong: 'boss',
        for (var i = 0; i < _word.length; i++) lettersStart + i * letterEvery: 'click',
        underlineStart: 'start',
      };

  @override
  Map<int, int> get haptics => {gong: 2};

  @override
  void paint(Canvas canvas, _Stage st, int f) {
    if (f < exit + 2) {
      _scene(canvas, st, f);
      if (f >= exit) {
        // The cut: a white line across the middle.
        canvas.drawRect(Rect.fromLTWH(0, st.size.height * 0.5 - st.cell / 2, st.size.width, st.cell),
            Paint()..color = Colors.white);
      }
      return;
    }
    // The two halves slide apart; the app shows between them.
    canvas.drawRect(st.bleed, Paint()..blendMode = BlendMode.clear);
    final p = (f - exit - 2) / (end - exit - 3);
    final shift = st.size.height * 0.5 * p * p * 1.1;
    final half = st.size.height / 2;
    for (final (top, dir) in [(true, -1.0), (false, 1.0)]) {
      canvas.save();
      canvas.translate(0, dir * shift);
      canvas.clipRect(Rect.fromLTWH(0, top ? 0 : half, st.size.width, half));
      canvas.drawRect(Offset.zero & st.size, Paint()..color = Px.black);
      _scene(canvas, st, f);
      canvas.restore();
    }
  }

  void _scene(Canvas canvas, _Stage st, int f) {
    final pc = PixelCanvas(canvas, st.cell, glow: true);
    _leaf(pc, st, f);
    _enso(pc, st, f);
    _ripples(pc, st, f);
    _emblem(pc, st, f);
    pc.commit(strength: 0.8);
    _wordmark(canvas, st, f);
    if (f == gong) _flash(canvas, st, 0.25, Px.bloodLight);
  }

  /// The ensō: one stroke round, thick where the brush lands, dry and broken
  /// where it runs out.
  void _enso(PixelCanvas pc, _Stage st, int f) {
    if (f < ensoStart) return;
    final sweep = ((f - ensoStart) / (ensoEnd - ensoStart)).clamp(0.0, 1.0) * 330;
    final r = LogoSprite.width * 0.78;
    for (var d = 0.0; d <= sweep; d += 2.5) {
      final a = (d - 100) * math.pi / 180;
      final thick = (3.2 - d / 330 * 2.4);
      // Dry brush: gaps appear toward the end of the stroke.
      if (d > 220 && pxRand((d * 3).round()) < (d - 220) / 160) continue;
      for (var k = 0.0; k < thick; k += 1) {
        final x = st.cx + math.cos(a) * (r + k), y = st.cy + math.sin(a) * (r + k) * 0.9;
        pc.px(x.round(), y.round(), k < 1 ? Px.goldDark : Px.gold);
      }
    }
  }

  void _emblem(PixelCanvas pc, _Stage st, int f) {
    if (f < gildStart) return;
    final colors = emblemPalette(FxStyle.samurai);
    // The gilding front sweeps from top left to bottom right.
    final front = -10 + (f - gildStart) * 4.0;
    for (final (x, y, k) in LogoSprite.cells()) {
      final at = x + y * 0.8;
      if (at > front + 6) continue;
      var c = colors[k]!;
      if (k != 'A') {
        if (at > front) {
          c = Px.bloodDark; // bronze, not yet gilded
        } else if (front - at < 2) {
          c = Px.bloodLight; // the leaf going on, bright
        }
      }
      pc.px(st.ox + x, st.oy + y, c);
    }
  }

  /// The gong's sound, as rings spreading out.
  void _ripples(PixelCanvas pc, _Stage st, int f) {
    final t = f - gong;
    if (t < 0 || t > 18) return;
    for (final lag in [0, 6]) {
      final r = (t - lag) * 2.4 + 18;
      if (t - lag < 0) continue;
      final alpha = math.max(0.0, 0.7 - (t - lag) / 14);
      final reach = r.ceil() + 1;
      for (var dy = -reach; dy <= reach; dy += 1) {
        for (var dx = -reach; dx <= reach; dx += 1) {
          final d = math.sqrt(dx * dx + dy * dy);
          if ((d - r).abs() < 0.5 && (dx + dy).isEven) pc.ghost(st.cx + dx, st.cy + dy, 1, 1, Px.blood, alpha);
        }
      }
    }
  }

  void _leaf(PixelCanvas pc, _Stage st, int f) {
    if (f < gong) return;
    final t = f - gong;
    for (var i = 0; i < 26; i++) {
      final seed = i * 37 + 5;
      final x = (pxRand(seed) * st.gw + math.sin(t * 0.2 + i) * 3).round();
      final y = (-4 + t * (0.4 + pxRand(seed + 1) * 0.5) + pxRand(seed + 2) * st.gh * 0.4).round();
      drawFlake(pc, x, y, (t ~/ 2 + i) & 3, alpha: 0.9);
    }
  }

  void _wordmark(Canvas canvas, _Stage st, int f) {
    if (f < lettersStart) return;
    final fs = st.fontSize;
    final style = PxFont.label(fs, color: Px.blood, height: 1.2).copyWith(shadows: [
      ...PxFont.outline(fs / 10),
      Shadow(color: Px.bloodDeep, offset: Offset(fs / 6, fs / 6)),
    ]);
    final full = _text(_word, style);
    final left = (st.size.width - full.width) / 2;
    for (var i = 0; i < _word.length; i++) {
      final at = lettersStart + i * letterEvery;
      if (f < at) break;
      // Each letter settles from a little above, in two steps.
      final drop = math.max(0, 2 - (f - at)) * st.cell;
      final x = left + _text(_word.substring(0, i), style).width;
      _text(_word[i], style).paint(canvas, Offset(x, st.wordTop - drop));
    }
    if (f >= underlineStart) {
      // A vermilion brush stroke under the word.
      final p = ((f - underlineStart) / (underlineEnd - underlineStart)).clamp(0.0, 1.0);
      final y = st.wordTop + full.height + st.cell;
      final paint = Paint()..color = Px.gold;
      for (var x = 0.0; x < full.width * p; x += st.cell) {
        final h = st.cell * (1.6 - x / full.width);
        canvas.drawRect(Rect.fromLTWH(left + x, y + (pxRand(x.round()) - 0.5) * st.cell * 0.5, st.cell, h), paint);
      }
    }
  }
}
