import 'package:aether_ui/aether_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildThemedApp({required Widget child, bool isDark = false}) {
  return MaterialApp(
    home: AetherTheme(
      data: isDark ? AetherThemeData.dark() : AetherThemeData.light(),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AetherTextField', () {
    testWidgets('renders label, hint, and accepts text input', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherTextField(
            controller: ctrl,
            label: 'ABHA ID',
            hintText: 'Enter 14-digit ID',
          ),
        ),
      );

      expect(find.text('ABHA ID'), findsOneWidget);
      expect(find.text('Enter 14-digit ID'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '12345678901234');
      expect(ctrl.text, '12345678901234');
    });

    testWidgets('password mode obscures text and toggles visibility via key button', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherTextField(
            label: 'Password',
            isPassword: true,
          ),
        ),
      );

      final tfBefore = tester.widget<TextField>(find.byType(TextField));
      expect(tfBefore.obscureText, isTrue);

      await tester.tap(find.byKey(const Key('aether_password_visibility_btn')));
      await tester.pump();

      final tfAfter = tester.widget<TextField>(find.byType(TextField));
      expect(tfAfter.obscureText, isFalse);
    });

    testWidgets('renders errorText and helperText', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const Column(
            children: [
              AetherTextField(
                errorText: 'Invalid ABHA format',
              ),
              AetherTextField(
                helperText: 'Must contain 14 numeric digits',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Invalid ABHA format'), findsOneWidget);
      expect(find.text('Must contain 14 numeric digits'), findsOneWidget);
    });

    testWidgets('renders custom prefix and suffix icons', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherTextField(
            prefixIcon: Icon(Icons.person),
            suffixIcon: Icon(Icons.check),
          ),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('disabled field prevents editing', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherTextField(
            enabled: false,
          ),
        ),
      );

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.enabled, isFalse);
    });
  });

  group('AetherSearchInput', () {
    testWidgets('renders search icon and hint text', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherSearchInput(hintText: 'Search patients…'),
        ),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Search patients…'), findsOneWidget);
    });

    testWidgets('debounces onChanged triggers', (tester) async {
      String query = '';
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherSearchInput(
            debounceDuration: const Duration(milliseconds: 150),
            onChanged: (q) => query = q,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Cardiology');
      await tester.pump(const Duration(milliseconds: 50));
      expect(query, '');

      await tester.pump(const Duration(milliseconds: 120));
      expect(query, 'Cardiology');
    });

    testWidgets('clear button clears query and invokes onClear', (tester) async {
      final ctrl = TextEditingController(text: 'MRI Brain');
      bool cleared = false;

      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherSearchInput(
            controller: ctrl,
            onClear: () => cleared = true,
          ),
        ),
      );

      expect(find.byKey(const Key('aether_search_clear_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('aether_search_clear_btn')));
      await tester.pump();

      expect(ctrl.text, '');
      expect(cleared, isTrue);
    });

    testWidgets('filter tap invokes onFilterTap callback', (tester) async {
      bool filterTapped = false;
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherSearchInput(
            onFilterTap: () => filterTapped = true,
          ),
        ),
      );

      expect(find.byKey(const Key('aether_search_filter_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('aether_search_filter_btn')));
      await tester.pump();

      expect(filterTapped, isTrue);
    });

    testWidgets('onSubmitted triggers on keyboard submit', (tester) async {
      String submitted = '';
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherSearchInput(
            onSubmitted: (s) => submitted = s,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Scan Report 001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submitted, 'Scan Report 001');
    });
  });

  group('AetherChoiceChipGroup', () {
    testWidgets('single-selection mode fires onSelected callback', (tester) async {
      String selected = 'all';
      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return AetherChoiceChipGroup<String>(
                items: const [
                  AetherChoiceChipItem(value: 'all', label: 'All Scans'),
                  AetherChoiceChipItem(value: 'mri', label: 'MRI'),
                  AetherChoiceChipItem(value: 'ct', label: 'CT'),
                ],
                selectedValue: selected,
                onSelected: (val) => setState(() => selected = val),
              );
            },
          ),
        ),
      );

      expect(find.text('All Scans'), findsOneWidget);
      expect(find.text('MRI'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chip_mri')));
      await tester.pump();

      expect(selected, 'mri');
    });

    testWidgets('multi-selection mode fires onMultiSelected callback', (tester) async {
      List<String> selected = ['mri'];
      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return AetherChoiceChipGroup<String>(
                isMultiSelect: true,
                items: const [
                  AetherChoiceChipItem(value: 'mri', label: 'MRI'),
                  AetherChoiceChipItem(value: 'ct', label: 'CT'),
                  AetherChoiceChipItem(value: 'xray', label: 'X-Ray'),
                ],
                selectedValues: selected,
                onMultiSelected: (vals) => setState(() => selected = vals),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chip_ct')));
      await tester.pump();

      expect(selected, containsAll(['mri', 'ct']));

      await tester.tap(find.byKey(const ValueKey('chip_mri')));
      await tester.pump();

      expect(selected, ['ct']);
    });

    testWidgets('scrollable mode renders SingleChildScrollView', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherChoiceChipGroup<String>(
            isScrollable: true,
            items: [
              AetherChoiceChipItem(value: '1', label: 'Filter 1'),
              AetherChoiceChipItem(value: '2', label: 'Filter 2'),
            ],
          ),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('empty items with isScrollable: true does not throw RangeError', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherChoiceChipGroup<String>(
            isScrollable: true,
            items: [],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('AetherButton', () {
    testWidgets('renders primary variant and handles tap', (tester) async {
      bool clicked = false;
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherButton(
            labelText: 'Submit Scan',
            icon: const Icon(Icons.upload),
            onPressed: () => clicked = true,
          ),
        ),
      );

      expect(find.text('Submit Scan'), findsOneWidget);
      expect(find.byIcon(Icons.upload), findsOneWidget);

      await tester.tap(find.text('Submit Scan'));
      await tester.pump();
      expect(clicked, isTrue);
    });

    testWidgets('renders secondary, outline, text, and danger factory variants', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: Column(
            children: [
              AetherButton.secondary(labelText: 'Secondary', onPressed: () {}),
              AetherButton.outline(labelText: 'Outline', onPressed: () {}),
              AetherButton.text(labelText: 'Text Button', onPressed: () {}),
              AetherButton.danger(labelText: 'Danger Button', onPressed: () {}),
              AetherButton.icon(icon: const Icon(Icons.settings), onPressed: () {}),
            ],
          ),
        ),
      );

      expect(find.text('Secondary'), findsOneWidget);
      expect(find.text('Outline'), findsOneWidget);
      expect(find.text('Text Button'), findsOneWidget);
      expect(find.text('Danger Button'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('loading state displays spinner and disables interaction', (tester) async {
      bool clicked = false;
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherButton(
            labelText: 'Marking…',
            isLoading: true,
            onPressed: () => clicked = true,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(AetherButton));
      await tester.pump();
      expect(clicked, isFalse);
    });

    testWidgets('disabled button (null onPressed) does not fire callback', (tester) async {
      await tester.pumpWidget(
        _buildThemedApp(
          child: const AetherButton(
            labelText: 'Disabled Button',
            onPressed: null,
          ),
        ),
      );

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('enforces >= 48px touch targets on mobile viewports for small and icon sizes', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _buildThemedApp(
          child: Column(
            children: [
              AetherButton.primary(
                labelText: 'Small Button',
                size: AetherButtonSize.sm,
                onPressed: () {},
              ),
              AetherButton.icon(
                icon: const Icon(Icons.settings),
                size: AetherButtonSize.sm,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      final smBtn = tester.getSize(find.byType(ElevatedButton).at(0));
      expect(smBtn.height, greaterThanOrEqualTo(48.0));

      final iconBtn = tester.getSize(find.byType(ElevatedButton).at(1));
      expect(iconBtn.width, greaterThanOrEqualTo(48.0));
      expect(iconBtn.height, greaterThanOrEqualTo(48.0));
    });
  });

  group('AetherSwitchTile', () {
    testWidgets('toggles switch value and fires onChanged', (tester) async {
      bool isEnabled = false;
      await tester.pumpWidget(
        _buildThemedApp(
          child: StatefulBuilder(
            builder: (ctx, setState) {
              return AetherSwitchTile(
                title: 'Enable FPGA Watermark',
                subtitle: 'Hardware Enclave 119 PL cycles',
                leading: const Icon(Icons.security),
                value: isEnabled,
                onChanged: (v) => setState(() => isEnabled = v),
              );
            },
          ),
        ),
      );

      expect(find.text('Enable FPGA Watermark'), findsOneWidget);
      expect(find.text('Hardware Enclave 119 PL cycles'), findsOneWidget);
      expect(find.byIcon(Icons.security), findsOneWidget);
      expect(isEnabled, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(isEnabled, isTrue);
    });

    testWidgets('disabled switch tile does not toggle', (tester) async {
      bool isEnabled = false;
      await tester.pumpWidget(
        _buildThemedApp(
          child: AetherSwitchTile(
            title: 'Locked Setting',
            enabled: false,
            value: isEnabled,
            onChanged: (v) => isEnabled = v,
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(isEnabled, isFalse);
    });
  });
}
