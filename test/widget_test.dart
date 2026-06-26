import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_hud/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GuardianHudApp());
    expect(find.byType(GuardianHudApp), findsOneWidget);
  });
}
