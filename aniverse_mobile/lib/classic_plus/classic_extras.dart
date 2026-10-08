// What the 2D app gained since the classic UI was set aside -- My List, the
// airing schedule, downloads, and a settings page -- in the classic look
// (lib/theme.dart), so the classic UI can ship again (kUse2DUi in main.dart)
// without losing them. They share every service with the 2D UI; only the
// widgets are classic.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_version.dart';
import '../screens/detail_screen.dart';
import '../screens/history_screen.dart';
import '../screens/watch_screen.dart';
import '../services/api_service.dart';
import '../services/app_settings.dart';
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../services/native_bridge.dart';
import '../services/watchlist_service.dart';
import '../theme.dart';
import '../widgets/aniverse_logo.dart';

// The same rules as the 2D UI's titleOf / coverOf / airedEpisodes (pixel_extras.dart).
String _titleOf(Map? a) {
  final t = a?['title'];
  if (t is Map) {
    for (final k in const ['english', 'romaji']) {
      final v = t[k];
      if (v is String && v.isNotEmpty) return v;
    }
  }
  return (a?['name'] ?? 'Untitled').toString();
}

String _coverOf(Map? a) {
  final c = a?['coverImage'];
  if (c is Map) return (c['large'] ?? c['medium'] ?? '').toString();
  return (a?['cover'] ?? '').toString();
}

int _aired(Map? a) {
  final next = a?['nextAiringEpisode'];
  if (next is Map && next['episode'] is num && (next['episode'] as num) > 1) {
    return (next['episode'] as num).toInt() - 1;
  }
  if (a?['status'] == 'NOT_YET_RELEASED') return 0;
  final eps = a?['episodes'];
  return eps is num && eps > 0 ? eps.toInt() : 12;
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

Widget _cover(String url, double w, double h) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url.isEmpty
          ? Container(width: w, height: h, color: AniVerseTheme.surfaceHigh)
          : CachedNetworkImage(
              imageUrl: url,
              width: w,
              height: h,
              fit: BoxFit.cover,
              memCacheWidth: (w * 2).round(),
              errorWidget: (_, __, ___) => Container(width: w, height: h, color: AniVerseTheme.surfaceHigh),
            ),
    );

Widget _empty(IconData icon, String title, String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: AniVerseTheme.textFaint),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AniVerseTheme.textDim, height: 1.4)),
        ]),
      ),
    );

/// The home screen's menu: everything that isn't browsing.
class ClassicMoreMenu extends StatelessWidget {
  final VoidCallback onServer;
  const ClassicMoreMenu({super.key, required this.onServer});

  @override
  Widget build(BuildContext context) {
    void open(Widget page) => Navigator.push(context, FadeScaleRoute(page: page));
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, color: Colors.white70),
      color: AniVerseTheme.surface,
      onSelected: (v) => switch (v) {
        'list' => open(const ClassicMyListScreen()),
        'schedule' => open(const ClassicScheduleScreen()),
        'downloads' => open(const ClassicDownloadsScreen()),
        'history' => open(const HistoryScreen()),
        'settings' => open(const ClassicSettingsScreen()),
        _ => onServer(),
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'list', child: ListTile(leading: Icon(Icons.bookmark_outline), title: Text('My List'))),
        PopupMenuItem(value: 'schedule', child: ListTile(leading: Icon(Icons.event_outlined), title: Text('Airing schedule'))),
        PopupMenuItem(value: 'downloads', child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Downloads'))),
        PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('History'))),
        PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
        PopupMenuItem(value: 'server', child: ListTile(leading: Icon(Icons.dns_outlined), title: Text('Server address'))),
      ],
    );
  }
}

