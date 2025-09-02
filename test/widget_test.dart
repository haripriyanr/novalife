import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novalife/main.dart';
import 'package:novalife/services/theme_service.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // ✅ Fixed: Provide required themeService parameter
    final themeService = ThemeService();
    await themeService.initialize();

    // Build our app and trigger a frame.
    await tester.pumpWidget(NovaLifeApp(themeService: themeService));

    // Verify that our counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
