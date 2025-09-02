import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ModelPathService {
  static const String _modelPathKey = 'ai_model_path';

  /// Save model path to SharedPreferences
  static Future<void> saveModelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelPathKey, path);
  }

  /// Load model path from SharedPreferences
  static Future<String?> loadModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modelPathKey);
  }

  /// Remove saved model path
  static Future<void> clearModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modelPathKey);
  }

  /// Let user pick a model file from device storage
  static Future<String?> pickModelFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf'],
        allowMultiple: false,
        dialogTitle: 'Select AI Model File',
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path!;
      }
    } catch (e) {
      debugPrint('Error picking model file: $e');
    }
    return null;
  }
}
