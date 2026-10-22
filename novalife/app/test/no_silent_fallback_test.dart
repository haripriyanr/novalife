import 'package:flutter_test/flutter_test.dart';
import 'package:novalife/config/demo_mode.dart';
import 'package:novalife/services/hub_patients_service.dart';

/// Without a backend (hubDb is null in tests) and without demo mode, the services must say so:
/// no sample patients, reports or notes, and a note must never look saved when it was not.
void main() {
  test('demo mode is off by default', () {
    expect(kDemoMode, isFalse);
  });

  test('listPatients throws instead of returning sample data', () async {
    expect(HubPatientsService.listPatients(), throwsA(isA<HubDataException>()));
  });

  test('reportsFor throws instead of returning sample data', () async {
    expect(HubPatientsService.reportsFor('patient_001'), throwsA(isA<HubDataException>()));
  });

  test('notesFor throws instead of returning sample data', () async {
    expect(HubPatientsService.notesFor('RPT-1'), throwsA(isA<HubDataException>()));
  });

  test('addNote throws and never pretends to save', () async {
    expect(
      HubPatientsService.addNote(reportId: 'RPT-1', noteText: 'x'),
      throwsA(isA<HubDataException>()),
    );
  });
}
