/// Standard viewport breakpoint classifications for adaptive layout and styling.
///
/// Categorized into three tiers:
/// - [mobile]: Handheld devices ($320\text{px} \le w \le 600\text{px}$).
/// - [tablet]: Medium screens and tablets ($601\text{px} \le w \le 1024\text{px}$).
/// - [desktop]: Large viewports, laptops, and desktop monitors ($w \ge 1025\text{px}$).
enum AetherBreakpoint {
  mobile,
  tablet,
  desktop;

  /// Returns true if this breakpoint represents a mobile device ($w \le 600\text{px}$).
  bool get isMobile => this == AetherBreakpoint.mobile;

  /// Returns true if this breakpoint represents a tablet device ($600\text{px} < w \le 1024\text{px}$).
  bool get isTablet => this == AetherBreakpoint.tablet;

  /// Returns true if this breakpoint represents a desktop device ($w > 1024\text{px}$).
  bool get isDesktop => this == AetherBreakpoint.desktop;

  /// Returns true if this breakpoint is tablet or desktop ($w > 600\text{px}$).
  bool get isTabletOrDesktop => isTablet || isDesktop;

  /// Returns true if this breakpoint is mobile or tablet ($w \le 1024\text{px}$).
  bool get isMobileOrTablet => isMobile || isTablet;
}

/// Upper bound cutoff for mobile devices in logical pixels (inclusive).
const double kMobileMaxWidth = 600.0;

/// Upper bound cutoff for tablet devices in logical pixels (inclusive).
const double kTabletMaxWidth = 1024.0;

/// Standard maximum width cutoff for desktop viewports in logical pixels.
const double kDesktopMaxWidth = 1920.0;

/// Recommended maximum content constraint for dashboards, forms, and cards
/// to prevent excessive stretching on ultra-wide / 4K displays.
const double kMaxContentWidth = 1440.0;
