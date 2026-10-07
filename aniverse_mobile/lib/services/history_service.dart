import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'auth_service.dart';

/// One episode the user has watched, and how far into it they got.
class HistoryEntry {
  final String animeId;
  final int episode;
  String title;
  String cover;
  int positionMs;
  int durationMs;

  /// Milliseconds since the epoch. The newest write wins when devices merge.
  int updatedAt;

  /// Removed by the user. Kept as a marker so the removal reaches the account
  /// and other devices instead of the entry being synced straight back.
  bool deleted;

  /// Changed locally since the account last saw it.
  bool dirty;

  HistoryEntry({
    required this.animeId,
    required this.episode,
    this.title = '',
    this.cover = '',
    this.positionMs = 0,
    this.durationMs = 0,
    required this.updatedAt,
    this.deleted = false,
    this.dirty = false,
  });

  String get key => '$animeId|$episode';

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  double get fraction =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  /// Close enough to the end that the credits are all that is left.
  bool get finished => durationMs > 0 && positionMs >= durationMs * 0.9;

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        animeId: j['anime_id'].toString(),
        episode: (j['episode'] as num).toInt(),
        title: (j['title'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        positionMs: ((j['position_ms'] ?? 0) as num).toInt(),
        durationMs: ((j['duration_ms'] ?? 0) as num).toInt(),
        updatedAt: ((j['updated_at'] ?? 0) as num).toInt(),
        deleted: j['deleted'] == true,
        dirty: j['dirty'] == true,
      );

  Map<String, dynamic> toJson({bool includeLocal = true}) => {
        'anime_id': animeId,
        'episode': episode,
        'title': title,
        'cover': cover,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at': updatedAt,
        'deleted': deleted,
        if (includeLocal) 'dirty': dirty,
      };
}

/// Watch history.
///
/// Always kept on the device, so it works signed out and while the server is
/// unreachable. When signed in, changes are pushed to the account and merged
/// with what other devices have written (newest change wins per episode).
class HistoryService {
  static const _prefsKey = 'aniverse_history_v1';
  static const _maxEntries = 400;
  static const _tombstoneTtl = Duration(days: 30);

  static final Map<String, HistoryEntry> _entries = {};

