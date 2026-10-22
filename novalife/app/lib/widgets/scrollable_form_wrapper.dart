import 'package:flutter/material.dart';

/// A reusable widget to handle keyboard-aware scrolling for forms and inputs.
/// Prevents over-scrolling and fixes overflow issues.
class ScrollableFormWrapper extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool hasAppBar;

  const ScrollableFormWrapper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16), // Reduced default padding
    this.hasAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea( // KEY: Prevent system UI overlap
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate available height more accurately
          final availableHeight = constraints.maxHeight -
              (hasAppBar ? 0 : 0) - // AppBar handled by SafeArea
              32; // Account for padding

          return SingleChildScrollView(
            padding: padding,
            physics: const ClampingScrollPhysics(), // Prevent over-scroll
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: availableHeight > 0 ? availableHeight : 0,
              ),
              child: child, // Removed IntrinsicHeight to prevent overflow
            ),
          );
        },
      ),
    );
  }
}
