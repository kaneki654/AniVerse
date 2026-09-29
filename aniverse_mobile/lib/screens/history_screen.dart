import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../theme.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/continue_watching.dart';
import 'account_screen.dart';
import 'detail_screen.dart';

/// Everything the user has watched, newest first, one row per anime.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Pick up what other devices have watched since this one last synced.
    HistoryService.sync();
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear watch history?', style: TextStyle(color: Colors.white)),
        content: Text(
          AuthService.signedIn
              ? 'This removes it from your account on every device.'
              : 'This removes it from this phone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: AniVerseTheme.red)),
          ),
        ],
      ),
    );
    if (ok == true) HistoryService.clearAll();
  }

  void _remove(HistoryEntry e) {
    HistoryService.removeAnime(e.animeId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed ${e.title.isEmpty ? 'from history' : e.title}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HistoryService.changes,
      builder: (context, _, __) {
        final entries = HistoryService.latestPerAnime();
        return Scaffold(
          appBar: AppBar(
            title: const Text('History', style: TextStyle(fontSize: 18)),
            actions: [
              if (entries.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
                  tooltip: 'Clear history',
                  onPressed: _confirmClear,
                ),
            ],
          ),
          body: RefreshIndicator(
            color: AniVerseTheme.red,
            onRefresh: HistoryService.sync,
            child: entries.isEmpty
                ? ListView(children: const [_Empty()])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: entries.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) return const _SyncNote();
                      final e = entries[i - 1];
                      return Dismissible(
                        key: ValueKey(e.animeId),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AniVerseTheme.redDark,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        onDismissed: (_) => _remove(e),
                        child: _HistoryTile(entry: e),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryTile({required this.entry});

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final watched = e.finished
        ? 'Watched'
        : e.durationMs > 0
            ? '${_fmt(e.position)} / ${_fmt(e.duration)}'
            : _fmt(e.position);
    return Material(
      color: AniVerseTheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openHistoryEntry(context, e),
        onLongPress: () => Navigator.push(
          context,
          FadeScaleRoute(page: DetailScreen(id: e.animeId)),
        ),
        child: SizedBox(
          height: 96,
          child: Row(
            children: [
              SizedBox(
                width: 68,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    HistoryCover(url: e.cover),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ProgressStrip(fraction: e.fraction),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title.isEmpty ? 'Anime ${e.animeId}' : e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        EpisodeBadge(episode: e.episode),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            watched,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AniVerseTheme.textDim, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeAgo(e.updatedAt),
                      style: const TextStyle(color: AniVerseTheme.textFaint, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.play_circle_fill, color: AniVerseTheme.red, size: 30),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed out: say where the history lives and how to take it along.
class _SyncNote extends StatelessWidget {
  const _SyncNote();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthService.user,
      builder: (context, user, _) {
        if (user != null) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              'Synced to ${user.displayName}. Swipe left to remove · long-press for details.',
              style: const TextStyle(color: AniVerseTheme.textFaint, fontSize: 11),
            ),
          );
        }
        return Material(
          color: AniVerseTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(
              context,
              FadeScaleRoute(page: const AccountScreen()),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.cloud_upload_outlined, color: AniVerseTheme.red),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'History is saved on this phone only. Sign in to keep it '
                      'across devices.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 120, 32, 0),
      child: Column(
        children: [
          Icon(Icons.history, size: 56, color: AniVerseTheme.textFaint),
          SizedBox(height: 16),
          Text('Nothing watched yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text(
            'Episodes you watch show up here, and you can pick up right where you stopped.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AniVerseTheme.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
