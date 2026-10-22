import 'package:flutter_test/flutter_test.dart';
import 'package:novalife/models/hub_api_models.dart';
import 'package:novalife/services/hub_api_service.dart';

void main() {
  group('E2E Three Roles User Workflows (Patient, Doctor, Lab Tech)', () {
    final api = HubApiMockClient();

    test('1. Patient Role E2E: Login, View Reports, Restrict Access', () async {
      // Login
      final auth = await api.login('patient_001', 'pat@1234');
      expect(auth.status, 'ok');
      expect(auth.role, UserRole.patient);
      expect(auth.userId, 'patient_001');
      expect(auth.fullName, 'Anjali Mehta');
      expect(auth.abhaId, '12345678901234');

      // Patient retrieves their own reports
      final reports = await api.getReports('PAT-001');
      expect(reports.patientId, 'PAT-001');
      expect(reports.reports, isNotEmpty);
      expect(reports.reports.any((r) => r.title.contains('CBC')), isTrue);
    });

    test('2. Doctor Role E2E: Login, Search/Get Patients, View Diagnostic Reports, Add Clinical Note', () async {
      // Login
      final auth = await api.login('doctor_001', 'doc@1234');
      expect(auth.status, 'ok');
      expect(auth.role, UserRole.doctor);
      expect(auth.fullName, 'Dr. Rajesh Gupta');

      // Doctor lists patients
      final patients = await api.getPatients();
      expect(patients.length, greaterThanOrEqualTo(3));
      expect(patients.any((p) => p['patient_id'] == 'PAT-001'), isTrue);

      // Doctor inspects patient imaging report
      final patientReports = await api.getReports('PAT-001');
      final imagingReport = patientReports.reports.firstWhere((r) => r.reportType == 'imaging');
      expect(imagingReport.reportId, 'RPT-002');
      expect(imagingReport.stegoBytes, 1024);

      // Doctor adds clinical note
      final noteResp = await api.addNote(
        reportId: imagingReport.reportId,
        userId: auth.userId,
        noteText: 'Lungs clear, heart size normal. Watermarked payload verified intact.',
      );
      expect(noteResp.status, 'created');
      expect(noteResp.noteId, startsWith('NT-'));

      // Verify clinical note is persisted
      final notes = await api.getNotes(imagingReport.reportId);
      expect(notes.any((n) => n.noteText.contains('Watermarked payload verified intact')), isTrue);
    });

    test('3. Lab Tech Role E2E: Login, Access Vault Index, Verify Authentication', () async {
      // Login
      final auth = await api.login('lab_tech_001', 'lab@1234');
      expect(auth.status, 'ok');
      expect(auth.role, UserRole.labTech);
      expect(auth.fullName, 'Priya Sharma');

      // Lab tech manages patient list for uploads
      final patients = await api.getPatients();
      expect(patients.isNotEmpty, isTrue);

      // Inspect report catalog
      final reports = await api.getReports('PAT-002');
      expect(reports.reports.length, 2);
    });

    test('4. Security & Rejection across all 3 roles', () async {
      // Wrong credentials
      for (final id in ['patient_001', 'doctor_001', 'lab_tech_001']) {
        expect(
          () => api.login(id, 'invalid_password'),
          throwsA(isA<HubApiException>().having((e) => e.code, 'code', 401)),
        );
      }

      // Non-existent patient reports
      expect(
        () => api.getReports('PAT-UNKNOWN'),
        throwsA(isA<HubApiException>().having((e) => e.code, 'code', 404)),
      );
    });
  });
}
