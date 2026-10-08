import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'api_service.dart';

/// Crashes and episodes that would not play, sent to the server
/// (POST /api/client-errors, shown on its /status page) so problems on real
/// phones are visible. At most a few per launch; never throws, never retries.
class ErrorReporter {
  static int _left = 5;

  /// Catches what Flutter and the engine would otherwise only print.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report('crash', details.exceptionAsString(), stack: details.stack?.toString() ?? '', where: details.library ?? '');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report('crash', error.toString(), stack: stack.toString());
      return false; // still the default handling (logged)
    };
  }

  /// An episode no source would play.
  static void playback(String animeId, int episode, String category, String reason) =>
      report('playback', 'EP $episode ($category): $reason', where: 'watch/$animeId');

  static void report(String kind, String message, {String stack = '', String where = ''}) {
    if (_left <= 0 || message.isEmpty || ApiService.webUrl.isEmpty) return;
    _left--;
    final body = json.encode({
      'source': 'app',
      'version': kAppVersionName,
      'kind': kind,
      'message': message.length > 2000 ? message.substring(0, 2000) : message,
      'stack': stack.length > 8000 ? stack.substring(0, 8000) : stack,
      'where': where.length > 200 ? where.substring(0, 200) : where,
    });
    http
        .post(Uri.parse('${ApiService.webUrl}/api/client-errors'), headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 10))
        .then((_) {}, onError: (_) {}); // a report must never become an error itself
  }
}
