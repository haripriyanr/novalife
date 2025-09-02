import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
    }
  }

  static Future<String?> uploadProfileImage(String localFilePath) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final file = File(localFilePath);
      final fileExtension = localFilePath.split('.').last;
      final fileName = '${user.id}/avatar.$fileExtension';

      // ✅ Fixed: Removed unused uploadedPath variable
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        await _supabase.storage
            .from('avatars')
            .uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
          ),
        );
      } else {
        await _supabase.storage
            .from('avatars')
            .upload(
          fileName,
          file,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
          ),
        );
      }

      final publicUrl = _supabase.storage
          .from('avatars')
          .getPublicUrl(fileName);

      await updateProfile({'avatar_url': publicUrl});

      return publicUrl;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  static Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase
          .from('profiles')
          .upsert({
        'id': user.id,
        'updated_at': DateTime.now().toIso8601String(),
        ...data,
      });

      return true;
    } catch (e) {
      debugPrint('Profile update error: $e');
      return false;
    }
  }

  static Future<bool> updateEmail(String newEmail) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(email: newEmail),
      );

      return response.user != null;
    } catch (e) {
      debugPrint('Email update error: $e');
      return false;
    }
  }

  static Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      return response.user != null;
    } catch (e) {
      debugPrint('Password change error: $e');
      return false;
    }
  }

  static Future<String?> getUserName() async {
    try {
      final profile = await getCurrentUserProfile();
      if (profile != null && profile['full_name'] != null) {
        return profile['full_name'];
      }

      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_name');
    } catch (e) {
      debugPrint('Error getting user name: $e');
      return null;
    }
  }

  static Future<void> saveUserName(String name) async {
    try {
      await updateProfile({'full_name': name});

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', name);
    } catch (e) {
      debugPrint('Error saving user name: $e');
    }
  }

  static Future<String?> getUserEmail() async {
    try {
      final user = _supabase.auth.currentUser;
      return user?.email;
    } catch (e) {
      debugPrint('Error getting user email: $e');
      return null;
    }
  }

  static Future<String?> getUserAvatar() async {
    try {
      final profile = await getCurrentUserProfile();
      return profile?['avatar_url'];
    } catch (e) {
      debugPrint('Error getting user avatar: $e');
      return null;
    }
  }

  static Future<bool> hasUserAvatar() async {
    final avatarUrl = await getUserAvatar();
    return avatarUrl != null && avatarUrl.isNotEmpty;
  }

  static Future<void> clearUserData() async {
    try {
      await _supabase.auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Error clearing user data: $e');
    }
  }

  static Future<bool> signOut() async {
    try {
      await _supabase.auth.signOut();
      await clearUserData();
      return true;
    } catch (e) {
      debugPrint('Sign out error: $e');
      return false;
    }
  }

  static Future<bool> deleteAccount() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase.from('profiles').delete().eq('id', user.id);

      await _supabase.storage
          .from('avatars')
          .remove(['${user.id}/avatar.jpg', '${user.id}/avatar.png']);

      await signOut();

      return true;
    } catch (e) {
      debugPrint('Account deletion error: $e');
      return false;
    }
  }
}
