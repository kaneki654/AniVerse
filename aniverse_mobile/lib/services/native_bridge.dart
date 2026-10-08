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

  /// Media buttons -- headset, car, TV remote, lock screen -- while an episode
  /// is open: play, pause, next, forward, rewind, or seek (to [position] ms).
  static void Function(String action, int position)? onMedia;

  /// The Chromecast being cast to, by name, or null when not casting.
  static final ValueNotifier<String?> castDevice = ValueNotifier<String?>(null);

  /// A cast ended, with where the TV had got to (ms), for the phone to carry on from.
  static void Function(int positionMs)? onCastEnded;

  /// Where the TV is while casting: (position ms, duration ms, playing).
  static final ValueNotifier<(int, int, bool)> castProgress = ValueNotifier((0, 0, false));

  /// The episode on the TV played to its end.
  static void Function()? onCastFinished;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'pipChanged':
          inPip.value = call.arguments == true;
        case 'media':
          final a = call.arguments;
          if (a is Map) onMedia?.call('${a['action']}', (a['position'] as num?)?.toInt() ?? 0);
        case 'cast':
          final a = call.arguments;
          if (a is! Map) return null;
          if (a['state'] == 'connected') {
            castDevice.value = '${a['device']}';
          } else {
            final was = castDevice.value;
            castDevice.value = null;
            if (was != null) onCastEnded?.call((a['position'] as num?)?.toInt() ?? 0);
          }
        case 'castProgress':
          final a = call.arguments;
          if (a is Map) {
            castProgress.value = (
              (a['position'] as num?)?.toInt() ?? 0,
              (a['duration'] as num?)?.toInt() ?? 0,
              a['playing'] == true,
            );
          }
        case 'castFinished':
          onCastFinished?.call();
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

  /// True on Android TV: bigger posters, a layout for the remote. Set once at start.
  static bool isTv = false;
  static Future<void> detectTv() async => isTv = await _call<bool>('isTv') ?? false;

  static Future<bool> pipSupported() async => await _call<bool>('pipSupported') ?? false;

  /// Whether leaving the app now should shrink the video into a window.
  static Future<void> setPipReady(bool ready, {int w = 16, int h = 9}) =>
      _call('setPipReady', {'ready': ready, 'w': w, 'h': h});

  static Future<bool> enterPip() async => await _call<bool>('enterPip') ?? false;

  /// Whether the current network is metered (mobile data, or a hotspot).
  static Future<bool> isMetered() async => await _call<bool>('isMetered') ?? false;

  /// Keeps downloads running with the app in the background: a foreground
  /// service with a progress notification while [active], none otherwise.
  static Future<void> downloadsActive(bool active, {String text = '', int progress = -1}) =>
      _call('downloadsActive', {'on': active, 'text': text, 'progress': progress});

  /// This window's brightness 0..1 (the system's when the app hasn't set one).
  static Future<double> brightness() async => await _call<double>('getBrightness') ?? 0.5;

  /// Sets this window's brightness; null hands it back to the system.
  static Future<void> setBrightness(double? value) => _call('setBrightness', {'value': value ?? -1.0});

  /// The media volume 0..1, and setting it.
  static Future<double> volume() async => await _call<double>('getVolume') ?? 0.5;
  static Future<void> setVolume(double value) => _call('setVolume', {'value': value});

  /// Android's share sheet for a PNG in the app's cache/share folder.
  static Future<void> shareImage(String path, String text) => _call('shareImage', {'path': path, 'text': text});

  /// Hold the screen on (while a video plays). Replaces the wakelock_plus
  /// plugin, which pulled in package_info_plus and the Kotlin plugin with it.
  static Future<void> keepScreenOn(bool on) => _call('keepScreenOn', {'on': on});

  /// The system media session: what is playing and where, for the lock
  /// screen and media buttons. [active] false takes it down.
  static Future<void> mediaSession(bool active,
          {String title = '', String subtitle = '', bool playing = false, int position = 0, int duration = 0,
          bool hasNext = false}) =>
      _call('mediaSession', {
        'active': active,
        'title': title,
        'subtitle': subtitle,
        'playing': playing,
        'position': position,
        'duration': duration,
        'hasNext': hasNext,
      });

  /// Whether this device can cast at all (Google Play services is there).
  static Future<bool> castAvailable() async => await _call<bool>('castAvailable') ?? false;

  /// The list of Chromecasts to pick from, or the controls while casting.
  static Future<bool> castPick() async => await _call<bool>('castPick') ?? false;

  /// Hands the episode to the Chromecast, from [position] ms, with a WebVTT
  /// [subtitles] track if there is one. The URLs must be reachable from the TV.
  static Future<bool> castLoad(String url,
          {String title = '', String subtitle = '', int position = 0, String? subtitles, bool hls = true}) async =>
      await _call<bool>('castLoad', {
        'url': url,
        'title': title,
        'subtitle': subtitle,
        'position': position,
        'subtitles': subtitles,
        'hls': hls,
      }) ??
      false;

  static Future<void> castStop() => _call('castStop');
  static Future<void> castSeek(int positionMs) => _call('castSeek', {'position': positionMs});
  static Future<void> castPlayPause() => _call('castPlayPause');

  /// The device a cast is already running to (one left over from before), if any.
  static Future<String?> castCurrent() => _call<String>('castDevice');

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
/// and bright, Sakura lower and softer, Game Boy a little brighter, Gold
/// samurai deep, like a temple bell.
class Sfx {
  static void play(String name) {
    if (!AppSettings.sfx) return;
    final (rate, gain) = switch (AppSettings.theme.value) {
      'neon' => (1.3, 1.0),
      'sakura' => (0.82, 0.75),
      'gameboy' => (1.15, 0.9),
      'samurai' => (0.7, 0.95),
      _ => (1.0, 1.0),
    };
    NativeBridge._call('sfx', {'name': name, 'volume': AppSettings.volume * gain, 'rate': rate});
  }
}
