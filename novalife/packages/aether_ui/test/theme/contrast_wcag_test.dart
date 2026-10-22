import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_ui/aether_ui.dart';

void main() {
  group('ContrastChecker Mathematical Verification', () {
    test('relativeLuminance computes standard BT.709 values', () {
      expect(ContrastChecker.relativeLuminance(const Color(0xFF000000)), 0.0);
      expect(ContrastChecker.relativeLuminance(const Color(0xFFFFFFFF)), 1.0);
    });

    test('contrastRatio calculates exact ratios and commutativity', () {
      final ratioWhiteBlack = ContrastChecker.contrastRatio(
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
      );
      expect(ratioWhiteBlack, closeTo(21.0, 0.01));

      final ratioIdentical = ContrastChecker.contrastRatio(
        const Color(0xFF2563EB),
        const Color(0xFF2563EB),
      );
      expect(ratioIdentical, closeTo(1.0, 0.01));

      // Commutative property: CR(A, B) == CR(B, A)
      final cr1 = ContrastChecker.contrastRatio(
        const Color(0xFF2563EB),
        const Color(0xFFFFFFFF),
      );
      final cr2 = ContrastChecker.contrastRatio(
        const Color(0xFFFFFFFF),
        const Color(0xFF2563EB),
      );
      expect(cr1, equals(cr2));
    });

    test('isWcagAaNormalText and isWcagAaLargeTextOrUi thresholds', () {
      expect(ContrastChecker.isWcagAaNormalText(Colors.black, Colors.white), isTrue);
      expect(ContrastChecker.isWcagAaLargeTextOrUi(Colors.black, Colors.white), isTrue);
      expect(ContrastChecker.isWcagAaNormalText(Colors.white, Colors.white), isFalse);
    });
  });

  group('Light Theme WCAG AA Compliance', () {
    final colors = AetherColors.light();

    test('textPrimary on background satisfies WCAG AA (>= 4.5:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textPrimary, colors.background);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Light textPrimary on background must be >= 4.5');
    });

    test('textPrimary on surface satisfies WCAG AA (>= 4.5:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textPrimary, colors.surface);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Light textPrimary on surface must be >= 4.5');
    });

    test('textSecondary on background satisfies WCAG AA (>= 4.5:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textSecondary, colors.background);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Light textSecondary on background must be >= 4.5');
    });

    test('textSecondary on surface satisfies WCAG AA (>= 4.5:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textSecondary, colors.surface);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Light textSecondary on surface must be >= 4.5');
    });

    test('textMuted on background satisfies large/placeholder threshold (>= 3.0:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textMuted, colors.background);
      expect(ratio, greaterThanOrEqualTo(3.0), reason: 'Light textMuted on background must be >= 3.0');
    });

    test('onPrimary on primary satisfies contrast threshold (>= 4.5:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.onPrimary, colors.primary);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Light onPrimary on primary must be >= 4.5');
    });
  });

  group('Dark Theme WCAG AA Compliance', () {
    final colors = AetherColors.dark();

    test('textPrimary on background satisfies WCAG AA (>= 4.5:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textPrimary, colors.background);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Dark textPrimary on background must be >= 4.5');
    });

    test('textPrimary on surface satisfies WCAG AA (>= 4.5:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textPrimary, colors.surface);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Dark textPrimary on surface must be >= 4.5');
    });

    test('textSecondary on background satisfies WCAG AA (>= 4.5:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textSecondary, colors.background);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Dark textSecondary on background must be >= 4.5');
    });

    test('textSecondary on surface satisfies UI component threshold (>= 3.0:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.textSecondary, colors.surface);
      expect(ratio, greaterThanOrEqualTo(3.0), reason: 'Dark textSecondary on surface must be >= 3.0');
    });

    test('onPrimary on primary satisfies UI component threshold (>= 3.0:1)', () {
      final ratio = ContrastChecker.contrastRatio(colors.onPrimary, colors.primary);
      expect(ratio, greaterThanOrEqualTo(3.0), reason: 'Dark onPrimary on primary must be >= 3.0');
    });
  });

  group('Semantic State Quads WCAG AA Verification', () {
    test('Light theme semantic quad contrast ratios exceed thresholds', () {
      final light = AetherColors.light();
      final states = [
        light.success,
        light.danger,
        light.warning,
        light.info,
        light.neutral,
      ];

      for (final state in states) {
        final onContainerRatio = ContrastChecker.contrastRatio(state.onContainer, state.container);
        expect(onContainerRatio, greaterThanOrEqualTo(4.5),
            reason: 'onContainer text on tinted container must meet WCAG AA normal text (>= 4.5:1)');

        final onBaseRatio = ContrastChecker.contrastRatio(state.onBase, state.base);
        expect(onBaseRatio, greaterThanOrEqualTo(3.0),
            reason: 'onBase on solid base must meet UI/large text threshold (>= 3.0:1)');
      }
    });

    test('Dark theme semantic quad contrast ratios exceed thresholds', () {
      final dark = AetherColors.dark();
      final states = [
        dark.success,
        dark.danger,
        dark.warning,
        dark.info,
        dark.neutral,
      ];

      for (final state in states) {
        final onContainerRatio = ContrastChecker.contrastRatio(state.onContainer, state.container);
        expect(onContainerRatio, greaterThanOrEqualTo(4.5),
            reason: 'onContainer text on dark tinted container must meet WCAG AA (>= 4.5:1)');

        final onBaseRatio = ContrastChecker.contrastRatio(state.onBase, state.base);
        expect(onBaseRatio, greaterThanOrEqualTo(3.0),
            reason: 'onBase on dark solid base must meet UI/large text threshold (>= 3.0:1)');
      }
    });
  });
}
