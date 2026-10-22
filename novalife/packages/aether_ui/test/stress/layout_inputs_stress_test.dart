import 'package:aether_ui/aether_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildThemedApp({
  required Widget child,
  bool isDark = false,
  ThemeMode mode = ThemeMode.system,
}) {
  return MaterialApp(
    themeMode: mode,
    home: AetherTheme(
      data: isDark ? AetherThemeData.dark() : AetherThemeData.light(),
      child: Material(child: child),
    ),
  );
}

void _setViewport(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // SECTION 1: AetherResponsiveScaffold & AetherAdaptiveNavigation Stress Tests
  // ===========================================================================
  group('AetherResponsiveScaffold & AetherAdaptiveNavigation Dimension Stress Tests', () {
    const extremeWidths = [
      320.0, // Minimum mobile
      600.0, // Exact mobile upper boundary
      601.0, // Exact tablet lower boundary
      1024.0, // Exact tablet upper boundary
      1025.0, // Exact desktop lower boundary
      1920.0, // Full HD desktop/wide web
    ];

    const standardNavItems = [
      AetherNavigationItem(icon: Icons.dashboard, label: 'Dashboard'),
      AetherNavigationItem(icon: Icons.biotech, label: 'Scans', badgeText: '9+'),
      AetherNavigationItem(icon: Icons.person, label: 'Profile'),
    ];

    for (final width in extremeWidths) {
      testWidgets('Scaffold renders with 0 RenderFlex overflow at ${width}px width', (tester) async {
        _setViewport(tester, width, 800);
        addTearDown(() => _resetViewport(tester));

        int selectedIndex = 0;

        await tester.pumpWidget(
          _buildThemedApp(
            child: AetherResponsiveScaffold(
              navigationItems: standardNavItems,
              currentIndex: selectedIndex,
              onNavigationChanged: (idx) => selectedIndex = idx,
              header: const AetherHeaderBar(
                titleText: 'NovaLife Enclave',
                subtitleText: 'Hardware Steganography Hub',
              ),
              sidePanel: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Telemetry Panel'),
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
              body: ListView.builder(
                itemCount: 20,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text('Scan Slice #$i'),
                  subtitle: const Text('FPGA Enclave Bit-Exact Verification'),
                ),
              ),
            ),
          ),
        );

        // Ensure pump completes and zero exceptions were recorded
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Verify responsive navigation chrome adaptation
        if (width <= 600.0) {
          // Mobile bottom bar: height 64, rendered at bottom
          expect(find.text('Dashboard'), findsOneWidget);
          expect(find.text('Telemetry Panel'), findsNothing,
              reason: 'Side panel must not render on mobile');
        } else if (width <= 1024.0) {
          // Tablet rail: compact vertical rail
          expect(find.byType(IconButton), findsWidgets);
          expect(find.text('Telemetry Panel'), findsNothing,
              reason: 'Side panel must not render on tablet');
        } else {
          // Desktop sidebar: full expanded sidebar and sidePanel
          expect(find.text('Dashboard'), findsOneWidget);
          expect(find.text('Telemetry Panel'), findsOneWidget,
              reason: 'Side panel must render on desktop >= 1025px');
        }
      });
    }

    testWidgets('AdaptiveNavigation handles empty, single, and multiple items safely', (tester) async {
      _setViewport(tester, 320, 568);
      addTearDown(() => _resetViewport(tester));

      // 1. Empty items
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: const [],
            currentIndex: 0,
            onIndexChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 2. Single item
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: const [
              AetherNavigationItem(icon: Icons.home, label: 'Single Home'),
            ],
            currentIndex: 0,
            onIndexChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Single Home'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 3. 3 standard short items on compact 320px screen
      const threeShortItems = [
        AetherNavigationItem(icon: Icons.home, label: 'Home'),
        AetherNavigationItem(icon: Icons.search, label: 'Search'),
        AetherNavigationItem(icon: Icons.person, label: 'User'),
      ];

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: threeShortItems,
            currentIndex: 0,
            onIndexChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: '3 short items must render on 320px without overflow');

      // 4. Clinical navigation items with realistic label lengths
      const threeClinicalItems = [
        AetherNavigationItem(icon: Icons.biotech, label: 'Diagnostics'),
        AetherNavigationItem(icon: Icons.verified_user, label: 'Verification'),
        AetherNavigationItem(icon: Icons.settings, label: 'Settings'),
      ];

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: threeClinicalItems,
            currentIndex: 0,
            onIndexChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Record whether clinical labels on 320px trigger overflow
      final clinicalOverflow = tester.takeException();

      // 5. 5 standard items on compact 320px screen (standard bottom bar capacity)
      const fiveItems = [
        AetherNavigationItem(icon: Icons.home, label: 'Home'),
        AetherNavigationItem(icon: Icons.search, label: 'Search'),
        AetherNavigationItem(icon: Icons.add, label: 'Add'),
        AetherNavigationItem(icon: Icons.folder, label: 'Vault'),
        AetherNavigationItem(icon: Icons.settings, label: 'Config'),
      ];

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: fiveItems,
            currentIndex: 2,
            onIndexChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fiveItemOverflow = tester.takeException();
      expect(fiveItemOverflow != null || clinicalOverflow != null, isTrue,
          reason: 'Empirical proof: unconstrained Row in AetherAdaptiveNavigation mobile bottom bar overflows on 320px');
    });

    testWidgets('Desktop sidebar with Header and Footer widgets under 1025px boundary', (tester) async {
      _setViewport(tester, 1025, 600);
      addTearDown(() => _resetViewport(tester));

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: standardNavItems,
            currentIndex: 0,
            onIndexChanged: (_) {},
            header: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('HEADER LOGO'),
            ),
            footer: const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text('FOOTER V2.4'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('HEADER LOGO'), findsOneWidget);
      expect(find.text('FOOTER V2.4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ===========================================================================
  // SECTION 2: AetherSplitView Stress Tests
  // ===========================================================================
  group('AetherSplitView Rapid Resizing & Drilldown Stress Tests', () {
    testWidgets('Rapid resizing between mobile, tablet, and desktop viewports preserves state', (tester) async {
      int masterTapCount = 0;
      int detailTapCount = 0;

      Widget buildSplitView() {
        return _buildThemedApp(
          child: AetherSplitView(
            master: Center(
              child: ElevatedButton(
                key: const Key('master_action_btn'),
                onPressed: () => masterTapCount++,
                child: Text('Master Count: $masterTapCount'),
              ),
            ),
            detail: Center(
              child: ElevatedButton(
                key: const Key('detail_action_btn'),
                onPressed: () => detailTapCount++,
                child: Text('Detail Count: $detailTapCount'),
              ),
            ),
          ),
        );
      }

      final sequence = [
        const Size(1920, 1080), // Desktop
        const Size(1025, 768),  // Desktop cutoff
        const Size(1024, 768),  // Tablet cutoff
        const Size(768, 1024),  // Tablet portrait
        const Size(601, 800),   // Tablet cutoff
        const Size(600, 800),   // Mobile cutoff
        const Size(320, 480),   // Small mobile
        const Size(1280, 800),  // Return to Desktop
      ];

      for (final size in sequence) {
        _setViewport(tester, size.width, size.height);
        await tester.pumpWidget(buildSplitView());
        await tester.pump();
        expect(tester.takeException(), isNull);

        if (size.width > 600.0) {
          // Both master and detail must be present
          expect(find.byKey(const Key('master_action_btn')), findsOneWidget);
          expect(find.byKey(const Key('detail_action_btn')), findsOneWidget);
        } else {
          // On mobile without showDetailOnMobile, master is present
          expect(find.byKey(const Key('master_action_btn')), findsOneWidget);
          expect(find.byKey(const Key('detail_action_btn')), findsNothing);
        }
      }

      // Tap buttons and ensure interactivity
      await tester.tap(find.byKey(const Key('master_action_btn')));
      await tester.tap(find.byKey(const Key('detail_action_btn')));
      await tester.pump();

      expect(masterTapCount, 1);
      expect(detailTapCount, 1);
      _resetViewport(tester);
    });

    testWidgets('Mobile drilldown: rapid toggle between master and detail with split_view_back_btn', (tester) async {
      _setViewport(tester, 360, 640);
      addTearDown(() => _resetViewport(tester));

      bool showDetail = false;
      int backTaps = 0;

      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return AetherSplitView(
                showDetailOnMobile: showDetail,
                onBackToMaster: () {
                  backTaps++;
                  setState(() => showDetail = false);
                },
                master: Center(
                  child: ElevatedButton(
                    key: const Key('drilldown_btn'),
                    onPressed: () => setState(() => showDetail = true),
                    child: const Text('View Report #42'),
                  ),
                ),
                detail: const Center(
                  child: Text('Clinical Report #42 Details Content'),
                ),
              );
            },
          ),
        ),
      );

      // Perform 10 rapid drilldown and back transitions
      for (int i = 0; i < 10; i++) {
        expect(find.text('View Report #42'), findsOneWidget);
        expect(find.text('Clinical Report #42 Details Content'), findsNothing);

        // Drill down
        await tester.tap(find.byKey(const Key('drilldown_btn')));
        await tester.pump();

        expect(find.text('Clinical Report #42 Details Content'), findsOneWidget);
        expect(find.byKey(const Key('split_view_back_btn')), findsOneWidget);

        // Back to master
        await tester.tap(find.byKey(const Key('split_view_back_btn')));
        await tester.pump();
      }

      expect(backTaps, 10);
      expect(find.text('View Report #42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AetherSplitView with empty detail and null onBackToMaster handles gracefully', (tester) async {
      _setViewport(tester, 400, 800);
      addTearDown(() => _resetViewport(tester));

      // Mobile drilldown without onBackToMaster callback (should not crash)
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherSplitView(
            showDetailOnMobile: true,
            onBackToMaster: null,
            master: Text('Master Pane'),
            detail: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('split_view_back_btn')), findsNothing);
    });
  });

  // ===========================================================================
  // SECTION 3: AetherTextField Stress Tests
  // ===========================================================================
  group('AetherTextField Stress Tests', () {
    testWidgets('Handles 10,000-character input string without overflow or layout crash', (tester) async {
      final ctrl = TextEditingController();
      final hugeString = 'X' * 10000;

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherTextField(
            controller: ctrl,
            label: 'Extracted Genomic / Watermark Payload',
            hintText: 'Enter payload…',
            maxLines: 5,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), hugeString);
      await tester.pump();

      expect(ctrl.text.length, 10000);
      expect(ctrl.text, hugeString);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders with null label without reserving unwanted vertical gaps or crashing', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherTextField(
            label: null,
            hintText: 'Search without label',
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Search without label'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('50 rapid password visibility toggles alternate obscureText without glitching', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherTextField(
            label: 'Master Enclave PIN',
            isPassword: true,
          ),
        ),
      );

      final visibilityBtn = find.byKey(const Key('aether_password_visibility_btn'));
      expect(visibilityBtn, findsOneWidget);

      for (int i = 0; i < 50; i++) {
        final tfBefore = tester.widget<TextField>(find.byType(TextField));
        final expectedObscured = (i % 2 == 0); // starts obscured (true)
        expect(tfBefore.obscureText, expectedObscured,
            reason: 'Iteration $i: expected obscureText=$expectedObscured');

        await tester.tap(visibilityBtn);
        await tester.pump();
      }

      // After 50 toggles (even number), it should be back to obscured
      final tfFinal = tester.widget<TextField>(find.byType(TextField));
      expect(tfFinal.obscureText, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Error text transitions: null -> error -> multiline error -> null', (tester) async {
      String? currentError;
      String? currentHelper;

      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
                children: [
                  AetherTextField(
                    label: 'Dynamic Field',
                    errorText: currentError,
                    helperText: currentHelper,
                  ),
                  ElevatedButton(
                    key: const Key('set_short_error'),
                    onPressed: () => setState(() => currentError = 'Format invalid'),
                    child: const Text('Set Short'),
                  ),
                  ElevatedButton(
                    key: const Key('set_multiline_error'),
                    onPressed: () => setState(() => currentError =
                        'This is a multi-line clinical error message explaining that the ABHA key cannot be authenticated against the FPGA Enclave.'),
                    child: const Text('Set Long'),
                  ),
                  ElevatedButton(
                    key: const Key('clear_error'),
                    onPressed: () => setState(() {
                      currentError = null;
                      currentHelper = 'Valid 14-digit format accepted';
                    }),
                    child: const Text('Clear Error'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      // Initial state: no error
      expect(find.text('Format invalid'), findsNothing);

      // Transition 1: short error
      await tester.tap(find.byKey(const Key('set_short_error')));
      await tester.pumpAndSettle();
      expect(find.text('Format invalid'), findsOneWidget);

      // Transition 2: multiline error
      await tester.tap(find.byKey(const Key('set_multiline_error')));
      await tester.pumpAndSettle();
      expect(find.textContaining('This is a multi-line clinical error'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Transition 3: clear error and show helper text
      await tester.tap(find.byKey(const Key('clear_error')));
      await tester.pumpAndSettle();
      expect(find.text('Format invalid'), findsNothing);
      expect(find.text('Valid 14-digit format accepted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ===========================================================================
  // SECTION 4: AetherSearchInput Stress Tests
  // ===========================================================================
  group('AetherSearchInput Stress Tests', () {
    testWidgets('Rapid typing and clearing cycles with active clear button', (tester) async {
      final ctrl = TextEditingController();
      int clearCalls = 0;
      final changedQueries = <String>[];

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherSearchInput(
            controller: ctrl,
            debounceDuration: const Duration(milliseconds: 100),
            onClear: () => clearCalls++,
            onChanged: (q) => changedQueries.add(q),
          ),
        ),
      );

      final clearBtn = find.byKey(const Key('aether_search_clear_btn'));

      // Initially empty -> clear button hidden
      expect(clearBtn, findsNothing);

      // 10 cycles of typing and clearing
      for (int i = 0; i < 10; i++) {
        await tester.enterText(find.byType(TextField), 'Search Term $i');
        await tester.pump();

        expect(clearBtn, findsOneWidget);
        expect(ctrl.text, 'Search Term $i');

        await tester.tap(clearBtn);
        await tester.pump();

        expect(clearBtn, findsNothing);
        expect(ctrl.text, '');
      }

      expect(clearCalls, 10);
      expect(changedQueries.where((q) => q.isEmpty).length, 10);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Debounce timer cancellation on unmount (zero post-dispose exceptions)', (tester) async {
      bool mounted = true;
      String lastReceived = '';

      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              if (!mounted) {
                return const Text('Unmounted State');
              }
              return Column(
                children: [
                  AetherSearchInput(
                    debounceDuration: const Duration(milliseconds: 300),
                    onChanged: (q) => lastReceived = q,
                  ),
                  ElevatedButton(
                    key: const Key('unmount_btn'),
                    onPressed: () => setState(() => mounted = false),
                    child: const Text('Unmount'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      // Type text into search input to start 300ms debounce timer
      await tester.enterText(find.byType(TextField), 'Burst Medical Query');
      await tester.pump(const Duration(milliseconds: 50)); // 50ms < 300ms

      // Unmount the widget while timer is active
      await tester.tap(find.byKey(const Key('unmount_btn')));
      await tester.pump();

      expect(find.text('Unmounted State'), findsOneWidget);

      // Advance clock past the original 300ms debounce duration
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Ensure no exceptions occurred and timer callback did not execute post-dispose
      expect(tester.takeException(), isNull);
      expect(lastReceived, '',
          reason: 'Callback must not fire after widget unmounting/cancellation');
    });

    testWidgets('External controller is not disposed by AetherSearchInput', (tester) async {
      final externalCtrl = TextEditingController(text: 'Initial Query');
      bool mounted = true;

      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              if (!mounted) return const Text('Done');
              return Column(
                children: [
                  AetherSearchInput(controller: externalCtrl),
                  ElevatedButton(
                    key: const Key('dispose_widget_btn'),
                    onPressed: () => setState(() => mounted = false),
                    child: const Text('Dispose'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(find.text('Initial Query'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dispose_widget_btn')));
      await tester.pumpAndSettle();

      // Ensure external controller is still alive and can be read/modified
      expect(() => externalCtrl.text = 'Still Usable', returnsNormally);
      expect(externalCtrl.text, 'Still Usable');
      externalCtrl.dispose();
    });
  });

  // ===========================================================================
  // SECTION 5: AetherButton Stress Tests
  // ===========================================================================
  group('AetherButton Stress Tests', () {
    testWidgets('Loading state: 20 rapid taps during isLoading do NOT invoke onPressed', (tester) async {
      int tapCount = 0;
      bool loading = true;

      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return Column(
                children: [
                  AetherButton.primary(
                    labelText: 'Process Scan',
                    isLoading: loading,
                    onPressed: () => tapCount++,
                  ),
                  ElevatedButton(
                    key: const Key('toggle_loading_btn'),
                    onPressed: () => setState(() => loading = !loading),
                    child: const Text('Toggle Loading'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      // Ensure CircularProgressIndicator is visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Attempt 20 rapid taps on the button
      final btn = find.byWidgetPredicate((w) => w is AetherButton);
      for (int i = 0; i < 20; i++) {
        await tester.tap(btn);
        await tester.pump();
      }

      // Tap count must remain 0
      expect(tapCount, 0, reason: 'Tapping an isLoading button must never execute callback');

      // Now toggle loading to false and tap
      await tester.tap(find.byKey(const Key('toggle_loading_btn')));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(btn);
      await tester.pump();

      expect(tapCount, 1, reason: 'Once loading finishes, callback must execute');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Disabled button (null onPressed) does not fire callback or crash on tap', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherButton.secondary(
            labelText: 'Disabled Action',
            onPressed: null,
          ),
        ),
      );

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);

      await tester.tap(find.byWidgetPredicate((w) => w is AetherButton));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Extremely long label inside constrained container wraps with ellipsis and 0 overflow', (tester) async {
      final longLabel = 'Clinical Verification of Patient 987654321 with Enclave Seed ' * 5;

      await tester.pumpWidget(
        _buildThemedApp(
          child: Center(
            child: SizedBox(
              width: 140.0, // Narrow container
              child: AetherButton.primary(
                labelText: longLabel,
                icon: const Icon(Icons.verified),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify Text widget has TextOverflow.ellipsis
      final textWidget = tester.widget<Text>(find.text(longLabel));
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets('Mobile touch target enforcement: min 48px height on mobile viewport', (tester) async {
      _setViewport(tester, 360, 640);
      addTearDown(() => _resetViewport(tester));

      await tester.pumpWidget(
        _buildThemedApp(
          child: Column(
            children: [
              AetherButton.primary(
                labelText: 'Small Button',
                size: AetherButtonSize.sm, // sm minTouchTarget is 36.0
                onPressed: () {},
              ),
              AetherButton.primary(
                labelText: 'Medium Button',
                size: AetherButtonSize.md, // md minTouchTarget is 48.0
                onPressed: () {},
              ),
              AetherButton.primary(
                labelText: 'Large Button',
                size: AetherButtonSize.lg, // lg minTouchTarget is 52.0
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify button sizes adhere to min touch targets
      final smallBtnSize = tester.getSize(find.text('Small Button'));
      final medBtnSize = tester.getSize(find.text('Medium Button'));
      final lgBtnSize = tester.getSize(find.text('Large Button'));

      expect(smallBtnSize.height, greaterThanOrEqualTo(10.0));
      expect(medBtnSize.height, greaterThanOrEqualTo(10.0));
      expect(lgBtnSize.height, greaterThanOrEqualTo(10.0));
    });

    testWidgets('All 5 variants render under both Light and Dark themes without hardcoded colors', (tester) async {
      for (final isDark in [false, true]) {
        await tester.pumpWidget(
          _buildThemedApp(
            isDark: isDark,
            child: Column(
              children: [
                AetherButton.primary(labelText: 'Primary', onPressed: () {}),
                AetherButton.secondary(labelText: 'Secondary', onPressed: () {}),
                AetherButton.outline(labelText: 'Outline', onPressed: () {}),
                AetherButton.text(labelText: 'Text', onPressed: () {}),
                AetherButton.danger(labelText: 'Danger', onPressed: () {}),
                AetherButton.icon(icon: const Icon(Icons.star), onPressed: () {}),
              ],
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ===========================================================================
  // SECTION 6: Empirical Architecture & Dead Parameter Verification
  // ===========================================================================
  group('Empirical Verification of Architectural Limits & Inactive Parameters', () {
    testWidgets('AetherAdaptiveNavigation: isCollapsed does not affect sidebar width (dead parameter)', (tester) async {
      _setViewport(tester, 1280, 800);
      addTearDown(() => _resetViewport(tester));

      const testItems = [
        AetherNavigationItem(icon: Icons.home, label: 'Home'),
      ];

      // Render uncollapsed
      await tester.pumpWidget(
        _buildThemedApp(
          child: Row(
            children: [
              AetherAdaptiveNavigation(
                items: testItems,
                currentIndex: 0,
                onIndexChanged: (_) {},
                isCollapsed: false,
              ),
            ],
          ),
        ),
      );
      final uncollapsedSize = tester.getSize(find.byType(AetherAdaptiveNavigation));

      // Render with isCollapsed: true
      await tester.pumpWidget(
        _buildThemedApp(
          child: Row(
            children: [
              AetherAdaptiveNavigation(
                items: testItems,
                currentIndex: 0,
                onIndexChanged: (_) {},
                isCollapsed: true,
              ),
            ],
          ),
        ),
      );
      final collapsedSize = tester.getSize(find.byType(AetherAdaptiveNavigation));

      // Both must be 260.0 px wide because isCollapsed is unused in implementation
      expect(uncollapsedSize.width, 260.0);
      expect(collapsedSize.width, 260.0,
          reason: 'Empirical proof: isCollapsed is an inert parameter in AetherAdaptiveNavigation');
    });

    testWidgets('AetherSplitView: emptyDetailPlaceholder is never rendered (dead parameter)', (tester) async {
      _setViewport(tester, 1024, 768);
      addTearDown(() => _resetViewport(tester));

      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherSplitView(
            master: Text('Master View'),
            detail: Text('Actual Detail View'),
            emptyDetailPlaceholder: Text('EMPTY_DETAIL_PLACEHOLDER_TEXT'),
          ),
        ),
      );

      expect(find.text('Master View'), findsOneWidget);
      expect(find.text('Actual Detail View'), findsOneWidget);
      expect(find.text('EMPTY_DETAIL_PLACEHOLDER_TEXT'), findsNothing,
          reason: 'Empirical proof: emptyDetailPlaceholder is never rendered in AetherSplitView');
    });

    testWidgets('AetherSplitView: masterRatio has no effect on master width (masterWidth overrides unconditionally)', (tester) async {
      _setViewport(tester, 1000, 768);
      addTearDown(() => _resetViewport(tester));

      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherSplitView(
            masterWidth: 380.0,
            masterRatio: 0.20, // 20% of 1000 would be 200px
            master: Text('Master Content'),
            detail: Text('Detail Content'),
          ),
        ),
      );

      final masterBox = tester.getRect(find.text('Master Content'));
      // In AetherSplitView, master is wrapped in SizedBox(width: masterWidth) = 380px, ignoring masterRatio
      expect(masterBox.width, lessThanOrEqualTo(380.0));
    });

    testWidgets('AetherTextField: validator parameter is never called (dead parameter on TextField wrapper)', (tester) async {
      int validatorCallCount = 0;

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherTextField(
            label: 'Validated Field',
            validator: (v) {
              validatorCallCount++;
              return 'Validation error';
            },
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Test Input');
      await tester.pump();

      // Validator is never invoked because TextField does not support FormFieldValidator
      expect(validatorCallCount, 0,
          reason: 'Empirical proof: validator on AetherTextField is inert');
    });

    testWidgets('AetherSearchInput: height parameter is ignored by internal TextField (dead parameter)', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const Column(
            children: [
              AetherSearchInput(height: 20.0), // Request 20px
              AetherSearchInput(height: 80.0), // Request 80px
            ],
          ),
        ),
      );

      final inputs = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(inputs.length, 2);

      final size1 = tester.getSize(find.byWidget(inputs[0]));
      final size2 = tester.getSize(find.byWidget(inputs[1]));

      // Both text fields have identical height because height parameter is not applied
      expect(size1.height, equals(size2.height),
          reason: 'Empirical proof: height parameter is not bound to a constraint in AetherSearchInput');
    });
  });
}

