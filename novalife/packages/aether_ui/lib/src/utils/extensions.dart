import 'package:flutter/material.dart';

import '../responsive/aether_breakpoint.dart';
import '../responsive/aether_responsive.dart';
import '../theme/aether_colors.dart';
import '../theme/aether_shadows.dart';
import '../theme/aether_theme.dart';
import '../theme/aether_typography.dart';

/// Ergonomic theme accessors on [BuildContext].
extension AetherThemeContextExtension on BuildContext {
  /// The ambient [AetherThemeData] for this context.
  AetherThemeData get aetherTheme => AetherTheme.of(this);

  /// Convenient access to semantic color tokens.
  AetherColors get aetherColors => aetherTheme.colors;

  /// Convenient access to typography tokens.
  AetherTypography get aetherTypography => aetherTheme.typography;

  /// Convenient access to elevation shadow tokens.
  AetherShadows get aetherShadows => aetherTheme.shadows;

  /// True if current ambient theme is dark mode.
  bool get aetherIsDark => aetherTheme.isDark;

  /// True if current ambient theme is light mode.
  bool get aetherIsLight => aetherTheme.isLight;
}

/// Ergonomic responsive accessors on [BuildContext].
extension AetherResponsiveContextExtension on BuildContext {
  /// The ambient [AetherBreakpoint] for this context.
  AetherBreakpoint get aetherBreakpoint => AetherResponsive.of(this);

  /// True if current viewport is mobile ($w \le 600$px).
  bool get aetherIsMobile => AetherResponsive.isMobile(this);

  /// True if current viewport is tablet ($600$px $< w \le 1024$px).
  bool get aetherIsTablet => AetherResponsive.isTablet(this);

  /// True if current viewport is desktop ($w > 1024$px).
  bool get aetherIsDesktop => AetherResponsive.isDesktop(this);

  /// True if current viewport is tablet or desktop ($w > 600$px).
  bool get aetherIsTabletOrDesktop => AetherResponsive.isTabletOrDesktop(this);
}
