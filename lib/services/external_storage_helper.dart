import 'dart:io';
import 'package:external_path/external_path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class ExternalStorageHelper {
  /// Request storage permissions
  static Future<bool> requestStoragePermissions() async {
    try {
      // Check Android version
      if (Platform.isAndroid) {
        // For Android 13+ (API 33+), we need different permissions
        if (await _isAndroid13OrAbove()) {
          return await _requestAndroid13Permissions();
        } else {
          return await _requestLegacyPermissions();
        }
      }
      return true; // iOS doesn't need external storage permissions
    } catch (e) {
      debugPrint('Error requesting storage permissions: $e');
      return false;
    }
  }

  /// Check if Android 13 or above
  static Future<bool> _isAndroid13OrAbove() async {
    // This is a simplified check - in production you might want to use
    // device_info_plus to get exact Android version
    return true; // Assume modern Android for safety
  }

  /// Request permissions for Android 13+
  static Future<bool> _requestAndroid13Permissions() async {
    // For Android 13+, MANAGE_EXTERNAL_STORAGE is needed for full access
    final manageStorage = await Permission.manageExternalStorage.request();

    if (manageStorage.isGranted) {
      return true;
    }

    // Fallback to basic storage permissions
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  /// Request legacy storage permissions
  static Future<bool> _requestLegacyPermissions() async {
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  /// Get external Downloads directory path
  static Future<String?> getDownloadsDirectory() async {
    try {
      final downloadsPath = await ExternalPath.getExternalStoragePublicDirectory(
          ExternalPath.DIRECTORY_DOWNLOAD
      );
      return downloadsPath; // e.g., /storage/emulated/0/Download
    } catch (e) {
      debugPrint('Error getting downloads directory: $e');
      return null;
    }
  }

  /// Get custom app folder in external storage
  static Future<String> getAppExternalDirectory() async {
    try {
      // Try to get Downloads directory first
      final downloadsDir = await getDownloadsDirectory();

      if (downloadsDir != null) {
        // Create NovaLife folder in Downloads
        final appDir = Directory('$downloadsDir/NovaLife');
        if (!await appDir.exists()) {
          await appDir.create(recursive: true);
        }
        return appDir.path;
      }
    } catch (e) {
      debugPrint('Error creating external app directory: $e');
    }

    // Fallback to app's external storage directory
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final appDir = Directory('${externalDir.path}/novalife');
        if (!await appDir.exists()) {
          await appDir.create(recursive: true);
        }
        return appDir.path;
      }
    } catch (e) {
      debugPrint('Error with external storage directory: $e');
    }

    // Final fallback to app documents directory
    final appDocDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory('${appDocDir.path}/novalife');
    if (!await fallbackDir.exists()) {
      await fallbackDir.create(recursive: true);
    }
    return fallbackDir.path;
  }

  /// Get the complete path for model file
  static Future<String> getModelFilePath() async {
    final appDir = await getAppExternalDirectory();
    return '$appDir/medgemma-4b-it-Q4_K_M.gguf';
  }

  /// Check if we have storage permissions
  static Future<bool> hasStoragePermissions() async {
    if (Platform.isAndroid) {
      final manageStorage = await Permission.manageExternalStorage.status;
      if (manageStorage.isGranted) return true;

      final storage = await Permission.storage.status;
      return storage.isGranted;
    }
    return true;
  }

  /// Get human-readable storage location
  static Future<String> getStorageLocationDescription() async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        return 'Downloads/NovaLife/';
      }

      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return 'External Storage/novalife/';
      }

      return 'App Storage/novalife/';
    } catch (e) {
      return 'Device Storage/novalife/';
    }
  }
}
