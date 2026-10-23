import 'package:flutter/material.dart';

import '../../services/download_service.dart';
import '../../services/native_bridge.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/pixel_extras.dart';
import '../widgets/poster_card.dart';
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
                    style: PxFont.label(6, color: Px.ash)),
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
    return PressableScale(
      onTap: item.done
          ? () => Navigator.push(
                context,
                FadeScaleRoute(
                  backdrop: false,
                  page: WatchScreen(animeId: item.animeId, epNum: item.episode, title: item.title, cover: item.cover, category: item.category),
                ),
              )
          : () {},
      child: PixelBox(
        border: item.status == 'failed' ? Px.bloodDark : Px.black,
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(width: 46, height: 64, child: PixelCover(url: item.cover, decodeWidth: 44)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.title.isEmpty ? 'Anime ${item.animeId}' : item.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: PxFont.text(15, height: 1.25)),
                    const SizedBox(height: 4),
                    Text('EP ${item.episode} · ${item.category.toUpperCase()}', style: PxFont.label(7)),
                    const SizedBox(height: 4),
                    Text(status.toUpperCase(), maxLines: 2, style: PxFont.label(6, color: item.status == 'failed' ? Px.bloodLight : Px.ash)),
                  ]),
                ),
                if (item.done) PixelSprite(Sprites.play, scale: 2, color: Px.bloodLight),
                if (item.status == 'failed')
                  PixelIconButton(
                    sprite: Sprites.refresh,
                    tooltip: 'Retry',
                    onPressed: () => DownloadService.enqueue(
                        animeId: item.animeId, episode: item.episode, category: item.category, title: item.title, cover: item.cover),
                  ),
                PixelIconButton(
                  sprite: Sprites.trash,
                  tooltip: 'Delete',
                  color: Px.ash,
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
              PixelBar(fraction: item.progress, height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
