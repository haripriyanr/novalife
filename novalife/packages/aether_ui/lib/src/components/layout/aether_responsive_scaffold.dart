import 'package:flutter/material.dart';

import '../../responsive/aether_breakpoint.dart';
import '../../utils/extensions.dart';
import 'aether_adaptive_navigation.dart';

/// Universal responsive scaffold that automatically adapts navigation chrome,
/// body constraints, and docking side panels across all screen sizes.
class AetherResponsiveScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? header;
  final List<AetherNavigationItem>? navigationItems;
  final int currentIndex;
  final ValueChanged<int>? onNavigationChanged;
  final Widget? floatingActionButton;
  final Widget? sidePanel;
  final bool showNavigation;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
  final Widget? navigationHeader;
  final Widget? navigationFooter;

  const AetherResponsiveScaffold({
    super.key,
    required this.body,
    this.header,
    this.navigationItems,
    this.currentIndex = 0,
    this.onNavigationChanged,
    this.floatingActionButton,
    this.sidePanel,
    this.showNavigation = true,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.navigationHeader,
    this.navigationFooter,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.aetherBreakpoint;
    final colors = context.aetherColors;

    final navWidget = (showNavigation && navigationItems != null && onNavigationChanged != null)
        ? AetherAdaptiveNavigation(
            items: navigationItems!,
            currentIndex: currentIndex,
            onIndexChanged: onNavigationChanged!,
            header: navigationHeader,
            footer: navigationFooter,
          )
        : null;

    if (bp.isMobile) {
      return Scaffold(
        backgroundColor: backgroundColor ?? colors.background,
        appBar: header,
        body: SafeArea(child: body),
        bottomNavigationBar: navWidget,
        floatingActionButton: floatingActionButton,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? colors.background,
      appBar: header,
      floatingActionButton: floatingActionButton,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: Row(
        children: [
          ?navWidget,
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
                child: body,
              ),
            ),
          ),
          if (sidePanel != null && bp.isDesktop)
            SizedBox(
              width: 320.0,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: colors.border)),
                ),
                child: sidePanel!,
              ),
            ),
        ],
      ),
    );
  }
}
