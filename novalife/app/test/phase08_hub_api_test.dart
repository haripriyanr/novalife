import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:novalife/models/hub_api_models.dart';
import 'package:novalife/services/hub_api_service.dart';

// Verified on hardware 2026-09-16: board IP 192.168.31.86, GET /status 167B JSON vault_files 4, GET /vault/index.txt 176B JSONL, POST /embed stego 1024B via EMIO UART1 R19/T19, SD vault 0:/vault/*.png + index.txt

void main() {
  group('HubApiMockClient.login', () {
    final api = HubApiMockClient();

    test('doctor_001 authenticates with correct password', () async {
      final resp = await api.login('doctor_001', 'doc@1234');
      expect(resp.status, 'ok');
      expect(resp.userId, 'doctor_001');
      expect(resp.fullName, 'Dr. Rajesh Gupta');
      expect(resp.role, UserRole.doctor);
    });

    test('patient_001 authenticates with correct password', () async {
      final resp = await api.login('patient_001', 'pat@1234');
      expect(resp.role, UserRole.patient);
      expect(resp.abhaId, '12345678901234');
    });

    test('lab_tech_001 authenticates', () async {
      final resp = await api.login('lab_tech_001', 'lab@1234');
      expect(resp.role, UserRole.labTech);
    });

    test('wrong password throws 401', () async {
      expect(
        () => api.login('doctor_001', 'wrong'),
        throwsA(isA<HubApiException>().having((e) => e.code, 'code', 401)),
      );
    });

    test('unknown user throws 401', () async {
      expect(
        () => api.login('nobody', 'x'),
        throwsA(isA<HubApiException>().having((e) => e.code, 'code', 401)),
      );
    });
  });

  group('HubApiMockClient.getReports', () {
    final api = HubApiMockClient();

    test('PAT-001 has 2 reports', () async {
      final resp = await api.getReports('PAT-001');
      expect(resp.patientId, 'PAT-001');
      expect(resp.abhaId, '12345678901234');
      expect(resp.reports.length, 2);
      expect(resp.reports.first.title, contains('CBC'));
    });

    test('unknown patient throws 404', () async {
      expect(
        () => api.getReports('PAT-999'),
        throwsA(isA<HubApiException>().having((e) => e.code, 'code', 404)),
      );
    });
  });

  group('HubApiMockClient.addNote', () {
    final api = HubApiMockClient();

    test('adds a note and returns 201 shape', () async {
      final resp = await api.addNote(
        reportId: 'RPT-001',
        userId: 'doctor_001',
        noteText: 'Test note',
      );
      expect(resp.status, 'created');
      expect(resp.noteId, startsWith('NT-'));
      expect(resp.createdAt, isNotEmpty);
    });
  });

  group('HubApiMockClient.getPatients', () {
    test('returns registered patients', () async {
      final api = HubApiMockClient();
      final patients = await api.getPatients();
      expect(patients.length, 3);
      expect(patients.first['abha_id'], hasLength(14));
    });
  });

  group('LoginResponse JSON round-trip', () {
    test('encode/decode preserves fields', () {
      const resp = LoginResponse(
        status: 'ok',
        userId: 'doctor_001',
        fullName: 'Dr. Rajesh Gupta',
        role: UserRole.doctor,
        abhaId: null,
        token: 'nvltok_test',
      );
      final json = jsonDecode(jsonEncode({
        'status': resp.status,
        'user_id': resp.userId,
        'full_name': resp.fullName,
        'role': userRoleToJson(resp.role),
        'abha_id': resp.abhaId,
        'token': resp.token,
      }));
      final decoded = LoginResponse.fromJson(json as Map<String, dynamic>);
      expect(decoded.userId, resp.userId);
      expect(decoded.role, UserRole.doctor);
    });
  });

  group('ReportItem type icon mapping', () {
    test('report_type enum values', () {
      expect(userRoleToJson(UserRole.doctor), 'doctor');
      expect(userRoleToJson(UserRole.patient), 'patient');
      expect(userRoleToJson(UserRole.labTech), 'lab_tech');
      expect(userRoleFromJson('doctor'), UserRole.doctor);
      expect(userRoleFromJson('patient'), UserRole.patient);
      expect(userRoleFromJson('lab_tech'), UserRole.labTech);
    });
  });
}
