import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_ui/aether_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adversarial 1: Rapid Theme Toggling Stress Test (100+ cycles)', () {
    testWidgets('Rapid theme toggling across 120 cycles ensures zero desync and exact frame updates',
        (WidgetTester tester) async {
      int buildCountLevel1 = 0;
      int buildCountLevel3 = 0;
      int buildCountLeaf = 0;

      Brightness? currentObservedBrightness;
      Color? currentObservedPrimary;
      Color? currentObservedBackground;

      bool isDark = false;

      late StateSetter triggerRebuild;

      final widget = StatefulBuilder(
        builder: (context, setState) {
          triggerRebuild = setState;
          final themeData = isDark ? AetherThemeData.dark() : AetherThemeData.light();

          return AetherTheme(
            data: themeData,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Builder(
                builder: (context) {
                  buildCountLevel1++;
                  return Column(
                    children: [
                      // Level 2 intermediate
                      Builder(
                        builder: (context) {
                          // Level 3 nested
                          return Builder(
                            builder: (context) {
                              buildCountLevel3++;
                              return Builder(
                                builder: (context) {
                                  // Leaf consumer
                                  buildCountLeaf++;
                                  final colors = context.aetherColors;
                                  currentObservedBrightness = colors.brightness;
                                  currentObservedPrimary = colors.primary;
                                  currentObservedBackground = colors.background;
                                  return Container(
                                    color: colors.background,
                                    child: Text(
                                      colors.brightness == Brightness.dark ? 'Dark' : 'Light',
                                      style: TextStyle(color: colors.primary),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(widget);

      // Verify initial state (Light)
      expect(currentObservedBrightness, Brightness.light);
      expect(currentObservedPrimary, AetherColors.light().primary);
      expect(currentObservedBackground, AetherColors.light().background);
      expect(buildCountLeaf, 1);

      const int kCycles = 120;
      for (int i = 1; i <= kCycles; i++) {
        final targetDark = (i % 2 == 1); // alternate Dark, Light, Dark, Light...
        triggerRebuild(() {
          isDark = targetDark;
        });

        await tester.pump();

        final expectedColors = targetDark ? AetherColors.dark() : AetherColors.light();
        final expectedBrightness = targetDark ? Brightness.dark : Brightness.light;

        expect(currentObservedBrightness, equals(expectedBrightness),
            reason: 'Cycle $i: Observed brightness desynced from expected $expectedBrightness');
        expect(currentObservedPrimary, equals(expectedColors.primary),
            reason: 'Cycle $i: Primary color desynced');
        expect(currentObservedBackground, equals(expectedColors.background),
            reason: 'Cycle $i: Background color desynced');

        // Verify that every listener received exactly 1 rebuild per toggle
        expect(buildCountLevel1, equals(i + 1),
            reason: 'Cycle $i: Level 1 build count mismatch');
        expect(buildCountLevel3, equals(i + 1),
            reason: 'Cycle $i: Level 3 build count mismatch');
        expect(buildCountLeaf, equals(i + 1),
            reason: 'Cycle $i: Leaf build count mismatch');
      }

      expect(buildCountLeaf, equals(kCycles + 1));
    });

    testWidgets('updateShouldNotify prevents redundant rebuilds when identical theme is passed',
        (WidgetTester tester) async {
      int leafRebuilds = 0;
      late StateSetter triggerRebuild;
      final fixedTheme = AetherThemeData.light();

      // Create a cached child widget to ensure parent rebuild does not force child rebuild
      final cachedChild = Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            leafRebuilds++;
            final colors = context.aetherColors;
            return Text(colors.isLight ? 'Light' : 'Dark');
          },
        ),
      );

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            triggerRebuild = setState;
            return AetherTheme(
              data: fixedTheme,
              child: cachedChild,
            );
          },
        ),
      );

      expect(leafRebuilds, 1);

      // Rebuild outer state 10 times with identical AetherThemeData instance
      for (int i = 0; i < 10; i++) {
        triggerRebuild(() {});
        await tester.pump();
      }

      // Leaf widget should NOT rebuild because data != oldWidget.data is false
      expect(leafRebuilds, 1,
          reason: 'AetherTheme.updateShouldNotify must return false when theme data is unchanged');
    });

    testWidgets('Nested scoped AetherTheme maintains theme isolation under 100 root toggles',
        (WidgetTester tester) async {
      bool rootIsDark = false;
      late StateSetter toggleRoot;

      Brightness? innerObservedBrightness;
      Brightness? rootObservedBrightness;

      final widget = StatefulBuilder(
        builder: (context, setState) {
          toggleRoot = setState;
          return AetherTheme(
            data: rootIsDark ? AetherThemeData.dark() : AetherThemeData.light(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Builder(
                    builder: (context) {
                      rootObservedBrightness = context.aetherColors.brightness;
                      return const SizedBox();
                    },
                  ),
                  // Scoped inner theme locked to Light
                  AetherTheme(
                    data: AetherThemeData.light(),
                    child: Builder(
                      builder: (context) {
                        innerObservedBrightness = context.aetherColors.brightness;
                        return const SizedBox();
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(widget);

      for (int i = 0; i < 100; i++) {
        toggleRoot(() {
          rootIsDark = !rootIsDark;
        });
        await tester.pump();

        expect(rootObservedBrightness, rootIsDark ? Brightness.dark : Brightness.light);
        expect(innerObservedBrightness, Brightness.light,
            reason: 'Nested scoped theme must remain strictly isolated regardless of root toggles');
      }
    });
  });

  group('Adversarial 2: Unmounted Context & Missing Ancestor Edge Cases', () {
    testWidgets('Querying AetherTheme.of(context) with Theme(brightness: dark) falls back to Dark',
        (WidgetTester tester) async {
      late AetherThemeData captured;

      await tester.pumpWidget(
        Theme(
          data: ThemeData(brightness: Brightness.dark),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                captured = AetherTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(captured.isDark, isTrue);
      expect(captured.colors.brightness, Brightness.dark);
    });

    testWidgets('Querying AetherTheme.of(context) with Theme(brightness: light) falls back to Light',
        (WidgetTester tester) async {
      late AetherThemeData captured;

      await tester.pumpWidget(
        Theme(
          data: ThemeData(brightness: Brightness.light),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                captured = AetherTheme.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(captured.isDark, isFalse);
      expect(captured.colors.brightness, Brightness.light);
    });

    testWidgets('Querying AetherTheme.of(context) without any Theme or AetherTheme ancestor falls back safely to Light',
        (WidgetTester tester) async {
      late AetherThemeData captured;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              captured = AetherTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(captured.isDark, isFalse);
      expect(captured.colors.brightness, Brightness.light);
    });

    testWidgets('AetherTheme.maybeOf(context) returns null when not present',
        (WidgetTester tester) async {
      late AetherThemeData? captured;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              captured = AetherTheme.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(captured, isNull);
    });

    testWidgets(
        'AetherTheme.of(unmountedContext) executes safely and returns light theme fallback without throwing',
        (WidgetTester tester) async {
      late BuildContext savedContext;

      await tester.pumpWidget(
        AetherTheme(
          data: AetherThemeData.dark(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                savedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Verify context is mounted initially
      expect(savedContext.mounted, isTrue);
      expect(AetherTheme.of(savedContext).isDark, isTrue);

      // Unmount the element by pumping a completely different widget
      await tester.pumpWidget(const SizedBox());
      expect(savedContext.mounted, isFalse);

      // Empirical verification: AetherTheme.of on unmounted context returns light theme fallback safely
      late AetherThemeData fallbackTheme;
      expect(() => fallbackTheme = AetherTheme.of(savedContext), returnsNormally);
      expect(fallbackTheme, equals(AetherThemeData.light()));
      expect(fallbackTheme.isDark, isFalse);
    });

    testWidgets(
        'AetherTheme.maybeOf(unmountedContext) executes safely and returns null without throwing',
        (WidgetTester tester) async {
      late BuildContext savedContext;

      await tester.pumpWidget(
        AetherTheme(
          data: AetherThemeData.dark(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                savedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Unmount
      await tester.pumpWidget(const SizedBox());
      expect(savedContext.mounted, isFalse);

      // Empirical verification: maybeOf on unmounted context returns null safely
      late AetherThemeData? maybeTheme;
      expect(() => maybeTheme = AetherTheme.maybeOf(savedContext), returnsNormally);
      expect(maybeTheme, isNull);
    });

    testWidgets(
        'context extensions execute safely on unmounted context without throwing',
        (WidgetTester tester) async {
      late BuildContext savedContext;

      await tester.pumpWidget(
        AetherTheme(
          data: AetherThemeData.dark(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                savedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Unmount
      await tester.pumpWidget(const SizedBox());
      expect(savedContext.mounted, isFalse);

      // Verify all extension getters execute safely without throwing and return light fallback
      expect(() => savedContext.aetherTheme, returnsNormally);
      expect(savedContext.aetherTheme, equals(AetherThemeData.light()));
      expect(() => savedContext.aetherColors, returnsNormally);
      expect(savedContext.aetherColors, equals(AetherThemeData.light().colors));
      expect(() => savedContext.aetherTypography, returnsNormally);
      expect(savedContext.aetherTypography, equals(AetherThemeData.light().typography));
      expect(() => savedContext.aetherShadows, returnsNormally);
      expect(savedContext.aetherShadows, equals(AetherThemeData.light().shadows));
      expect(() => savedContext.aetherIsDark, returnsNormally);
      expect(savedContext.aetherIsDark, isFalse);
      expect(() => savedContext.aetherIsLight, returnsNormally);
      expect(savedContext.aetherIsLight, isTrue);
    });
  });

  group('Adversarial 3: Semantic State Quad Consistency & WCAG AA Contrast', () {
    test('Light mode: All 5 semantic state onContainer on container exceed WCAG AA (>= 4.5:1)', () {
      final light = AetherColors.light();
      final Map<String, AetherSemanticColor> states = {
        'success': light.success,
        'danger': light.danger,
        'warning': light.warning,
        'info': light.info,
        'neutral': light.neutral,
      };

      for (final entry in states.entries) {
        final name = entry.key;
        final quad = entry.value;

        final ratio = ContrastChecker.contrastRatio(quad.onContainer, quad.container);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'Light state "$name": onContainer on container ratio ($ratio) must be >= 4.5:1 (WCAG AA)',
        );
      }
    });

    test('Dark mode: All 5 semantic state onContainer on container exceed WCAG AA (>= 4.5:1)', () {
      final dark = AetherColors.dark();
      final Map<String, AetherSemanticColor> states = {
        'success': dark.success,
        'danger': dark.danger,
        'warning': dark.warning,
        'info': dark.info,
        'neutral': dark.neutral,
      };

      for (final entry in states.entries) {
        final name = entry.key;
        final quad = entry.value;

        final ratio = ContrastChecker.contrastRatio(quad.onContainer, quad.container);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'Dark state "$name": onContainer on container ratio ($ratio) must be >= 4.5:1 (WCAG AA)',
        );
      }
    });

    test('All 5 semantic state onBase on base contrast verification', () {
      final light = AetherColors.light();
      final dark = AetherColors.dark();

      void verifyOnBase(String themeName, Map<String, AetherSemanticColor> states) {
        for (final entry in states.entries) {
          final name = entry.key;
          final quad = entry.value;

          final ratio = ContrastChecker.contrastRatio(quad.onBase, quad.base);
          // onBase on base is used on buttons, badges, and chips
          // Graphical UI elements / large text requires >= 3.0:1
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: '$themeName state "$name": onBase on base ratio ($ratio) must be >= 3.0:1',
          );
        }
      }

      verifyOnBase('Light', {
        'success': light.success,
        'danger': light.danger,
        'warning': light.warning,
        'info': light.info,
        'neutral': light.neutral,
      });

      verifyOnBase('Dark', {
        'success': dark.success,
        'danger': dark.danger,
        'warning': dark.warning,
        'info': dark.info,
        'neutral': dark.neutral,
      });
    });

    test('Exact numerical contrast audit for all 10 semantic state pairings', () {
      final light = AetherColors.light();
      final dark = AetherColors.dark();

      final quads = <String, AetherSemanticColor>{
        'Light success': light.success,
        'Light danger': light.danger,
        'Light warning': light.warning,
        'Light info': light.info,
        'Light neutral': light.neutral,
        'Dark success': dark.success,
        'Dark danger': dark.danger,
        'Dark warning': dark.warning,
        'Dark info': dark.info,
        'Dark neutral': dark.neutral,
      };

      for (final entry in quads.entries) {
        final q = entry.value;
        final crOnC = ContrastChecker.contrastRatio(q.onContainer, q.container);
        final crOnB = ContrastChecker.contrastRatio(q.onBase, q.base);

        expect(crOnC, greaterThanOrEqualTo(4.5), reason: '${entry.key} onContainer on container failed WCAG AA');
        expect(crOnB, greaterThanOrEqualTo(3.0), reason: '${entry.key} onBase on base failed graphical/UI threshold');
      }
    });
  });
}
