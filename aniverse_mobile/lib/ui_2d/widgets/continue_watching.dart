import 'package:flutter/material.dart';

import '../../services/history_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../screens/watch_screen.dart';
import '../theme_2d.dart';
import 'aniverse_logo.dart';
import 'poster_card.dart';

/// Open [entry] in the player. The player resumes from the saved position by
/// itself, so every way into an episode gets that for free.
void openHistoryEntry(BuildContext context, HistoryEntry entry) {
  Navigator.push(
    context,
    FadeScaleRoute(
      backdrop: false,
      page: WatchScreen(
        animeId: entry.animeId,
        epNum: entry.episode,
        title: entry.title.isEmpty ? null : entry.title,
        cover: entry.cover.isEmpty ? null : entry.cover,
      ),
    ),
  );
}

/// "Continue Watching" row for the home screen: the latest episode of each
/// anime, with how far into it the user got. Hidden when there is nothing yet.
class ContinueWatchingRow extends StatelessWidget {
  final VoidCallback onSeeAll;

  const ContinueWatchingRow({super.key, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HistoryService.changes,
      builder: (context, _, __) {
        final entries = HistoryService.latestPerAnime().take(15).toList();
        if (entries.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: 'Continue Watching', onMore: onSeeAll),
              SizedBox(
                height: 218,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _ResumeCard(
                    entry: entries[i],
                    onTap: () => openHistoryEntry(context, entries[i]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResumeCard extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onTap;

  const _ResumeCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 130,
        child: PressableScale(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PixelBox(
                  fill: Px.black,
                  shadow: 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HistoryCover(url: entry.cover),
                      const Center(
                        child: PixelBox(
                          fill: Px.blood,
                          shadow: 2,
                          bevel: true,
                          padding: EdgeInsets.fromLTRB(9, 7, 7, 7),
                          child: PixelSprite(Sprites.play, scale: 2),
                        ),
                      ),
                      Positioned(left: 4, bottom: 12, child: EpisodeBadge(episode: entry.episode)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ProgressStrip(fraction: entry.fraction, height: 8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: Text(
                  entry.title.isEmpty ? 'Episode ${entry.episode}' : entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PxFont.text(13, height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryCover extends StatelessWidget {
  final String url;

  const HistoryCover({super.key, required this.url});

  @override
  Widget build(BuildContext context) => PixelCover(url: url);
}

class EpisodeBadge extends StatelessWidget {
  final int episode;

  const EpisodeBadge({super.key, required this.episode});

  @override
  Widget build(BuildContext context) => PixelChip('EP $episode');
}

/// How much of an episode has been watched, as a health bar.
class ProgressStrip extends StatelessWidget {
  final double fraction;
  final double height;

  const ProgressStrip({super.key, required this.fraction, this.height = 6});

  @override
  Widget build(BuildContext context) => PixelBar(fraction: fraction, height: height);
}

/// "5m ago", "3h ago", "2d ago", or a date for anything older.
String timeAgo(int millis) {
  final then = DateTime.fromMillisecondsSinceEpoch(millis);
  final d = DateTime.now().difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[then.month - 1]} ${then.day}';
}