/// Follow or unfollow an anime (My List), for the detail screen's header.
class ClassicFollowButton extends StatelessWidget {
  final String animeId;
  final Map<String, dynamic>? anime;
  const ClassicFollowButton({super.key, required this.animeId, this.anime});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: WatchlistService.changes,
      builder: (context, _, __) {
        final on = WatchlistService.has(animeId);
        return IconButton(
          tooltip: on ? 'Remove from My List' : 'Add to My List',
          icon: Icon(on ? Icons.bookmark : Icons.bookmark_outline, color: on ? AniVerseTheme.red : Colors.white70),
          onPressed: () {
            if (on) {
              WatchlistService.unfollow(animeId);
              return;
            }
            WatchlistService.follow(animeId, title: _titleOf(anime), cover: _coverOf(anime), seen: _aired(anime));
            _snack(context, 'Added to My List. Turn on alerts in Settings to hear about new episodes.');
          },
        );
      },
    );
  }
}

// --- My List ---------------------------------------------------------------------------------

class ClassicMyListScreen extends StatelessWidget {
  const ClassicMyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My List')),
      body: RefreshIndicator(
        onRefresh: () => WatchlistService.sync(full: true),
        child: ValueListenableBuilder<int>(
          valueListenable: WatchlistService.changes,
          builder: (context, _, __) {
            final entries = WatchlistService.all();
            if (entries.isEmpty) {
              return ListView(children: [
                _empty(Icons.bookmark_outline, 'Your list is empty',
                    'Tap the bookmark on any anime to follow it and get told when new episodes air.'),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ListRow(entry: entries[i], key: ValueKey(entries[i].animeId)),
            );
          },
        ),
      ),
    );
  }
}

class _ListRow extends StatefulWidget {
  final WatchEntry entry;
  const _ListRow({super.key, required this.entry});

  @override
  State<_ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<_ListRow> {
  Map<String, dynamic>? _info;

  @override
  void initState() {
    super.initState();
    ApiService.getAnimeDetails(widget.entry.animeId).then((a) {
      if (!mounted || a == null) return;
      setState(() => _info = a);
      // Seen now: the alert for these episodes has done its job.
      Future.delayed(const Duration(milliseconds: 1500), () => WatchlistService.markSeen(widget.entry.animeId, _aired(a)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final info = _info;
    final aired = _aired(info);
    final fresh = info != null && e.seenEpisode > 0 ? aired - e.seenEpisode : 0;
    final watched = HistoryService.episodesOf(e.animeId).keys.fold<int>(0, (m, n) => n > m ? n : m);
    final next = aired == 0 ? 1 : (watched + 1).clamp(1, aired);
    return Material(
      color: AniVerseTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.push(context, FadeScaleRoute(page: DetailScreen(id: e.animeId))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            _cover(e.cover, 52, 74),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title.isEmpty ? 'Untitled' : e.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  info == null
                      ? 'Checking…'
                      : '${fresh > 0 ? '$fresh new · ' : ''}$aired out'
                          '${info['status'] == 'RELEASING' ? ' · airing' : ''}${watched > 0 ? ' · on $watched' : ''}',
                  style: TextStyle(fontSize: 12, color: fresh > 0 ? AniVerseTheme.red : AniVerseTheme.textDim),
                ),
              ]),
            ),
            if (info != null && aired > 0)
              FilledButton(
                onPressed: () => Navigator.push(
                    context, FadeScaleRoute(page: WatchScreen(animeId: e.animeId, epNum: next, title: e.title, cover: e.cover))),
                child: Text('EP $next'),
              ),
            IconButton(
              tooltip: 'Remove ${e.title}',
              icon: const Icon(Icons.delete_outline, color: AniVerseTheme.textDim),
              onPressed: () => WatchlistService.unfollow(e.animeId),
            ),
          ]),
        ),
      ),
    );
  }
}

// --- Airing schedule ---------------------------------------------------------------------------

class ClassicScheduleScreen extends StatefulWidget {
  const ClassicScheduleScreen({super.key});

  @override
  State<ClassicScheduleScreen> createState() => _ClassicScheduleScreenState();
}

