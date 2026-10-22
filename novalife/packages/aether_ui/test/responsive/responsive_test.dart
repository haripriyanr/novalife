import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_ui/aether_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AetherBreakpoint Enum & Getters', () {
    test('mobile breakpoint getters return expected booleans', () {
      const bp = AetherBreakpoint.mobile;
      expect(bp.isMobile, isTrue);
      expect(bp.isTablet, isFalse);
      expect(bp.isDesktop, isFalse);
      expect(bp.isTabletOrDesktop, isFalse);
      expect(bp.isMobileOrTablet, isTrue);
    });

    test('tablet breakpoint getters return expected booleans', () {
      const bp = AetherBreakpoint.tablet;
      expect(bp.isMobile, isFalse);
      expect(bp.isTablet, isTrue);
      expect(bp.isDesktop, isFalse);
      expect(bp.isTabletOrDesktop, isTrue);
      expect(bp.isMobileOrTablet, isTrue);
    });

    test('desktop breakpoint getters return expected booleans', () {
      const bp = AetherBreakpoint.desktop;
      expect(bp.isMobile, isFalse);
      expect(bp.isTablet, isFalse);
      expect(bp.isDesktop, isTrue);
      expect(bp.isTabletOrDesktop, isTrue);
      expect(bp.isMobileOrTablet, isFalse);
    });
  });

  group('Cutoff Constants & Width Boundaries', () {
    test('constants match specification exactly', () {
      expect(kMobileMaxWidth, 600.0);
      expect(kTabletMaxWidth, 1024.0);
      expect(kDesktopMaxWidth, 1920.0);
      expect(kMaxContentWidth, 1440.0);
    });

    test('breakpointForWidth classifies boundary values correctly', () {
      // Mobile interval [0, 600.0]
      expect(AetherResponsive.breakpointForWidth(320.0), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(599.9), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(600.0), AetherBreakpoint.mobile);

      // Tablet interval (600.0, 1024.0]
      expect(AetherResponsive.breakpointForWidth(600.1), AetherBreakpoint.tablet);
      expect(AetherResponsive.breakpointForWidth(768.0), AetherBreakpoint.tablet);
      expect(AetherResponsive.breakpointForWidth(1024.0), AetherBreakpoint.tablet);

      // Desktop interval (1024.0, +inf)
      expect(AetherResponsive.breakpointForWidth(1024.1), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(1280.0), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(1440.0), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(1920.0), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(2560.0), AetherBreakpoint.desktop);
    });
  });

  group('AetherResponsive Context Helpers', () {
    testWidgets('of(context) and isMobile/isTablet/isDesktop resolve from MediaQuery', (tester) async {
      Widget buildTest(double width) {
        return MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              final bp = AetherResponsive.of(context);
              final isMobile = AetherResponsive.isMobile(context);
              final isTablet = AetherResponsive.isTablet(context);
              final isDesktop = AetherResponsive.isDesktop(context);
              final isTabletOrDesktop = AetherResponsive.isTabletOrDesktop(context);

              return Text('$bp|$isMobile|$isTablet|$isDesktop|$isTabletOrDesktop',
                  textDirection: TextDirection.ltr);
            },
          ),
        );
      }

      await tester.pumpWidget(buildTest(400.0));
      expect(find.text('AetherBreakpoint.mobile|true|false|false|false'), findsOneWidget);

      await tester.pumpWidget(buildTest(800.0));
      expect(find.text('AetherBreakpoint.tablet|false|true|false|true'), findsOneWidget);

      await tester.pumpWidget(buildTest(1200.0));
      expect(find.text('AetherBreakpoint.desktop|false|false|true|true'), findsOneWidget);
    });

    testWidgets('value<T> selects correct value and respects fallbacks', (tester) async {
      Widget buildValueTest(double width, {String? tablet, String? desktop}) {
        return MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              final selected = AetherResponsive.value<String>(
                context,
                mobile: 'M',
                tablet: tablet,
                desktop: desktop,
              );
              return Text(selected, textDirection: TextDirection.ltr);
            },
          ),
        );
      }

      // Explicit values
      await tester.pumpWidget(buildValueTest(400, tablet: 'T', desktop: 'D'));
      expect(find.text('M'), findsOneWidget);

      await tester.pumpWidget(buildValueTest(800, tablet: 'T', desktop: 'D'));
      expect(find.text('T'), findsOneWidget);

      await tester.pumpWidget(buildValueTest(1200, tablet: 'T', desktop: 'D'));
      expect(find.text('D'), findsOneWidget);

      // Fallbacks
      await tester.pumpWidget(buildValueTest(800, tablet: null, desktop: 'D'));
      expect(find.text('M'), findsOneWidget, reason: 'Tablet falls back to mobile if null');

      await tester.pumpWidget(buildValueTest(1200, tablet: 'T', desktop: null));
      expect(find.text('T'), findsOneWidget, reason: 'Desktop falls back to tablet if desktop is null');

      await tester.pumpWidget(buildValueTest(1200, tablet: null, desktop: null));
      expect(find.text('M'), findsOneWidget, reason: 'Desktop falls back to mobile if both are null');
    });

    testWidgets('gridColumns and horizontalGutter return standard tokens', (tester) async {
      Widget buildMetricsTest(double width) {
        return MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              final cols = AetherResponsive.gridColumns(context);
              final gutter = AetherResponsive.horizontalGutter(context);
              return Text('$cols|$gutter', textDirection: TextDirection.ltr);
            },
          ),
        );
      }

      await tester.pumpWidget(buildMetricsTest(400));
      expect(find.text('1|12.0'), findsOneWidget); // 1 col, AetherSpacing.md (12.0)

      await tester.pumpWidget(buildMetricsTest(800));
      expect(find.text('2|24.0'), findsOneWidget); // 2 cols, AetherSpacing.xl (24.0)

      await tester.pumpWidget(buildMetricsTest(1200));
      expect(find.text('3|32.0'), findsOneWidget); // 3 cols, AetherSpacing.xxl (32.0)
    });
  });

  group('AetherResponsiveBuilder Local Layout Evaluation', () {
    testWidgets('evaluates local parent BoxConstraints over window MediaQuery', (tester) async {
      // Global window is desktop (1400px), but local container is constrained to mobile (500px)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1400, 900)),
          child: Center(
            child: SizedBox(
              width: 500.0,
              child: AetherResponsiveBuilder(
                builder: (context, breakpoint, constraints) {
                  return Text('${breakpoint.name}|${constraints.maxWidth.toInt()}',
                      textDirection: TextDirection.ltr);
                },
              ),
            ),
          ),
        ),
      );

      // Local builder must evaluate to mobile because local width is 500px <= 600px
      expect(find.text('mobile|500'), findsOneWidget);
    });

    testWidgets('handles infinite/unconstrained width gracefully with MediaQuery fallback', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: UnconstrainedBox(
            child: AetherResponsiveBuilder(
              builder: (context, breakpoint, constraints) {
                return Text('resolved:${breakpoint.name}', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );

      // With unbounded local constraint, falls back to 800px window width -> tablet
      expect(find.text('resolved:tablet'), findsOneWidget);
    });

    testWidgets('AetherResponsiveBuilder.select renders declared breakpoint branches', (tester) async {
      Widget buildSelectTest(double containerWidth) {
        return OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: containerWidth,
            child: AetherResponsiveBuilder.select(
              mobile: (context, constraints) => const Text('branch:mobile', textDirection: TextDirection.ltr),
              tablet: (context, constraints) => const Text('branch:tablet', textDirection: TextDirection.ltr),
              desktop: (context, constraints) => const Text('branch:desktop', textDirection: TextDirection.ltr),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildSelectTest(360));
      expect(find.text('branch:mobile'), findsOneWidget);

      await tester.pumpWidget(buildSelectTest(768));
      expect(find.text('branch:tablet'), findsOneWidget);

      await tester.pumpWidget(buildSelectTest(1280));
      expect(find.text('branch:desktop'), findsOneWidget);
    });

    testWidgets('dynamic resize triggers reactive rebuild with updated breakpoint', (tester) async {
      final widthNotifier = ValueNotifier<double>(400.0);

      await tester.pumpWidget(
        OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: widthNotifier,
            builder: (context, width, _) {
              return SizedBox(
                width: width,
                child: AetherResponsiveBuilder(
                  builder: (context, breakpoint, constraints) {
                    return Text('current:${breakpoint.name}', textDirection: TextDirection.ltr);
                  },
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('current:mobile'), findsOneWidget);

      // Resize container to tablet width
      widthNotifier.value = 850.0;
      await tester.pump();
      expect(find.text('current:tablet'), findsOneWidget);

      // Resize container to desktop width
      widthNotifier.value = 1400.0;
      await tester.pump();
      expect(find.text('current:desktop'), findsOneWidget);
    });
  });
}
