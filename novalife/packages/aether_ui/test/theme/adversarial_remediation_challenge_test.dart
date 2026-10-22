import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_ui/aether_ui.dart';

class _LifecycleProbeWidget extends StatefulWidget {
  final void Function(BuildContext context)? onDeactivate;
  final void Function(BuildContext context)? onDispose;

  const _LifecycleProbeWidget({
    this.onDeactivate,
    this.onDispose,
  });

  @override
  State<_LifecycleProbeWidget> createState() => _LifecycleProbeWidgetState();
}

class _LifecycleProbeWidgetState extends State<_LifecycleProbeWidget> {
  @override
  void deactivate() {
    widget.onDeactivate?.call(context);
    super.deactivate();
  }

  @override
  void dispose() {
    widget.onDispose?.call(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adversarial Challenge 1: Unmounted & Deactivated Context Resilience', () {
    testWidgets('AetherTheme.of and maybeOf execute safely during element deactivate()',
        (WidgetTester tester) async {
      bool deactivateRan = false;
      AetherThemeData? themeInDeactivate;
      AetherThemeData? maybeThemeInDeactivate;

      await tester.pumpWidget(
        AetherTheme(
          data: AetherThemeData.dark(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: _LifecycleProbeWidget(
              onDeactivate: (context) {
                deactivateRan = true;
                expect(() => themeInDeactivate = AetherTheme.of(context), returnsNormally);
                expect(() => maybeThemeInDeactivate = AetherTheme.maybeOf(context), returnsNormally);
              },
            ),
          ),
        ),
      );

      // Trigger deactivation by replacing widget tree
      await tester.pumpWidget(const SizedBox());

      expect(deactivateRan, isTrue);
      // In deactivate, element is being deactivated; lookup executes safely without crashing
      expect(themeInDeactivate, isNotNull);
      expect(themeInDeactivate, equals(AetherThemeData.dark()));
      expect(maybeThemeInDeactivate, equals(AetherThemeData.dark()));
    });

    testWidgets('AetherTheme.of and maybeOf execute safely during element dispose()',
        (WidgetTester tester) async {
      bool disposeRan = false;
      AetherThemeData? themeInDispose;
      AetherThemeData? maybeThemeInDispose;

      await tester.pumpWidget(
        AetherTheme(
          data: AetherThemeData.dark(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: _LifecycleProbeWidget(
              onDispose: (context) {
                disposeRan = true;
                expect(context.mounted, isFalse);
                expect(() => themeInDispose = AetherTheme.of(context), returnsNormally);
                expect(() => maybeThemeInDispose = AetherTheme.maybeOf(context), returnsNormally);
              },
            ),
          ),
        ),
      );

      // Trigger dispose by replacing widget tree
      await tester.pumpWidget(const SizedBox());

      expect(disposeRan, isTrue);
      expect(themeInDispose, equals(AetherThemeData.light()));
      expect(maybeThemeInDispose, isNull);
    });

    testWidgets('AetherTheme.of returns light fallback across 200 rapid unmounted queries',
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

      for (int i = 0; i < 200; i++) {
        expect(() => AetherTheme.of(savedContext), returnsNormally);
        final theme = AetherTheme.of(savedContext);
        expect(theme, equals(AetherThemeData.light()));
        expect(theme.isDark, isFalse);

        expect(() => AetherTheme.maybeOf(savedContext), returnsNormally);
        final maybeTheme = AetherTheme.maybeOf(savedContext);
        expect(maybeTheme, isNull);
      }
    });

    testWidgets('Unmounted context originally in Theme(brightness: dark) returns safe light fallback without crashing Theme.of',
        (WidgetTester tester) async {
      late BuildContext savedContext;

      await tester.pumpWidget(
        Theme(
          data: ThemeData(brightness: Brightness.dark),
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

      // While mounted, of() resolves to dark via Theme.of fallback
      expect(savedContext.mounted, isTrue);
      expect(AetherTheme.of(savedContext).isDark, isTrue);

      // Unmount
      await tester.pumpWidget(const SizedBox());
      expect(savedContext.mounted, isFalse);

      // When unmounted, must NOT call Theme.of(context) which would throw ancestor lookup error
      late AetherThemeData unmountedResult;
      expect(() => unmountedResult = AetherTheme.of(savedContext), returnsNormally);
      expect(unmountedResult, equals(AetherThemeData.light()));
      expect(AetherTheme.maybeOf(savedContext), isNull);
    });

    testWidgets('Post-async callback on disposed context executes safely',
        (WidgetTester tester) async {
      final completer = Completer<void>();
      late BuildContext savedContext;
      AetherThemeData? asyncQueriedTheme;

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

      // Unmount before future completes
      await tester.pumpWidget(const SizedBox());
      expect(savedContext.mounted, isFalse);

      // Simulate async completion
      completer.complete();
      await completer.future;

      expect(() {
        asyncQueriedTheme = AetherTheme.of(savedContext);
      }, returnsNormally);

      expect(asyncQueriedTheme, equals(AetherThemeData.light()));
      expect(savedContext.aetherIsDark, isFalse);
      expect(savedContext.aetherIsLight, isTrue);
    });
  });

  group('Adversarial Challenge 2: Context Extensions on Unmounted Contexts', () {
    testWidgets('All context extensions return exact light theme defaults on unmounted context',
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

      await tester.pumpWidget(const SizedBox());
      expect(savedContext.mounted, isFalse);

      // 1. context.aetherTheme
      expect(() => savedContext.aetherTheme, returnsNormally);
      expect(savedContext.aetherTheme, equals(AetherThemeData.light()));

      // 2. context.aetherColors
      expect(() => savedContext.aetherColors, returnsNormally);
      final colors = savedContext.aetherColors;
      expect(colors, equals(AetherColors.light()));
      expect(colors.primary, equals(const Color(0xFF2563EB)));
      expect(colors.background, equals(const Color(0xFFF8FAFC)));
      expect(colors.surface, equals(const Color(0xFFFFFFFF)));
      expect(colors.textPrimary, equals(const Color(0xFF0F172A)));
      expect(colors.border, equals(const Color(0xFFCBD5E1)));

      // 3. context.aetherTypography
      expect(() => savedContext.aetherTypography, returnsNormally);
      final typography = savedContext.aetherTypography;
      expect(typography, equals(AetherTypography.standard()));
      expect(typography.displayLarge.fontSize, equals(32.0));
      expect(typography.bodyMedium.fontSize, equals(14.0));

      // 4. context.aetherShadows
      expect(() => savedContext.aetherShadows, returnsNormally);
      final shadows = savedContext.aetherShadows;
      expect(shadows, equals(AetherShadows.light()));
      expect(shadows.none, isEmpty);
      expect(shadows.sm, isNotEmpty);
      expect(shadows.md, isNotEmpty);
      expect(shadows.lg, isNotEmpty);

      // 5. context.aetherIsDark and context.aetherIsLight
      expect(() => savedContext.aetherIsDark, returnsNormally);
      expect(savedContext.aetherIsDark, isFalse);
      expect(() => savedContext.aetherIsLight, returnsNormally);
      expect(savedContext.aetherIsLight, isTrue);
    });

    testWidgets('Extensions in dispose() of a dying widget return safe values without throwing',
        (WidgetTester tester) async {
      bool checkedInDispose = false;

      await tester.pumpWidget(
        AetherTheme(
          data: AetherThemeData.dark(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: _LifecycleProbeWidget(
              onDispose: (context) {
                checkedInDispose = true;
                expect(context.aetherTheme, equals(AetherThemeData.light()));
                expect(context.aetherColors, equals(AetherColors.light()));
                expect(context.aetherTypography, equals(AetherTypography.standard()));
                expect(context.aetherShadows, equals(AetherShadows.light()));
                expect(context.aetherIsDark, isFalse);
                expect(context.aetherIsLight, isTrue);
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox());
      expect(checkedInDispose, isTrue);
    });
  });

  group('Adversarial Challenge 3: AetherShadows Equality & Hash Code Stress Testing', () {
    test('Reflexivity: instance equals itself', () {
      final s = AetherShadows.light();
      expect(s == s, isTrue);
      expect(s.hashCode == s.hashCode, isTrue);
    });

    test('Symmetry: a == b implies b == a', () {
      final s1 = AetherShadows.light();
      final s2 = AetherShadows.light();
      expect(s1 == s2, isTrue);
      expect(s2 == s1, isTrue);
      expect(s1.hashCode, equals(s2.hashCode));
    });

    test('Transitivity: a == b and b == c implies a == c', () {
      final s1 = AetherShadows.light();
      final s2 = AetherShadows.light();
      final s3 = AetherShadows.light();
      expect(s1 == s2, isTrue);
      expect(s2 == s3, isTrue);
      expect(s1 == s3, isTrue);
      expect(s1.hashCode == s3.hashCode, isTrue);
    });

    test('Varying none elevations: empty vs non-empty none lists produce inequality and distinct hashCodes', () {
      const shadowA = BoxShadow(color: Color(0x11000000), blurRadius: 1);
      const shadowB = BoxShadow(color: Color(0x22000000), blurRadius: 2);

      final base = AetherShadows.light();
      final withShadowA = base.copyWith(none: const [shadowA]);
      final withShadowB = base.copyWith(none: const [shadowB]);
      final withBoth = base.copyWith(none: const [shadowA, shadowB]);
      final withEmpty = base.copyWith(none: const []);

      // Base vs modified none
      expect(base == withShadowA, isFalse);
      expect(base == withShadowB, isFalse);
      expect(base == withBoth, isFalse);
      expect(base == withEmpty, isTrue);

      // Pairwise comparisons of varying none elevations
      expect(withShadowA == withShadowB, isFalse);
      expect(withShadowA == withBoth, isFalse);
      expect(withShadowB == withBoth, isFalse);

      // Hash code distinctions
      expect(base.hashCode != withShadowA.hashCode, isTrue);
      expect(base.hashCode != withShadowB.hashCode, isTrue);
      expect(base.hashCode != withBoth.hashCode, isTrue);
      expect(withShadowA.hashCode != withShadowB.hashCode, isTrue);
    });

    test('Identical const none lists evaluate as equal with identical hashCodes', () {
      const customList1 = [BoxShadow(color: Color(0x33000000), blurRadius: 3)];
      const customList2 = [BoxShadow(color: Color(0x33000000), blurRadius: 3)];

      final s1 = AetherShadows.light().copyWith(none: customList1);
      final s2 = AetherShadows.light().copyWith(none: customList2);

      expect(s1 == s2, isTrue);
      expect(s1.hashCode, equals(s2.hashCode));
    });

    test('Single-field variations for sm, md, lg also enforce inequality', () {
      const testShadow = [BoxShadow(color: Color(0xFF000000), blurRadius: 99)];
      final base = AetherShadows.light();

      final modSm = base.copyWith(sm: testShadow);
      final modMd = base.copyWith(md: testShadow);
      final modLg = base.copyWith(lg: testShadow);

      expect(base == modSm, isFalse);
      expect(base.hashCode != modSm.hashCode, isTrue);

      expect(base == modMd, isFalse);
      expect(base.hashCode != modMd.hashCode, isTrue);

      expect(base == modLg, isFalse);
      expect(base.hashCode != modLg.hashCode, isTrue);

      // sm, md, lg modifications are distinct from one another
      expect(modSm == modMd, isFalse);
      expect(modMd == modLg, isFalse);
      expect(modSm == modLg, isFalse);
    });

    test('Non-AetherShadows equality comparisons evaluate to false without throwing', () {
      final dynamic sDyn = AetherShadows.light();
      expect(sDyn == null, isFalse);
      expect(sDyn == Object(), isFalse);
      expect(sDyn == 'AetherShadows', isFalse);
      expect(sDyn == 42, isFalse);
      expect(sDyn == AetherColors.light(), isFalse);
    });
  });
}
