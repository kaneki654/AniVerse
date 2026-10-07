import 'dart:async';
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

  /// The same address, as published to the GitHub repository by
  /// scripts/publish_address.py (start_all.sh with ANIVERSE_PUBLISH_GIT=1).
  /// Tried first: GitHub stays up, while the Vercel site above went dead.
  static const String githubDiscoveryUrl =
      'https://raw.githubusercontent.com/kaneki654/AniVerse/main/discovery/host.json';

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

  /// The published address that answers: GitHub's copy first, then the
  /// install site's. Null if neither can be reached or neither works.
  static Future<String?> _publishedHost() async {
    String? fallback;
    for (final url in [githubDiscoveryUrl, discoveryUrl]) {
      final host = await _hostFrom(url);
      if (host == null) continue;
      if (await _reachable(host)) return host;
      fallback ??= host;
    }
    return fallback;
  }

  static Future<String?> _hostFrom(String url) async {
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
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
      'https://webcams-neck-input-artwork.trycloudflare.com';

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

  static Map<String, Map<String, dynamic>>? _genreArt;

  /// Background art for the genre tiles: each genre's top-rated anime, as
  /// `{genre: {id, title, score, banner, cover}}`. Kept for the session once
  /// it arrives. Returns {} on failure, which leaves the tiles plain.
  static Future<Map<String, Map<String, dynamic>>> genreArt() async {
    final cached = _genreArt;
    if (cached != null) return cached;
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/anime/genres/top'
              '?genres=${Uri.encodeQueryComponent(genres.join(','))}'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return {};
      final body = json.decode(response.body);
      if (body is! Map) return {};
      final art = {
        for (final e in body.entries)
          if (e.value is Map) e.key.toString(): Map<String, dynamic>.from(e.value as Map),
      };
      if (art.isNotEmpty) _genreArt = art;
      return art;
    } catch (_) {
      return {};
    }
  }

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
  /// When nothing was found, `error` says why, so the player can tell a dead
  /// connection apart from an episode no provider has.
  /// [fresh] asks the server to resolve again instead of answering from its
  /// cache. Use it once a stream the server handed out has failed to play:
  /// stream links carry tokens that can die before the server's cache entry
  /// does, and without this every retry got the same dead link back.
  static Future<Map<String, dynamic>> getSources(
      String id, int epNum, String category, {bool fresh = false}) async {
    try {
      // A cold resolve fans out across every provider and can take a couple
      // of minutes; the web app itself waits up to 180s for the backend.
      final query = 'episode_id=$id/$epNum&category=$category${fresh ? '&fresh=true' : ''}';
      final response = await http
          .get(Uri.parse('$webUrl/api/source?$query'))
          .timeout(const Duration(seconds: 200));
      if (response.statusCode != 200) {
        return {'sources': [], 'error': 'The server returned an error (HTTP ${response.statusCode}).'};
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
        // The subtitle files timed to this source. Most "sub" streams are the
        // raw episode with the text in a separate file, so without these the
        // episode plays in Japanese with nothing on screen.
        map['subtitles'] = ((map['subtitles'] ?? []) as List).map((t) {
          final track = Map<String, dynamic>.from(t as Map);
          final u = (track['url'] ?? '').toString();
          if (u.startsWith('/')) track['url'] = '$webUrl$u';
          return track;
        }).toList();
        return map;
      }).toList();

      return {
        'sources': resolved,
        'subtitles': data['subtitles'] ?? [],
        'intro': data['intro'],
        'outro': data['outro'],
        'hasDub': data['hasDub'],
        'error': data['error'],
      };
    } on TimeoutException {
      return {'sources': [], 'error': 'The server took too long to find a stream.'};
    } catch (e) {
      print('getSources failed: $e');
      return {'sources': [], 'error': "Can't reach the AniVerse server.", 'offline': true};
    }
  }

  /// Intro/outro for the video playing: `{intro, outro, source, pending}`, or
  /// null on failure. [duration] is that video's length in seconds -- times
  /// only fit the release they were taken from. `pending` means the server is
  /// still finding them in the audio; ask again in a minute or two.
  static Future<Map<String, dynamic>?> skipTimes(
      String id, int epNum, double duration, String server, String category) async {
    try {
      final q = 'duration=${duration.toStringAsFixed(2)}'
          '&server=${Uri.encodeQueryComponent(server)}&category=$category';
      final response = await http
          .get(Uri.parse('$baseUrl/anime/skip/${Uri.encodeComponent(id)}/$epNum?$q'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body);
      return body is Map<String, dynamic> ? body : null;
    } catch (e) {
      print('skipTimes failed: $e');
      return null;
    }
  }

  /// A WebVTT subtitle file's text, or null if it could not be had. The proxy
  /// answers 200 even when the host refused it, so the body is what is checked.
  static Future<String?> getSubtitleFile(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final text = utf8.decode(response.bodyBytes, allowMalformed: true).replaceFirst('﻿', '');
      return text.trimLeft().startsWith('WEBVTT') ? text : null;
    } catch (e) {
      print('getSubtitleFile failed: $e');
      return null;
    }
  }
  // --- 1.9: extras, schedule, filters, reports ----------------------------------------

  static Future<dynamic> _getJson(String url, {Duration timeout = const Duration(seconds: 25)}) async {
    final r = await http.get(Uri.parse(url)).timeout(timeout);
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
    return json.decode(utf8.decode(r.bodyBytes));
  }

  /// Studio, season, trailer, relations, recommendations and characters, or {}.
  static Future<Map<String, dynamic>> extra(String id) async {
    try {
      final body = await _getJson('$baseUrl/anime/extra/${Uri.encodeComponent(id)}');
      return body is Map ? Map<String, dynamic>.from(body) : {};
    } catch (_) {
      return {};
    }
  }

  /// Per-episode titles, synopses, screenshots and air dates, or [].
  static Future<List<Map<String, dynamic>>> episodes(String id) async {
    try {
      final body = await _getJson('$baseUrl/anime/episodes/${Uri.encodeComponent(id)}');
      return body is List ? [for (final e in body) if (e is Map) Map<String, dynamic>.from(e)] : [];
    } catch (_) {
      return [];
    }
  }

  /// What airs in the next [days] days: [{airingAt, episode, media}], or [].
  static Future<List<Map<String, dynamic>>> schedule({int days = 7}) async {
    try {
      final body = await _getJson('$baseUrl/anime/schedule?days=$days', timeout: const Duration(seconds: 30));
      return body is List ? [for (final e in body) if (e is Map) Map<String, dynamic>.from(e)] : [];
    } catch (_) {
      return [];
    }
  }

  /// Search with filters: {media, hasNextPage, available}. [filters] keys are
  /// q, genres, year, season, format, status, min_score, sort, page, per_page.
  static Future<Map<String, dynamic>> filter(Map<String, String> filters) async {
    try {
      final q = Uri(queryParameters: {
        for (final e in filters.entries) if (e.value.isNotEmpty) e.key: e.value,
      }).query;
      final body = await _getJson('$baseUrl/anime/filter?$q');
      return body is Map ? Map<String, dynamic>.from(body) : {'media': [], 'available': false};
    } catch (_) {
      return {'media': [], 'hasNextPage': false, 'available': false};
    }
  }

  /// Tells the server a stream plays wrong, so it is left out for a while.
  static Future<bool> report(String id, int epNum, String category, String url, String reason) async {
    try {
      final r = await http
          .post(Uri.parse('$webUrl/api/report'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'episode_id': '$id/$epNum', 'category': category, 'url': url, 'reason': reason}))
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Which tracking services this server can connect: {anilist: {enabled,
  /// authorize_url}, mal: {enabled}}.
  static Future<Map<String, dynamic>> trackingConfig() async {
    try {
      final body = await _getJson('$baseUrl/tracking/config', timeout: const Duration(seconds: 10));
      return body is Map ? Map<String, dynamic>.from(body) : {};
    } catch (_) {
      return {};
    }
  }
}
