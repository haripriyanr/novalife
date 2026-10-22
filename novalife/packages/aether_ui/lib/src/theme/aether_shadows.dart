import 'package:flutter/material.dart';

/// Elevation box shadow tokens for Aether UI.
@immutable
class AetherShadows {
  final List<BoxShadow> none;
  final List<BoxShadow> sm;
  final List<BoxShadow> md;
  final List<BoxShadow> lg;

  const AetherShadows({
    this.none = const [],
    required this.sm,
    required this.md,
    required this.lg,
  });

  /// Subtle elevation shadows tuned for light backgrounds.
  factory AetherShadows.light() {
    return const AetherShadows(
      none: [],
      sm: [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 4.0,
          offset: Offset(0, 1),
        ),
      ],
      md: [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 10.0,
          offset: Offset(0, 4),
        ),
      ],
      lg: [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 20.0,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  /// Deep elevation shadows tuned for dark mode.
  factory AetherShadows.dark() {
    return const AetherShadows(
      none: [],
      sm: [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 4.0,
          offset: Offset(0, 1),
        ),
      ],
      md: [
        BoxShadow(
          color: Color(0x4D000000),
          blurRadius: 10.0,
          offset: Offset(0, 4),
        ),
      ],
      lg: [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 20.0,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  AetherShadows copyWith({
    List<BoxShadow>? none,
    List<BoxShadow>? sm,
    List<BoxShadow>? md,
    List<BoxShadow>? lg,
  }) {
    return AetherShadows(
      none: none ?? this.none,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AetherShadows &&
          runtimeType == other.runtimeType &&
          none == other.none &&
          sm == other.sm &&
          md == other.md &&
          lg == other.lg;

  @override
  int get hashCode => Object.hash(none, sm, md, lg);
}
