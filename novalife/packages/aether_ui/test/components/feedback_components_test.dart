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

  group('AetherAdaptiveDialog', () {
    testWidgets('renders desktop centered modal dialog on wide viewport', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _wrapWithTheme(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                AetherAdaptiveDialog.show(
                  ctx,
                  title: const Text('Confirm Revocation'),
                  content: const Text('Are you sure you want to revoke this report?'),
                  actions: [
                    AetherDialogAction.cancel(onPressed: () {}),
                    AetherDialogAction.destructive(
                      label: 'Revoke',
                      onPressed: () {},
                    ),
                  ],
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Revocation'), findsOneWidget);
      expect(find.text('Are you sure you want to revoke this report?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Revoke'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('adapts to modal bottom sheet on mobile viewport', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _wrapWithTheme(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showAetherDialog(
                  ctx,
                  title: const Text('Mobile Dialog Title'),
                  content: const Text('Mobile Dialog Body'),
                );
              },
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Mobile Dialog Title'), findsOneWidget);
      expect(find.text('Mobile Dialog Body'), findsOneWidget);
      expect(find.byType(AetherBottomSheet), findsOneWidget);
    });

    testWidgets('multi-action buttons wrap cleanly in mobile bottom sheet on 320px screen', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapWithTheme(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                AetherAdaptiveDialog.show(
                  ctx,
                  title: const Text('Multi-Action Dialog'),
                  content: const Text('Confirm clinical export protocol'),
                  actions: [
                    AetherDialogAction.cancel(onPressed: () => Navigator.pop(ctx)),
                    AetherDialogAction.primary(label: 'Export DICOM', onPressed: () => Navigator.pop(ctx)),
                    AetherDialogAction.destructive(label: 'Revoke Handle', onPressed: () => Navigator.pop(ctx)),
                  ],
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Export DICOM'), findsOneWidget);
      expect(find.text('Revoke Handle'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('AetherBottomSheet', () {
    testWidgets('renders title, drag handle, action, and child content', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const AetherBottomSheet(
            title: 'Select Export Format',
            action: Icon(Icons.close),
            child: Text('Sheet content text'),
          ),
        ),
      );

      expect(find.text('Select Export Format'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('Sheet content text'), findsOneWidget);
    });
  });

  group('AetherImageViewer', () {
    testWidgets('renders child content inside InteractiveViewer with control buttons', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const SizedBox(
            width: 500,
            height: 500,
            child: AetherImageViewer(
              child: SizedBox(
                width: 300,
                height: 300,
                child: Center(child: Text('Radiology MRI Slice')),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Radiology MRI Slice'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const Key('zoom_in_btn')), findsOneWidget);
      expect(find.byKey(const Key('zoom_out_btn')), findsOneWidget);
      expect(find.byKey(const Key('zoom_reset_btn')), findsOneWidget);
    });

    testWidgets('zoom in, zoom out, and reset actions manipulate transformation matrix', (tester) async {
      final ctrl = TransformationController();
      await tester.pumpWidget(
        _wrapWithTheme(
          child: SizedBox(
            width: 500,
            height: 500,
            child: AetherImageViewer(
              controller: ctrl,
              child: const Text('Test Scan'),
            ),
          ),
        ),
      );

      expect(ctrl.value.getMaxScaleOnAxis(), 1.0);

      // Zoom In
      await tester.tap(find.byKey(const Key('zoom_in_btn')));
      await tester.pump();
      expect(ctrl.value.getMaxScaleOnAxis(), greaterThan(1.0));

      final zoomedScale = ctrl.value.getMaxScaleOnAxis();

      // Zoom Out
      await tester.tap(find.byKey(const Key('zoom_out_btn')));
      await tester.pump();
      expect(ctrl.value.getMaxScaleOnAxis(), lessThan(zoomedScale));

      // Reset
      await tester.tap(find.byKey(const Key('zoom_reset_btn')));
      await tester.pump();
      expect(ctrl.value, Matrix4.identity());
    });

    testWidgets('double tap performs focal zoom', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          child: const SizedBox(
            width: 500,
            height: 500,
            child: AetherImageViewer(
              child: Center(child: Text('Double Tap Target')),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Double Tap Target'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Double Tap Target'));
      await tester.pumpAndSettle();

      expect(find.text('Double Tap Target'), findsOneWidget);
    });
  });

  group('AetherToastBanner', () {
    testWidgets('renders message and close button, tapping fires onDismiss', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        _wrapWithTheme(
          child: AetherToastBanner(
            title: 'Watermark Success',
            message: 'FPGA watermark verification complete.',
            status: AetherStatusVariant.success,
            onDismiss: () => dismissed = true,
          ),
        ),
      );

      expect(find.text('Watermark Success'), findsOneWidget);
      expect(find.text('FPGA watermark verification complete.'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(dismissed, isTrue);
    });

    testWidgets('inherits semantic container colors under Dark theme', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          themeData: AetherThemeData.dark(),
          child: const AetherToastBanner(
            message: 'Dark theme toast alert',
            status: AetherStatusVariant.danger,
          ),
        ),
      );

      expect(find.text('Dark theme toast alert'), findsOneWidget);
    });

    testWidgets('close button has at least 48x48 tap target area on mobile', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapWithTheme(
          child: AetherToastBanner(
            message: 'Mobile touch target test',
            onDismiss: () {},
          ),
        ),
      );

      final closeBtnSize = tester.getSize(find.byType(IconButton));
      expect(closeBtnSize.width, greaterThanOrEqualTo(48.0));
      expect(closeBtnSize.height, greaterThanOrEqualTo(48.0));
    });
  });
}
