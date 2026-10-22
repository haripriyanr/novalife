import 'package:aether_ui/aether_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapWithTheme({
  required Widget child,
  AetherThemeData? themeData,
}) {
  return MaterialApp(
    home: AetherTheme(
      data: themeData ?? AetherThemeData.light(),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AetherStatusBadge', () {
    testWidgets('renders all 5 semantic status variants with labels', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const Column(
            children: [
              AetherStatusBadge(text: 'Pass', status: AetherStatusVariant.success),
              AetherStatusBadge(text: 'Fail', status: AetherStatusVariant.danger),
              AetherStatusBadge(text: 'Pending', status: AetherStatusVariant.warning),
              AetherStatusBadge(text: 'Info', status: AetherStatusVariant.info),
              AetherStatusBadge(text: 'Draft', status: AetherStatusVariant.neutral),
            ],
          ),
        ),
      );

      expect(find.text('Pass'), findsOneWidget);
      expect(find.text('Fail'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
    });

    testWidgets('supports label parameter and variant parameter', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherStatusBadge(
            label: 'Active',
            variant: AetherStatusVariant.success,
          ),
        ),
      );

      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('renders subtle, solid, and outline badge styles without error', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const Column(
            children: [
              AetherStatusBadge(
                text: 'Subtle',
                status: AetherStatusVariant.info,
                style: AetherStatusStyle.subtle,
              ),
              AetherStatusBadge(
                text: 'Solid',
                status: AetherStatusVariant.success,
                style: AetherStatusStyle.solid,
              ),
              AetherStatusBadge(
                text: 'Outline',
                status: AetherStatusVariant.danger,
                style: AetherStatusStyle.outline,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Subtle'), findsOneWidget);
      expect(find.text('Solid'), findsOneWidget);
      expect(find.text('Outline'), findsOneWidget);
    });

    testWidgets('renders status dot and custom icon', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherStatusBadge(
            text: 'Hardware Active',
            status: AetherStatusVariant.success,
            showDot: true,
            icon: Icon(Icons.memory, size: 14),
          ),
        ),
      );

      expect(find.text('Hardware Active'), findsOneWidget);
      expect(find.byIcon(Icons.memory), findsOneWidget);
    });
  });

  group('AetherDataCard', () {
    testWidgets('renders title, subtitle, leading, and trailing badge', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherDataCard(
            title: 'Diagnostic Brain MRI',
            subtitle: 'Patient PAT-001',
            leading: Icon(Icons.medical_services),
            badge: AetherStatusBadge(text: 'Verified', status: AetherStatusVariant.success),
          ),
        ),
      );

      expect(find.text('Diagnostic Brain MRI'), findsOneWidget);
      expect(find.text('Patient PAT-001'), findsOneWidget);
      expect(find.byIcon(Icons.medical_services), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('renders key-value metadata fields cleanly', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherDataCard(
            title: 'Report Summary',
            fields: [
              AetherDataCardField(label: 'Date', value: '2026-10-28'),
              AetherDataCardField(label: 'Type', value: 'Radiology'),
            ],
          ),
        ),
      );

      expect(find.text('Date: '), findsOneWidget);
      expect(find.text('2026-10-28'), findsOneWidget);
      expect(find.text('Type: '), findsOneWidget);
      expect(find.text('Radiology'), findsOneWidget);
    });

    testWidgets('renders safely with null subtitle and empty fields list', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherDataCard(
            title: 'Empty Fields Card',
            subtitle: null,
            fields: [],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Empty Fields Card'), findsOneWidget);
    });

    testWidgets('triggers onTap callback when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _wrapWithTheme(
          child: AetherDataCard(
            title: 'Clickable Card',
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Clickable Card'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('renders selection border when isSelected is true', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherDataCard(
            title: 'Selected Card',
            isSelected: true,
          ),
        ),
      );

      expect(find.text('Selected Card'), findsOneWidget);
    });

    testWidgets('multi-action buttons wrap cleanly without overflow on 320px screen', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapWithTheme(
          child: SingleChildScrollView(
            child: AetherDataCard(
              title: 'Card with Actions',
              actions: [
                TextButton(
                  onPressed: () {},
                  child: const Text('Export DICOM'),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Revoke Handle'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Export DICOM'), findsOneWidget);
      expect(find.text('Revoke Handle'), findsOneWidget);
    });
  });

  group('AetherMetricTile', () {
    testWidgets('renders metric label, value, and unit', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherMetricTile(
            label: 'Watermark Capacity',
            value: '128',
            unit: 'bits',
            caption: 'Hardware-verified bits',
          ),
        ),
      );

      expect(find.text('Watermark Capacity'), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      expect(find.text('bits'), findsOneWidget);
      expect(find.text('Hardware-verified bits'), findsOneWidget);
    });

    testWidgets('renders positive trend and negative trend indicators', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const Column(
            children: [
              AetherMetricTile(
                label: 'Recovery Rate',
                value: '100%',
                trend: '+2.4%',
                isTrendPositive: true,
              ),
              AetherMetricTile(
                label: 'BER Error',
                value: '0.00',
                trend: '-0.12%',
                isTrendPositive: false,
              ),
            ],
          ),
        ),
      );

      expect(find.text('+2.4%'), findsOneWidget);
      expect(find.text('-0.12%'), findsOneWidget);
    });

    testWidgets('renders semantic tint on primary value', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherMetricTile(
            label: 'Pass Verdict',
            value: 'PASS',
            semantic: AetherStatusVariant.success,
          ),
        ),
      );

      expect(find.text('PASS'), findsOneWidget);
    });

    testWidgets('triggers onTap callback when pressed', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _wrapWithTheme(
          child: AetherMetricTile(
            label: 'Scans Verified',
            value: '42',
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Scans Verified'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('AetherAvatarBadge', () {
    test('computes two-word uppercase initials correctly', () {
      expect(AetherAvatarBadge.computeInitials('Anjali Mehta'), 'AM');
      expect(AetherAvatarBadge.computeInitials('John Doe'), 'JD');
    });

    test('computes single-word uppercase initials correctly', () {
      expect(AetherAvatarBadge.computeInitials('Admin'), 'AD');
      expect(AetherAvatarBadge.computeInitials('Zynq'), 'ZY');
    });

    test('computes fallback for null and empty names', () {
      expect(AetherAvatarBadge.computeInitials(null), '??');
      expect(AetherAvatarBadge.computeInitials(''), '??');
      expect(AetherAvatarBadge.computeInitials('   '), '??');
    });

    testWidgets('renders initials and status dot indicator on screen', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherAvatarBadge(
            name: 'Anjali Mehta',
            size: 48,
            statusDot: AetherStatusVariant.success,
          ),
        ),
      );

      expect(find.text('AM'), findsOneWidget);
    });
  });
}