class _ClassicScheduleScreenState extends State<ClassicScheduleScreen> {
  List<Map<String, dynamic>>? _items;
  String? _day;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await ApiService.schedule();
    if (!mounted) return;
    setState(() {
      _items = items;
      _day = items.isEmpty ? null : _dayKey(_at(items.first));
    });
  }

  static int _at(Map it) => (it['airingAt'] as num).toInt();

  static String _dayKey(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${d.year}-${d.month}-${d.day}';
  }

  static String _countdown(int secs) {
    if (secs <= 0) return 'Out now';
    final d = secs ~/ 86400, h = (secs % 86400) ~/ 3600, m = (secs % 3600) ~/ 60;
    return d > 0 ? 'in ${d}d ${h}h' : h > 0 ? 'in ${h}h ${m}m' : 'in ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Airing schedule')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? _empty(Icons.event_busy, 'No schedule right now', "AniList didn't answer. Pull down or come back in a moment.")
              : ValueListenableBuilder<int>(
                  valueListenable: WatchlistService.changes,
                  builder: (context, _, __) => _body(items),
                ),
    );
  }

  Widget _body(List<Map<String, dynamic>> items) {
    final days = <String>[];
    for (final it in items) {
      final k = _dayKey(_at(it));
      if (!days.contains(k)) days.add(k);
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final rows = items.where((it) => _dayKey(_at(it)) == _day).toList()
      ..sort((a, b) {
        final fa = WatchlistService.has(a['media']['id'].toString()) ? 0 : 1;
        final fb = WatchlistService.has(b['media']['id'].toString()) ? 0 : 1;
        return fa != fb ? fa - fb : _at(a).compareTo(_at(b));
      });
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          children: [
            for (final k in days)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(k == _dayKey(now)
                      ? 'Today'
                      : () {
                          final d = DateTime.fromMillisecondsSinceEpoch(_at(items.firstWhere((it) => _dayKey(_at(it)) == k)) * 1000);
                          return '${_weekdays[d.weekday - 1]} ${d.day}';
                        }()),
                  selected: k == _day,
                  selectedColor: AniVerseTheme.red,
                  onSelected: (_) => setState(() => _day = k),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(color: AniVerseTheme.surfaceHigh, height: 16),
          itemBuilder: (_, i) => _row(rows[i], now),
        ),
      ),
    ]);
  }

  Widget _row(Map<String, dynamic> it, int now) {
    final media = Map<String, dynamic>.from(it['media'] as Map);
    final id = media['id'].toString();
    final at = _at(it);
    final ep = (it['episode'] as num).toInt();
    final aired = at <= now;
    final mine = WatchlistService.has(id);
    final when = DateTime.fromMillisecondsSinceEpoch(at * 1000);
    final time = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    return Opacity(
      opacity: aired ? 0.6 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: () => Navigator.push(
          context,
          FadeScaleRoute(
            page: aired
                ? WatchScreen(animeId: id, epNum: ep, title: _titleOf(media), cover: _coverOf(media))
                : DetailScreen(id: id),
          ),
        ),
        leading: _cover(_coverOf(media), 44, 62),
        title: Text(_titleOf(media), maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('$time · Episode $ep · ${_countdown(at - now)}',
            style: TextStyle(color: mine ? AniVerseTheme.red : AniVerseTheme.textDim, fontSize: 12)),
        trailing: IconButton(
          tooltip: mine ? 'Remove from My List' : 'Add to My List',
          icon: Icon(mine ? Icons.bookmark : Icons.bookmark_outline, color: mine ? AniVerseTheme.red : Colors.white54),
          onPressed: () => mine
              ? WatchlistService.unfollow(id)
              : WatchlistService.follow(id, title: _titleOf(media), cover: _coverOf(media), seen: ep - 1 < 0 ? 0 : ep - 1),
        ),
      ),
    );
  }
}

// --- Downloads ----------------------------------------------------------------------------------

class ClassicDownloadsScreen extends StatelessWidget {
  const ClassicDownloadsScreen({super.key});

