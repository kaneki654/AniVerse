import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Measures how fast this app is actually downloading, in megabits per second.
///
/// The video plugin does not expose ExoPlayer's bandwidth meter, so this reads
/// the bytes Android has counted for the app (TrafficStats, via MainActivity)
/// and differentiates. While the player is buffering, that traffic is the
/// stream itself, which is what the buffering circle wants to show.
class NetSpeedMeter {
  static const _channel = MethodChannel('aniverse/net');

  /// Current speed in Mbps, or null until two samples exist or when the
  /// device does not report traffic.
  final ValueNotifier<double?> mbps = ValueNotifier<double?>(null);

  Timer? _timer;
  int? _lastBytes;
  int? _lastMicros;
  final Stopwatch _clock = Stopwatch();

  /// Total bytes the app had received at the latest sample, or null before
  /// the first one. Lets the player count how much of a segment has arrived
  /// before the video plugin reports any of it as buffered.
  int? get totalBytes => _lastBytes;

  void start() {
    if (_timer != null) return;
    _clock.start();
    _sample();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _sample());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    mbps.dispose();
  }

  Future<void> _sample() async {
    int bytes;
    try {
      bytes = (await _channel.invokeMethod<int>('rxBytes')) ?? -1;
    } catch (_) {
      bytes = -1;
    }
    if (_timer == null) return; // stopped while the call was in flight
    if (bytes < 0) {
      // Android returns UNSUPPORTED (-1) on some devices; show nothing rather
      // than a made-up number.
      mbps.value = null;
      return;
    }

    final now = _clock.elapsedMicroseconds;
    final lastBytes = _lastBytes;
    final lastMicros = _lastMicros;
    _lastBytes = bytes;
    _lastMicros = now;
    if (lastBytes == null || lastMicros == null || now <= lastMicros) return;

    final delta = bytes - lastBytes;
    if (delta < 0) return; // counter reset
    final instant = delta * 8 / ((now - lastMicros) / 1e6) / 1e6;

    // Smoothed, so the readout settles instead of jittering every half second,
    // but still drops to ~0 within a couple of seconds when traffic stops.
    final previous = mbps.value;
    mbps.value = previous == null ? instant : previous * 0.55 + instant * 0.45;
  }
}
