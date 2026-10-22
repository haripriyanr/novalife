/// Hub patient/report reads and lab-tech writes against Supabase.
///
/// Every method tries the live database first and falls back to the in-app mock
/// data when offline or unconfigured, so the UI keeps working. Writes (lab tech
/// scan/report rows) have no offline path: they throw, and the caller must say so.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/demo_mode.dart';
import '../main.dart' show hubDb;
import '../models/hub_api_models.dart';
import 'hub_api_service.dart';

class HubPatientsService {
  static SupabaseClient? get _db => hubDb;

  static HubDataException _unavailable(String what) =>
      HubDataException('Cannot load $what: the backend is not reachable. Check the connection and sign in again.');

  /// All patients for pickers and search. Filters out [excludeAbha] and [excludePatientId]
  /// if provided (e.g. to enforce conflict-of-interest prevention).
  /// Throws [HubDataException] when the backend cannot be read (sample data only in demo mode).
  static Future<List<Map<String, dynamic>>> listPatients({
    String? excludeAbha,
    String? excludePatientId,
  }) async {
    final db = _db;
    if (db == null) {
      if (kDemoMode) {
        final all = await HubApiMockClient().getPatients();
        return all.where((p) {
          if (excludeAbha != null && p['abha_id'] == excludeAbha) return false;
          if (excludePatientId != null && p['patient_id'] == excludePatientId) return false;
          return true;
        }).toList();
      }
      throw _unavailable('patients');
    }
    try {
      final rows = await db
          .from('hub_patients')
          .select('patient_id, abha_id, full_name, dob, gender, phone')
          .order('full_name');
      final list = rows
          .map((r) => {
                'patient_id': r['patient_id'],
                'abha_id': r['abha_id'],
                'full_name': r['full_name'],
                'dob': r['dob']?.toString(),
                'gender': r['gender'],
                'phone': r['phone'],
              })
          .toList();
      if (excludeAbha != null || excludePatientId != null) {
        return list.where((p) {
          if (excludeAbha != null && p['abha_id'] == excludeAbha) return false;
          if (excludePatientId != null && p['patient_id'] == excludePatientId) return false;
          return true;
        }).toList();
      }
      return list;
    } catch (_) {
      if (kDemoMode) {
        final all = await HubApiMockClient().getPatients();
        return all.where((p) {
          if (excludeAbha != null && p['abha_id'] == excludeAbha) return false;
          if (excludePatientId != null && p['patient_id'] == excludePatientId) return false;
          return true;
        }).toList();
      }
      throw _unavailable('patients');
    }
  }

  /// Reports for one patient (an empty list is a real answer, not a reason to show sample data).
  static Future<ReportsResponse> reportsFor(
    String patientId, {
    String? patientName,
    String? abhaId,
  }) async {
    final db = _db;
    if (db == null) {
      if (kDemoMode) return HubApiMockClient().getReports(patientId);
      throw _unavailable('reports');
    }
    try {
      final rows = await db
          .from('hub_reports')
          .select(
              'report_id, scan_id, title, body, report_type, created_at, hub_scans(image_path, stego_bytes)')
          .eq('patient_id', patientId)
          .order('created_at', ascending: false);
      return ReportsResponse(
        patientId: patientId,
        abhaId: abhaId,
        reports: rows.map((r) {
          final scan = r['hub_scans'];
          final scanRow = scan is Map<String, dynamic>
              ? scan
              : (scan is List && scan.isNotEmpty ? scan.first as Map<String, dynamic> : null);
          final img = (scanRow?['image_url'] as String?) ?? (scanRow?['image_path'] as String?);
          return ReportItem(
            reportId: r['report_id'] as String,
            scanId: r['scan_id'] as String?,
            title: r['title'] as String,
            body: r['body'] as String?,
            reportType: (r['report_type'] as String?) ?? 'clinical',
            imagePath: img,
            stegoBytes: scanRow?['stego_bytes'] as int?,
            createdAt: r['created_at'].toString(),
          );
        }).toList(),
      );
    } catch (_) {
      if (kDemoMode) return HubApiMockClient().getReports(patientId);
      throw _unavailable('reports');
    }
  }

