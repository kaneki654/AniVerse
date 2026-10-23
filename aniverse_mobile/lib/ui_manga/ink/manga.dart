import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/app_settings.dart';

/// The manga UI's ink and paper: one look, like a printed page -- off-white
/// paper, black ink, screentone greys and a single red spot colour (with a
/// rare yellow, as on a colour cover).
class Mg {
  static const paper = Color(0xFFF5F1E8);
  static const panel = Color(0xFFFFFFFF);
  static const panelHigh = Color(0xFFEAE4D8);
  static const tone = Color(0xFFD6CFC2);
  static const ink = Color(0xFF121010);
  static const black = Color(0xFF0A0909);
  static const gray = Color(0xFF5C5852);
  static const grayLight = Color(0xFF9A948B);
  static const white = Color(0xFFFFFFFF);
  static const red = Color(0xFFE50914);
  static const redDark = Color(0xFF9E0610);
  static const redDeep = Color(0xFF4A0308);
  static const redLight = Color(0xFFFF5A64);
  static const gold = Color(0xFFF2B705);
  static const goldDark = Color(0xFF9A7400);
  static const googleBlue = Color(0xFF4285F4);
}

/// Lettering: heavy titles (Lato Black), condensed captions and text (Roboto
/// Condensed), and Japanese sound effects (Noto Sans CJK, cut to the kana).
class MgFont {
  static const title = 'MangaTitle';
  static const body = 'MangaText';
  static const sfxFace = 'MangaSfx';

  /// Caption lettering, bold and condensed. Sizes follow the pixel UI's
  /// (whose face drew much larger per point), so they are scaled up here.
  static TextStyle label(double size, {Color color = Mg.ink, double height = 1.25}) => TextStyle(
      fontFamily: body, fontWeight: FontWeight.w700, fontSize: size * 1.5, color: color, height: height,
      letterSpacing: 0.3);

  static TextStyle text(double size, {Color color = Mg.ink, double height = 1.35}) =>
      TextStyle(fontFamily: body, fontSize: size * 1.02, color: color, height: height);

  /// A heavy, slightly forward-leaning headline.
  static TextStyle heading(double size, {Color color = Mg.ink, double height = 1.1}) => TextStyle(
      fontFamily: title, fontSize: size, color: color, height: height, letterSpacing: -0.2,
      fontStyle: FontStyle.italic);

  /// A sound effect: ドン, ゴゴゴ.
  static TextStyle sfx(double size, {Color color = Mg.ink}) =>
      TextStyle(fontFamily: sfxFace, fontSize: size, color: color, height: 1.0, fontWeight: FontWeight.w700);

  /// A hard outline round lettering: eight offset copies, no blur.
  static List<Shadow> outline(double w, {Color color = Mg.ink}) => [
        for (final o in const [
          Offset(-1, -1), Offset(0, -1), Offset(1, -1), Offset(-1, 0),
          Offset(1, 0), Offset(-1, 1), Offset(0, 1), Offset(1, 1),
        ])
          Shadow(color: color, offset: o * w),
      ];
}

/// How much moves: 'full' (speed lines, shakes, drifting tone), 'lite' (the
/// transitions only), 'off' (nothing animates) -- Settings > Effects.
enum MangaFx { full, lite, off }

MangaFx get mangaFx => switch (AppSettings.effects) {
      'off' => MangaFx.off,
      'lite' => MangaFx.lite,
      _ => AppSettings.highContrast ? MangaFx.lite : MangaFx.full,
    };

/// Icons, by the same names the screens use. Material's bold glyphs, drawn in
/// ink at the size a pixel sprite of [scale] would have been.
class InkIcons {
  static const play = Icons.play_arrow_rounded;
  static const pause = Icons.pause_rounded;
  static const back = Icons.arrow_back_rounded;
  static const chevron = Icons.chevron_right_rounded;
  static const rewind = Icons.fast_rewind_rounded;
  static const forward = Icons.fast_forward_rounded;
  static const skipNext = Icons.skip_next_rounded;
  static const search = Icons.search_rounded;
  static const gear = Icons.settings_rounded;
  static const user = Icons.person_rounded;
  static const grid = Icons.grid_view_rounded;
  static const list = Icons.view_agenda_rounded;
  static const clock = Icons.schedule_rounded;
  static const trash = Icons.delete_rounded;
  static const fullscreen = Icons.fullscreen_rounded;
  static const fullscreenExit = Icons.fullscreen_exit_rounded;
  static const swap = Icons.swap_horiz_rounded;
  static const refresh = Icons.refresh_rounded;
  static const check = Icons.check_rounded;
  static const close = Icons.close_rounded;
  static const eye = Icons.visibility_rounded;
  static const eyeOff = Icons.visibility_off_rounded;
  static const lock = Icons.lock_rounded;
  static const logout = Icons.logout_rounded;
  static const floppy = Icons.save_rounded;
  static const star = Icons.star_rounded;
  static const bloodDrop = Icons.water_drop_rounded;
  static const skull = Icons.sentiment_very_dissatisfied_rounded;
  static const skullSmall = Icons.sentiment_dissatisfied_rounded;
  static const download = Icons.download_rounded;
  static const home = Icons.home_rounded;
  static const calendar = Icons.calendar_month_rounded;
  static const bookmark = Icons.bookmark_rounded;
  static const bookmarkOff = Icons.bookmark_border_rounded;
  static const bell = Icons.notifications_rounded;
  static const trophy = Icons.emoji_events_rounded;
  static const flag = Icons.flag_rounded;
  static const party = Icons.groups_rounded;
  static const sword = Icons.bolt_rounded;
  static const pip = Icons.picture_in_picture_alt_rounded;
  static const gauge = Icons.speed_rounded;
}

/// An ink icon. [scale] is the pixel UI's sprite scale (a 9-cell sprite), so
/// the copied screens keep their proportions.
class InkIcon extends StatelessWidget {
  final IconData icon;
  final double scale;
  final Color color;

  const InkIcon(this.icon, {super.key, this.scale = 2, this.color = Mg.ink});

  @override
  Widget build(BuildContext context) => Icon(icon, size: scale * 9.5, color: color);
}

/// Rebuilds [builder] at [fps] with a frame count that wraps at [frames]:
/// for loops that should feel drawn, a few frames a second, like limited
/// animation. Stops when effects are off.
class MangaClock extends StatefulWidget {
  final int fps;
  final int frames;
  final Widget Function(BuildContext context, int frame) builder;

  const MangaClock({super.key, this.fps = 12, this.frames = 1 << 30, required this.builder});

  @override
  State<MangaClock> createState() => _MangaClockState();
}

class _MangaClockState extends State<MangaClock> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final f = (elapsed.inMilliseconds * widget.fps ~/ 1000) % widget.frames;
      if (f != _frame && mounted) setState(() => _frame = f);
    });
    if (mangaFx != MangaFx.off) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _frame);
}

/// A deterministic wobble for hand-drawn lines: the same seed draws the same
/// stroke every frame, so ink does not shimmer.
double wobble(int seed, double amount) {
  final x = math.sin(seed * 12.9898) * 43758.5453;
  return (x - x.floorToDouble() - 0.5) * 2 * amount;
}
