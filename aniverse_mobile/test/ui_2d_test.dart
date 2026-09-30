import 'package:aniverse_mobile/services/auth_service.dart';
import 'package:aniverse_mobile/ui_2d/pixel/pixel.dart';
import 'package:aniverse_mobile/ui_2d/pixel/pixel_widgets.dart';
import 'package:aniverse_mobile/ui_2d/pixel/sprites.dart';
import 'package:aniverse_mobile/ui_2d/screens/account_screen.dart';
import 'package:aniverse_mobile/ui_2d/widgets/buffer_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The 2D UI animates continuously (dripping logo, frame clocks), so
/// pumpAndSettle would never settle; advance time by a fixed step instead.
Future<void> _step(WidgetTester tester) => tester.pump(const Duration(milliseconds: 700));

void main() {
  test('every sprite is a rectangle of known palette keys', () {
    const all = {
      'play': Sprites.play, 'pause': Sprites.pause, 'back': Sprites.back,
      'chevron': Sprites.chevron, 'rewind': Sprites.rewind, 'forward': Sprites.forward,
      'skipNext': Sprites.skipNext, 'search': Sprites.search, 'gear': Sprites.gear,
      'user': Sprites.user, 'grid': Sprites.grid, 'clock': Sprites.clock,
      'trash': Sprites.trash, 'fullscreen': Sprites.fullscreen,
      'fullscreenExit': Sprites.fullscreenExit, 'swap': Sprites.swap,
      'refresh': Sprites.refresh, 'check': Sprites.check, 'close': Sprites.close,
      'eye': Sprites.eye, 'eyeOff': Sprites.eyeOff, 'lock': Sprites.lock,
      'logout': Sprites.logout, 'floppy': Sprites.floppy, 'star': Sprites.star,
      'bloodDrop': Sprites.bloodDrop, 'skull': Sprites.skull, 'skullSmall': Sprites.skullSmall,
    };
    for (final MapEntry(key: name, value: s) in all.entries) {
      // A short row would shift every pixel after it and draw a skewed icon.
      expect(s.rows.every((r) => r.length == s.w), isTrue, reason: '$name has ragged rows');
      for (final ch in s.rows.join().split('')) {
        expect(ch == '.' || ch == 'X' || Px.keys.containsKey(ch), isTrue,
            reason: '$name uses unknown colour "$ch"');
      }
    }
  });

  testWidgets('buffer orb shows the speed and how full the buffer is', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: BufferOverlay(label: 'Buffering', progress: 0.3, mbps: 4.24)),
      ),
    ));
    await _step(tester);
    expect(find.text('4.2'), findsOneWidget);
    expect(find.text('MBPS'), findsOneWidget);
    expect(find.text('BUFFERING 30%'), findsOneWidget);

    // Unknown speed is shown as unknown, not as zero.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: BufferOverlay(label: 'Reconnecting'))),
    ));
    await _step(tester);
    expect(find.text('--'), findsOneWidget);
    expect(find.text('RECONNECTING'), findsOneWidget);
  });

  group('2D account screen', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AuthService.sessionExpired();
    });

    testWidgets('switching modes clears errors but keeps credentials', (tester) async {
      tester.view.physicalSize = const Size(480, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Finder button(String label) => find.widgetWithText(PixelButton, label);

      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
        await _step(tester);

        await tester.tap(button('CREATE ACCOUNT').first);
        await _step(tester);
        await tester.enterText(find.byType(TextFormField).at(0), 'AnimeFan');
        await tester.enterText(find.byType(TextFormField).at(1), 'short');
        // The last CREATE ACCOUNT is the submit button; the first is the tab.
        await tester.tap(button('CREATE ACCOUNT').last);
        await _step(tester);
        expect(find.text('At least 8 characters'), findsOneWidget);
        expect(find.text("Passwords don't match"), findsOneWidget);

        await tester.tap(button('SIGN IN').first);
        await _step(tester);
        expect(find.text('At least 8 characters'), findsNothing);
        expect(find.text("Passwords don't match"), findsNothing);
        expect(find.text('AnimeFan'), findsOneWidget);

        await tester.enterText(find.byType(TextFormField).at(1), 'password123');
        await tester.tap(button('SIGN IN').last);
        await _step(tester);
        await _step(tester);
        expect(find.textContaining('Account services are unavailable'), findsOneWidget);
        // A failed request must re-enable the form so a retry remains possible.
        expect(tester.widget<PixelButton>(button('SIGN IN').last).onPressed, isNotNull);
        await tester.pumpWidget(const SizedBox());
      },
          () => MockClient((request) async => request.url.path == '/api/auth/config'
              ? http.Response('{"password":true,"google":{"enabled":false}}', 200)
              : http.Response('{"detail":"Not Found"}', 404)));
    });
  });
}
