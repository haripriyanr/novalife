import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Evaluates mathematical relative luminance and WCAG 2.1 contrast ratios
/// using ITU-R BT.709 gamma linearization.
class ContrastChecker {
  const ContrastChecker._();

  /// Calculates the relative luminance $L$ of an sRGB color per ITU-R BT.709.
  ///
  /// Output ranges from `0.0` (pure black) to `1.0` (pure white).
  static double relativeLuminance(Color color) {
    double linearize(double channel) {
      final clamped = channel.clamp(0.0, 1.0);
      return (clamped <= 0.04045)
          ? clamped / 12.92
          : math.pow((clamped + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = linearize(color.r);
    final g = linearize(color.g);
    final b = linearize(color.b);

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Calculates the contrast ratio between two colors: $(L_1 + 0.05) / (L_2 + 0.05)$.
  ///
  /// Output ranges from `1.0` (identical colors) to `21.0` (black vs white).
  static double contrastRatio(Color foreground, Color background) {
    final l1 = relativeLuminance(foreground);
    final l2 = relativeLuminance(background);

    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);

    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Evaluates whether the contrast satisfies WCAG AA for normal text ($\ge 4.5:1$).
  static bool isWcagAaNormalText(Color foreground, Color background) =>
      contrastRatio(foreground, background) >= 4.5;

  /// Evaluates whether the contrast satisfies WCAG AA for large text or graphical UI elements ($\ge 3.0:1$).
  ///
  /// Large text is defined as at least 18pt (24px) or 14pt (18.66px) bold.
  static bool isWcagAaLargeTextOrUi(Color foreground, Color background) =>
      contrastRatio(foreground, background) >= 3.0;

  /// Evaluates whether the contrast satisfies WCAG AAA for normal text ($\ge 7.0:1$).
  static bool isWcagAaaNormalText(Color foreground, Color background) =>
      contrastRatio(foreground, background) >= 7.0;

  /// Evaluates whether the contrast satisfies WCAG AAA for large text ($\ge 4.5:1$).
  static bool isWcagAaaLargeText(Color foreground, Color background) =>
      contrastRatio(foreground, background) >= 4.5;

  /// Composites a semi-transparent foreground color over an opaque background color.
  static Color compositeOver(Color foreground, Color background) {
    final a = foreground.a;
    if (a >= 1.0) return foreground;

    final r = (foreground.r * a) + (background.r * (1.0 - a));
    final g = (foreground.g * a) + (background.g * (1.0 - a));
    final b = (foreground.b * a) + (background.b * (1.0 - a));

    return Color.fromARGB(
      255,
      (r * 255.0).round().clamp(0, 255),
      (g * 255.0).round().clamp(0, 255),
      (b * 255.0).round().clamp(0, 255),
    );
  }
}
