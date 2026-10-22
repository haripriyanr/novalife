import 'package:flutter_test/flutter_test.dart';
import 'package:novalife/services/hub_jobs_service.dart';

void main() {
  group('HubJob model', () {
    test('parses queued row correctly', () {
      final row = {
        'job_id': 'job-1234',
        'kind': 'verify_tag',
        'status': 'queued',
        'created_at': '2026-10-22T10:00:00.000Z',
        'result': null,
        'error': null,
      };
      final job = HubJob.fromRow(row);
      expect(job.id, 'job-1234');
      expect(job.kind, 'verify_tag');
      expect(job.status, HubJobStatus.queued);
      expect(job.finished, isFalse);
      expect(job.verdict, isNull);
    });

    test('parses done row with verdict correctly', () {
      final row = {
        'job_id': 'job-5678',
        'kind': 'verify_tag',
        'status': 'done',
        'created_at': '2026-10-22T10:00:00.000Z',
        'result': {
          'ok': true,
          'verdict': 'unknown',
          'reason': 'genuine tag, handle not in the registry',
          'pl_cycles': 119,
        },
        'error': null,
      };
      final job = HubJob.fromRow(row);
      expect(job.id, 'job-5678');
      expect(job.status, HubJobStatus.done);
      expect(job.finished, isTrue);
      expect(job.verdict, 'unknown');
      expect(job.result?['pl_cycles'], 119);
    });

    test('parses failed row with error message', () {
      final row = {
        'job_id': 'job-9999',
        'kind': 'mark_image',
        'status': 'failed',
        'created_at': '2026-10-22T10:00:00.000Z',
        'result': null,
        'error': 'device timeout',
      };
      final job = HubJob.fromRow(row);
      expect(job.id, 'job-9999');
      expect(job.status, HubJobStatus.failed);
      expect(job.finished, isTrue);
      expect(job.error, 'device timeout');
    });
  });
}
