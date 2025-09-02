import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Function(String) onSpeak;
  final Function(String)? onDelete; // ✅ UUID-based delete callback
  final Function(String)? onRegenerate; // ✅ UUID-based regenerate callback

  const MessageBubble({
    super.key,
    required this.message,
    required this.onSpeak,
    this.onDelete,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.role == MessageRole.user;
    final isSystem = message.role == MessageRole.system;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: isSystem
                  ? Colors.orange.withAlpha(51)
                  : Theme.of(context).colorScheme.primary.withAlpha(51),
              child: Icon(
                isSystem ? Icons.info : Icons.smart_toy,
                size: 16,
                color: isSystem ? Colors.orange : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () => _showMessageActions(context), // ✅ Long press for UUID-based actions
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isUser
                      ? Theme.of(context).colorScheme.primary
                      : isSystem
                      ? Colors.orange.withAlpha(25)
                      : isDark
                      ? Colors.grey[800]
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(18).copyWith(
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.imagePath != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(message.imagePath!),
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    if (message.isLoading)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                isUser ? Colors.white : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Thinking...',
                            style: TextStyle(
                              color: isUser ? Colors.white : null,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        message.content,
                        style: TextStyle(
                          color: isUser ? Colors.white : null,
                          fontSize: 16,
                        ),
                      ),

                    if (message.showSetupButton) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: message.onSetupPressed,
                        icon: const Icon(Icons.download),
                        label: const Text('Setup AI Model'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],

                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTimestamp(message.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: isUser
                                ? Colors.white.withAlpha(179)
                                : Theme.of(context).colorScheme.onSurface.withAlpha(153),
                          ),
                        ),
                        if (!isUser && !message.isLoading && message.content.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => onSpeak(message.content),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.volume_up,
                                size: 16,
                                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: message.content));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copied to clipboard')),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.copy,
                                size: 16,
                                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                              ),
                            ),
                          ),
                          // ✅ Add regenerate button for AI messages using UUID
                          if (onRegenerate != null && message.role == MessageRole.assistant) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => onRegenerate!(message.id), // ✅ Use message UUID
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.refresh,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(51),
              child: Icon(
                Icons.person,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ✅ Show message actions using UUID for identification
  void _showMessageActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Message Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Copy message action
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Message'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Message copied to clipboard'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),

            // Speak message action (for non-user messages)
            if (!message.isLoading && message.content.isNotEmpty && message.role != MessageRole.user)
              ListTile(
                leading: const Icon(Icons.volume_up),
                title: const Text('Speak Message'),
                onTap: () {
                  Navigator.pop(context);
                  onSpeak(message.content);
                },
              ),

            // Regenerate response action (for AI messages only)
            if (message.role == MessageRole.assistant && onRegenerate != null)
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.blue),
                title: const Text('Regenerate Response', style: TextStyle(color: Colors.blue)),
                onTap: () {
                  Navigator.pop(context);
                  onRegenerate!(message.id); // ✅ Use message UUID
                },
              ),

            // Delete message action (except system messages)
            if (message.role != MessageRole.system && onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Message', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ✅ Show delete confirmation dialog
  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message? This action cannot be undone.'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete!(message.id); // ✅ Use message UUID
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Message deleted'),
                    ],
                  ),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${timestamp.day}/${timestamp.month}';
    }
  }
}
