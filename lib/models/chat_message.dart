import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart'; // ✅ Add UUID import

enum MessageRole {
  user,
  assistant,
  system,
}

class ChatMessage {
  final String id; // ✅ Add unique ID field
  final String content;
  final MessageRole role;
  final DateTime timestamp;
  final bool isLoading;
  final String? imagePath;
  final bool showSetupButton;
  final VoidCallback? onSetupPressed;

  ChatMessage({
    String? id, // ✅ Optional ID parameter
    required this.content,
    required this.role,
    required this.timestamp,
    this.isLoading = false,
    this.imagePath,
    this.showSetupButton = false,
    this.onSetupPressed,
  }) : id = id ?? const Uuid().v4(); // ✅ Generate UUID if not provided

  // ✅ Add copyWith method for message updates
  ChatMessage copyWith({
    String? id,
    String? content,
    MessageRole? role,
    DateTime? timestamp,
    bool? isLoading,
    String? imagePath,
    bool? showSetupButton,
    VoidCallback? onSetupPressed,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      isLoading: isLoading ?? this.isLoading,
      imagePath: imagePath ?? this.imagePath,
      showSetupButton: showSetupButton ?? this.showSetupButton,
      onSetupPressed: onSetupPressed ?? this.onSetupPressed,
    );
  }
}
