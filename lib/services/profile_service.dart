import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static final _supabase = Supabase.instance.client;

  static User? get currentUser => _supabase.auth.currentUser;

  // Read display name from auth.users user_metadata
  static Future<String?> getDisplayName() async {
    try {
      await _supabase.auth.getUser(); // refresh cache if needed
    } catch (_) {}
    final user = _supabase.auth.currentUser;
    return user?.userMetadata?['full_name'] as String?;
  }

  // Save display name into auth.users user_metadata
  static Future<void> saveDisplayName(String name) async {
    final res = await _supabase.auth.updateUser(
      UserAttributes(data: {'full_name': name}),
    );
    if (res.user == null) {
      throw Exception('Failed to update display name');
    }
  }

  // Read email from auth.users
  static Future<String?> getUserEmail() async {
    try {
      await _supabase.auth.getUser();
    } catch (_) {}
    return _supabase.auth.currentUser?.email;
  }

  // Read avatar URL from auth.users user_metadata
  static Future<String?> getAvatarUrl() async {
    try {
      await _supabase.auth.getUser();
    } catch (_) {}
    final user = _supabase.auth.currentUser;
    return user?.userMetadata?['avatar_url'] as String?;
  }

  // Upload avatar to a fixed path, overwrite (upsert), and update user_metadata with cache-busted URL
  static Future<String> uploadAvatarFixed({
    required String imagePath,
    String bucket = 'avatars',
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }

    // Fixed canonical path to always overwrite the same file
    final objectPath = '${user.id}/avatar.jpg';

    // Overwrite existing file
    await _supabase.storage
        .from(bucket)
        .upload(
      objectPath,
      file,
      fileOptions: const FileOptions(
        upsert: true, // required to overwrite
        cacheControl: '3600',
      ),
    );

    // Public URL + cache-buster to avoid stale CDN content
    final publicUrl = _supabase.storage.from(bucket).getPublicUrl(objectPath);
    final bustedUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

    final res = await _supabase.auth.updateUser(
      UserAttributes(data: {'avatar_url': bustedUrl}),
    );
    if (res.user == null) {
      throw Exception('Failed to update avatar URL metadata');
    }

    return bustedUrl;
  }

  // Optional: remove any stray files under the user folder except avatar.jpg (requires DELETE policy)
  static Future<void> cleanupOldAvatars({String bucket = 'avatars'}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final folder = user.id;

    // list API: supply the folder prefix
    final items = await _supabase.storage.from(bucket).list(path: folder);
    if (items.isEmpty) return;

    final toRemove = <String>[];
    for (final item in items) {
      // keep the canonical name
      if (item.name != 'avatar.jpg') {
        toRemove.add('$folder/${item.name}');
      }
    }
    if (toRemove.isNotEmpty) {
      await _supabase.storage.from(bucket).remove(toRemove);
    }
  }

  // Update email/password via auth API
  static Future<void> updateEmail(String newEmail) async {
    final res = await _supabase.auth.updateUser(
      UserAttributes(email: newEmail),
    );
    if (res.user == null) {
      throw Exception('Failed to update email');
    }
  }

  static Future<void> updatePassword(String newPassword) async {
    final res = await _supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    if (res.user == null) {
      throw Exception('Failed to update password');
    }
  }
}
