import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';

/// The Android side of the app (MainActivity.kt, AlertCheck.kt): picture in
/// picture, 8-bit sound effects through SoundPool, notification permission and
/// the scheduled new-episode check. Every call fails quietly -- none of these
/// may ever stop an episode from playing.
class NativeBridge {
  static const _ch = MethodChannel('aniverse/native');

  /// True while the app is shrunk into a picture-in-picture window.
  static final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

  /// Called with an anime id when an alert notification is tapped.
  static void Function(String animeId)? onOpenAnime;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipChanged':
          inPip.value = call.arguments == true;
        case 'openAnime':
          final id = call.arguments?.toString();
          if (id != null && id.isNotEmpty) onOpenAnime?.call(id);
      }
      return null;
    });
  }

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> pipSupported() async => await _call<bool>('pipSupported') ?? false;

  /// Whether leaving the app now should shrink the video into a window.
  static Future<void> setPipReady(bool ready, {int w = 16, int h = 9}) =>
      _call('setPipReady', {'ready': ready, 'w': w, 'h': h});

  static Future<bool> enterPip() async => await _call<bool>('enterPip') ?? false;

  static Future<bool> notificationsAllowed() async => await _call<bool>('notificationsAllowed') ?? false;
  static Future<bool> requestNotifications() async => await _call<bool>('requestNotifications') ?? false;
  static Future<void> scheduleAlerts(bool on) => _call('scheduleAlerts', {'on': on});
  static Future<int> checkAlertsNow() async => await _call<int>('checkAlertsNow') ?? 0;

  /// The anime of the alert the app was opened from, if any (once).
  static Future<String?> takeLaunchAnime() => _call<String>('takeLaunchAnime');
}

/// 8-bit sound effects: click, select, splat, slash, start, skip, error,
/// achieve, hit, boss -- the website's set (scripts/make_sfx.py renders them).
///
/// Each palette has its own voice: Blood as recorded, Neon cyber pitched up
/// and bright, Sakura lower and softer.
class Sfx {
  static void play(String name) {
    if (!AppSettings.sfx) return;
    final (rate, gain) = switch (AppSettings.theme.value) {
      'neon' => (1.3, 1.0),
      'sakura' => (0.82, 0.75),
      _ => (1.0, 1.0),
    };
    NativeBridge._call('sfx', {'name': name, 'volume': AppSettings.volume * gain, 'rate': rate});
  }
}
