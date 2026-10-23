import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/history_service.dart';
import '../ink/manga.dart';
import '../ink/ink_widgets.dart';
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
            child: Text('CANCEL', style: MgFont.label(9, color: Mg.gray)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('CLEAR', style: MgFont.label(9, color: Mg.redLight)),
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
                    ? Padding(
                        padding: const EdgeInsets.all(15),
                        child: InkSpinner(color: Mg.gray),
                      )
                    : InkIconButton(
                        icon: InkIcons.refresh,
                        tooltip: 'Sync',
                        color: Mg.gray,
                        onPressed: _sync,
                      ),
              if (entries.isNotEmpty)
                InkIconButton(
                  icon: InkIcons.trash,
                  tooltip: 'Clear history',
                  color: Mg.gray,
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
                      background: PanelBox(
                        fill: Mg.redDark,
                        shadow: 0,
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(right: 20),
                            child: InkIcon(InkIcons.trash, scale: 2.4),
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
    return InkPress(
      onTap: () => openHistoryEntry(context, e),
      child: GestureDetector(
        onLongPress: () => Navigator.push(
          context,
          PageTurnRoute(page: DetailScreen(id: e.animeId)),
        ),
        child: SizedBox(
          height: 108,
          child: PanelBox(
            fill: Mg.panel,
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HistoryCover(url: e.cover),
                      if (e.finished)
                        const Center(child: InkIcon(InkIcons.skullSmall, scale: 3)),
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
                        style: MgFont.text(15, height: 1.2),
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
                              style: MgFont.label(7, color: Mg.gray),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkBar(fraction: e.fraction, height: 7),
                      ),
                      const SizedBox(height: 4),
                      Text(timeAgo(e.updatedAt), style: MgFont.text(12, color: Mg.grayLight)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: PanelBox(
                    fill: Mg.red,
                    shadow: 2,
                    bevel: true,
                    padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                    child: const InkIcon(InkIcons.play, scale: 1.8),
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
            style: MgFont.text(13, color: Mg.grayLight),
          );
        }
        return InkPress(
          onTap: () => Navigator.push(
            context,
            PageTurnRoute(page: const AccountScreen()),
          ),
          child: PanelBox(
            fill: Mg.panelHigh,
            border: Mg.redDark,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                InkIcon(InkIcons.floppy, scale: 2.2, color: Mg.redLight),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'History is saved on this phone only. Sign in to keep it across devices.',
                    style: MgFont.text(14),
                  ),
                ),
                InkIcon(InkIcons.chevron, scale: 1.6, color: Mg.grayLight),
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
            const InkIcon(InkIcons.skull, scale: 5),
            const SizedBox(height: 22),
            Text('NOTHING WATCHED YET', style: MgFont.label(11)),
            const SizedBox(height: 10),
            Text(
              'Episodes you watch show up here, and you can pick up right where you stopped.',
              textAlign: TextAlign.center,
              style: MgFont.text(14, color: Mg.gray),
            ),
          ],
        ),
      ),
    );
  }
}
