/// Mock HUB API client for Phase 8 integration.
///
/// Returns the same data shape as the real HUB REST endpoints
/// (see novalife_hub/docs/hub_http_api.md) but from in-memory dictionaries.
/// Used during development and widget testing until firmware is live.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/hub_api_models.dart';

/// In-memory mock store mirroring the SD Vault seed data.
class HubApiMockClient {
  // -- patients -----------------------------------------------------------
  static const _patients = <String, Map<String, dynamic>>{
    'PAT-001': {
      'patient_id': 'PAT-001',
      'abha_id': '12345678901234',
      'full_name': 'Anjali Mehta',
      'dob': '1990-03-15',
      'gender': 'F',
      'phone': '+91-9876543210',
    },
    'PAT-002': {
      'patient_id': 'PAT-002',
      'abha_id': '23456789012345',
      'full_name': 'Dr. Priya Nair',
      'dob': '1985-07-22',
      'gender': 'F',
      'phone': '+91-9876543211',
    },
    'PAT-003': {
      'patient_id': 'PAT-003',
      'abha_id': '34567890123456',
      'full_name': 'Rajesh Sharma',
      'dob': '1988-11-08',
      'gender': 'M',
      'phone': '+91-9876543212',
    },
  };

  // -- users --------------------------------------------------------------
  static const _users = <String, Map<String, dynamic>>{
    'lab_tech_001': {
      'user_id': 'lab_tech_001',
      'password': 'lab@1234',
      'full_name': 'Priya Sharma',
      'role': 'lab_tech',
    },
    'doctor_001': {
      'user_id': 'doctor_001',
      'password': 'doc@1234',
      'full_name': 'Dr. Rajesh Gupta',
      'role': 'doctor',
    },
    'patient_001': {
      'user_id': 'patient_001',
      'password': 'pat@1234',
      'full_name': 'Anjali Mehta',
      'role': 'patient',
    },
  };

  // -- reports ------------------------------------------------------------
  static final _reports = <String, List<Map<String, dynamic>>>{
    'PAT-001': [
      {
        'report_id': 'RPT-001',
        'scan_id': null,
        'title': 'CBC — Complete Blood Count',
        'body': 'Hemoglobin 12.4 g/dL, WBC 7200, Platelets 2.4L. Within normal limits.',
        'report_type': 'lab',
        'image_path': null,
        'stego_bytes': null,
        'created_at': '2026-09-15T10:30:00Z',
      },
      {
        'report_id': 'RPT-002',
        'scan_id': 'SCN-002',
        'title': 'Chest X-Ray PA View',
        'body': 'Clear lung fields. No cardiomegaly. Normal mediastinum.',
        'report_type': 'imaging',
        'image_path': 'scans/PAT-001/scan_002.png',
        'stego_bytes': 1024,
        'created_at': '2026-09-15T11:00:00Z',
      },
    ],
    'PAT-002': [
      {
        'report_id': 'RPT-003',
        'scan_id': null,
        'title': 'Fasting Lipid Panel',
        'body': 'Total cholesterol 210 mg/dL, LDL 140, HDL 38. Borderline high LDL.',
        'report_type': 'lab',
        'image_path': null,
        'stego_bytes': null,
        'created_at': '2026-09-14T09:15:00Z',
      },
      {
        'report_id': 'RPT-004',
        'scan_id': 'SCN-004',
        'title': 'MRI Brain — Contrast Enhanced',
        'body': 'No intracranial mass. Normal ventricles. White matter hyperintensities Fazekas 1.',
        'report_type': 'imaging',
        'image_path': 'scans/PAT-002/scan_004.png',
        'stego_bytes': 256,
        'created_at': '2026-09-13T14:00:00Z',
      },
    ],
    'PAT-003': [
      {
        'report_id': 'RPT-005',
        'scan_id': 'SCN-005',
        'title': 'Renal Function Panel',
        'body': 'Creatinine 1.1 mg/dL, BUN 18, eGFR 72. Mildly reduced GFR stage 2 CKD.',
        'report_type': 'lab',
        'image_path': null,
        'stego_bytes': null,
        'created_at': '2026-09-12T08:00:00Z',
      },
      {
        'report_id': 'RPT-006',
        'scan_id': 'SCN-006',
        'title': 'Right Knee X-Ray — Lateral View',
        'body': 'Mild degenerative joint disease. Joint space narrowing at medial compartment.',
        'report_type': 'imaging',
        'image_path': 'scans/PAT-003/scan_006.png',
        'stego_bytes': 512,
        'created_at': '2026-09-12T09:30:00Z',
      },
    ],
    'PAT-004': [
      {
        'report_id': 'RPT-007',
        'scan_id': null,
        'title': 'HbA1c — Diabetes Screen',
        'body': 'HbA1c 6.8%. Pre-diabetic range. Recommend lifestyle modification.',
        'report_type': 'lab',
        'image_path': null,
        'stego_bytes': null,
        'created_at': '2026-09-11T12:00:00Z',
      },
    ],
    'PAT-005': [
      {
        'report_id': 'RPT-009',
        'scan_id': null,
        'title': 'Thyroid Profile',
        'body': 'TSH 2.4 mIU/L, Free T4 1.1 ng/dL. Normal thyroid function.',
        'report_type': 'lab',
        'image_path': null,
        'stego_bytes': null,
        'created_at': '2026-09-10T16:00:00Z',
      },
    ],
  };