  static String _size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ValueListenableBuilder<int>(
        valueListenable: DownloadService.changes,
        builder: (context, _, __) {
          final items = DownloadService.items;
          if (items.isEmpty) {
            return _empty(Icons.download_outlined, 'Nothing saved yet',
                'Long-press an episode on an anime\'s page to save it. Saved episodes play without a connection.');
          }
          final total = items.fold<int>(0, (s, i) => s + i.bytes);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('${items.length} episode${items.length == 1 ? '' : 's'} · ${_size(total)} · '
                  'downloads carry on in the background',
                  style: const TextStyle(color: AniVerseTheme.textDim, fontSize: 12)),
              const SizedBox(height: 12),
              for (final item in items) _row(context, item),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, DownloadItem item) {
    final status = switch (item.status) {
      'done' => '${item.quality.isEmpty ? '' : '${item.quality} · '}${_size(item.bytes)}',
      'downloading' => 'Downloading ${(item.progress * 100).toStringAsFixed(0)}% · ${_size(item.bytes)}',
      'queued' => 'Waiting',
      'waiting' => 'Waiting for Wi-Fi',
      _ => item.error ?? 'Failed',
    };
    return Card(
      color: AniVerseTheme.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: item.done
            ? () => Navigator.push(
                context,
                FadeScaleRoute(
                    page: WatchScreen(animeId: item.animeId, epNum: item.episode, title: item.title, cover: item.cover)))
            : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Row(children: [
              _cover(item.cover, 46, 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title.isEmpty ? 'Anime ${item.animeId}' : item.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Episode ${item.episode} · ${item.category.toUpperCase()}', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(status,
                      maxLines: 2,
                      style: TextStyle(fontSize: 12, color: item.status == 'failed' ? AniVerseTheme.red : AniVerseTheme.textDim)),
                ]),
              ),
              if (item.done) const Icon(Icons.play_circle_outline, color: AniVerseTheme.red),
              if (item.status == 'failed')
                IconButton(
                  tooltip: 'Retry',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => DownloadService.enqueue(
                      animeId: item.animeId, episode: item.episode, category: item.category, title: item.title, cover: item.cover),
                ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline, color: AniVerseTheme.textDim),
                onPressed: () => DownloadService.delete(item),
              ),
            ]),
            if (item.status == 'downloading') ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: item.progress),
            ],
          ]),
        ),
      ),
    );
  }
}

// --- Settings -----------------------------------------------------------------------------------

class ClassicSettingsScreen extends StatefulWidget {
  const ClassicSettingsScreen({super.key});

  @override
  State<ClassicSettingsScreen> createState() => _ClassicSettingsScreenState();
}

class _ClassicSettingsScreenState extends State<ClassicSettingsScreen> {
  static const _langs = ['', 'English', 'Spanish', 'Portuguese', 'French', 'German', 'Italian', 'Arabic', 'Russian', 'Indonesian'];

  Future<void> _set(String key, Object value) async {
    await AppSettings.set(key, value);
    if (mounted) setState(() {});
  }

