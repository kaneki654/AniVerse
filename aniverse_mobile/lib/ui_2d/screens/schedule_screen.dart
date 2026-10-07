import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/native_bridge.dart';
import '../../services/watchlist_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../widgets/aniverse_loader.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/pixel_extras.dart';
import '../widgets/poster_card.dart';
import 'detail_screen.dart';
import 'watch_screen.dart';

/// The airing schedule: the next seven days, one tab per day, each episode with
/// its local air time and a countdown. Shows on My List float to the top.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Map<String, dynamic>>? _items;
  String? _day;

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
      _day = items.isEmpty ? null : _dayKey((items.first['airingAt'] as num).toInt());
    });
  }

  static String _dayKey(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${d.year}-${d.month}-${d.day}';
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _countdown(int secs) {
    if (secs <= 0) return 'OUT NOW';
    final d = secs ~/ 86400, h = (secs % 86400) ~/ 3600, m = (secs % 3600) ~/ 60;
    return d > 0 ? 'IN ${d}D ${h}H' : h > 0 ? 'IN ${h}H ${m}M' : 'IN ${m}M';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('AIRING')),
      body: items == null
          ? const AniVerseLoadingScreen(label: 'LOADING')
          : items.isEmpty
              ? Center(
                  child: EmptyState(
                    title: 'No schedule right now',
                    text: "AniList didn't answer. Try again in a moment.",
                    action: PixelButton(label: 'Retry', icon: Sprites.refresh, onPressed: () {
                      setState(() => _items = null);
                      _load();
                    }),
                  ),
                )
              : ValueListenableBuilder<int>(
                  valueListenable: WatchlistService.changes,
                  builder: (context, _, __) => _body(items),
                ),
    );
  }

  Widget _body(List<Map<String, dynamic>> items) {
    final days = <String>[];
    for (final it in items) {
      final k = _dayKey((it['airingAt'] as num).toInt());
      if (!days.contains(k)) days.add(k);
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final todayKey = _dayKey(now);
    final rows = items.where((it) => _dayKey((it['airingAt'] as num).toInt()) == _day).toList()
      ..sort((a, b) {
        final fa = WatchlistService.has(a['media']['id'].toString()) ? 0 : 1;
        final fb = WatchlistService.has(b['media']['id'].toString()) ? 0 : 1;
        return fa != fb ? fa - fb : (a['airingAt'] as num).compareTo(b['airingAt'] as num);
      });

    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            children: [
              for (final k in days)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PixelButton(
                    label: k == todayKey ? 'Today' : () {
                      final d = DateTime.fromMillisecondsSinceEpoch(
                          (items.firstWhere((it) => _dayKey((it['airingAt'] as num).toInt()) == k)['airingAt'] as num).toInt() * 1000);
                      return '${_weekdays[d.weekday - 1]} ${d.day}';
                    }(),
                    fontSize: 7,
                    kind: k == _day ? PixelButtonKind.blood : PixelButtonKind.dark,
                    onPressed: () {
                      Sfx.play('select');
                      setState(() => _day = k);
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _row(rows[i], now),
          ),
        ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> it, int now) {
    final media = Map<String, dynamic>.from(it['media'] as Map);
    final id = media['id'].toString();
    final at = (it['airingAt'] as num).toInt();
    final ep = (it['episode'] as num).toInt();
    final aired = at <= now;
    final mine = WatchlistService.has(id);
    final when = DateTime.fromMillisecondsSinceEpoch(at * 1000);
    final time = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';

    void open() => Navigator.push(
          context,
          FadeScaleRoute(
            backdrop: !aired,
            page: aired
                ? WatchScreen(animeId: id, epNum: ep, title: titleOf(media), cover: coverOf(media))
                : DetailScreen(id: id),
          ),
        );

    return Opacity(
      opacity: aired ? 0.6 : 1,
      child: PressableScale(
        onTap: open,
        child: PixelBox(
          border: mine ? Px.gold : Px.black,
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(time, style: PxFont.label(9)),
                  const SizedBox(height: 4),
                  Text(_countdown(at - now), style: PxFont.label(6, color: Px.bloodLight)),
                ]),
              ),
              SizedBox(width: 44, height: 62, child: PixelCover(url: coverOf(media), decodeWidth: 40)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titleOf(media), maxLines: 2, overflow: TextOverflow.ellipsis, style: PxFont.text(15, height: 1.25)),
                  const SizedBox(height: 4),
                  Text('EPISODE $ep${mine ? ' · ON MY LIST' : ''}', style: PxFont.label(6, color: Px.ash)),
                ]),
              ),
              PixelIconButton(
                sprite: mine ? Sprites.bookmark : Sprites.bookmarkOff,
                tooltip: mine ? 'Remove from My List' : 'Add to My List',
                color: mine ? Px.gold : Px.ash,
                scale: 2,
                onPressed: () {
                  if (mine) {
                    WatchlistService.unfollow(id);
                  } else {
                    WatchlistService.follow(id, title: titleOf(media), cover: coverOf(media), seen: ep - 1 < 0 ? 0 : ep - 1);
                    Sfx.play('achieve');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
