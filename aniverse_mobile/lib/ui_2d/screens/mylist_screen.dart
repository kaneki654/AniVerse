import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/app_settings.dart';
import '../../services/history_service.dart';
import '../../services/native_bridge.dart';
import '../../services/watchlist_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/pixel_extras.dart';
import '../widgets/poster_card.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';
import 'watch_screen.dart';

/// My List: the anime you follow, with new episodes flagged and one tap to
/// the next episode. Opening it marks what you see as seen.
class MyListScreen extends StatelessWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MY LIST'),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: AppSettings.changes,
            builder: (context, _, __) => PixelIconButton(
              sprite: Sprites.bell,
              tooltip: AppSettings.alerts ? 'Alerts on' : 'Turn on alerts',
              color: AppSettings.alerts ? Px.gold : Px.ash,
              onPressed: () => Navigator.push(context, FadeScaleRoute(page: const SettingsScreen())),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Px.blood,
        onRefresh: () => WatchlistService.sync(full: true),
        child: ValueListenableBuilder<int>(
          valueListenable: WatchlistService.changes,
          builder: (context, _, __) {
            final entries = WatchlistService.all();
            if (entries.isEmpty) {
              return ListView(children: const [
                EmptyState(
                  title: 'Your list is empty',
                  text: 'Tap the bookmark on any anime to follow it and get told when new episodes air.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _Row(entry: entries[i], key: ValueKey(entries[i].animeId)),
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  final WatchEntry entry;
  const _Row({super.key, required this.entry});

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  Map<String, dynamic>? _info;

  @override
  void initState() {
    super.initState();
    ApiService.getAnimeDetails(widget.entry.animeId).then((a) {
      if (!mounted || a == null) return;
      setState(() => _info = a);
      // Seen now: the alert for these episodes has done its job.
      Future.delayed(const Duration(milliseconds: 1500), () => WatchlistService.markSeen(widget.entry.animeId, airedEpisodes(a)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final info = _info;
    final aired = info == null ? 0 : airedEpisodes(info);
    final fresh = info != null && e.seenEpisode > 0 ? aired - e.seenEpisode : 0;
    final watched = HistoryService.episodesOf(e.animeId).keys.fold<int>(0, (m, n) => n > m ? n : m);
    final next = aired == 0 ? 1 : (watched + 1).clamp(1, aired);
    final airing = info?['status'] == 'RELEASING';

    return PressableScale(
      onTap: () => Navigator.push(context, FadeScaleRoute(page: DetailScreen(id: e.animeId))),
      child: PixelBox(
        border: fresh > 0 ? Px.bloodLight : Px.black,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(width: 52, height: 74, child: PixelCover(url: e.cover, decodeWidth: 48)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title.isEmpty ? 'Untitled' : e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: PxFont.text(15, height: 1.25)),
                const SizedBox(height: 6),
                if (info == null)
                  Text('CHECKING…', style: PxFont.label(6, color: Px.ashDark))
                else
                  Text.rich(TextSpan(children: [
                    if (fresh > 0) TextSpan(text: '$fresh NEW · ', style: PxFont.label(6, color: Px.bloodLight)),
                    TextSpan(
                      text: '$aired OUT${airing ? ' · AIRING' : ''}${watched > 0 ? ' · ON $watched' : ''}',
                      style: PxFont.label(6, color: Px.ash),
                    ),
                  ])),
              ]),
            ),
            if (info != null && aired > 0)
              PixelButton(
                label: 'EP $next',
                fontSize: 7,
                onPressed: () => Navigator.push(
                  context,
                  FadeScaleRoute(backdrop: false, page: WatchScreen(animeId: e.animeId, epNum: next, title: e.title, cover: e.cover)),
                ),
              ),
            PixelIconButton(
              sprite: Sprites.trash,
              tooltip: 'Remove ${e.title}',
              color: Px.ash,
              scale: 1.8,
              size: 40,
              onPressed: () {
                Sfx.play('slash');
                WatchlistService.unfollow(e.animeId);
              },
            ),
          ],
        ),
      ),
    );
  }
}