  Future<T?> _pick<T>(String title, List<(T, String)> options, T current) => showDialog<T>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(title),
          children: [
            for (final (v, label) in options)
              ListTile(
                title: Text(label),
                trailing: v == current ? const Icon(Icons.check, color: AniVerseTheme.red) : null,
                onTap: () => Navigator.pop(ctx, v),
              ),
          ],
        ),
      );

  Future<void> _toggleAlerts(bool on) async {
    if (on && !await NativeBridge.requestNotifications()) {
      if (mounted) _snack(context, 'Notifications are off for AniVerse. Turn them on in Android settings.');
      return;
    }
    await _set('alerts', on);
    await NativeBridge.scheduleAlerts(on);
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: SectionHeader(title: text),
      );

  @override
  Widget build(BuildContext context) {
    const sizes = [('s', 'Small'), ('m', 'Medium'), ('l', 'Large'), ('xl', 'Extra large')];
    const qualities = [('auto', 'Auto'), ('1080', '1080p'), ('720', '720p'), ('480', '480p'), ('360', '360p')];
    const limits = [(0.0, 'No limit'), (2.0, '2 GB'), (5.0, '5 GB'), (10.0, '10 GB'), (20.0, '20 GB')];
    String labelOf<T>(List<(T, String)> opts, T v) => opts.firstWhere((o) => o.$1 == v, orElse: () => opts.first).$2;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _header('Playback'),
          ListTile(
            title: const Text('Quality'),
            subtitle: Text(labelOf(qualities, AppSettings.quality)),
            onTap: () async {
              final v = await _pick('Quality', qualities, AppSettings.quality);
              if (v != null) _set('quality', v);
            },
          ),
          SwitchListTile(
            title: const Text('Data saver'),
            subtitle: const Text('Always play and download the lowest quality.'),
            value: AppSettings.dataSaver,
            onChanged: (v) => _set('dataSaver', v),
          ),
          SwitchListTile(
            title: const Text('Picture in picture'),
            subtitle: const Text('Leaving the app while a video plays shrinks it into a window.'),
            value: AppSettings.pipAuto,
            onChanged: (v) => _set('pipAuto', v),
          ),
          SwitchListTile(
            title: const Text('Background audio'),
            subtitle: const Text('Keep the sound going with the screen off or in another app.'),
            value: AppSettings.bgAudio,
            onChanged: (v) => _set('bgAudio', v),
          ),
          _header('Subtitles'),
          ListTile(
            title: const Text('Language'),
            subtitle: Text(AppSettings.subLang.isEmpty ? 'Source default' : AppSettings.subLang),
            onTap: () async {
              final v = await _pick('Subtitle language', [for (final l in _langs) (l, l.isEmpty ? 'Source default' : l)],
                  AppSettings.subLang);
              if (v != null) _set('subLang', v);
            },
          ),
          ListTile(
            title: const Text('Size'),
            subtitle: Text(labelOf(sizes, AppSettings.subSize)),
            onTap: () async {
              final v = await _pick('Subtitle size', sizes, AppSettings.subSize);
              if (v != null) _set('subSize', v);
            },
          ),
          _header('Downloads'),
          SwitchListTile(
            title: const Text('Wi-Fi only'),
            subtitle: const Text('Wait for Wi-Fi before downloading, so it never uses mobile data.'),
            value: AppSettings.wifiOnly,
            onChanged: (v) async {
              await _set('wifiOnly', v);
              DownloadService.resume();
            },
          ),
          ListTile(
            title: const Text('Storage limit'),
            subtitle: Text(labelOf(limits, AppSettings.downloadLimitGb)),
            onTap: () async {
              final v = await _pick('Storage limit', limits, AppSettings.downloadLimitGb);
              if (v == null) return;
              await _set('downloadLimitGb', v);
              DownloadService.resume();
            },
          ),
          SwitchListTile(
            title: const Text('Delete when watched'),
            subtitle: const Text("Remove an episode's saved copy once you've watched it to the end."),
            value: AppSettings.autoDeleteWatched,
            onChanged: (v) => _set('autoDeleteWatched', v),
          ),
          _header('Alerts'),
          SwitchListTile(
            title: const Text('New-episode alerts'),
            subtitle: const Text('A notification when a show on My List airs a new episode, even with the app closed.'),
            value: AppSettings.alerts,
            onChanged: _toggleAlerts,
          ),
          if (AppSettings.alerts)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Check now'),
              onTap: () async {
                final n = await NativeBridge.checkAlertsNow();
                if (context.mounted) {
                  _snack(context, n == 0 ? 'Nothing new on My List right now.' : '$n new episode alert${n == 1 ? '' : 's'}.');
                }
              },
            ),
          _header('Server'),
          ListTile(
            title: const Text('Server address'),
            subtitle: Text(ApiService.host),
            onTap: () async {
              final ctl = TextEditingController(text: ApiService.host);
              final saved = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Server address'),
                  content: TextField(
                    controller: ctl,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'https://xxxx.trycloudflare.com'),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
                  ],
                ),
              );
              if (saved == null || saved.trim().isEmpty) return;
              await ApiService.setHost(saved);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('AniVerse $kAppVersionName (build $kAppBuildNumber)',
                style: const TextStyle(color: AniVerseTheme.textFaint, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
