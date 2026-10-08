import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The viewer's settings for the 2D app: palette, sound, data saver, subtitle
/// look, alerts and the player's background behaviour. The same choices as the
/// website's Settings page, kept on the device.
///
/// One key per setting so the native alert job can read `av.alerts` straight
/// from SharedPreferences.
class AppSettings {
  static SharedPreferences? _prefs;

  /// Bumped on every change; listen to rebuild.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// The palette; the app rebuilds its whole tree when this changes.
  static final ValueNotifier<String> theme = ValueNotifier<String>('blood');

  /// Bumped when the effects level changes; the app rebuilds for that too.
  static final ValueNotifier<int> effectsChanged = ValueNotifier<int>(0);

  static Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      theme.value = _prefs!.getString('av.theme') ?? 'blood';
    } catch (_) {
      // Defaults all round.
    }
  }

  static bool _b(String k, bool d) => _prefs?.getBool(k) ?? d;
  static String _s(String k, String d) => _prefs?.getString(k) ?? d;
  static double _d(String k, double d) => _prefs?.getDouble(k) ?? d;

  static bool get sfx => _b('av.sfx', true);
  static double get volume => _d('av.volume', 0.35);
  static bool get dataSaver => _b('av.dataSaver', false);

  /// s | m | l | xl
  static String get subSize => _s('av.subSize', 'm');
  static bool get subBg => _b('av.subBg', true);

  /// Preferred subtitle language ("English", "Spanish"...); '' = the source's default.
  static String get subLang => _s('av.subLang', '');
  static bool get alerts => _b('av.alerts', false);

  /// Leaving the app while a video plays shrinks it into a floating window.
  static bool get pipAuto => _b('av.pipAuto', true);

  /// Keep the sound going with the screen off or the app in the background.
  static bool get bgAudio => _b('av.bgAudio', false);

  /// Playback speed and last quality pick ('auto' or a height like '720').
  static double get speed => _d('av.speed', 1.0);
  static String get quality => _s('av.quality', 'auto');

  /// Downloads: only on Wi-Fi (or another unmetered network).
  static bool get wifiOnly => _b('av.wifiOnly', true);

  /// Downloads: the most they may take, in GB; 0 is no limit.
  static double get downloadLimitGb => _d('av.downloadLimitGb', 0);

  /// Downloads: delete an episode's copy once it has been watched to the end.
  static bool get autoDeleteWatched => _b('av.autoDeleteWatched', false);

  /// How much ambient animation: full | lite (fewer particles, no glow) | off.
  static String get effects => _s('av.effects', 'full');

  /// The pixel-art logo intro as the app opens.
  static bool get intro => _b('av.intro', true);

  /// The detail screen's episode view: grid | list.
  static String get epView => _s('av.epView', 'grid');

  static Future<void> set(String key, Object value) async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    if (value is bool) {
      await p.setBool('av.$key', value);
    } else if (value is double) {
      await p.setDouble('av.$key', value);
    } else if (value is int) {
      await p.setDouble('av.$key', value.toDouble());
    } else {
      await p.setString('av.$key', value.toString());
    }
    if (key == 'theme') theme.value = value.toString();
    if (key == 'effects') effectsChanged.value++;
    changes.value++;
  }
}
