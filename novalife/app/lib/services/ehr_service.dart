// lib/services/ehr_service.dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class EHRService {
  static final _supabase = Supabase.instance.client;

  static Future<List<String>> listUserReportPaths() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final storage = _supabase.storage.from('medical-reports');
    final root = user.id;

    Future<List<String>> walk(String path) async {
      final entries = await storage.list(path: path);
      final out = <String>[];
      for (final e in entries) {
        final looksLikeFile = e.metadata != null;
        if (looksLikeFile) {
          out.add('$path/${e.name}');
        } else {
          final sub = await storage.list(path: '$path/${e.name}');
          if (sub.isNotEmpty) {
            out.addAll(await walk('$path/${e.name}'));
          } else {
            out.add('$path/${e.name}');
          }
        }
      }
      return out;
    }

    return await walk(root);
  }

  static String getPublicUrlForPath(String fullPath) {
    return _supabase.storage.from('medical-reports').getPublicUrl(fullPath);
  }

  static Future<String> getSignedUrlForPath(String fullPath, {int expiresInSeconds = 900}) async {
    return await _supabase.storage.from('medical-reports').createSignedUrl(fullPath, expiresInSeconds);
  }

  static Future<Uint8List> downloadReportByPath(String fullPath) async {
    return await _supabase.storage.from('medical-reports').download(fullPath);
  }

  // NEW: Upload helper
  // In EHRService class
  static Future<String> uploadReportBytes({
    required String fullPath,
    required Uint8List bytes,
    bool upsert = true,
  }) async {
    await _supabase.storage.from('medical-reports').uploadBinary(
      fullPath,
      bytes,
      fileOptions: const FileOptions(
        contentType: 'image/png',
        upsert: true,
      ),
    );
    return fullPath;
  }

}
