import 'package:flutter/widgets.dart';

import 'aether_breakpoint.dart';
import 'aether_responsive.dart';

/// Signature for builder functions that provide both [AetherBreakpoint] and [BoxConstraints].
typedef AetherResponsiveWidgetBuilder = Widget Function(
  BuildContext context,
  AetherBreakpoint breakpoint,
  BoxConstraints constraints,
);

/// A widget that evaluates its local layout [BoxConstraints] and builds content
/// adapted to the resolved [AetherBreakpoint].
///
/// Unlike [AetherResponsive.of], which queries the global window dimensions via [MediaQuery],
/// [AetherResponsiveBuilder] operates locally on the constraints passed by its parent widget.
/// This enables split-views, cards, dialogs, and embedded containers to adapt to their local available width.
///
/// If [BoxConstraints.maxWidth] is unconstrained (e.g. inside an unbound horizontal scroll view),
/// it gracefully falls back to querying [MediaQuery.sizeOf].
class AetherResponsiveBuilder extends StatelessWidget {
  /// Builder callback called with context, resolved breakpoint, and parent constraints.
  final AetherResponsiveWidgetBuilder builder;

  const AetherResponsiveBuilder({
    super.key,
    required this.builder,
  });

  /// Factory constructor allowing declarative per-breakpoint widget builders.
  factory AetherResponsiveBuilder.select({
    Key? key,
    required Widget Function(BuildContext context, BoxConstraints constraints) mobile,
    Widget Function(BuildContext context, BoxConstraints constraints)? tablet,
    Widget Function(BuildContext context, BoxConstraints constraints)? desktop,
  }) {
    return AetherResponsiveBuilder(
      key: key,
      builder: (context, breakpoint, constraints) {
        switch (breakpoint) {
          case AetherBreakpoint.mobile:
            return mobile(context, constraints);
          case AetherBreakpoint.tablet:
            return (tablet ?? mobile)(context, constraints);
          case AetherBreakpoint.desktop:
            return (desktop ?? tablet ?? mobile)(context, constraints);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width;
        if (constraints.maxWidth.isFinite) {
          width = constraints.maxWidth;
        } else {
          width = MediaQuery.sizeOf(context).width;
        }
        final breakpoint = AetherResponsive.breakpointForWidth(width);
        return builder(context, breakpoint, constraints);
      },
    );
  }
}
