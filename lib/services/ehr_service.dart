// lib/services/ehr_service.dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class EHRService {
  static final _supabase = Supabase.instance.client;

  // Recursively list all file paths under medical-reports/<userId>/
  static Future<List<String>> listUserReportPaths() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final storage = _supabase.storage.from('medical-reports');
    final root = user.id;

    Future<List<String>> walk(String path) async {
      final entries = await storage.list(path: path);
      final out = <String>[];

      for (final e in entries) {
        // Heuristic: if metadata is null, treat as folder; if not null, treat as file
        // Some SDK versions only return files at this level; if you see folders, recurse.
        final looksLikeFile = e.metadata != null; // common for files
        if (looksLikeFile) {
          out.add('$path/${e.name}');
        } else {
          // Might be a directory; try to recurse
          final sub = await storage.list(path: '$path/${e.name}');
          final couldBeDir = sub.isNotEmpty;
          if (couldBeDir) {
            out.addAll(await walk('$path/${e.name}'));
          } else {
            // If it wasn't a dir, assume file anyway
            out.add('$path/${e.name}');
          }
        }
      }
      return out;
    }

    // Start at the user UUID folder
    return await walk(root);
  } // Uses list() to enumerate paths under a prefix [1]

  // Public URL for public buckets (expects full path, e.g., '<uuid>/file.png')
  static String getPublicUrlForPath(String fullPath) {
    return _supabase.storage.from('medical-reports').getPublicUrl(fullPath);
  } // Public URL helper for public buckets [4]

  // Signed URL for private buckets (expects full path, e.g., '<uuid>/file.png')
  static Future<String> getSignedUrlForPath(String fullPath, {int expiresInSeconds = 900}) async {
    return await _supabase.storage.from('medical-reports').createSignedUrl(fullPath, expiresInSeconds);
  } // Signed URL helper for private buckets [5]

  // Optional: download bytes for a single file path
  static Future<Uint8List> downloadReportByPath(String fullPath) async {
    return await _supabase.storage.from('medical-reports').download(fullPath);
  } // Download API for a specific object path [6]
}
