import 'package:aether_ui/aether_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildThemedApp({required Widget child, bool isDark = false}) {
  return MaterialApp(
    home: AetherTheme(
      data: isDark ? AetherThemeData.dark() : AetherThemeData.light(),
      child: Scaffold(body: child),
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

  const testItems = [
    AetherNavigationItem(icon: Icons.home, label: 'Home'),
    AetherNavigationItem(icon: Icons.description, label: 'Records', badgeText: '3'),
    AetherNavigationItem(icon: Icons.person, label: 'Profile'),
  ];

  group('AetherAdaptiveNavigation & AetherResponsiveScaffold', () {
    testWidgets('renders bottom bar with labels and badge on mobile (<= 600px)', (tester) async {
      _setViewport(tester, 400, 800);
      addTearDown(() => _resetViewport(tester));

      int selected = 0;
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: testItems,
            currentIndex: selected,
            onIndexChanged: (i) => selected = i,
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Records'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav_item_1')));
      await tester.pump();
      expect(selected, 1);
    });

    testWidgets('renders vertical rail with IconButtons on tablet (601px - 1024px)', (tester) async {
      _setViewport(tester, 768, 1024);
      addTearDown(() => _resetViewport(tester));

      int selected = 0;
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: testItems,
            currentIndex: selected,
            onIndexChanged: (i) => selected = i,
            header: const Icon(Icons.local_hospital),
          ),
        ),
      );

      expect(find.byType(IconButton), findsNWidgets(3));
      expect(find.byKey(const ValueKey('nav_item_0')), findsOneWidget);
      expect(find.byIcon(Icons.local_hospital), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav_item_2')));
      await tester.pump();
      expect(selected, 2);
    });

    testWidgets('renders expanded sidebar with ListTiles on desktop (>= 1025px)', (tester) async {
      _setViewport(tester, 1280, 800);
      addTearDown(() => _resetViewport(tester));

      int selected = 0;
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherAdaptiveNavigation(
            items: testItems,
            currentIndex: selected,
            onIndexChanged: (i) => selected = i,
            header: const Text('NovaLife Hub'),
            footer: const Text('v2.4.0'),
          ),
        ),
      );

      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Records'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('NovaLife Hub'), findsOneWidget);
      expect(find.text('v2.4.0'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('nav_item_1')));
      await tester.pump();
      expect(selected, 1);
    });

    testWidgets('AetherResponsiveScaffold integrates adaptive navigation, body, and side panel', (tester) async {
      _setViewport(tester, 1280, 800);
      addTearDown(() => _resetViewport(tester));

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherResponsiveScaffold(
            navigationItems: testItems,
            currentIndex: 0,
            onNavigationChanged: (_) {},
            body: const Text('Clinical Scans Dashboard'),
            sidePanel: const Text('Side Panel Details'),
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.text('Clinical Scans Dashboard'), findsOneWidget);
      expect(find.text('Side Panel Details'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('AetherResponsiveScaffold adapts to mobile bottom bar', (tester) async {
      _setViewport(tester, 400, 800);
      addTearDown(() => _resetViewport(tester));

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherResponsiveScaffold(
            navigationItems: testItems,
            currentIndex: 0,
            onNavigationChanged: (_) {},
            body: const Text('Mobile Content View'),
          ),
        ),
      );

      expect(find.text('Mobile Content View'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('AetherHeaderBar', () {
    testWidgets('renders titleText, actions, and searchSlot cleanly', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherHeaderBar(
            titleText: 'Patient Vault',
            subtitleText: 'ABHA Records',
            actions: [
              IconButton(icon: const Icon(Icons.refresh), onPressed: () {}),
            ],
            searchSlot: const TextField(decoration: InputDecoration(hintText: 'Search…')),
          ),
        ),
      );

      expect(find.text('Patient Vault'), findsOneWidget);
      expect(find.text('ABHA Records'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Search…'), findsOneWidget);
    });

    testWidgets('calculates preferredSize including bottom widget', (tester) async {
      const headerBar = AetherHeaderBar(
        titleText: 'Title',
        height: 60.0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(40.0),
          child: SizedBox(height: 40.0),
        ),
      );

      expect(headerBar.preferredSize.height, 100.0);
    });
  });

  group('AetherSectionCard', () {
    testWidgets('renders title, subtitle, leadingIcon, child content, and handles onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherSectionCard(
            title: 'Diagnostic Findings',
            subtitle: 'MRI Brain Tumor Protocol',
            leadingIcon: const Icon(Icons.medical_services),
            headerAction: const Icon(Icons.more_vert),
            footer: const Text('Footer Actions'),
            onTap: () => tapped = true,
            child: const Text('Findings content'),
          ),
        ),
      );

      expect(find.text('Diagnostic Findings'), findsOneWidget);
      expect(find.text('MRI Brain Tumor Protocol'), findsOneWidget);
      expect(find.byIcon(Icons.medical_services), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.text('Findings content'), findsOneWidget);
      expect(find.text('Footer Actions'), findsOneWidget);

      await tester.tap(find.text('Diagnostic Findings'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('renders elevated style with shadow under dark theme', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          isDark: true,
          child: const AetherSectionCard(
            title: 'Elevated Dark Card',
            isElevated: true,
            child: Text('Card Content'),
          ),
        ),
      );

      expect(find.text('Elevated Dark Card'), findsOneWidget);
      expect(find.text('Card Content'), findsOneWidget);
    });
  });

  group('AetherSplitView', () {
    testWidgets('mobile drilldown into detail and returns to master via back button', (tester) async {
      _setViewport(tester, 400, 800);
      addTearDown(() => _resetViewport(tester));

      bool showDetail = false;
      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return AetherSplitView(
                showDetailOnMobile: showDetail,
                onBackToMaster: () => setState(() => showDetail = false),
                master: ElevatedButton(
                  onPressed: () => setState(() => showDetail = true),
                  child: const Text('Open Record'),
                ),
                detail: const Text('Detailed Medical Record'),
              );
            },
          ),
        ),
      );

      expect(find.text('Open Record'), findsOneWidget);
      expect(find.text('Detailed Medical Record'), findsNothing);

      await tester.tap(find.text('Open Record'));
      await tester.pump();

      expect(find.text('Detailed Medical Record'), findsOneWidget);
      expect(find.byKey(const Key('split_view_back_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('split_view_back_btn')));
      await tester.pump();

      expect(find.text('Open Record'), findsOneWidget);
      expect(find.text('Detailed Medical Record'), findsNothing);
    });

    testWidgets('tablet and desktop render dual panes concurrently with divider', (tester) async {
      _setViewport(tester, 1024, 768);
      addTearDown(() => _resetViewport(tester));

      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherSplitView(
            masterWidth: 350,
            showDivider: true,
            master: Text('Master Records List'),
            detail: Text('Selected Record Details'),
          ),
        ),
      );

      expect(find.text('Master Records List'), findsOneWidget);
      expect(find.text('Selected Record Details'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsOneWidget);
    });

    testWidgets('tablet and desktop respect masterRatio and emptyDetailPlaceholder', (tester) async {
      _setViewport(tester, 1000, 700);
      addTearDown(() => _resetViewport(tester));

      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherSplitView(
            masterRatio: 0.4,
            master: Text('Master 40%'),
            emptyDetailPlaceholder: Text('No record selected'),
          ),
        ),
      );

      expect(find.text('Master 40%'), findsOneWidget);
      expect(find.text('No record selected'), findsOneWidget);

      final masterBox = tester.getSize(find.ancestor(
        of: find.text('Master 40%'),
        matching: find.byType(SizedBox),
      ).first);
      // 1000 * 0.4 = 400.0
      expect(masterBox.width, 400.0);
    });
  });
}
