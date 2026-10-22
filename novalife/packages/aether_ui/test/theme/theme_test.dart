import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_ui/aether_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AetherColors', () {
    test('light palette initializes all semantic tokens with valid brightness', () {
      final colors = AetherColors.light();
      expect(colors.brightness, Brightness.light);
      expect(colors.isLight, isTrue);
      expect(colors.isDark, isFalse);
      expect(colors.background, const Color(0xFFF8FAFC));
      expect(colors.surface, const Color(0xFFFFFFFF));
      expect(colors.surfaceElevated, const Color(0xFFFFFFFF));
      expect(colors.surfaceSubtle, const Color(0xFFF1F5F9));
      expect(colors.primary, const Color(0xFF2563EB));
      expect(colors.primaryHover, const Color(0xFF1D4ED8));
      expect(colors.primaryContainer, const Color(0xFFEFF6FF));
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
      expect(colors.textPrimary, const Color(0xFF0F172A));
      expect(colors.textSecondary, const Color(0xFF475569));
      expect(colors.textMuted, const Color(0xFF64748B));
      expect(colors.textDisabled, const Color(0xFF94A3B8));
      expect(colors.border, const Color(0xFFCBD5E1));
      expect(colors.borderSubtle, const Color(0xFFF1F5F9));
      expect(colors.borderFocused, const Color(0xFF2563EB));
    });

    test('dark palette initializes all semantic tokens with valid brightness', () {
      final colors = AetherColors.dark();
      expect(colors.brightness, Brightness.dark);
      expect(colors.isDark, isTrue);
      expect(colors.isLight, isFalse);
      expect(colors.background, const Color(0xFF0F172A));
      expect(colors.surface, const Color(0xFF1E293B));
      expect(colors.surfaceElevated, const Color(0xFF334155));
      expect(colors.surfaceSubtle, const Color(0xFF182234));
      expect(colors.primary, const Color(0xFF3B82F6));
      expect(colors.primaryHover, const Color(0xFF60A5FA));
      expect(colors.primaryContainer, const Color(0xFF1E3A8A));
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
      expect(colors.textPrimary, const Color(0xFFF8FAFC));
      expect(colors.textSecondary, const Color(0xFF94A3B8));
      expect(colors.textMuted, const Color(0xFF64748B));
      expect(colors.textDisabled, const Color(0xFF475569));
      expect(colors.border, const Color(0xFF334155));
      expect(colors.borderSubtle, const Color(0xFF1E293B));
      expect(colors.borderFocused, const Color(0xFF60A5FA));
    });

    test('semantic quads are non-null and distinct for light and dark palettes', () {
      final light = AetherColors.light();
      final dark = AetherColors.dark();

      for (final colors in [light, dark]) {
        expect(colors.success.base, isNotNull);
        expect(colors.success.container, isNotNull);
        expect(colors.success.onBase, isNotNull);
        expect(colors.success.onContainer, isNotNull);

        expect(colors.danger.base, isNotNull);
        expect(colors.danger.container, isNotNull);
        expect(colors.danger.onBase, isNotNull);
        expect(colors.danger.onContainer, isNotNull);

        expect(colors.warning.base, isNotNull);
        expect(colors.warning.container, isNotNull);
        expect(colors.warning.onBase, isNotNull);
        expect(colors.warning.onContainer, isNotNull);

        expect(colors.info.base, isNotNull);
        expect(colors.info.container, isNotNull);
        expect(colors.info.onBase, isNotNull);
        expect(colors.info.onContainer, isNotNull);

        expect(colors.neutral.base, isNotNull);
        expect(colors.neutral.container, isNotNull);
        expect(colors.neutral.onBase, isNotNull);
        expect(colors.neutral.onContainer, isNotNull);
      }
    });
  });

  group('AetherTypography', () {
    test('all 12 text styles are non-null and have positive font sizes', () {
      final typo = AetherTypography.standard();
      expect(typo.displayLarge.fontSize, 32.0);
      expect(typo.displayMedium.fontSize, 26.0);
      expect(typo.titleLarge.fontSize, 20.0);
      expect(typo.titleMedium.fontSize, 17.0);
      expect(typo.titleSmall.fontSize, 15.0);
      expect(typo.bodyLarge.fontSize, 16.0);
      expect(typo.bodyMedium.fontSize, 14.0);
      expect(typo.bodySmall.fontSize, 12.0);
      expect(typo.labelLarge.fontSize, 14.0);
      expect(typo.labelMedium.fontSize, 12.0);
      expect(typo.labelSmall.fontSize, 10.0);
      expect(typo.code.fontSize, 13.0);
    });

    test('applyColor creates updated typography with given text color', () {
      final typo = AetherTypography.standard();
      const testColor = Color(0xFFEF4444);
      final colored = typo.applyColor(testColor);
      expect(colored.bodyMedium.color, testColor);
      expect(colored.titleLarge.color, testColor);
    });
  });

  group('AetherSpacing, AetherRadii, AetherShadows', () {
    test('AetherSpacing follows mathematical progression', () {
      expect(AetherSpacing.xxs, 2.0);
      expect(AetherSpacing.xs, 4.0);
      expect(AetherSpacing.sm, 8.0);
      expect(AetherSpacing.md, 12.0);
      expect(AetherSpacing.lg, 16.0);
      expect(AetherSpacing.xl, 24.0);
      expect(AetherSpacing.xxl, 32.0);
      expect(AetherSpacing.xxxl, 48.0);
    });

    test('AetherRadii contains valid radii', () {
      expect(AetherRadii.none, BorderRadius.zero);
      expect(AetherRadii.xs, BorderRadius.circular(4.0));
      expect(AetherRadii.sm, BorderRadius.circular(8.0));
      expect(AetherRadii.md, BorderRadius.circular(12.0));
      expect(AetherRadii.lg, BorderRadius.circular(16.0));
      expect(AetherRadii.xl, BorderRadius.circular(24.0));
      expect(AetherRadii.full, BorderRadius.circular(999.0));
    });

    test('AetherShadows provides defined box shadows', () {
      expect(AetherShadows.light().none, isEmpty);
      expect(AetherShadows.light().sm, isNotEmpty);
      expect(AetherShadows.light().md, isNotEmpty);
      expect(AetherShadows.light().lg, isNotEmpty);
      expect(AetherShadows.dark().none, isEmpty);
      expect(AetherShadows.dark().sm, isNotEmpty);
      expect(AetherShadows.dark().md, isNotEmpty);
      expect(AetherShadows.dark().lg, isNotEmpty);
    });

    test('AetherShadows equality and hashCode account for none', () {
      const customShadow = BoxShadow(color: Color(0xFF000000), blurRadius: 1);
      final s1 = AetherShadows.light();
      final s2 = AetherShadows.light();
      final s3 = s1.copyWith(none: [customShadow]);

      expect(s1 == s2, isTrue);
      expect(s1.hashCode == s2.hashCode, isTrue);
      expect(s1 == s3, isFalse);
      expect(s1.hashCode == s3.hashCode, isFalse);
    });
  });

  group('AetherTheme InheritedWidget & Context Fallback', () {
    testWidgets('provides AetherThemeData to child subtree', (tester) async {
      late AetherThemeData capturedData;
      await tester.pumpWidget(
        AetherTheme(
          data: AetherThemeData.dark(),
          child: Builder(
            builder: (context) {
              capturedData = AetherTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(capturedData.isDark, isTrue);
      expect(capturedData.colors.brightness, Brightness.dark);
    });

    testWidgets('unscoped mounted context fallback safely returns default theme based on Theme.of', (tester) async {
      late AetherThemeData capturedLight;
      late AetherThemeData capturedDark;

      await tester.pumpWidget(
        Theme(
          data: ThemeData(brightness: Brightness.light),
          child: Builder(
            builder: (context) {
              capturedLight = AetherTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(capturedLight.isDark, isFalse);

      await tester.pumpWidget(
        Theme(
          data: ThemeData(brightness: Brightness.dark),
          child: Builder(
            builder: (context) {
              capturedDark = AetherTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(capturedDark.isDark, isTrue);
    });

    testWidgets('unmounted context fallback safely returns default light theme without throwing', (tester) async {
      late BuildContext savedContext;
      await tester.pumpWidget(
        AetherTheme(
          data: AetherThemeData.dark(),
          child: Builder(
            builder: (context) {
              savedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(savedContext.mounted, isTrue);
      expect(AetherTheme.of(savedContext).isDark, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(savedContext.mounted, isFalse);

      expect(() => AetherTheme.of(savedContext), returnsNormally);
      expect(AetherTheme.of(savedContext), equals(AetherThemeData.light()));
      expect(() => AetherTheme.maybeOf(savedContext), returnsNormally);
      expect(AetherTheme.maybeOf(savedContext), isNull);
    });

    testWidgets('toThemeData produces valid Material 3 ThemeData', (tester) async {
      final aetherData = AetherThemeData.light();
      final materialTheme = aetherData.toThemeData();
      expect(materialTheme.useMaterial3, isTrue);
      expect(materialTheme.brightness, Brightness.light);
      expect(materialTheme.colorScheme.primary, aetherData.colors.primary);
      expect(materialTheme.scaffoldBackgroundColor, aetherData.colors.background);
    });
  });
}
