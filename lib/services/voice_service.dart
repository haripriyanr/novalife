import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isInitialized = false;
  bool _isListening = false;

  // ✅ FIXED: Add missing isAvailable getter
  bool get isAvailable => _speechToText.isAvailable;
  bool get isListening => _isListening;

  /// Initialize speech services
  Future<void> initialize() async {
    try {
      // Initialize speech-to-text
      final available = await _speechToText.initialize();

      // Initialize text-to-speech
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isInitialized = available;
      debugPrint('Voice service initialized: $available');
    } catch (e) {
      debugPrint('Error initializing voice service: $e');
      _isInitialized = false;
    }
  }

  /// ✅ FIXED: Start listening and return recognized text
  Future<String?> startListening() async {
    if (!_isInitialized || !_speechToText.isAvailable) {
      throw Exception('Speech recognition not available');
    }

    try {
      _isListening = true;

      String recognizedText = '';

      await _speechToText.listen(
        onResult: (result) {
          recognizedText = result.recognizedWords;
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      );

      // Wait for listening to complete
      while (_speechToText.isListening) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _isListening = false;

      return recognizedText.isNotEmpty ? recognizedText : null;
    } catch (e) {
      _isListening = false;
      throw Exception('Speech recognition failed: $e');
    }
  }

  /// ✅ FIXED: Speak the given text
  Future<void> speak(String text) async {
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  /// Stop current speech operations
  Future<void> stop() async {
    if (_isListening) {
      await _speechToText.stop();
      _isListening = false;
    }
    await _flutterTts.stop();
  }

  /// Dispose of resources
  void dispose() {
    _speechToText.stop();
    _flutterTts.stop();
  }
}
