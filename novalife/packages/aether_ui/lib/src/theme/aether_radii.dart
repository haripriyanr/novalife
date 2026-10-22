import 'package:flutter/material.dart';

/// Corner radius constants for Aether UI.
class AetherRadii {
  const AetherRadii._();

  // Raw numeric radius values
  static const double valueNone = 0.0;
  static const double valueXs = 4.0;
  static const double valueSm = 8.0;
  static const double valueMd = 12.0;
  static const double valueLg = 16.0;
  static const double valueXl = 24.0;
  static const double valueFull = 999.0;

  // Compile-time constant BorderRadius instances
  static const BorderRadius none = BorderRadius.zero;
  static const BorderRadius xs = BorderRadius.all(Radius.circular(valueXs));
  static const BorderRadius sm = BorderRadius.all(Radius.circular(valueSm));
  static const BorderRadius md = BorderRadius.all(Radius.circular(valueMd));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(valueLg));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(valueXl));
  static const BorderRadius full = BorderRadius.all(Radius.circular(valueFull));

  // Radius objects for custom border geometries
  static const Radius radiusXs = Radius.circular(valueXs);
  static const Radius radiusSm = Radius.circular(valueSm);
  static const Radius radiusMd = Radius.circular(valueMd);
  static const Radius radiusLg = Radius.circular(valueLg);
  static const Radius radiusXl = Radius.circular(valueXl);
  static const Radius radiusFull = Radius.circular(valueFull);

  // Functional helpers
  static BorderRadius circular(double radius) => BorderRadius.circular(radius);
  static BorderRadius top(double radius) =>
      BorderRadius.vertical(top: Radius.circular(radius));
  static BorderRadius bottom(double radius) =>
      BorderRadius.vertical(bottom: Radius.circular(radius));
}
