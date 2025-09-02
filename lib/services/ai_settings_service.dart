import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AIModelSettings {
  double temperature;
  int maxTokens;
  int contextSize;
  double topP;
  int topK;
  bool streamResponse;
  String systemPrompt;

  AIModelSettings({
    this.temperature = 0.7,
    this.maxTokens = 512,
    this.contextSize = 2048,
    this.topP = 0.9,
    this.topK = 40,
    this.streamResponse = true,
    this.systemPrompt = 'You are a helpful AI assistant.',
  });

  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'maxTokens': maxTokens,
      'contextSize': contextSize,
      'topP': topP,
      'topK': topK,
      'streamResponse': streamResponse,
      'systemPrompt': systemPrompt,
    };
  }

  factory AIModelSettings.fromJson(Map<String, dynamic> json) {
    return AIModelSettings(
      temperature: json['temperature']?.toDouble() ?? 0.7,
      maxTokens: json['maxTokens']?.toInt() ?? 512,
      contextSize: json['contextSize']?.toInt() ?? 2048,
      topP: json['topP']?.toDouble() ?? 0.9,
      topK: json['topK']?.toInt() ?? 40,
      streamResponse: json['streamResponse'] ?? true,
      systemPrompt: json['systemPrompt'] ?? 'You are a helpful AI assistant.',
    );
  }
}

class AISettingsService {
  static const String _settingsKey = 'ai_model_settings';

  static Future<void> saveSettings(AIModelSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(settings.toJson());
    await prefs.setString(_settingsKey, jsonString);
  }

  static Future<AIModelSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_settingsKey);

    if (jsonString != null) {
      final jsonMap = jsonDecode(jsonString);
      return AIModelSettings.fromJson(jsonMap);
    }

    return AIModelSettings(); // Return default settings
  }

  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_settingsKey);
  }
}
