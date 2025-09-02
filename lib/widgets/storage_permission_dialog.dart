import 'package:flutter/material.dart';
import '../services/external_storage_helper.dart';

class StoragePermissionDialog extends StatelessWidget {
  final VoidCallback onPermissionGranted;

  const StoragePermissionDialog({
    super.key,
    required this.onPermissionGranted,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            Icons.folder_open,
            color: Colors.blue[600],
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text('Storage Permission'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NovaLife needs storage permission to save the AI model to your Downloads folder.',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.blue.withAlpha(25),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Benefits:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Access model files from any app\n'
                      '• Easy backup and transfer\n'
                      '• No app uninstall data loss',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            final granted = await ExternalStorageHelper.requestStoragePermissions();
            if (granted) {
              onPermissionGranted();
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Storage permission is required to save model files'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
          ),
          child: const Text('Allow'),
        ),
      ],
    );
  }
}
