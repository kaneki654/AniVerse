import 'package:aniverse_mobile/screens/account_screen.dart';
import 'package:aniverse_mobile/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService.sessionExpired();
  });

  testWidgets('switching account modes clears errors but keeps credentials',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'AnimeFan');
      await tester.enterText(find.byType(TextFormField).at(1), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(find.text("Passwords don't match"), findsOneWidget);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('At least 8 characters'), findsNothing);
      expect(find.text("Passwords don't match"), findsNothing);
      expect(find.text('AnimeFan'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Account services are unavailable'),
          findsOneWidget);
      // A failed request must re-enable the form so a retry remains possible.
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Account services are unavailable'),
          findsNothing);
      expect(find.text('AnimeFan'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async => request.url.path ==
                '/api/auth/config'
            ? http.Response('{"password":true,"google":{"enabled":false}}', 200)
            : http.Response('{"detail":"Not Found"}', 404)));
  });
}
