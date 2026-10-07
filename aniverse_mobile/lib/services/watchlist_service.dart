import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'auth_service.dart';

/// One anime on My List. [seenEpisode] is how many episodes were out when the
/// viewer last looked; anything aired since is "new".
class WatchEntry {
  final String animeId;
  String title;
  String cover;
  int seenEpisode;
  int updatedAt;
  bool deleted;

  WatchEntry({
    required this.animeId,
    this.title = '',
    this.cover = '',
    this.seenEpisode = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  factory WatchEntry.fromJson(Map<String, dynamic> j) => WatchEntry(
        animeId: j['anime_id'].toString(),
        title: (j['title'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        seenEpisode: ((j['seen_episode'] ?? 0) as num).toInt(),
        updatedAt: ((j['updated_at'] ?? 0) as num).toInt(),
        deleted: j['deleted'] == true,
      );

  Map<String, dynamic> toJson() => {
        'anime_id': animeId,
        'title': title,
        'cover': cover,
        'seen_episode': seenEpisode,
        'updated_at': updatedAt,
        'deleted': deleted,
      };
}

/// My List, the same as the website's: kept on the device, synced with the
/// account when signed in (newest change wins per anime, removals kept as
/// tombstones). The native alert job reads [prefsKey] directly.
class WatchlistService {
  static const prefsKey = 'av.watchlist.v1';
  static const _syncedKey = 'av.watchlist.synced';

  static final Map<String, WatchEntry> _entries = {};
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static Timer? _syncTimer;
  static Future<void>? _syncing;

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null) return;
      for (final item in json.decode(raw) as List) {
        final e = WatchEntry.fromJson(Map<String, dynamic>.from(item as Map));
        _entries[e.animeId] = e;
      }
      changes.value++;
    } catch (e) {
      debugPrint('watchlist load failed: $e');
    }
  }

  /// Followed anime, most recently changed first.
  static List<WatchEntry> all() =>
      _entries.values.where((e) => !e.deleted).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  static bool has(String animeId) => _entries[animeId]?.deleted == false;
  static WatchEntry? entry(String animeId) => has(animeId) ? _entries[animeId] : null;

  static void follow(String animeId, {String title = '', String cover = '', int seen = 0}) {
    _entries[animeId] = WatchEntry(animeId: animeId, title: title, cover: cover, seenEpisode: seen, updatedAt: _now);
    _changed(syncNow: true);
  }

  static void unfollow(String animeId) {
    final e = _entries[animeId];
    if (e == null) return;
    e
      ..deleted = true
      ..updatedAt = _now;
    _changed(syncNow: true);
  }

  /// The viewer has seen that [aired] episodes are out: no longer new.
  static void markSeen(String animeId, int aired) {
    final e = entry(animeId);
    if (e == null || e.seenEpisode >= aired) return;
    e
      ..seenEpisode = aired
      ..updatedAt = _now;
    _changed();
  }

  static void _changed({bool syncNow = false}) {
    changes.value++;
    _persist();
    if (!AuthService.signedIn) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(syncNow ? const Duration(seconds: 1) : const Duration(seconds: 8), () => sync());
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, json.encode([for (final e in _entries.values) e.toJson()]));
    } catch (e) {
      debugPrint('watchlist save failed: $e');
    }
  }

  /// Push changes since the last sync and merge what the account has.
  static Future<void> sync({bool full = false}) {
    if (!AuthService.signedIn) return Future.value();
    return _syncing ??= _sync(full).whenComplete(() => _syncing = null);
  }

  static Future<void> _sync(bool full) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final since = full ? 0 : (prefs.getInt(_syncedKey) ?? 0);
      final startedAt = _now;
      final pending = [for (final e in _entries.values) if (e.updatedAt > since) e.toJson()];
      final r = await http
          .put(Uri.parse('${ApiService.baseUrl}/watchlist'),
              headers: AuthService.headers, body: json.encode({'entries': pending.take(200).toList()}))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode == 401) {
        await AuthService.sessionExpired();
        return;
      }
      if (r.statusCode != 200) return;
      for (final item in (json.decode(r.body) as Map)['entries'] as List) {
        final remote = WatchEntry.fromJson(Map<String, dynamic>.from(item as Map));
        final local = _entries[remote.animeId];
        if (local == null || remote.updatedAt >= local.updatedAt) _entries[remote.animeId] = remote;
      }
      await prefs.setInt(_syncedKey, startedAt);
      changes.value++;
      await _persist();
    } catch (e) {
      debugPrint('watchlist sync failed: $e');
    }
  }
}
