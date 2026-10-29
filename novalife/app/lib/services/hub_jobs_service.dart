/// Cloud relay client: queue a job for the FPGA board and wait for its result.
///
/// The app never talks to the board directly (so it works from any network). It inserts a row in
/// `hub_jobs`; the board claims the oldest queued job over an outbound connection, runs it in the
/// PL and writes the result back (supabase/migrations/010_hub_job_queue.sql). Jobs are served first
/// come, first served, one at a time, so a second user's job simply shows `queued` until the first
/// is done. There is no offline path: without the database a job cannot be queued, and this says so.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart' show hubDb;

enum HubJobStatus { queued, running, done, failed }

class HubJob {
  final String id;
  final String? authUid;
  final String kind;
  final String? imagePath;
  final HubJobStatus status;
  final Map<String, dynamic>? result;
  final String? error;
  final DateTime createdAt;

  const HubJob({
    required this.id,
    this.authUid,
    required this.kind,
    this.imagePath,
    required this.status,
    required this.createdAt,
    this.result,
    this.error,
  });

  /// `pass`, `fail`, `revoked`, `unknown` for a verify job once done; null otherwise.
  String? get verdict => result?['verdict'] as String?;
  bool get finished => status == HubJobStatus.done || status == HubJobStatus.failed;

  /// Path in `hub-jobs` storage bucket where the marked PNG is uploaded for mark_image jobs
  String get markedResultPath =>
      (result?['result_image_path'] as String?) ??
      (authUid != null ? '$authUid/results/$id.png' : '');

  factory HubJob.fromRow(Map<String, dynamic> r) => HubJob(
        id: r['job_id'] as String,
        authUid: r['auth_uid'] as String?,
        kind: r['kind'] as String,
        imagePath: r['image_path'] as String?,
        status: HubJobStatus.values.firstWhere(
          (s) => s.name == r['status'],
          orElse: () => HubJobStatus.failed,
        ),
        result: (r['result'] as Map?)?.cast<String, dynamic>(),
        error: r['error'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}

class HubJobsException implements Exception {
  final String message;
  HubJobsException(this.message);
  @override
  String toString() => message;
}

class HubJobsService {
  static SupabaseClient get _db {
    final db = hubDb;
    if (db == null) throw HubJobsException('Database not configured: cannot queue a job.');
    return db;
  }

  /// Queue a tag check: the PL verifies the MAC of [version]/[hubId]/[handleHex]/[tagHex], then the
  /// server checks the handle (exists, not revoked) and writes the audit row.
  static Future<HubJob> submitVerifyTag({
    required int version,
    required int hubId,
    required String handleHex,
    required String tagHex,
  }) =>
      _insert('verify_tag', {
        'v': version,
        'hub': hubId,
        'handle': handleHex,
        'tag': tagHex,
      });

  /// Queue an image watermark verification: board downloads scan from hub-jobs, runs RPP-QIM extraction,
  /// verifies tag in PL enclave, and records audit row.
  static Future<HubJob> submitVerifyImage({
    required String imagePath,
    Map<String, dynamic>? payload,
  }) =>
      _insert('verify_image', payload ?? {}, imagePath: imagePath);

  /// Queue an image watermarking job: board downloads scan, embeds 128-bit payload, uploads marked PNG to
  /// `hub-jobs/<auth_uid>/results/<job_id>.png`.
  static Future<HubJob> submitMarkImage({
    required String imagePath,
    Map<String, dynamic>? payload,
  }) =>
      _insert('mark_image', payload ?? {}, imagePath: imagePath);

  /// Helper to upload a scan file to private bucket 'hub-jobs' at `<auth_uid>/scans/<filename>`
  static Future<String> uploadJobScan(Uint8List bytes, String filename) async {
    final user = _db.auth.currentUser;
    if (user == null) throw HubJobsException('Not authenticated');
    final path = '${user.id}/scans/$filename';
    await _db.storage.from('hub-jobs').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/png'),
        );
    return path;
  }

  static Future<HubJob> _insert(String kind, Map<String, dynamic> payload,
      {String? imagePath}) async {
    try {
      final row = await _db
          .from('hub_jobs')
          .insert({'kind': kind, 'payload': payload, 'image_path': ?imagePath})
          .select()
          .single();
      return HubJob.fromRow(row);
    } on PostgrestException catch (e) {
      // the insert policy refuses a sixth active job for the same user
      throw HubJobsException(e.code == '42501'
          ? 'Too many jobs waiting (limit 5). Wait for one to finish.'
          : 'Could not queue the job: ${e.message}');
    }
  }

  /// The signed-in user's most recent jobs (RLS shows only their own), newest first.
  static Future<List<HubJob>> recentJobs({int limit = 10}) async {
    final rows = await _db.from('hub_jobs').select().order('created_at', ascending: false).limit(limit);
    return rows.map<HubJob>((r) => HubJob.fromRow(r)).toList();
  }

  static Future<HubJob> fetch(String jobId) async {
    final row = await _db.from('hub_jobs').select().eq('job_id', jobId).single();
    return HubJob.fromRow(row);
  }

  /// Number of jobs ahead of [job] in the queue (its position, 0 = next or running).
  static Future<int> queuePosition(HubJob job) async {
    if (job.status != HubJobStatus.queued) return 0;
    final rows = await _db
        .from('hub_jobs')
        .select('job_id')
        .eq('status', 'queued')
        .lt('created_at', job.createdAt.toUtc().toIso8601String());
    // RLS shows only the caller's own jobs, so this under-counts other users' jobs: it is a
    // lower bound, labelled as such in the UI.
    return rows.length;
  }

  /// Poll until the job finishes or [timeout] passes; [onUpdate] sees every state change.
  static Future<HubJob> waitFor(
    HubJob job, {
    Duration every = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
    void Function(HubJob)? onUpdate,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var current = job;
    while (!current.finished) {
      if (DateTime.now().isAfter(deadline)) {
        throw HubJobsException('The board did not answer in time (job ${job.id} is still ${current.status.name}).');
      }
      await Future<void>.delayed(every);
      final next = await fetch(job.id);
      if (next.status != current.status) onUpdate?.call(next);
      current = next;
    }
    return current;
  }
}