  /// Resolve the hub patient_id for an ABHA id. Null when unknown.
  static Future<String?> patientIdForAbha(String abha) async {
    final db = _db;
    if (db != null) {
      try {
        final row = await db
            .from('hub_patients')
            .select('patient_id')
            .eq('abha_id', abha.trim())
            .maybeSingle();
        return row?['patient_id'] as String?;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Record a lab-tech upload: one `hub_scans` row plus one `hub_reports` row
  /// for the chosen patient. Requires the lab_tech insert policies (migration
  /// 008). Throws on any failure — the caller reports it.
  static Future<void> recordLabUpload({
    required String patientId,
    required String title,
    required String body,
    required String reportType,
    required String imagePath,
    required int imageBytes,
    required String sha256,
    required String issuedBy,
  }) async {
    final db = _db;
    if (db == null) {
      throw StateError('Backend not configured; cannot record the upload.');
    }
    final scanId =
        'SCN-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    await db.from('hub_scans').insert({
      'scan_id': scanId,
      'patient_id': patientId,
      'sha256': sha256,
      'image_path': imagePath,
      // Column name is legacy (migration 004); it now means the image byte size.
      'stego_bytes': imageBytes,
    });
    await db.from('hub_reports').insert({
      'report_id':
          'RPT-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      'patient_id': patientId,
      'scan_id': scanId,
      'title': title,
      'body': body,
      'report_type': reportType,
    });
  }

  /// Notes on a report.  The table is `hub_doctor_notes` (columns note_id, report_id, user_id, note_text,
  /// created_at); an earlier version queried a table that does not exist and silently showed sample notes.
  static Future<List<DoctorNote>> notesFor(String reportId) async {
    final db = _db;
    if (db == null) {
      if (kDemoMode) return HubApiMockClient().getNotes(reportId);
      throw _unavailable('notes');
    }
    try {
      final rows = await db
          .from('hub_doctor_notes')
          .select('note_id, report_id, user_id, note_text, created_at')
          .eq('report_id', reportId)
          .order('created_at', ascending: true);
      return rows
          .map((r) => DoctorNote(
                noteId: r['note_id'] as String,
                reportId: r['report_id'] as String,
                userId: r['user_id'] as String,
                doctorName: r['user_id'] as String,
                noteText: r['note_text'] as String,
                createdAt: r['created_at'].toString(),
              ))
          .toList();
    } catch (_) {
      if (kDemoMode) return HubApiMockClient().getNotes(reportId);
      throw _unavailable('notes');
    }
  }

  /// The hub user id of the signed-in person (from `hub_identity_links`), or null when the account is not linked.
  static Future<String?> currentHubUserId() async {
    final db = _db;
    if (db == null) return null;
    try {
      final row = await db.from('hub_identity_links').select('hub_user_id').maybeSingle();
      return row?['hub_user_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Save a note.  Throws [HubDataException] when it could not be saved: a note must never look
  /// saved when it was not.
  static Future<void> addNote({
    required String reportId,
    required String noteText,
    String? authorId,
  }) async {
    final db = _db;
    if (db == null) {
      if (kDemoMode) {
        await HubApiMockClient().addNote(
            reportId: reportId, userId: authorId ?? 'doctor_001', noteText: noteText);
        return;
      }
      throw const HubDataException('The note was NOT saved: the backend is not reachable.');
    }
    final author = authorId ?? await currentHubUserId();
    if (author == null) {
      throw const HubDataException(
          'The note was NOT saved: this account is not linked to a hospital user.');
    }
    final noteId = 'NOTE-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    try {
      await db.from('hub_doctor_notes').insert({
        'note_id': noteId,
        'report_id': reportId,
        'user_id': author,
        'note_text': noteText,
      });
    } catch (e) {
      throw HubDataException('The note was NOT saved: $e');
    }
  }
}
