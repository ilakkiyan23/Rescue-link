// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:rescue_link/main.dart';

void main() {
  testWidgets('Rescue Link renders base navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const RescueLinkApp());

    expect(find.text('Emergency SOS'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