  // -- doctor notes (mutable) ---------------------------------------------
  final _notes = <String, List<Map<String, dynamic>>>{
    'RPT-001': [
      {
        'note_id': 'NT-001',
        'report_id': 'RPT-001',
        'user_id': 'doctor_001',
        'note_text': 'Values normal. No follow-up needed unless symptomatic.',
        'doctor_name': 'Dr. Rajesh Gupta',
        'created_at': '2026-09-15T11:30:00Z',
      },
    ],
    'RPT-003': [
      {
        'note_id': 'NT-003',
        'report_id': 'RPT-003',
        'user_id': 'doctor_001',
        'note_text': 'LDL elevated. Start statin therapy if no contraindication. Recheck in 3 months.',
        'doctor_name': 'Dr. Rajesh Gupta',
        'created_at': '2026-09-14T10:00:00Z',
      },
    ],
  };

  int _noteCounter = 6;

  // -- public API ---------------------------------------------------------

  /// GET /login
  Future<LoginResponse> login(String userId, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final u = _users[userId];
    if (u == null || u['password'] != password) {
      throw HubApiException(401, 'Invalid credentials');
    }
    final patientEntry = _patients.values.where(
      (p) => p['full_name'] == u['full_name'],
    );
    final abhaId =
        patientEntry.isNotEmpty ? patientEntry.first['abha_id'] as String : null;
    return LoginResponse(
      status: 'ok',
      userId: u['user_id'] as String,
      fullName: u['full_name'] as String,
      role: userRoleFromJson(u['role'] as String),
      abhaId: abhaId,
      token: 'nvltok_mock_${u['user_id']}',
    );
  }

  /// GET /reports/{patientId}
  Future<ReportsResponse> getReports(String patientId) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final p = _patients[patientId];
    if (p == null) throw HubApiException(404, 'Patient not found');
    final items = _reports[patientId] ?? [];
    return ReportsResponse(
      patientId: patientId,
      abhaId: p['abha_id'] as String,
      reports: items.map((j) => ReportItem.fromJson(j)).toList(),
    );
  }

  /// GET /patients  (list all — used by the patient list screen)
  Future<List<Map<String, dynamic>>> getPatients() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return _patients.values.toList();
  }

  /// POST /notes
  Future<NoteResponse> addNote({
    required String reportId,
    required String userId,
    required String noteText,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final noteId = 'NT-${(_noteCounter++).toString().padLeft(3, '0')}';
    final now = DateTime.now().toUtc().toIso8601String();
    _notes.putIfAbsent(reportId, () => []);
    _notes[reportId]!.add({
      'note_id': noteId,
      'report_id': reportId,
      'user_id': userId,
      'note_text': noteText,
      'doctor_name': _users[userId]?['full_name'] ?? userId,
      'created_at': now,
    });
    return NoteResponse(status: 'created', noteId: noteId, createdAt: now);
  }

  /// GET /notes/{reportId}
  Future<List<DoctorNote>> getNotes(String reportId) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final items = _notes[reportId] ?? [];
    return items.map((j) => DoctorNote.fromJson(j)).toList();
  }
}

