// Smoke test: the default `flutter create` test drove a counter template that
// this app never had, and referenced a `MyApp` class that does not exist here.

import 'package:flutter_test/flutter_test.dart';

import 'package:aniverse_mobile/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const AniVerseApp());
    expect(find.byType(AniVerseApp), findsOneWidget);
  });
}
