// The 1.9 pieces that are pure logic: achievements and levels, palettes and
// their effects, the download playlist rewrite, watch-party state and My List
// entries.
import 'package:aniverse_mobile/classic_plus/classic_extras.dart';
import 'package:aniverse_mobile/services/app_settings.dart';
import 'package:aniverse_mobile/services/download_service.dart';
import 'package:aniverse_mobile/services/history_service.dart';
import 'package:aniverse_mobile/services/party_service.dart';
import 'package:aniverse_mobile/services/watchlist_service.dart';
import 'package:aniverse_mobile/ui_2d/achievements.dart';
import 'package:aniverse_mobile/ui_2d/intro/logo_sprite.dart';
import 'package:aniverse_mobile/ui_2d/pixel/pixel.dart';
import 'package:aniverse_mobile/ui_2d/pixel/theme_fx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HistoryEntry watched(String anime, int ep, DateTime at, {bool finished = true}) => HistoryEntry(
      animeId: anime,
      episode: ep,
      positionMs: finished ? 1400000 : 300000,
      durationMs: 1440000,
      updatedAt: at.millisecondsSinceEpoch,
    );

void main() {
  group('achievements', () {
    test('nothing watched is level 1 with no badges', () {
      final s = Achievements.stats(const []);
      expect(s.finished, 0);
      final lv = Achievements.level(s);
      expect(lv.level, 1);
      expect(lv.rank, 'Peasant');
      expect(lv.frame, 'bronze');
      expect(Achievements.unlocked(s), isEmpty);
    });

    test('counts finished episodes, anime, binges and streaks', () {
      final now = DateTime.now();
      final entries = [
        for (var e = 1; e <= 6; e++) watched('154587', e, now),
        watched('1', 1, now.subtract(const Duration(days: 1))),
        watched('2', 1, now.subtract(const Duration(days: 2))),
        watched('3', 1, now, finished: false),
      ];
      final s = Achievements.stats(entries);
      expect(s.finished, 8);
      expect(s.anime, 4);
      expect(s.bestDay, 6);
      expect(s.streak, 3);
      expect(Achievements.unlocked(s), containsAll(['first_blood', 'binge', 'streak_3']));
      expect(Achievements.unlocked(s), isNot(contains('ten_slain')));
      // XP: 8 finished x10 + 4 anime x25 + 3 streak days x15.
      expect(Achievements.level(s).xp, 80 + 100 + 45);
    });
  });

  group('palettes', () {
    tearDown(() => Px.apply('blood'));

    test('applying a palette changes the colours and the effects style', () {
      Px.apply('neon');
      expect(Px.blood, const Color(0xFF00D9FF));
      expect(Px.keys['R'], Px.blood);
      expect(fxStyle, FxStyle.neon);
      Px.apply('sakura');
      expect(fxStyle, FxStyle.sakura);
      Px.apply('no-such-palette');
      expect(Px.theme, 'blood');
      expect(fxStyle, FxStyle.blood);
    });

    test('colorsOf reads a palette without switching to it', () {
      Px.apply('blood');
      expect(Px.colorsOf('sakura').blood, const Color(0xFFFF5FA2));
      expect(Px.blood, const Color(0xFFD10A1A));
    });

    test('the emblem keeps its crimson for Blood and takes the palette otherwise', () {
      Px.apply('blood');
      expect(emblemPalette()['B'], LogoSprite.palette['B']);
      Px.apply('neon');
      expect(emblemPalette()['B'], Px.blood);
      expect(LogoSprite.cells().length, greaterThan(500));
    });
  });

  group('downloads', () {
    const master = '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360\nlow/index.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720\nmid/index.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\nhigh/index.m3u8\n';
    final base = Uri.parse('https://cdn.example/show/master.m3u8');

    test('saves 720p normally, the lowest with data saver', () {
      expect(DownloadService.pickVariant(master, base, dataSaver: false),
          ('https://cdn.example/show/mid/index.m3u8', '720p'));
      expect(DownloadService.pickVariant(master, base, dataSaver: true),
          ('https://cdn.example/show/low/index.m3u8', '360p'));
    });

    test('rewrites a playlist to local files, keys and all', () {
      const media = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="/keys/k1"\n'
          '#EXTINF:6.0,\nseg1.ts\n#EXTINF:6.0,\nhttps://other.example/seg2.ts\n#EXT-X-ENDLIST\n';
      final (local, files) = DownloadService.localPlaylist(media, base);
      expect(files, [
        ('https://cdn.example/keys/k1', 'key0.bin'),
        ('https://cdn.example/show/seg1.ts', 's00000.ts'),
        ('https://other.example/seg2.ts', 's00001.ts'),
      ]);
      expect(local, contains('URI="key0.bin"'));
      expect(local, contains('s00001.ts'));
      expect(local, isNot(contains('https://')));
    });

    test('a playlist with no segments gives nothing to save', () {
      final (local, files) = DownloadService.localPlaylist('#EXTM3U\n#EXT-X-ENDLIST\n', base);
      expect(local, isEmpty);
      expect(files, isEmpty);
    });
  });

  group('watch party', () {
    test('state survives the trip through JSON', () {
      const s = PartyState(anime: '154587', ep: 3, category: 'dub', playing: true, t: 61.5);
      final back = PartyState.fromJson({...s.toJson(), 'at': 10.0, 'by': 'Kai'});
      expect((back.anime, back.ep, back.category, back.playing, back.t, back.by), ('154587', 3, 'dub', true, 61.5, 'Kai'));
    });

    test('codes are six easy-to-read characters', () {
      final code = PartyConnection.newCode();
      expect(code.length, 6);
      expect(code, isNot(matches(RegExp('[01OI]'))));
      expect(PartyConnection.validCode(code), isTrue);
      expect(PartyConnection.validCode('ab!'), isFalse);
    });
  });

  test('My List entries survive the trip through JSON', () {
    final e = WatchEntry(animeId: '154587', title: 'Frieren', seenEpisode: 12, updatedAt: 5, deleted: true);
    final back = WatchEntry.fromJson(e.toJson());
    expect((back.animeId, back.title, back.seenEpisode, back.updatedAt, back.deleted), ('154587', 'Frieren', 12, 5, true));
  });

  group('classic UI extras', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.load();
    });

    testWidgets('settings lists every section and a switch changes the setting', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ClassicSettingsScreen()));
      for (final t in ['Playback', 'Subtitles']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(AppSettings.dataSaver, isFalse);
      await tester.tap(find.text('Data saver'));
      await tester.pumpAndSettle();
      expect(AppSettings.dataSaver, isTrue);
      await tester.scrollUntilVisible(find.text('New-episode alerts'), 200);
      expect(find.text('Wi-Fi only'), findsOneWidget);
    });

    testWidgets('empty My List and Downloads say how to fill them', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ClassicMyListScreen()));
      expect(find.text('Your list is empty'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: ClassicDownloadsScreen()));
      expect(find.text('Nothing saved yet'), findsOneWidget);
    });
  });
}
