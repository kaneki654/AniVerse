import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../services/history_service.dart';
import 'pixel/pixel.dart';
import 'pixel/sprites.dart';

/// Achievements and levels, worked out from watch history alone, so they are
/// the same on every device the history syncs to. The website has the same
/// rules in app/static/pixel/js/achievements.js; change both together.
class Badge {
  final String id;
  final String name;
  final String text;
  final Sprite sprite;
  final bool Function(WatchStats s) test;
  const Badge(this.id, this.name, this.text, this.sprite, this.test);
}

class WatchStats {
  final int finished;
  final int anime;
  final int streak;
  final int bestDay;
  final bool nightOwl;
  final double hours;
  const WatchStats({
    required this.finished,
    required this.anime,
    required this.streak,
    required this.bestDay,
    required this.nightOwl,
    required this.hours,
  });
}

class Level {
  final int xp;
  final int level;
  final String rank;
  final double progress;

  /// bronze | silver | gold | blood | legend, one step every 10 levels.
  final String frame;
  const Level(this.xp, this.level, this.rank, this.progress, this.frame);

  int get toNext => level >= 99 ? 0 : math.max(0, 40 * level * level - xp);
}

class Achievements {
  static final List<Badge> badges = [
    Badge('first_blood', 'First Blood', 'Finish your first episode', Sprites.bloodDrop, (s) => s.finished >= 1),
    Badge('ten_slain', 'Ten Slain', 'Finish 10 episodes', Sprites.skullSmall, (s) => s.finished >= 10),
    Badge('hundred_slain', '100 Episodes Slain', 'Finish 100 episodes', Sprites.skull, (s) => s.finished >= 100),
    Badge('thousand_slain', 'Demon Lord', 'Finish 1,000 episodes', Sprites.skull, (s) => s.finished >= 1000),
    Badge('collector', 'Collector', 'Watch 10 different anime', Sprites.grid, (s) => s.anime >= 10),
    Badge('binge', 'Binge', '6 episodes of one anime in a day', Sprites.play, (s) => s.bestDay >= 6),
    Badge('streak_3', 'On a Roll', 'Watch 3 days in a row', Sprites.check, (s) => s.streak >= 3),
    Badge('streak_7', 'Week of Blood', 'Watch 7 days in a row', Sprites.star, (s) => s.streak >= 7),
    Badge('streak_30', 'Unstoppable', 'Watch 30 days in a row', Sprites.star, (s) => s.streak >= 30),
    Badge('night_owl', 'Night Owl', 'Finish an episode between 1 and 4 AM', Sprites.clock, (s) => s.nightOwl),
    Badge('marathon', 'Marathon', 'Watch 24 hours in total', Sprites.clock, (s) => s.hours >= 24),
  ];

  static const ranks = ['Peasant', 'Ronin', 'Samurai', 'Hatamoto', 'Daimyo', 'Shogun', 'Demon Hunter', 'Demon Lord'];

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static WatchStats stats([List<HistoryEntry>? entries]) {
    final all = entries ?? HistoryService.all();
    final done = all.where((e) => e.finished).toList();
    final days = {for (final e in all) _day(DateTime.fromMillisecondsSinceEpoch(e.updatedAt))};
    // Streak: consecutive days with any watching, ending today or yesterday.
    var streak = 0;
    final today = DateTime.now();
    for (var d = today;; d = d.subtract(const Duration(days: 1))) {
      if (days.contains(_day(d))) {
        streak++;
      } else if (streak > 0 || _day(d) != _day(today)) {
        break;
      }
      if (streak > 400) break;
    }
    final perDay = <String, int>{};
    for (final e in done) {
      final k = '${e.animeId}|${_day(DateTime.fromMillisecondsSinceEpoch(e.updatedAt))}';
      perDay[k] = (perDay[k] ?? 0) + 1;
    }
    final ms = all.fold<int>(0, (sum, e) => sum + (e.finished ? e.durationMs : e.positionMs));
    return WatchStats(
      finished: done.length,
      anime: {for (final e in all) e.animeId}.length,
      streak: streak,
      bestDay: perDay.values.fold(0, math.max),
      nightOwl: done.any((e) {
        final h = DateTime.fromMillisecondsSinceEpoch(e.updatedAt).hour;
        return h >= 1 && h < 4;
      }),
      hours: ms / 3600000,
    );
  }

  static Level level([WatchStats? s]) {
    s ??= stats();
    final xp = s.finished * 10 + s.anime * 25 + math.min(s.streak, 60) * 15;
    final lvl = math.min(99, (math.sqrt(xp / 40)).floor() + 1);
    final floor = 40 * (lvl - 1) * (lvl - 1), next = 40 * lvl * lvl;
    const frames = ['bronze', 'silver', 'gold', 'blood', 'legend'];
    return Level(
      xp,
      lvl,
      ranks[math.min(ranks.length - 1, (lvl - 1) ~/ 6)],
      lvl >= 99 ? 1 : (xp - floor) / (next - floor),
      frames[math.min(4, (lvl - 1) ~/ 10)],
    );
  }

  static Set<String> unlocked([WatchStats? s]) {
    s ??= stats();
    return {for (final b in badges) if (b.test(s)) b.id};
  }

  /// The avatar frame's colour.
  static int frameColor(String frame) => switch (frame) {
        'silver' => 0xFFC9D2DE,
        'gold' => Px.gold.toARGB32(),
        'blood' => Px.bloodLight.toARGB32(),
        'legend' => 0xFFB48CFF,
        _ => 0xFFB06A2C,
      };

  /// Badges newly earned since the last call, remembered so each shows once.
  /// The first run on a device returns none, so old history is no burst.
  static Future<List<Badge>> newlyUnlocked() async {
    final now = unlocked();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('av.badges');
      await prefs.setString('av.badges', json.encode(now.toList()));
      if (raw == null) return const [];
      final seen = {for (final x in json.decode(raw) as List) x.toString()};
      return [for (final b in badges) if (now.contains(b.id) && !seen.contains(b.id)) b];
    } catch (_) {
      return const [];
    }
  }
}
