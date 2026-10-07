import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'app_settings.dart';

/// An episode saved for watching offline.
class DownloadItem {
  final String animeId;
  final int episode;
  final String category;
  String title;
  String cover;

  /// queued | downloading | done | failed
  String status;
  double progress;
  int bytes;
  String quality;
  String? error;

  /// Folder under downloads/, holding index.m3u8 (or video.mp4) and subs.vtt.
  final String dir;
  bool hasSubs;
  Map<String, dynamic>? intro;
  Map<String, dynamic>? outro;
  final int addedAt;

  DownloadItem({
    required this.animeId,
    required this.episode,
    required this.category,
    this.title = '',
    this.cover = '',
    this.status = 'queued',
    this.progress = 0,
    this.bytes = 0,
    this.quality = '',
    this.error,
    required this.dir,
    this.hasSubs = false,
    this.intro,
    this.outro,
    required this.addedAt,
  });

  String get key => '$animeId|$episode|$category';
  bool get done => status == 'done';

  factory DownloadItem.fromJson(Map<String, dynamic> j) => DownloadItem(
        animeId: j['anime_id'].toString(),
        episode: (j['episode'] as num).toInt(),
        category: (j['category'] ?? 'sub').toString(),
        title: (j['title'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        // A download cut off by the app closing picks up where it stopped.
        status: j['status'] == 'done' ? 'done' : 'failed',
        progress: ((j['progress'] ?? 0) as num).toDouble(),
        bytes: ((j['bytes'] ?? 0) as num).toInt(),
        quality: (j['quality'] ?? '').toString(),
        error: j['status'] == 'done' ? null : 'Stopped before it finished. Tap retry to carry on.',
        dir: j['dir'].toString(),
        hasSubs: j['subs'] == true,
        intro: j['intro'] is Map ? Map<String, dynamic>.from(j['intro'] as Map) : null,
        outro: j['outro'] is Map ? Map<String, dynamic>.from(j['outro'] as Map) : null,
        addedAt: ((j['added_at'] ?? 0) as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'anime_id': animeId,
        'episode': episode,
        'category': category,
        'title': title,
        'cover': cover,
        'status': status,
        'progress': progress,
        'bytes': bytes,
        'quality': quality,
        'dir': dir,
        'subs': hasSubs,
        'intro': intro,
        'outro': outro,
        'added_at': addedAt,
      };
}

/// Offline episodes. HLS streams are saved as their segments plus a local
/// playlist that points at them, which the player opens like any stream; MP4
/// sources are saved as one file. One download runs at a time, the rest wait.
/// Downloads only run while the app is open; one that was cut off resumes from
/// the segments it already has.
class DownloadService {
  static final List<DownloadItem> _items = [];
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static Directory? _root;
  static bool _running = false;
  static final Set<String> _cancelled = {};

  static Future<Directory> _dir() async {
    final r = _root;
    if (r != null) return r;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/downloads');
    await d.create(recursive: true);
    return _root = d;
  }

  static Future<void> load() async {
    try {
      final f = File('${(await _dir()).path}/index.json');
      if (!await f.exists()) return;
      for (final j in json.decode(await f.readAsString()) as List) {
        _items.add(DownloadItem.fromJson(Map<String, dynamic>.from(j as Map)));
      }
      changes.value++;
    } catch (e) {
      debugPrint('downloads load failed: $e');
    }
  }

  static Future<void> _save() async {
    try {
      final f = File('${(await _dir()).path}/index.json');
      await f.writeAsString(json.encode([for (final i in _items) i.toJson()]));
    } catch (e) {
      debugPrint('downloads save failed: $e');
    }
  }

  static List<DownloadItem> get items => List.unmodifiable(_items..sort((a, b) => b.addedAt.compareTo(a.addedAt)));

  /// The saved copy of an episode, if any; a finished one in [category] first.
  static DownloadItem? find(String animeId, int episode, {String? category}) {
    DownloadItem? best;
    for (final i in _items) {
      if (i.animeId != animeId || i.episode != episode) continue;
      if (category != null && i.category != category) continue;
      if (best == null || (i.done && !best.done)) best = i;
    }
    return best;
  }

  /// Where the player should open a finished download.
  static Future<String> mediaPath(DownloadItem item) async {
    final d = '${(await _dir()).path}/${item.dir}';
    return await File('$d/video.mp4').exists() ? '$d/video.mp4' : '$d/index.m3u8';
  }

  static Future<String?> subtitlePath(DownloadItem item) async {
    if (!item.hasSubs) return null;
    final f = File('${(await _dir()).path}/${item.dir}/subs.vtt');
    return await f.exists() ? f.path : null;
  }

  static Future<int> totalBytes() async => _items.fold<int>(0, (s, i) => s + i.bytes);

  /// Queue an episode. Returns false if it is already saved or queued.
  static bool enqueue({
    required String animeId,
    required int episode,
    String category = 'sub',
    String title = '',
    String cover = '',
  }) {
    final existing = find(animeId, episode, category: category);
    if (existing != null && existing.status != 'failed') return false;
    if (existing != null) {
      existing
        ..status = 'queued'
        ..error = null;
    } else {
      _items.add(DownloadItem(
        animeId: animeId,
        episode: episode,
        category: category,
        title: title,
        cover: cover,
        dir: '${animeId}_${episode}_$category',
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    _cancelled.remove('$animeId|$episode|$category');
    changes.value++;
    _save();
    _pump();
    return true;
  }

  static Future<void> delete(DownloadItem item) async {
    _cancelled.add(item.key);
    _items.remove(item);
    changes.value++;
    await _save();
    try {
      final d = Directory('${(await _dir()).path}/${item.dir}');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  static void _changed(DownloadItem item) {
    changes.value++;
  }

  static Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = _items.where((i) => i.status == 'queued').toList();
        if (next.isEmpty) break;
        await _download(next.first);
        await _save();
      }
    } finally {
      _running = false;
    }
  }

  static Future<void> _download(DownloadItem item) async {
    item
      ..status = 'downloading'
      ..error = null;
    _changed(item);
    final dir = Directory('${(await _dir()).path}/${item.dir}');
    await dir.create(recursive: true);
    try {
      final data = await ApiService.getSources(item.animeId, item.episode, item.category);
      final sources = [for (final s in (data['sources'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
      if (sources.isEmpty) throw StateError((data['error'] ?? 'No stream was found for this episode.').toString());

      Object? lastError;
      for (final src in sources) {
        if (_cancelled.contains(item.key)) return;
        try {
          final url = src['url'].toString();
          final hls = src['isM3U8'] == true || url.contains('m3u8');
          if (hls) {
            await _saveHls(item, url, dir);
          } else {
            await _saveFile(item, url, File('${dir.path}/video.mp4'));
            item.quality = 'MP4';
          }
          item.intro = src['intro'] is Map ? Map<String, dynamic>.from(src['intro'] as Map) : null;
          item.outro = src['outro'] is Map ? Map<String, dynamic>.from(src['outro'] as Map) : null;
          await _saveSubs(item, src, dir);
          item
            ..status = 'done'
            ..progress = 1;
          _changed(item);
          return;
        } catch (e) {
          lastError = e;
          debugPrint('download from ${src['serverName']} failed: $e');
        }
      }
      throw lastError ?? StateError('No stream would download.');
    } catch (e) {
      if (_cancelled.contains(item.key)) return;
      item
        ..status = 'failed'
        ..error = e is StateError ? e.message : 'The download stopped: check the connection and retry.';
      _changed(item);
    }
  }

  // --- HLS -----------------------------------------------------------------------------

  static Future<String> _text(String url) async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// The variant to save: the lowest with data saver on, else the best at or
  /// under 720p (a good picture for a phone at a sensible size).
  static (String, String) _pickVariant(String master, Uri base) {
    final lines = master.split('\n').map((l) => l.trim()).toList();
    final variants = <(int, int, String)>[]; // (height, bandwidth, uri)
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final res = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(lines[i]);
      final bw = RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i]);
      var j = i + 1;
      while (j < lines.length && (lines[j].isEmpty || lines[j].startsWith('#'))) {
        j++;
      }
      if (j >= lines.length) continue;
      variants.add((int.tryParse(res?.group(1) ?? '') ?? 0, int.tryParse(bw?.group(1) ?? '') ?? 0, base.resolve(lines[j]).toString()));
    }
    if (variants.isEmpty) return (base.toString(), '');
    variants.sort((a, b) => a.$2.compareTo(b.$2));
    var pick = variants.first;
    if (!AppSettings.dataSaver) {
      final fit = variants.where((v) => v.$1 > 0 && v.$1 <= 720).toList();
      if (fit.isNotEmpty) pick = fit.last;
    }
    return (pick.$3, pick.$1 > 0 ? '${pick.$1}p' : '');
  }

  static Future<void> _saveHls(DownloadItem item, String url, Directory dir) async {
    var playlistUrl = url;
    var text = await _text(url);
    if (text.contains('#EXT-X-STREAM-INF')) {
      final (variant, label) = _pickVariant(text, Uri.parse(url));
      playlistUrl = variant;
      item.quality = label;
      text = await _text(variant);
    }
    final base = Uri.parse(playlistUrl);
    final fmp4 = text.contains('#EXT-X-MAP');
    final out = StringBuffer();
    final jobs = <(String, File)>[];
    var n = 0, keys = 0;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        // Keys and init segments are files too: save them and point at the copies.
        if ((line.startsWith('#EXT-X-KEY') || line.startsWith('#EXT-X-MAP')) && line.contains('URI="')) {
          final m = RegExp(r'URI="([^"]+)"').firstMatch(line)!;
          final name = line.startsWith('#EXT-X-KEY') ? 'key${keys++}.bin' : 'init.mp4';
          jobs.add((base.resolve(m.group(1)!).toString(), File('${dir.path}/$name')));
          out.writeln(line.replaceFirst(m.group(0)!, 'URI="$name"'));
        } else {
          out.writeln(line);
        }
        continue;
      }
      final name = 's${(n++).toString().padLeft(5, '0')}.${fmp4 ? 'm4s' : 'ts'}';
      jobs.add((base.resolve(line).toString(), File('${dir.path}/$name')));
      out.writeln(name);
    }
    if (n == 0) throw StateError('The stream had no video segments.');

    var doneCount = 0;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (_cancelled.contains(item.key)) throw StateError('Cancelled');
        final i = next++;
        if (i >= jobs.length) return;
        final (u, f) = jobs[i];
        if (!(await f.exists() && await f.length() > 0)) {
          await _fetchTo(u, f);
        }
        item.bytes += await f.length();
        doneCount++;
        item.progress = doneCount / jobs.length;
        if (doneCount % 4 == 0 || doneCount == jobs.length) _changed(item);
      }
    }

    item.bytes = 0;
    await Future.wait([for (var w = 0; w < 4; w++) worker()]);
    await File('${dir.path}/index.m3u8').writeAsString(out.toString());
  }

  static Future<void> _fetchTo(String url, File f) async {
    Object? err;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw http.ClientException('HTTP ${r.statusCode}');
        final tmp = File('${f.path}.part');
        await tmp.writeAsBytes(r.bodyBytes, flush: true);
        await tmp.rename(f.path);
        return;
      } catch (e) {
        err = e;
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw err ?? StateError('download failed');
  }

  // --- MP4 -------------------------------------------------------------------------------

  static Future<void> _saveFile(DownloadItem item, String url, File f) async {
    final client = http.Client();
    try {
      final r = await client.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
      final total = r.contentLength ?? 0;
      final sink = File('${f.path}.part').openWrite();
      var got = 0;
      await for (final chunk in r.stream) {
        if (_cancelled.contains(item.key)) {
          await sink.close();
          throw StateError('Cancelled');
        }
        sink.add(chunk);
        got += chunk.length;
        item.bytes = got;
        if (total > 0) item.progress = got / total;
        _changed(item);
      }
      await sink.close();
      await File('${f.path}.part').rename(f.path);
    } finally {
      client.close();
    }
  }

  static Future<void> _saveSubs(DownloadItem item, Map<String, dynamic> src, Directory dir) async {
    final tracks = [for (final t in (src['subtitles'] as List? ?? const [])) if (t is Map) t];
    if (tracks.isEmpty) return;
    final lang = AppSettings.subLang.toLowerCase();
    bool named(Map t, String p) => (t['label'] ?? '').toString().toLowerCase().startsWith(p);
    final track = (lang.isNotEmpty ? tracks.where((t) => named(t, lang)).firstOrNull : null) ??
        tracks.where((t) => t['default'] == true).firstOrNull ??
        tracks.where((t) => named(t, 'english')).firstOrNull ??
        tracks.first;
    final text = await ApiService.getSubtitleFile((track['url'] ?? '').toString());
    if (text == null) return;
    await File('${dir.path}/subs.vtt').writeAsString(text);
    item.hasSubs = true;
  }
}
