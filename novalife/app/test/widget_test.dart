import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novalife/main.dart';
import 'package:novalife/services/theme_service.dart';
import 'package:novalife/widgets/scrollable_form_wrapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _dismissSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThemeService', () {
    test('initialize defaults to the system theme when nothing is stored',
        () async {
      final service = ThemeService();
      await service.initialize();
      expect(service.currentThemeMode, AppThemeMode.system);
      expect(service.themeMode, ThemeMode.system);
      expect(service.themeDisplayName, 'System');
      expect(service.themeIcon, Icons.brightness_auto);
    });

    test('initialize restores the stored theme mode', () async {
      final first = ThemeService();
      await first.initialize();
      await first.setThemeMode(AppThemeMode.dark);

      final service = ThemeService();
      await service.initialize();

      expect(service.currentThemeMode, AppThemeMode.dark);
      expect(service.themeMode, ThemeMode.dark);
      expect(service.themeDisplayName, 'Dark');
      expect(service.isDarkMode, isTrue);
      expect(service.currentTheme.brightness, Brightness.dark);
    });

    test('setThemeMode persists and notifies listeners', () async {
      final service = ThemeService();
      await service.initialize();
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.setThemeMode(AppThemeMode.light);

      expect(service.currentThemeMode, AppThemeMode.light);
      expect(service.lightTheme.brightness, Brightness.light);
      expect(notifications, 1);

      final reloaded = ThemeService();
      await reloaded.initialize();
      expect(reloaded.currentThemeMode, AppThemeMode.light);
    });

    test('toggleTheme cycles light -> dark -> system -> light', () async {
      final service = ThemeService();
      await service.initialize();
      await service.setThemeMode(AppThemeMode.light);
      await service.toggleTheme();
      expect(service.currentThemeMode, AppThemeMode.dark);
      await service.toggleTheme();
      expect(service.currentThemeMode, AppThemeMode.system);
      await service.toggleTheme();
      expect(service.currentThemeMode, AppThemeMode.light);
    });
  });

  group('ContextExtension snackbars', () {
    testWidgets('showSnackBar shows the message in the success colour',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeService().lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.showSnackBar('Uploaded'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.text('Uploaded'), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.backgroundColor, Colors.green);

      await _dismissSnackBars(tester);
    });

    testWidgets('showSnackBar uses the error colour for failures',
        (WidgetTester tester) async {
      final theme = ThemeService().lightTheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.showSnackBar('Boom', isError: true),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.text('Boom'), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          theme.colorScheme.error);

      await _dismissSnackBars(tester);
    });

    testWidgets('showLoadingSnackBar shows a spinner with the message',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.showLoadingSnackBar('Working'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.text('Working'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _dismissSnackBars(tester);
    });
  });

  group('ScrollableFormWrapper', () {
    testWidgets('renders tall content without overflow and scrolls it',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollableFormWrapper(
              child: Column(
                children: List<Widget>.generate(
                  40,
                  (i) => SizedBox(height: 60, child: Text('row $i')),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('row 0'), findsOneWidget);

      final scrollable =
          tester.widget<Scrollable>(find.byType(Scrollable).first);
      expect(scrollable.physics, isA<ClampingScrollPhysics>());

      await tester.drag(find.text('row 0'), const Offset(0, -400));
      await tester.pumpAndSettle();

      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.pixels, greaterThan(300));
      expect(tester.getTopLeft(find.text('row 0')).dy, lessThan(0));
      expect(tester.takeException(), isNull);
    });
  });
}
