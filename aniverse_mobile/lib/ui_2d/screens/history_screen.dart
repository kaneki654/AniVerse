import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/history_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
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
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    // Pick up what other devices have watched since this one last synced.
    _sync();
  }

  Future<void> _sync() async {
    if (!AuthService.signedIn) return;
    setState(() => _syncing = true);
    await HistoryService.sync();
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CLEAR HISTORY?'),
        content: Text(
          AuthService.signedIn
              ? 'This removes it from your account on every device.'
              : 'This removes it from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: PxFont.label(9, color: Px.ash)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('CLEAR', style: PxFont.label(9, color: Px.bloodLight)),
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
            title: const Text('HISTORY'),
            actions: [
              if (AuthService.signedIn)
                _syncing
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: PixelSpinner(color: Px.ash),
                      )
                    : PixelIconButton(
                        sprite: Sprites.refresh,
                        tooltip: 'Sync',
                        color: Px.ash,
                        onPressed: _sync,
                      ),
              if (entries.isNotEmpty)
                PixelIconButton(
                  sprite: Sprites.trash,
                  tooltip: 'Clear history',
                  color: Px.ash,
                  onPressed: _confirmClear,
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: entries.isEmpty
              ? const _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  itemCount: entries.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (i == 0) return const _SyncNote();
                    final e = entries[i - 1];
                    return Dismissible(
                      key: ValueKey(e.animeId),
                      direction: DismissDirection.endToStart,
                      background: const PixelBox(
                        fill: Px.bloodDark,
                        shadow: 0,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(right: 20),
                            child: PixelSprite(Sprites.trash, scale: 2.4),
                          ),
                        ),
                      ),
                      onDismissed: (_) => _remove(e),
                      child: _HistoryTile(entry: e),
                    );
                  },
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
    return PressableScale(
      onTap: () => openHistoryEntry(context, e),
      child: GestureDetector(
        onLongPress: () => Navigator.push(
          context,
          FadeScaleRoute(page: DetailScreen(id: e.animeId)),
        ),
        child: SizedBox(
          height: 108,
          child: PixelBox(
            fill: Px.panel,
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HistoryCover(url: e.cover),
                      if (e.finished)
                        const Center(child: PixelSprite(Sprites.skullSmall, scale: 3)),
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
                        style: PxFont.text(15, height: 1.2),
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
                              style: PxFont.label(7, color: Px.ash),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: PixelBar(fraction: e.fraction, height: 7),
                      ),
                      const SizedBox(height: 4),
                      Text(timeAgo(e.updatedAt), style: PxFont.text(12, color: Px.ashDark)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: PixelBox(
                    fill: Px.blood,
                    shadow: 2,
                    bevel: true,
                    padding: EdgeInsets.fromLTRB(8, 6, 6, 6),
                    child: PixelSprite(Sprites.play, scale: 1.8),
                  ),
                ),
              ],
            ),
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
          return Text(
            'Synced to ${user.displayName}. Swipe left to remove, long-press for details.',
            style: PxFont.text(13, color: Px.ashDark),
          );
        }
        return PressableScale(
          onTap: () => Navigator.push(
            context,
            FadeScaleRoute(page: const AccountScreen()),
          ),
          child: PixelBox(
            fill: Px.panelHigh,
            border: Px.bloodDark,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const PixelSprite(Sprites.floppy, scale: 2.2, color: Px.bloodLight),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'History is saved on this phone only. Sign in to keep it across devices.',
                    style: PxFont.text(14),
                  ),
                ),
                const PixelSprite(Sprites.chevron, scale: 1.6, color: Px.ashDark),
              ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PixelSprite(Sprites.skull, scale: 5),
            const SizedBox(height: 22),
            Text('NOTHING WATCHED YET', style: PxFont.label(11)),
            const SizedBox(height: 10),
            Text(
              'Episodes you watch show up here, and you can pick up right where you stopped.',
              textAlign: TextAlign.center,
              style: PxFont.text(14, color: Px.ash),
            ),
          ],
        ),
      ),
    );
  }
}
