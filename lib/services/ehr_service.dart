// lib/services/ehr_service.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Storage for encrypted records in the private `medical-reports` bucket.
///
/// Layout, one folder per user:
/// - `{uid}/vault.key`: the wrapped vault key (see VaultService)
/// - `{uid}/rec_{ms}.nlr`: one encrypted record each
/// - `{uid}/ehr_{ms}.png`: legacy records, moved into the vault on first unlock
///
/// Everything here is ciphertext. The bucket must still be private, with row-level policies
/// limiting each user to their own folder (see supabase/storage_policies.sql). No public URLs.
class EHRService {
  EHRService._();

  static const _bucket = 'medical-reports';
  static StorageFileApi get _storage => Supabase.instance.client.storage.from(_bucket);

  static String _vaultKeyPath(String uid) => '$uid/vault.key';

  static String newRecordPath(String uid, DateTime at) => '$uid/rec_${at.millisecondsSinceEpoch}.nlr';

  /// Record creation time, read from the file name, so the list can show dates without
  /// downloading and decrypting every record.
  static DateTime? dateFromPath(String path) {
    final m = RegExp(r'_(\d{10,})\.(nlr|png)$').firstMatch(path);
    return m == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(1)!));
  }

  static Future<List<String>> _listNames() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');
    final entries = await _storage.list(path: uid);
    return [for (final e in entries) if (e.metadata != null) '$uid/${e.name}'];
  }

  /// Vault records, newest first.
  static Future<List<String>> listRecordPaths() async {
    final paths = (await _listNames()).where((p) => p.endsWith('.nlr')).toList();
    paths.sort((a, b) => (dateFromPath(b) ?? DateTime(0)).compareTo(dateFromPath(a) ?? DateTime(0)));
    return paths;
  }

  static Future<List<String>> listLegacyPaths() async =>
      (await _listNames()).where((p) => p.endsWith('.png')).toList();

  static Future<Uint8List> download(String path) => _storage.download(path);

  static Future<void> upload(String path, Uint8List bytes) async {
    await _storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'application/octet-stream', upsert: false),
    );
  }

  static Future<void> delete(String path) async {
    await _storage.remove([path]);
  }

  static Future<Uint8List?> downloadVaultKey(String uid) async {
    try {
      return await _storage.download(_vaultKeyPath(uid));
    } on StorageException catch (e) {
      final code = e.statusCode;
      if (code == '404' || code == '400' || e.message.toLowerCase().contains('not found')) return null;
      rethrow;
    }
  }

  static Future<void> uploadVaultKey(String uid, Uint8List wrapped) async {
    await _storage.uploadBinary(
      _vaultKeyPath(uid),
      wrapped,
      fileOptions: const FileOptions(contentType: 'application/json', upsert: false),
    );
  }
}
