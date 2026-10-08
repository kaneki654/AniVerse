// 1.11: remote keys in the player, party host lock and reactions, rows that
// remember the remote's place, per-show memory, recent searches, new badges.
import 'dart:async';
import 'dart:convert';

import 'package:aniverse_mobile/services/app_settings.dart';
import 'package:aniverse_mobile/services/history_service.dart';
import 'package:aniverse_mobile/services/party_service.dart';
import 'package:aniverse_mobile/ui_2d/achievements.dart';
import 'package:aniverse_mobile/ui_2d/screens/home_screen.dart';
import 'package:aniverse_mobile/ui_2d/widgets/player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A video player that is always ready and remembers what it was asked to do.
class FakeVideo extends VideoPlayerPlatform {
  final calls = <String>[];
  final seeks = <Duration>[];
  // Not broadcast: events sent before the player listens wait for it.
  final _events = StreamController<VideoEvent>();

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    _events.add(VideoEvent(
        eventType: VideoEventType.initialized, duration: const Duration(minutes: 24), size: const Size(1280, 720)));
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events.stream;

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> seekTo(int playerId, Duration position) async => seeks.add(position);

  @override
  Future<Duration> getPosition(int playerId) async => seeks.isEmpty ? Duration.zero : seeks.last;

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox();

  @override
  Future<void> dispose(int playerId) async {}
}

PartyState _state({bool playing = true, double t = 10}) =>
    PartyState(anime: '1', ep: 1, category: 'sub', playing: playing, t: t);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.load();
  });

  group('player remote keys', () {
    testWidgets('select plays and pauses; arrows skip by the set length', (tester) async {
      final fake = FakeVideo();
      VideoPlayerPlatform.instance = fake;
      await AppSettings.set('seekStep', 15.0);
      final c = VideoPlayerController.networkUrl(Uri.parse('https://example.invalid/v.m3u8'));
      await tester.runAsync(c.initialize);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AniVersePlayerControls(controller: c, title: 'Test'))));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(fake.calls, contains('play'));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(fake.seeks.last, const Duration(seconds: 15));

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pump();
      expect(fake.calls.last, 'pause');

      // Done: let the HUD's timers run out with the widget gone.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(c.dispose);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('watch party', () {
    String msg(Map<String, Object?> m) => json.encode(m);

    test('a locked room puts a guest back where the host is', () {
      final moved = <double>[];
      var told = 0;
      final p = PartyConnection(code: 'LOCK01', getState: _state, onState: (s, t) => moved.add(s.t))
        ..onLockedOut = () => told++;
      p.handleMessage(msg({'type': 'hello', 'you': 'Guest', 'members': ['Host', 'Guest'], 'host': 'Host', 'locked': true,
          'state': {'anime': '1', 'ep': 1, 'category': 'sub', 'playing': false, 't': 42.0, 'at': 0}}));
      expect(p.isHost, isFalse);
      expect(p.canControl, isFalse);
      moved.clear();
      p.send(_state(t: 99)); // the guest seeks...
      expect(told, 1); // ...is told who is in control...
      expect(moved, [42.0]); // ...and is put back
      p.handleMessage(msg({'type': 'lock', 'on': false, 'host': 'Host'}));
      expect(p.canControl, isTrue);
      p.close();
    });

    test('reactions arrive from the fixed set only', () async {
      final p = PartyConnection(code: 'REACT1', getState: _state, onState: (_, __) {});
      final got = <(String, String)>[];
      final sub = p.reactions.stream.listen(got.add);
      p.handleMessage(msg({'type': 'react', 'emoji': '🔥', 'name': 'Kai'}));
      p.handleMessage(msg({'type': 'react', 'emoji': '<b>', 'name': 'Kai'}));
      await Future<void>.delayed(Duration.zero);
      expect(got, [('🔥', 'Kai')]);
      await sub.cancel();
      p.close();
    });
  });

  group('settings', () {
    test('per-show speed and auto-play, and muted alerts', () async {
      expect(AppSettings.speedFor('1'), isNull);
      await AppSettings.setSpeedFor('1', 1.5);
      expect(AppSettings.speedFor('1'), 1.5);
      expect(AppSettings.autoNextFor('1'), isTrue);
      await AppSettings.setAutoNextFor('1', false);
      expect(AppSettings.autoNextFor('1'), isFalse);
      expect(AppSettings.autoNextFor('2'), isTrue);
      await AppSettings.setAlertsFor('3', false);
      expect(AppSettings.alertsFor('3'), isFalse);
      expect(AppSettings.alertsFor('1'), isTrue);
    });

    test('watching in Tagalog is remembered per show until Sub / Dub is picked', () async {
      expect(AppSettings.tagalogFor('140960'), isFalse);
      await AppSettings.setTagalogFor('140960', true);
      expect(AppSettings.tagalogFor('140960'), isTrue);
      expect(AppSettings.tagalogFor('171018'), isFalse);
      await AppSettings.setTagalogFor('140960', false);
      expect(AppSettings.tagalogFor('140960'), isFalse);
    });

    test('recent searches: newest first, no repeats, at most ten', () async {
      for (var i = 0; i < 12; i++) {
        await AppSettings.addRecentSearch('show $i');
      }
      await AppSettings.addRecentSearch('SHOW 5');
      await AppSettings.addRecentSearch('x'); // too short to be a search
      final r = AppSettings.recentSearches;
      expect(r.length, 10);
      expect(r.first, 'SHOW 5');
      expect(r.where((q) => q.toLowerCase() == 'show 5').length, 1);
      await AppSettings.clearRecentSearches();
      expect(AppSettings.recentSearches, isEmpty);
    });
  });

  test('the new badges', () {
    final at6am = DateTime.now().copyWith(hour: 6, minute: 0);
    final entries = [
      for (var e = 1; e <= 10; e++)
        HistoryEntry(animeId: '1', episode: e, positionMs: 1400000, durationMs: 1440000, updatedAt: at6am.millisecondsSinceEpoch),
    ];
    final s = Achievements.stats(entries);
    expect(s.earlyBird, isTrue);
    expect(Achievements.unlocked(s), containsAll(['early_bird', 'possessed', 'binge']));
    expect(Achievements.unlocked(s), isNot(contains('archivist')));
  });

  testWidgets('a poster row sends the remote back to where it was', (tester) async {
    List<Map<String, dynamic>> posters(int n) => [
          for (var i = 0; i < n; i++)
            {'id': i, 'title': {'english': 'Show $i'}, 'coverImage': {'large': ''}},
        ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          PosterRow(title: 'One', animes: posters(5)),
          PosterRow(title: 'Two', animes: posters(5)),
        ]),
      ),
    ));
    await tester.pump();
    FocusNode node(String row, int i) =>
        Focus.of(tester.element(find.text('Show $i').at(row == 'One' ? 0 : 1)));
    node('One', 3).requestFocus();
    await tester.pump();
    node('Two', 0).requestFocus(); // down to the next row
    await tester.pump();
    node('One', 0).requestFocus(); // back up, landing on the nearest poster...
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(node('One', 3).hasPrimaryFocus, isTrue); // ...but sent to the one it left
  });
}
