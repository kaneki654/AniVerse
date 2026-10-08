import 'dart:convert';

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

  /// Bumped when the effects level, text size or high contrast changes; the
  /// app rebuilds for those too.
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

  // --- 1.11: player, downloads, alerts, accessibility ---------------------------------

  /// Seconds the skip buttons, double-tap, arrow keys and media keys jump.
  static int get seekStep => _d('av.seekStep', 10).round();

  /// Subtitle text colour: white | yellow | cyan | green.
  static String get subColor => _s('av.subColor', 'white');

  /// Recaps at the start of an episode are skipped without asking.
  static bool get skipRecap => _b('av.skipRecap', false);

  /// The next episode of each show on My List downloads by itself (on Wi-Fi
  /// when Wi-Fi only is on).
  static bool get smartDownloads => _b('av.smartDownloads', false);

  /// Alert quiet hours, local time: no notifications from [quietFrom] until
  /// [quietTo] (hours 0-23); -1 is off. Read by AlertCheck.kt too.
  static int get quietFrom => _d('av.quietFrom', -1).round();
  static int get quietTo => _d('av.quietTo', 8).round();

  /// Text size: 1.0, 1.15 or 1.3 times.
  static double get textScale => _d('av.textScale', 1.0);

  /// Brighter text and borders on top of the palette, for low vision.
  static bool get highContrast => _b('av.highContrast', false);

  static Map<String, dynamic> _map(String key) {
    try {
      final v = json.decode(_s(key, '{}'));
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  static List<String> _list(String key) {
    try {
      final v = json.decode(_s(key, '[]'));
      return v is List ? [for (final x in v) x.toString()] : [];
    } catch (_) {
      return [];
    }
  }

  /// Per-show memory, kept to the most recent [_perShowMax] shows.
  static const _perShowMax = 200;
  static Future<void> _setIn(String key, String anime, Object? value) async {
    final m = _map('av.$key')..remove(anime);
    if (value != null) m[anime] = value;
    while (m.length > _perShowMax) {
      m.remove(m.keys.first);
    }
    await set(key, json.encode(m));
  }

  /// The playback speed last used for this show, if any.
  static double? speedFor(String anime) => (_map('av.showSpeed')[anime] as num?)?.toDouble();
  static Future<void> setSpeedFor(String anime, double speed) => _setIn('showSpeed', anime, speed);

  /// Whether the next episode of this show plays by itself at the end.
  static bool autoNextFor(String anime) => _map('av.showAutoNext')[anime] != false;
  static Future<void> setAutoNextFor(String anime, bool on) => _setIn('showAutoNext', anime, on ? null : false);

  /// Watching this show in its official Tagalog dub: Continue Watching and the
  /// episode list open the Tagalog player until SUB / DUB is picked again.
  static bool tagalogFor(String anime) => _map('av.showAudio')[anime] == 'tl';
  static Future<void> setTagalogFor(String anime, bool on) => _setIn('showAudio', anime, on ? 'tl' : null);

  /// Shows on My List whose new-episode alerts are muted (read by AlertCheck.kt).
  static bool alertsFor(String anime) => !_list('av.alertsMuted').contains(anime);
  static Future<void> setAlertsFor(String anime, bool on) async {
    final l = _list('av.alertsMuted')..remove(anime);
    if (!on) l.add(anime);
    await set('alertsMuted', json.encode(l));
  }

  /// Searches that led somewhere, newest first.
  static List<String> get recentSearches => _list('av.recentSearches');
  static Future<void> addRecentSearch(String q) async {
    final t = q.trim();
    if (t.length < 2) return;
    final l = [t, ...recentSearches.where((x) => x.toLowerCase() != t.toLowerCase())];
    await set('recentSearches', json.encode(l.take(10).toList()));
  }

  static Future<void> clearRecentSearches() => set('recentSearches', '[]');

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
    if (key == 'effects' || key == 'textScale' || key == 'highContrast') effectsChanged.value++;
    changes.value++;
  }
}
