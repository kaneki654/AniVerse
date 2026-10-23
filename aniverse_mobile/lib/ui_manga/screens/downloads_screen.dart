import 'package:flutter/material.dart';

import '../../services/download_service.dart';
import '../../services/native_bridge.dart';
import '../ink/manga.dart';
import '../ink/ink_widgets.dart';
import '../widgets/manga_extras.dart';
import 'watch_screen.dart';

/// Episodes saved for watching offline, with what is still downloading.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  static String _size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DOWNLOADS')),
      body: ValueListenableBuilder<int>(
        valueListenable: DownloadService.changes,
        builder: (context, _, __) {
          final items = DownloadService.items;
          if (items.isEmpty) {
            return const Center(
              child: EmptyState(
                title: 'Nothing saved yet',
                text: "Open an anime, switch the episodes to the list view and tap the download arrow. "
                    "Saved episodes play without a connection.",
              ),
            );
          }
          final total = items.fold<int>(0, (s, i) => s + i.bytes);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 2),
                child: Text('${items.length} EPISODE${items.length == 1 ? '' : 'S'} · ${_size(total)} · DOWNLOADS CARRY ON IN THE BACKGROUND',
                    style: MgFont.label(6, color: Mg.gray)),
              ),
              for (final item in items) ...[_row(context, item), const SizedBox(height: 10)],
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, DownloadItem item) {
    final status = switch (item.status) {
      'done' => '${item.quality.isEmpty ? '' : '${item.quality} · '}${_size(item.bytes)}',
      'downloading' => 'DOWNLOADING ${(item.progress * 100).toStringAsFixed(0)}% · ${_size(item.bytes)}',
      'queued' => 'WAITING',
      'waiting' => 'WAITING FOR WI-FI',
      _ => item.error ?? 'FAILED',
    };
    return InkPress(
      onTap: item.done
          ? () => Navigator.push(
                context,
                PageTurnRoute(
                  backdrop: false,
                  page: WatchScreen(animeId: item.animeId, epNum: item.episode, title: item.title, cover: item.cover, category: item.category),
                ),
              )
          : () {},
      child: PanelBox(
        border: item.status == 'failed' ? Mg.redDark : Mg.ink,
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(width: 46, height: 64, child: InkCover(url: item.cover, decodeWidth: 44)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.title.isEmpty ? 'Anime ${item.animeId}' : item.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: MgFont.text(15, height: 1.25)),
                    const SizedBox(height: 4),
                    Text('EP ${item.episode} · ${item.category.toUpperCase()}', style: MgFont.label(7)),
                    const SizedBox(height: 4),
                    Text(status.toUpperCase(), maxLines: 2, style: MgFont.label(6, color: item.status == 'failed' ? Mg.redLight : Mg.gray)),
                  ]),
                ),
                if (item.done) InkIcon(InkIcons.play, scale: 2, color: Mg.redLight),
                if (item.status == 'failed')
                  InkIconButton(
                    icon: InkIcons.refresh,
                    tooltip: 'Retry',
                    onPressed: () => DownloadService.enqueue(
                        animeId: item.animeId, episode: item.episode, category: item.category, title: item.title, cover: item.cover),
                  ),
                InkIconButton(
                  icon: InkIcons.trash,
                  tooltip: 'Delete',
                  color: Mg.gray,
                  scale: 1.8,
                  onPressed: () {
                    Sfx.play('slash');
                    DownloadService.delete(item);
                  },
                ),
              ],
            ),
            if (item.status == 'downloading') ...[
              const SizedBox(height: 8),
              InkBar(fraction: item.progress, height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
