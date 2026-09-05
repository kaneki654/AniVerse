import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _hostKey = 'aniverse_host';

  /// Server address, editable in-app.
  ///
  /// Free trycloudflare URLs change every time the tunnel restarts, and a URL
  /// compiled into the APK means reinstalling after every restart. Keeping it
  /// in preferences lets the address be pasted in from the Settings icon
  /// instead.
  static String _host = defaultHost;

  static String get host => _host;

  /// Where the current server address is published.
  ///
  /// The tunnel URL rotates on every restart, so a build-time constant goes
  /// stale and used to mean rebuilding and reinstalling the APK. This page is
  /// on stable hosting and carries the live address, so a restart only needs
  /// the site redeployed -- the installed app picks the new address up by
  /// itself on next launch.
  static const String discoveryUrl =
      'https://aniversesite.vercel.app/version.json';

  static Future<void> load() async {
    var explicit = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_hostKey);
      if (saved != null && saved.trim().isNotEmpty) {
        _host = _clean(saved);
        explicit = true;
      }
    } catch (_) {
      // Preferences unavailable: fall back to the compiled-in default.
    }

    // A saved address is the user's explicit choice, so it is tried first and
    // kept whenever it still answers. Only when it has gone dead -- the usual
    // case, since the tunnel it names was restarted -- is the published address
    // consulted, which is what stops a stale entry stranding the app forever.
    if (explicit && await _reachable(_host)) return;

    final published = await _publishedHost();
    if (published != null && published != _host) {
      _host = published;
      // Remember it, so the next launch starts on the working address instead
      // of probing the dead one again.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_hostKey, _host);
      } catch (_) {
        // Not being able to persist it only costs one probe next launch.
      }
    }
  }

  /// Whether [host] still answers. Short timeout: this runs before first paint.
  static Future<bool> _reachable(String host) async {
    try {
      final r = await http
          .get(Uri.parse('$host/app/version.json'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// The address advertised by [discoveryUrl], or null if it cannot be reached.
  static Future<String?> _publishedHost() async {
    try {
      final r = await http
          .get(Uri.parse(discoveryUrl))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final body = json.decode(r.body);
      if (body is! Map) return null;
      final host = body['host'];
      if (host is String && host.trim().isNotEmpty) return _clean(host);
    } catch (_) {
      // Offline, or the site is unreachable: keep the compiled-in default.
    }
    return null;
  }

  static Future<void> setHost(String value) async {
    _host = _clean(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, _host);
  }

  static String _clean(String v) {
    var s = v.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    return s;
  }

  /// Public origin of the AniVerse web app, reached over a Cloudflare tunnel so
  /// the phone needs no LAN IP and no shared network - mobile data works.
  ///
  /// Everything goes through this one host: the web app proxies the API under
  /// /api/anime/* (a tunnel forwards a single port), serves playback through
  /// /proxy/* so the stream CDNs get the Referer they require, and supplies the
  /// intro/outro markers.
  ///
  /// Free trycloudflare URLs change every time the tunnel restarts. When that
  /// happens, update this one line and rebuild.
  static const String defaultHost =
      'https://writes-hindu-pediatric-creates.trycloudflare.com';

  /// API endpoints live under the web app's /api/anime/ passthrough.
  static String get baseUrl => '$_host/api';

  /// Playback and proxied stream URLs.
  static String get webUrl => _host;

  static Future<Map<String, dynamic>> getHomeData() async {
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$baseUrl/anime/popular?per_page=12')),
        http.get(Uri.parse('$baseUrl/anime/trending?per_page=12')),
        http.get(Uri.parse('$baseUrl/anime/latest?per_page=12')),
      ]);

      return {
        'popular': json.decode(responses[0].body),
        'trending': json.decode(responses[1].body),
        'latest': json.decode(responses[2].body),
      };
    } catch (e) {
      print('getHomeData failed: $e');
      return {};
    }
  }

  /// Anime details from the API rather than from AniList directly, so the app
  /// keeps working when AniList is unavailable and benefits from the server's
  /// caching. The shape is unchanged (title/coverImage/description/...).
  static Future<Map<String, dynamic>?> getAnimeDetails(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/anime/info/$id'));
      if (response.statusCode != 200) {
        print('getAnimeDetails: HTTP ${response.statusCode}');
        return null;
      }
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('getAnimeDetails failed: $e');
      return null;
    }
  }

  /// Anime matching [query]. Returns [] on failure or for a blank query.
  ///
  /// The list entries have the same shape as the home rows, so the existing
  /// card widget renders them unchanged.
  static Future<List<dynamic>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/anime/search/${Uri.encodeComponent(q)}'),
      );
      if (response.statusCode != 200) return [];
      final body = json.decode(response.body);
      return body is List ? body : [];
    } catch (e) {
      print('search failed: $e');
      return [];
    }
  }

  /// AniList's canonical genre names, as the API expects them.
  static const List<String> genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy',
    'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery',
    'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life', 'Sports',
    'Supernatural', 'Thriller',
  ];

  /// One page of anime in [genre]. Returns [] on failure or past the last page.
  static Future<List<dynamic>> byGenre(String genre, {int page = 1, int perPage = 24}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/anime/genre/${Uri.encodeComponent(genre)}'
            '?page=$page&per_page=$perPage'),
      );
      if (response.statusCode != 200) return [];
      final body = json.decode(response.body);
      return body is List ? body : [];
    } catch (e) {
      print('byGenre failed: $e');
      return [];
    }
  }

  /// Playable sources for an episode.
  ///
  /// Returns `{'sources': [...], 'intro': ..., 'outro': ...}` where each source
  /// has an absolute, proxied `url` that can be handed straight to the player.
  static Future<Map<String, dynamic>> getSources(
      String id, int epNum, String category) async {
    try {
      final response = await http.get(
        Uri.parse('$webUrl/api/source?episode_id=$id/$epNum&category=$category'),
      );
      if (response.statusCode != 200) {
        return {'sources': []};
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      final data = (body['data'] ?? {}) as Map<String, dynamic>;
      final sources = (data['sources'] ?? []) as List;

      // The web app returns proxy paths like "/proxy/m3u8?url=..."; the player
      // needs an absolute URL.
      final resolved = sources.map((s) {
        final map = Map<String, dynamic>.from(s as Map);
        final url = (map['url'] ?? '').toString();
        if (url.startsWith('/')) {
          map['url'] = '$webUrl$url';
        }
        return map;
      }).toList();

      return {
        'sources': resolved,
        'subtitles': data['subtitles'] ?? [],
        'intro': data['intro'],
        'outro': data['outro'],
        'hasDub': data['hasDub'],
      };
    } catch (e) {
      print('getSources failed: $e');
      return {'sources': []};
    }
  }
}
