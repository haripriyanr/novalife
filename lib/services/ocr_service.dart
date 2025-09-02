import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  static final TextRecognizer _textRecognizer = TextRecognizer();
  static bool _isInitialized = false;

  /// Initialize OCR service
  static Future<void> initialize() async {
    try {
      _isInitialized = true;
      debugPrint('OCR service initialized');
    } catch (e) {
      debugPrint('Error initializing OCR service: $e');
      _isInitialized = false;
    }
  }

  /// ✅ FIXED: Extract text from image file
  Future<String> extractText(File imageFile) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      return recognizedText.text;
    } catch (e) {
      debugPrint('OCR extraction error: $e');
      throw Exception('Failed to extract text from image: $e');
    }
  }

  /// ✅ FIXED: Static dispose method
  static void dispose() {
    _textRecognizer.close();
    _isInitialized = false;
  }
}
