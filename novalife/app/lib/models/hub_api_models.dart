/// API contract models for the NovaLife HUB Phase 8 integration.
///
/// These mirror the response shapes in novalife_hub/docs/hub_http_api.md (part 2, proposed).
library;

import 'dart:convert';

/// Roles supported by the HUB authentication system.
enum UserRole { patient, doctor, labTech }

String userRoleToJson(UserRole r) => switch (r) {
      UserRole.patient => 'patient',
      UserRole.doctor => 'doctor',
      UserRole.labTech => 'lab_tech',
    };

UserRole userRoleFromJson(String s) => switch (s) {
      'patient' => UserRole.patient,
      'doctor' => UserRole.doctor,
      'lab_tech' => UserRole.labTech,
      _ => throw ArgumentError('Unknown role: $s'),
    };

/// Login request body for GET /login.
class LoginRequest {
  final String userId;
  final String password;
  const LoginRequest({required this.userId, required this.password});

  Map<String, dynamic> toJson() => {'user_id': userId, 'password': password};
  String encode() => jsonEncode(toJson());
}

/// Login response from GET /login.
class LoginResponse {
  final String status;
  final String userId;
  final String fullName;
  final UserRole role;
  final String? abhaId;
  final String? token;

  const LoginResponse({
    required this.status,
    required this.userId,
    required this.fullName,
    required this.role,
    this.abhaId,
    this.token,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> j) => LoginResponse(
        status: j['status'] as String,
        userId: j['user_id'] as String,
        fullName: j['full_name'] as String,
        role: userRoleFromJson(j['role'] as String),
        abhaId: j['abha_id'] as String?,
        token: j['token'] as String?,
      );

  factory LoginResponse.decode(String s) =>
      LoginResponse.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Report item returned inside GET /reports/{patient_id}.
class ReportItem {
  final String reportId;
  final String? scanId;
  final String title;
  final String? body;
  final String reportType;
  final String? imagePath;
  final int? stegoBytes;
  final String createdAt;

  const ReportItem({
    required this.reportId,
    this.scanId,
    required this.title,
    this.body,
    required this.reportType,
    this.imagePath,
    this.stegoBytes,
    required this.createdAt,
  });

  factory ReportItem.fromJson(Map<String, dynamic> j) => ReportItem(
        reportId: j['report_id'] as String,
        scanId: j['scan_id'] as String?,
        title: j['title'] as String,
        body: j['body'] as String?,
        reportType: j['report_type'] as String,
        imagePath: j['image_path'] as String?,
        stegoBytes: j['stego_bytes'] as int?,
        createdAt: j['created_at'] as String,
      );
}

/// GET /reports/{patient_id} response.
class ReportsResponse {
  final String patientId;
  final String? abhaId;
  final List<ReportItem> reports;

  const ReportsResponse({
    required this.patientId,
    this.abhaId,
    required this.reports,
  });

  factory ReportsResponse.fromJson(Map<String, dynamic> j) => ReportsResponse(
        patientId: j['patient_id'] as String,
        abhaId: j['abha_id'] as String?,
        reports: (j['reports'] as List<dynamic>)
            .map((e) => ReportItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// POST /notes request body.
class NoteRequest {
  final String reportId;
  final String userId;
  final String noteText;

  const NoteRequest({
    required this.reportId,
    required this.userId,
    required this.noteText,
  });

  Map<String, dynamic> toJson() => {
        'report_id': reportId,
        'user_id': userId,
        'note_text': noteText,
      };

  String encode() => jsonEncode(toJson());
}

/// POST /notes response.
class NoteResponse {
  final String status;
  final String noteId;
  final String createdAt;

  const NoteResponse({
    required this.status,
    required this.noteId,
    required this.createdAt,
  });

  factory NoteResponse.fromJson(Map<String, dynamic> j) => NoteResponse(
        status: j['status'] as String,
        noteId: j['note_id'] as String,
        createdAt: j['created_at'] as String,
      );
}

/// Doctor note returned in report detail views.
class DoctorNote {
  final String noteId;
  final String reportId;
  final String userId;
  final String noteText;
  final String doctorName;
  final String createdAt;

  const DoctorNote({
    required this.noteId,
    required this.reportId,
    required this.userId,
    required this.noteText,
    required this.doctorName,
    required this.createdAt,
  });

  factory DoctorNote.fromJson(Map<String, dynamic> j) => DoctorNote(
        noteId: j['note_id'] as String,
        reportId: j['report_id'] as String,
        userId: j['user_id'] as String,
        noteText: j['note_text'] as String,
        doctorName: j['doctor_name'] as String? ?? j['user_id'] as String,
        createdAt: j['created_at'] as String,
      );
}
