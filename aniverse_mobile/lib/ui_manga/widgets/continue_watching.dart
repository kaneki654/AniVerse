import 'package:flutter/material.dart';

import '../../services/history_service.dart';
import '../ink/manga.dart';
import '../ink/ink_widgets.dart';
import '../screens/watch_screen.dart';
import '../manga_theme.dart';

/// Open [entry] in the player. The player resumes from the saved position by
/// itself, so every way into an episode gets that for free.
void openHistoryEntry(BuildContext context, HistoryEntry entry) {
  Navigator.push(
    context,
    PageTurnRoute(
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
        child: InkPress(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: PanelBox(
                  fill: Mg.ink,
                  shadow: 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HistoryCover(url: entry.cover),
                      Center(
                        child: PanelBox(
                          fill: Mg.red,
                          shadow: 2,
                          bevel: true,
                          padding: const EdgeInsets.fromLTRB(9, 7, 7, 7),
                          child: const InkIcon(InkIcons.play, scale: 2),
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
                  style: MgFont.text(13, height: 1.25),
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
  Widget build(BuildContext context) => InkCover(url: url);
}

class EpisodeBadge extends StatelessWidget {
  final int episode;

  const EpisodeBadge({super.key, required this.episode});

  @override
  Widget build(BuildContext context) => InkChip('EP $episode');
}

/// How much of an episode has been watched, as a health bar.
class ProgressStrip extends StatelessWidget {
  final double fraction;
  final double height;

  const ProgressStrip({super.key, required this.fraction, this.height = 6});

  @override
  Widget build(BuildContext context) => InkBar(fraction: fraction, height: height);
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