  /// Bumped on every change, so screens can rebuild with a
  /// ValueListenableBuilder instead of polling.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Timer? _saveTimer;
  static Timer? _syncTimer;
  static Future<void>? _syncing;

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      for (final item in json.decode(raw) as List) {
        final e = HistoryEntry.fromJson(Map<String, dynamic>.from(item as Map));
        _entries[e.key] = e;
      }
      changes.value++;
    } catch (e) {
      debugPrint('history load failed: $e');
    }
  }

  // --- reads -----------------------------------------------------------------

  static HistoryEntry? progressFor(String animeId, int episode) {
    final e = _entries['$animeId|$episode'];
    return (e == null || e.deleted) ? null : e;
  }

  /// Every episode watched, for the achievements.
  static List<HistoryEntry> all() => [for (final e in _entries.values) if (!e.deleted) e];

  /// Every episode watched of [animeId], keyed by episode number.
  static Map<int, HistoryEntry> episodesOf(String animeId) => {
        for (final e in _entries.values)
          if (!e.deleted && e.animeId == animeId) e.episode: e,
      };

  /// The most recent episode of each anime, newest first: "continue watching".
  static List<HistoryEntry> latestPerAnime() {
    final latest = <String, HistoryEntry>{};
    for (final e in _entries.values) {
      if (e.deleted) continue;
      final seen = latest[e.animeId];
      if (seen == null || e.updatedAt > seen.updatedAt) latest[e.animeId] = e;
    }
    return latest.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  // --- writes ----------------------------------------------------------------

  /// Save how far into an episode the user is.
  static void record({
    required String animeId,
    required int episode,
    String? title,
    String? cover,
    required Duration position,
    required Duration duration,
  }) {
    final key = '$animeId|$episode';
    final e = _entries[key] ??
        HistoryEntry(animeId: animeId, episode: episode, updatedAt: _now);
    if (title != null && title.isNotEmpty) e.title = title;
    if (cover != null && cover.isNotEmpty) e.cover = cover;
    e.positionMs = position.inMilliseconds;
    if (duration > Duration.zero) e.durationMs = duration.inMilliseconds;
    e.updatedAt = _now;
    e.deleted = false;
    e.dirty = true;
    _entries[key] = e;
    _changed();
  }

  static void removeAnime(String animeId) {
    final now = _now;
    for (final e in _entries.values) {
      if (e.animeId != animeId || e.deleted) continue;
      e
        ..deleted = true
        ..updatedAt = now
        ..dirty = true;
    }
    _changed(syncSoon: true);
  }

  static void clearAll() {
    final now = _now;
    for (final e in _entries.values) {
      if (e.deleted) continue;
      e
        ..deleted = true
        ..updatedAt = now
        ..dirty = true;
    }
    _changed(syncSoon: true);
  }

  /// Forget everything on this device. Used on sign-out: the history belongs to
  /// the account, and the next person to use the phone should not see it.
  static Future<void> clearLocal() async {
    _syncTimer?.cancel();
    _entries.clear();
    changes.value++;
    await _persist();
  }

  static void _changed({bool syncSoon = false}) {
    _prune();
    changes.value++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _persist);
    // Progress is recorded every few seconds while playing, so pushes are
    // batched; a removal is something the user did on purpose and goes sooner.
    _scheduleSync(
        syncSoon ? const Duration(seconds: 2) : const Duration(seconds: 20));
  }

  static void _prune() {
    final cutoff = _now - _tombstoneTtl.inMilliseconds;
    _entries
        .removeWhere((_, e) => e.deleted && !e.dirty && e.updatedAt < cutoff);

    final live = _entries.values.where((e) => !e.deleted).toList();
    if (live.length > _maxEntries) {
      live.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final e in live.take(live.length - _maxEntries)) {
        _entries.remove(e.key);
      }
    }
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        json.encode(_entries.values.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('history save failed: $e');
    }
  }

  /// Write pending changes now, e.g. as the player closes.
  static Future<void> flush() async {
    _saveTimer?.cancel();
    await _persist();
  }

  // --- account sync ------------------------------------------------------------

  static void _scheduleSync(Duration delay) {
    if (!AuthService.signedIn) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(delay, () => sync());
  }

  /// Push local changes to the account and pull everything it knows.
  ///
  /// Safe to call at any time; overlapping calls share one run. Failures are
  /// swallowed -- the entries stay dirty and go up on the next sync.
  static Future<void> sync() {
    if (!AuthService.signedIn) return Future.value();
    return _syncing ??= _sync().whenComplete(() => _syncing = null);
  }

  static Future<void> _sync() async {
    _syncTimer?.cancel();
    try {
      final pending = _entries.values.where((e) => e.dirty).toList();
      List<dynamic>? serverEntries;

      if (pending.isEmpty) {
        final r = await http
            .get(Uri.parse('${ApiService.baseUrl}/history'),
                headers: AuthService.headers)
            .timeout(const Duration(seconds: 30));
        if (r.statusCode == 401) {
          await AuthService.sessionExpired();
          return;
        }
        if (r.statusCode != 200) return;
        serverEntries = (json.decode(r.body) as Map)['entries'] as List;
      } else {
        // The server caps a batch at 200 entries.
        for (var i = 0; i < pending.length; i += 200) {
          final batch = pending.skip(i).take(200).toList();
          final sentAt = {for (final e in batch) e.key: e.updatedAt};
          final r = await http
              .put(
                Uri.parse('${ApiService.baseUrl}/history'),
                headers: AuthService.headers,
                body: json.encode({
                  'entries': [
                    for (final e in batch) e.toJson(includeLocal: false)
                  ],
                }),
              )
              .timeout(const Duration(seconds: 30));
          if (r.statusCode == 401) {
            await AuthService.sessionExpired();
            return;
          }
          if (r.statusCode != 200) return;
          for (final e in batch) {
            // Entries are updated in place while playing, so compare what was
            // sent: a write that landed during the request stays dirty.
            if (e.updatedAt == sentAt[e.key]) e.dirty = false;
          }
          serverEntries = (json.decode(r.body) as Map)['entries'] as List;
        }
      }

      for (final item in serverEntries ?? const []) {
        final remote =
            HistoryEntry.fromJson(Map<String, dynamic>.from(item as Map));
        final local = _entries[remote.key];
        if (local == null ||
            (!local.dirty && remote.updatedAt >= local.updatedAt)) {
          _entries[remote.key] = remote..dirty = false;
        }
      }
      _prune();
      changes.value++;
      await _persist();
    } catch (e) {
      debugPrint('history sync failed: $e');
    }
  }
}