class HubApiException implements Exception {
  final int code;
  final String message;
  HubApiException(this.code, this.message);
  @override
  String toString() => 'HubApiException($code): $message';
}

/// Real board client — talks to the Zynq board's HTTP surface at
/// 192.168.31.86:8080. The board no longer embeds anything; marking and
/// verification run in the PL enclave (`docs/system_architecture.md`).
class HubApiBoardClient {
  /// Board LAN address; there is no built-in default: the app talks to the board through the cloud queue.
  final String boardIp;
  HubApiBoardClient({required this.boardIp});

  String get base => 'http://$boardIp:8080';

  Future<LoginResponse> login(String userId, String password) async {
    final res = await http.post(Uri.parse('$base/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'password': password}));
    if (res.statusCode != 200) throw HubApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (j['status'] != 'ok') throw HubApiException(401, j['msg'] ?? 'Invalid credentials');
    // board returns ok with user_id/role/abha_id — map to LoginResponse
    return LoginResponse(
      status: 'ok',
      userId: j['user_id'] as String? ?? userId,
      fullName: j['user_id'] as String? ?? userId,
      role: userRoleFromJson(j['role'] as String? ?? 'patient'),
      abhaId: j['abha_id'] as String?,
      token: 'board_${j['user_id']}',
    );
  }

  Future<LoginResponse> signup(
      String userId, String password, String abhaId) async {
    final res = await http.post(Uri.parse('$base/auth/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'password': password,
          'abha_id': abhaId,
          'role': 'patient'
        }));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (j['status'] != 'ok') throw HubApiException(res.statusCode, j['msg'] ?? 'Signup failed');
    return LoginResponse(
        status: 'ok',
        userId: userId,
        fullName: userId,
        role: UserRole.patient,
        abhaId: abhaId,
        token: 'board_$userId');
  }
}

/// Client for the NovaLife gateway API (docs/hub_http_api.md, Part 2).
///
/// This is the *real* client shape: it talks to the gateway over HTTP, sends an
/// image, and the gateway extracts the tag, asks the enclave to verify it, and
/// decides.  The app never decides anything itself.
///
/// The reference gateway implementation lives in
/// `novalife_hub/gateway/gateway.py`; run it with
/// `.venv/bin/python novalife_hub/gateway/gateway.py --port 8080`.
class HubGatewayClient {
  /// Address of a LAN gateway (development only); there is no built-in default.
  final String host;
  final int port;

  HubGatewayClient({required this.host, this.port = 8080});

  String get base => 'http://$host:$port';

  /// Liveness probe.
  Future<Map<String, dynamic>> status() async {
    final res = await http.get(Uri.parse('$base/status'));
    if (res.statusCode != 200) throw HubApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Verify an image: the gateway extracts the tag and checks the handle.
  /// Returns `{ok: bool, reason: String, handle?: String}`.
  Future<Map<String, dynamic>> verifyImage(Uint8List imageBytes) async {
    final res = await http.post(
      Uri.parse('$base/api/v1/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'image_b64': base64Encode(imageBytes)}),
    );
    // 403/404 are legitimate answers from the gateway, not transport errors.
    final j = res.statusCode == 200
        ? jsonDecode(res.body) as Map<String, dynamic>
        : <String, dynamic>{'ok': false, 'reason': 'HTTP ${res.statusCode}'};
    return j;
  }

  /// Fetch the record view allowed for the caller's role and consent.
  Future<Map<String, dynamic>> fetchRecord(String handle) async {
    final res = await http.post(
      Uri.parse('$base/api/v1/records'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'handle': handle}),
    );
    if (res.statusCode != 200) {
      throw HubApiException(res.statusCode, res.body);
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['record_view'] as Map<String, dynamic>;
  }

  /// Submit a record (lab tech).
  Future<String> submit({
    required String title,
    required String body,
    Uint8List? imageBytes,
  }) async {
    final res = await http.post(
      Uri.parse('$base/api/v1/submit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'body': body,
        if (imageBytes != null) 'image_b64': base64Encode(imageBytes),
      }),
    );
    if (res.statusCode != 200) throw HubApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['handle'] as String;
  }
}
