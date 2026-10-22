import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static final _supabase = Supabase.instance.client;

  static User? get currentUser => _supabase.auth.currentUser;

  // Read display name from auth.users user_metadata (with Hub fallback)
  static Future<String?> getDisplayName() async {
    try {
      await _supabase.auth.getUser(); // refresh cache if needed
    } catch (_) {}
    final user = _supabase.auth.currentUser;
    final meta = user?.userMetadata?['full_name'] as String?;
    if (meta != null && meta.trim().isNotEmpty) return meta;
    // Fallback to Hub local session (for offline Hub mock, now deprecated)
    try {
      final prefs = await SharedPreferences.getInstance();
      final hubName = prefs.getString('hub_user_full_name');
      if (hubName != null && hubName.trim().isNotEmpty) return hubName;
      final hubId = prefs.getString('hub_user_id');
      if (hubId != null) return hubId;
    } catch (_) {}
    return null;
  }

  // Save display name into auth.users user_metadata (and hub fallback)
  static Future<void> saveDisplayName(String name) async {
    // Also persist to Hub local session for RoleLogin users
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hub_user_full_name', name);
    } catch (_) {}
    final user = _supabase.auth.currentUser;
    if (user == null) return; // Hub-only login, keep local only
    final res = await _supabase.auth.updateUser(
      UserAttributes(data: {'full_name': name}),
    );
    if (res.user == null) {
      throw Exception('Failed to update display name');
    }
  }

  // Read email from auth.users (real Supabase online)
  static Future<String?> getUserEmail() async {
    try {
      await _supabase.auth.getUser();
    } catch (_) {}
    final email = _supabase.auth.currentUser?.email;
    if (email != null && email.trim().isNotEmpty) return email;
    // Fallback to Hub local session for offline demo (synthetic userId@novalife.app)
    try {
      final prefs = await SharedPreferences.getInstance();
      final hubEmail = prefs.getString('hub_user_email');
      if (hubEmail != null && hubEmail.trim().isNotEmpty) return hubEmail;
    } catch (_) {}
    return null;
  }

  // Persist Hub session for offline fallback (called from RoleLogin, now optional)
  static Future<void> saveHubSession({required String userId, required String fullName, String? email}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hub_user_id', userId);
      await prefs.setString('hub_user_full_name', fullName);
      await prefs.setString('hub_user_email', email ?? '$userId@novalife.app');
    } catch (_) {}
  }

  static Future<void> clearHubSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('hub_user_id');
      await prefs.remove('hub_user_full_name');
      await prefs.remove('hub_user_email');
    } catch (_) {}
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

  static Future<void> clearAvatarUrl() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase.auth.updateUser(
      UserAttributes(data: {'avatar_url': null}),
    );
  }
}
