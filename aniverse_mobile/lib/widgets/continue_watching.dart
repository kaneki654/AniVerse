import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../screens/watch_screen.dart';
import '../services/history_service.dart';
import '../theme.dart';
import 'aniverse_logo.dart';

/// Open [entry] in the player. The player resumes from the saved position by
/// itself, so every way into an episode gets that for free.
void openHistoryEntry(BuildContext context, HistoryEntry entry) {
  Navigator.push(
    context,
    FadeScaleRoute(
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
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: 'Continue Watching', onMore: onSeeAll),
              SizedBox(
                height: 210,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HistoryCover(url: entry.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(gradient: AniVerseTheme.posterScrim),
                      ),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.55),
                            border: Border.all(color: Colors.white54),
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                        ),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 10,
                        child: EpisodeBadge(episode: entry.episode),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ProgressStrip(fraction: entry.fraction),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: Text(
                  entry.title.isEmpty ? 'Episode ${entry.episode}' : entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.3),
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
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const ColoredBox(
        color: AniVerseTheme.surfaceHigh,
        child: Center(child: Icon(Icons.movie_outlined, color: AniVerseTheme.textFaint)),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const ColoredBox(color: AniVerseTheme.surfaceHigh),
    );
  }
}

class EpisodeBadge extends StatelessWidget {
  final int episode;

  const EpisodeBadge({super.key, required this.episode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AniVerseTheme.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'EP $episode',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }
}

/// Thin red bar showing how much of an episode has been watched.
class ProgressStrip extends StatelessWidget {
  final double fraction;
  final double height;

  const ProgressStrip({super.key, required this.fraction, this.height = 3});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.white24),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0.0, 1.0),
            child: const ColoredBox(color: AniVerseTheme.red),
          ),
        ],
      ),
    );
  }
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
