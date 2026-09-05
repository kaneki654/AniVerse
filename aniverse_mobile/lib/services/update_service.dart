import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';
import 'api_service.dart';

/// Self-update over the same server the app already talks to.
///
/// The APK is published at /app/aniverse.apk with its version at
/// /app/version.json, so a new build is picked up in-app instead of being
/// sideloaded again every time.
class UpdateService {
  /// `{versionName, versionCode, url, size}` for the build on the server, or
  /// null when the check fails or nothing newer is published.
  static Future<Map<String, dynamic>?> check() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiService.host}/app/version.json'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final remote = json.decode(response.body) as Map<String, dynamic>;
      if (remote['available'] != true) return null;

      final published = (remote['versionCode'] as num?)?.toInt() ?? 0;
      const installed = kAppBuildNumber;

      return published > installed ? remote : null;
    } catch (e) {
      // A failed update check must never block using the app.
      print('update check failed: $e');
      return null;
    }
  }

  /// Downloads the APK and hands it to Android's package installer.
  ///
  /// [onProgress] receives 0..1, or null while the size is unknown.
  static Future<String?> downloadAndInstall({
    void Function(double? progress)? onProgress,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.host}/app/aniverse.apk');
      final request = http.Request('GET', uri);
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        return 'Server returned ${response.statusCode}';
      }

      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/aniverse-update.apk');
      final sink = file.openWrite();
      final total = response.contentLength ?? 0;
      var received = 0;

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : null);
      });
      await sink.close();

      // Android shows its own install prompt; this only opens it.
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        return 'Could not open installer: ${result.message}';
      }
      return null;
    } catch (e) {
      return 'Update failed: $e';
    }
  }
}
