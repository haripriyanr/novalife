import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_ui/aether_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // SECTION 1: Breakpoint Boundaries & Floating Point Cutoffs
  // ---------------------------------------------------------------------------
  group('Adversarial Breakpoint Boundaries & Cutoffs', () {
    test('exact boundary cutoffs classify precisely without off-by-one errors', () {
      // Mobile boundary: [0.0, 600.0]
      expect(AetherResponsive.breakpointForWidth(0.0), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(320.0), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(599.999), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(600.0), AetherBreakpoint.mobile,
          reason: '600.0 is the exact upper bound of mobile (kMobileMaxWidth)');

      // Microscopic epsilon over 600.0 must transition to tablet
      expect(AetherResponsive.breakpointForWidth(600.0001), AetherBreakpoint.tablet,
          reason: '600.0001 must transition into tablet');
      expect(AetherResponsive.breakpointForWidth(600.000000000001), AetherBreakpoint.tablet,
          reason: 'Sub-pixel floating point epsilon > 600.0 must be tablet');
      expect(AetherResponsive.breakpointForWidth(768.0), AetherBreakpoint.tablet);

      // Tablet boundary: (600.0, 1024.0]
      expect(AetherResponsive.breakpointForWidth(1023.999), AetherBreakpoint.tablet);
      expect(AetherResponsive.breakpointForWidth(1024.0), AetherBreakpoint.tablet,
          reason: '1024.0 is the exact upper bound of tablet (kTabletMaxWidth)');

      // Microscopic epsilon over 1024.0 must transition to desktop
      expect(AetherResponsive.breakpointForWidth(1024.0001), AetherBreakpoint.desktop,
          reason: '1024.0001 must transition into desktop');
      expect(AetherResponsive.breakpointForWidth(1024.000000000001), AetherBreakpoint.desktop,
          reason: 'Sub-pixel floating point epsilon > 1024.0 must be desktop');
      expect(AetherResponsive.breakpointForWidth(1280.0), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(1440.0), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(1920.0), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(2560.0), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(3840.0), AetherBreakpoint.desktop);
    });

    test('extreme and degenerate width values are handled safely without exceptions', () {
      // Zero width
      expect(AetherResponsive.breakpointForWidth(0.0), AetherBreakpoint.mobile);

      // Negative values (e.g. collapsed or inverted geometries)
      expect(AetherResponsive.breakpointForWidth(-0.0001), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(-1.0), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(-600.0), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(-1024.0), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(-1e12), AetherBreakpoint.mobile);
      expect(AetherResponsive.breakpointForWidth(-double.infinity), AetherBreakpoint.mobile);

      // Infinite and huge positive values
      expect(AetherResponsive.breakpointForWidth(double.infinity), AetherBreakpoint.desktop);
      expect(AetherResponsive.breakpointForWidth(double.maxFinite), AetherBreakpoint.desktop);

      // NaN (Dart comparison with NaN yields false for <=, falling through to desktop)
      expect(AetherResponsive.breakpointForWidth(double.nan), AetherBreakpoint.desktop);
    });

    test('value selection and column/gutter helpers at exact boundary thresholds', () {
      // Mobile upper bound (600.0)
      expect(AetherResponsive.gridColumnsForWidth(600.0), 1);
      expect(
        AetherResponsive.valueForWidth<String>(600.0, mobile: 'M', tablet: 'T', desktop: 'D'),
        'M',
      );

      // Tablet lower bound (600.0001)
      expect(AetherResponsive.gridColumnsForWidth(600.0001), 2);
      expect(
        AetherResponsive.valueForWidth<String>(600.0001, mobile: 'M', tablet: 'T', desktop: 'D'),
        'T',
      );

      // Tablet upper bound (1024.0)
      expect(AetherResponsive.gridColumnsForWidth(1024.0), 2);
      expect(
        AetherResponsive.valueForWidth<String>(1024.0, mobile: 'M', tablet: 'T', desktop: 'D'),
        'T',
      );

      // Desktop lower bound (1024.0001)
      expect(AetherResponsive.gridColumnsForWidth(1024.0001), 3);
      expect(
        AetherResponsive.valueForWidth<String>(1024.0001, mobile: 'M', tablet: 'T', desktop: 'D'),
        'D',
      );

      // Degenerate inputs
      expect(AetherResponsive.gridColumnsForWidth(0.0), 1);
      expect(AetherResponsive.gridColumnsForWidth(-100.0), 1);
      expect(AetherResponsive.gridColumnsForWidth(double.infinity), 3);
    });

    test('fallback chains at boundaries when intermediate values are omitted', () {
      // Tablet without tablet value falls back to mobile
      expect(
        AetherResponsive.valueForWidth<String>(600.0001, mobile: 'M', desktop: 'D'),
        'M',
      );
      expect(
        AetherResponsive.valueForWidth<String>(1024.0, mobile: 'M', desktop: 'D'),
        'M',
      );

      // Desktop without desktop value falls back to tablet, then mobile
      expect(
        AetherResponsive.valueForWidth<String>(1024.0001, mobile: 'M', tablet: 'T'),
        'T',
      );
      expect(
        AetherResponsive.valueForWidth<String>(1024.0001, mobile: 'M'),
        'M',
      );
      expect(
        AetherResponsive.valueForWidth<String>(double.infinity, mobile: 'M', tablet: 'T'),
        'T',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SECTION 2: Dynamic Container Resize with AetherResponsiveBuilder
  // ---------------------------------------------------------------------------
  group('Dynamic Container Resize & LayoutBuilder Stress', () {
    testWidgets('dynamic resize across 12 rapid width steps updates reactively', (tester) async {
      final widthNotifier = ValueNotifier<double>(320.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverflowBox(
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
                        return Text(
                          '${breakpoint.name}|${constraints.maxWidth.toStringAsFixed(4)}',
                          textDirection: TextDirection.ltr,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final sequence = <(double, String)>[
        (320.0, 'mobile|320.0000'),
        (599.999, 'mobile|599.9990'),
        (600.0, 'mobile|600.0000'),
        (600.0001, 'tablet|600.0001'),
        (768.0, 'tablet|768.0000'),
        (1024.0, 'tablet|1024.0000'),
        (1024.0001, 'desktop|1024.0001'),
        (1440.0, 'desktop|1440.0000'),
        (1920.0, 'desktop|1920.0000'),
        (2560.0, 'desktop|2560.0000'),
        (600.0, 'mobile|600.0000'),
        (0.0, 'mobile|0.0000'),
      ];

      for (final (width, expectedText) in sequence) {
        widthNotifier.value = width;
        await tester.pump();
        expect(find.text(expectedText), findsOneWidget,
            reason: 'Step at width $width must evaluate to $expectedText');
      }
    });

    testWidgets('dynamic resize with AetherResponsiveBuilder.select switches branches seamlessly', (tester) async {
      final widthNotifier = ValueNotifier<double>(400.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: widthNotifier,
                builder: (context, width, _) {
                  return SizedBox(
                    width: width,
                    child: AetherResponsiveBuilder.select(
                      mobile: (ctx, c) => const Text('active:MOBILE', textDirection: TextDirection.ltr),
                      tablet: (ctx, c) => const Text('active:TABLET', textDirection: TextDirection.ltr),
                      desktop: (ctx, c) => const Text('active:DESKTOP', textDirection: TextDirection.ltr),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('active:MOBILE'), findsOneWidget);

      // Transition to tablet
      widthNotifier.value = 600.0001;
      await tester.pump();
      expect(find.text('active:TABLET'), findsOneWidget);

      // Transition to desktop
      widthNotifier.value = 1024.0001;
      await tester.pump();
      expect(find.text('active:DESKTOP'), findsOneWidget);

      // Transition back to mobile boundary
      widthNotifier.value = 600.0;
      await tester.pump();
      expect(find.text('active:MOBILE'), findsOneWidget);
    });

    testWidgets('AetherResponsiveBuilder.select fallback behavior when optional branches are null', (tester) async {
      Widget buildWithOmissions(double width, {bool includeTablet = false, bool includeDesktop = false}) {
        return OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: AetherResponsiveBuilder.select(
              mobile: (ctx, c) => const Text('BRANCH_M', textDirection: TextDirection.ltr),
              tablet: includeTablet ? (ctx, c) => const Text('BRANCH_T', textDirection: TextDirection.ltr) : null,
              desktop: includeDesktop ? (ctx, c) => const Text('BRANCH_D', textDirection: TextDirection.ltr) : null,
            ),
          ),
        );
      }

      // Only mobile provided: should render BRANCH_M for mobile, tablet, and desktop widths
      await tester.pumpWidget(MaterialApp(home: buildWithOmissions(400)));
      expect(find.text('BRANCH_M'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: buildWithOmissions(800)));
      expect(find.text('BRANCH_M'), findsOneWidget, reason: 'Tablet falls back to mobile');

      await tester.pumpWidget(MaterialApp(home: buildWithOmissions(1400)));
      expect(find.text('BRANCH_M'), findsOneWidget, reason: 'Desktop falls back to mobile when tablet also null');

      // Mobile + Tablet provided: Desktop falls back to Tablet
      await tester.pumpWidget(MaterialApp(home: buildWithOmissions(1400, includeTablet: true)));
      expect(find.text('BRANCH_T'), findsOneWidget, reason: 'Desktop falls back to tablet');
    });

    testWidgets('unconstrained infinite maxWidth gracefully queries ambient MediaQuery', (tester) async {
      // 1. Ambient window is Mobile (400x800)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: UnconstrainedBox(
            child: AetherResponsiveBuilder(
              builder: (context, bp, c) {
                return Text('unbounded:${bp.name}', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );
      expect(find.text('unbounded:mobile'), findsOneWidget);

      // 2. Ambient window is Tablet (800x800)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 800)),
          child: UnconstrainedBox(
            child: AetherResponsiveBuilder(
              builder: (context, bp, c) {
                return Text('unbounded:${bp.name}', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );
      expect(find.text('unbounded:tablet'), findsOneWidget);

      // 3. Ambient window is Desktop (1600x900)
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1600, 900)),
          child: UnconstrainedBox(
            child: AetherResponsiveBuilder(
              builder: (context, bp, c) {
                return Text('unbounded:${bp.name}', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );
      expect(find.text('unbounded:desktop'), findsOneWidget);
    });

    testWidgets('zero width BoxConstraints render safely without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 0.0,
                height: 100.0,
                child: AetherResponsiveBuilder(
                  builder: (context, bp, constraints) {
                    return Text('zero:${bp.name}|w=${constraints.maxWidth}', textDirection: TextDirection.ltr);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('zero:mobile|w=0.0'), findsOneWidget);
    });

    testWidgets('nested AetherResponsiveBuilder instances adapt to local scopes independently', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 1400.0, // Desktop container
                child: AetherResponsiveBuilder(
                  builder: (context, outerBp, outerConstraints) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('outer:${outerBp.name}', textDirection: TextDirection.ltr),
                        SizedBox(
                          width: 450.0, // Nested container constrained to mobile
                          child: AetherResponsiveBuilder(
                            builder: (context, innerBp, innerConstraints) {
                              return Text('inner:${innerBp.name}', textDirection: TextDirection.ltr);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('outer:desktop'), findsOneWidget);
      expect(find.text('inner:mobile'), findsOneWidget);
    });
    testWidgets('dynamic transition from bounded to unbounded infinite constraints', (tester) async {
      final constraintsNotifier = ValueNotifier<BoxConstraints>(
        const BoxConstraints.tightFor(width: 500.0),
      );

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1200, 800)),
          child: ValueListenableBuilder<BoxConstraints>(
            valueListenable: constraintsNotifier,
            builder: (context, constraints, _) {
              return OverflowBox(
                minWidth: constraints.minWidth,
                maxWidth: constraints.maxWidth,
                alignment: Alignment.topLeft,
                child: AetherResponsiveBuilder(
                  builder: (ctx, bp, c) {
                    return Text('mode:${bp.name}', textDirection: TextDirection.ltr);
                  },
                ),
              );
            },
          ),
        ),
      );

      // Initially bounded 500px -> mobile
      expect(find.text('mode:mobile'), findsOneWidget);

      // Mutate to unbounded infinite maxWidth -> should fall back to 1200px MediaQuery -> desktop
      constraintsNotifier.value = const BoxConstraints(maxWidth: double.infinity);
      await tester.pump();
      expect(find.text('mode:desktop'), findsOneWidget);

      // Mutate to bounded 768px -> tablet
      constraintsNotifier.value = const BoxConstraints.tightFor(width: 768.0);
      await tester.pump();
      expect(find.text('mode:tablet'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // SECTION 3: Contrast Math Boundaries & WCAG Ratio Verification
  // ---------------------------------------------------------------------------
  group('Adversarial Contrast Math & Luminance Boundaries', () {
    test('pure black (0.0) and pure white (1.0) exact relative luminance', () {
      final lumBlack = ContrastChecker.relativeLuminance(const Color(0xFF000000));
      expect(lumBlack, 0.0, reason: 'Pure black must have relative luminance exactly 0.0');

      final lumWhite = ContrastChecker.relativeLuminance(const Color(0xFFFFFFFF));
      expect(lumWhite, 1.0, reason: 'Pure white must have relative luminance exactly 1.0');
    });

    test('ITU-R BT.709 spectral primary color luminances and coefficient summation', () {
      final lumRed = ContrastChecker.relativeLuminance(const Color(0xFFFF0000));
      final lumGreen = ContrastChecker.relativeLuminance(const Color(0xFF00FF00));
      final lumBlue = ContrastChecker.relativeLuminance(const Color(0xFF0000FF));

      expect(lumRed, closeTo(0.2126, 0.0001), reason: 'sRGB red luminance coefficient is 0.2126');
      expect(lumGreen, closeTo(0.7152, 0.0001), reason: 'sRGB green luminance coefficient is 0.7152');
      expect(lumBlue, closeTo(0.0722, 0.0001), reason: 'sRGB blue luminance coefficient is 0.0722');

      // The sum of the primary coefficients must equal exactly 1.0
      expect(lumRed + lumGreen + lumBlue, closeTo(1.0, 1e-12));

      // Secondary colors
      final lumYellow = ContrastChecker.relativeLuminance(const Color(0xFFFFFF00));
      expect(lumYellow, closeTo(0.2126 + 0.7152, 0.0001));

      final lumCyan = ContrastChecker.relativeLuminance(const Color(0xFF00FFFF));
      expect(lumCyan, closeTo(0.7152 + 0.0722, 0.0001));

      final lumMagenta = ContrastChecker.relativeLuminance(const Color(0xFFFF00FF));
      expect(lumMagenta, closeTo(0.2126 + 0.0722, 0.0001));
    });

    test('piecewise gamma threshold continuity at C = 0.04045', () {
      // Test continuity across the transition threshold (0.04045)
      // Below or at threshold: C / 12.92
      // Above threshold: ((C + 0.055) / 1.055)^2.4
      const cThreshold = 0.04045;
      const valLinear = cThreshold / 12.92;
      final valPow = math.pow((cThreshold + 0.055) / 1.055, 2.4).toDouble();

      expect(valLinear, closeTo(valPow, 0.0001),
          reason: 'ITU-R BT.709 gamma curve must be continuous at threshold 0.04045');
    });

    test('relative luminance monotonicity across 256 grayscale levels', () {
      double previousLuminance = -1.0;
      for (int i = 0; i <= 255; i++) {
        final color = Color.fromARGB(255, i, i, i);
        final currentLuminance = ContrastChecker.relativeLuminance(color);

        expect(currentLuminance, greaterThanOrEqualTo(0.0));
        expect(currentLuminance, lessThanOrEqualTo(1.0));
        expect(currentLuminance, greaterThan(previousLuminance),
            reason: 'Luminance must strictly increase from level $i');

        previousLuminance = currentLuminance;
      }
    });

    test('contrastRatio boundaries: black vs white (21.0:1) and identical colors (1.0:1)', () {
      // Maximum contrast: pure black vs pure white
      final crMax1 = ContrastChecker.contrastRatio(
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
      );
      expect(crMax1, closeTo(21.0, 1e-10), reason: '(1.0 + 0.05) / (0.0 + 0.05) = 21.0');

      final crMax2 = ContrastChecker.contrastRatio(
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
      );
      expect(crMax2, closeTo(21.0, 1e-10), reason: 'Commutative CR(white, black) must equal 21.0');

      // Minimum contrast: identical colors
      final testPalette = [
        const Color(0xFF000000),
        const Color(0xFFFFFFFF),
        const Color(0xFF123456),
        const Color(0xFF808080),
        const Color(0xFFFAFAFA),
        const Color(0xFFE2E8F0),
        const Color(0xFF2563EB),
      ];

      for (final color in testPalette) {
        final crIdentical = ContrastChecker.contrastRatio(color, color);
        expect(crIdentical, closeTo(1.0, 1e-10),
            reason: 'Contrast ratio of identical color ($color) must equal 1.0');
      }
    });

    test('contrast ratio mathematical invariants fuzzing (1000 color pairs)', () {
      // Deterministic PRNG for reproducibility
      final random = math.Random(42);

      for (int i = 0; i < 1000; i++) {
        final c1 = Color.fromARGB(
          255,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
        final c2 = Color.fromARGB(
          255,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );

        final cr1 = ContrastChecker.contrastRatio(c1, c2);
        final cr2 = ContrastChecker.contrastRatio(c2, c1);

        // 1. Commutativity: CR(A, B) == CR(B, A)
        expect(cr1, equals(cr2), reason: 'Contrast ratio must be strictly commutative');

        // 2. Strict range bounds: 1.0 <= CR <= 21.0
        expect(cr1, greaterThanOrEqualTo(1.0 - 1e-10),
            reason: 'Contrast ratio must never be less than 1.0');
        expect(cr1, lessThanOrEqualTo(21.0 + 1e-10),
            reason: 'Contrast ratio must never exceed 21.0');

        // 3. Finite, non-NaN guarantee
        expect(cr1.isFinite, isTrue);
        expect(cr1.isNaN, isFalse);
      }
    });

    test('WCAG AA and AAA threshold helper evaluations', () {
      // 21.0:1 satisfies all levels
      expect(ContrastChecker.isWcagAaNormalText(Colors.black, Colors.white), isTrue);
      expect(ContrastChecker.isWcagAaLargeTextOrUi(Colors.black, Colors.white), isTrue);
      expect(ContrastChecker.isWcagAaaNormalText(Colors.black, Colors.white), isTrue);
      expect(ContrastChecker.isWcagAaaLargeText(Colors.black, Colors.white), isTrue);

      // 1.0:1 fails all levels
      expect(ContrastChecker.isWcagAaNormalText(Colors.white, Colors.white), isFalse);
      expect(ContrastChecker.isWcagAaLargeTextOrUi(Colors.white, Colors.white), isFalse);
      expect(ContrastChecker.isWcagAaaNormalText(Colors.white, Colors.white), isFalse);
      expect(ContrastChecker.isWcagAaaLargeText(Colors.white, Colors.white), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // SECTION 4: Alpha Compositing (compositeOver) Stress Testing
  // ---------------------------------------------------------------------------
  group('Adversarial Alpha Compositing (compositeOver) Testing', () {
    test('opaque foreground (a = 1.0) returns foreground directly', () {
      const fg = Color(0xFF2563EB);
      const bg = Color(0xFFFFFFFF);
      final result = ContrastChecker.compositeOver(fg, bg);
      expect(result, equals(fg));
    });

    test('fully transparent foreground (a = 0.0) yields background with full alpha', () {
      const fg = Color(0x00FF0000); // 0% opacity red
      const bg = Color(0xFFFFFFFF); // 100% white
      final result = ContrastChecker.compositeOver(fg, bg);
      expect(result, equals(const Color(0xFFFFFFFF)),
          reason: 'Transparent foreground over white must yield pure white');

      const bgBlack = Color(0xFF000000);
      final resultBlack = ContrastChecker.compositeOver(fg, bgBlack);
      expect(resultBlack, equals(const Color(0xFF000000)),
          reason: 'Transparent foreground over black must yield pure black');
    });

    test('semi-transparent black (50%) over white yields mid-gray', () {
      const semiBlack = Color(0x80000000); // ~50.2% alpha black
      const white = Color(0xFFFFFFFF);
      final composited = ContrastChecker.compositeOver(semiBlack, white);

      // R = G = B = 1.0 * (1 - 128/255) = 127/255 -> 127
      expect(composited.r, closeTo(127.0 / 255.0, 0.01));
      expect(composited.g, closeTo(127.0 / 255.0, 0.01));
      expect(composited.b, closeTo(127.0 / 255.0, 0.01));
      expect(composited.a, 1.0);
    });

    test('semi-transparent white (50%) over black yields mid-gray', () {
      const semiWhite = Color(0x80FFFFFF); // ~50.2% alpha white
      const black = Color(0xFF000000);
      final composited = ContrastChecker.compositeOver(semiWhite, black);

      // R = G = B = 1.0 * (128/255) = 128/255 -> 128
      expect(composited.r, closeTo(128.0 / 255.0, 0.01));
      expect(composited.g, closeTo(128.0 / 255.0, 0.01));
      expect(composited.b, closeTo(128.0 / 255.0, 0.01));
      expect(composited.a, 1.0);
    });

    test('chromatic alpha blend: 50% red over pure blue yields expected purple', () {
      const semiRed = Color(0x80FF0000);
      const pureBlue = Color(0xFF0000FF);
      final composited = ContrastChecker.compositeOver(semiRed, pureBlue);

      // R should be around 128, G should be 0, B should be around 127
      expect((composited.r * 255).round(), 128);
      expect((composited.g * 255).round(), 0);
      expect((composited.b * 255).round(), 127);
      expect(composited.a, 1.0);
    });

    test('theme scrim tokens composited over background preserve expected contrast', () {
      final light = AetherColors.light();
      final dark = AetherColors.dark();

      // Scrim over Light background
      final lightOverlay = ContrastChecker.compositeOver(light.scrim, light.background);
      expect(lightOverlay.a, 1.0);
      expect(ContrastChecker.relativeLuminance(lightOverlay),
          lessThan(ContrastChecker.relativeLuminance(light.background)),
          reason: 'Scrim must darken the light background');

      // Scrim over Dark background
      final darkOverlay = ContrastChecker.compositeOver(dark.scrim, dark.background);
      expect(darkOverlay.a, 1.0);
      expect(ContrastChecker.relativeLuminance(darkOverlay),
          lessThanOrEqualTo(ContrastChecker.relativeLuminance(dark.background)),
          reason: 'Scrim must darken or maintain dark background');
    });

    test('multi-layer iterative alpha compositing converges monotonically and remains stable', () {
      Color current = const Color(0xFFFFFFFF); // White background
      const blackTint = Color(0x1A000000); // ~10% black overlay

      // Apply 20 successive layers of black tint
      for (int i = 0; i < 20; i++) {
        final next = ContrastChecker.compositeOver(blackTint, current);
        expect(next.a, 1.0);
        expect(ContrastChecker.relativeLuminance(next),
            lessThanOrEqualTo(ContrastChecker.relativeLuminance(current)),
            reason: 'Each overlay layer must monotonically darken or equal the previous layer');
        current = next;
      }

      // After 20 layers of ~10% black, should be significantly darker than initial white
      expect(ContrastChecker.relativeLuminance(current), lessThan(0.2));
    });

    test('extreme near-boundary alpha (0.001 and 0.999) behavior', () {
      const almostOpaque = Color.from(alpha: 0.999, red: 0.0, green: 0.0, blue: 0.0);
      const almostTransparent = Color.from(alpha: 0.001, red: 0.0, green: 0.0, blue: 0.0);
      const white = Color(0xFFFFFFFF);

      final resAlmostOpaque = ContrastChecker.compositeOver(almostOpaque, white);
      expect((resAlmostOpaque.r * 255).round(), inInclusiveRange(0, 1));
      expect(resAlmostOpaque.a, 1.0);

      final resAlmostTransparent = ContrastChecker.compositeOver(almostTransparent, white);
      expect((resAlmostTransparent.r * 255).round(), inInclusiveRange(254, 255));
      expect(resAlmostTransparent.a, 1.0);
    });

    test('delta-1 color difference contrast ratio is strictly > 1.0 and finite', () {
      const black = Color(0xFF000000);
      const nearBlack = Color(0xFF000001); // 1 LSB difference in blue channel
      final cr = ContrastChecker.contrastRatio(black, nearBlack);

      expect(cr, greaterThan(1.0));
      expect(cr, lessThan(1.01));
      expect(cr.isFinite, isTrue);
    });
  });
}

