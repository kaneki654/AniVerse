import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/app_settings.dart';
import '../../services/history_service.dart';
import '../../services/native_bridge.dart';
import '../../services/watchlist_service.dart';
import '../ink/manga.dart';
import '../ink/ink_widgets.dart';
import '../widgets/manga_extras.dart';
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
            builder: (context, _, __) => InkIconButton(
              icon: InkIcons.bell,
              tooltip: AppSettings.alerts ? 'Alerts on' : 'Turn on alerts',
              color: AppSettings.alerts ? Mg.red : Mg.gray,
              onPressed: () => Navigator.push(context, PageTurnRoute(page: const SettingsScreen())),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Mg.red,
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

    return InkPress(
      onTap: () => Navigator.push(context, PageTurnRoute(page: DetailScreen(id: e.animeId))),
      child: PanelBox(
        border: fresh > 0 ? Mg.redLight : Mg.ink,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(width: 52, height: 74, child: InkCover(url: e.cover, decodeWidth: 48)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title.isEmpty ? 'Untitled' : e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgFont.text(15, height: 1.25)),
                const SizedBox(height: 6),
                if (info == null)
                  Text('CHECKING…', style: MgFont.label(6, color: Mg.grayLight))
                else
                  Text.rich(TextSpan(children: [
                    if (fresh > 0) TextSpan(text: '$fresh NEW · ', style: MgFont.label(6, color: Mg.redLight)),
                    TextSpan(
                      text: '$aired OUT${airing ? ' · AIRING' : ''}${watched > 0 ? ' · ON $watched' : ''}',
                      style: MgFont.label(6, color: Mg.gray),
                    ),
                  ])),
              ]),
            ),
            if (info != null && aired > 0)
              InkButton(
                label: 'EP $next',
                fontSize: 7,
                onPressed: () => Navigator.push(
                  context,
                  PageTurnRoute(backdrop: false, page: WatchScreen(animeId: e.animeId, epNum: next, title: e.title, cover: e.cover)),
                ),
              ),
            // This show's alerts on or off (the alert check skips muted shows).
            ValueListenableBuilder<int>(
              valueListenable: AppSettings.changes,
              builder: (context, _, __) {
                final on = AppSettings.alertsFor(e.animeId);
                return InkIconButton(
                  icon: InkIcons.bell,
                  tooltip: on ? 'Mute alerts for ${e.title}' : 'Alerts for ${e.title} are muted',
                  color: on && AppSettings.alerts ? Mg.red : Mg.grayLight,
                  scale: 1.8,
                  size: 40,
                  onPressed: () {
                    Sfx.play('select');
                    AppSettings.setAlertsFor(e.animeId, !on);
                    mangaToast(context, on ? 'No more alerts for ${e.title}.' : 'Alerts back on for ${e.title}.');
                  },
                );
              },
            ),
            InkIconButton(
              icon: InkIcons.trash,
              tooltip: 'Remove ${e.title}',
              color: Mg.gray,
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
