// lib/screens/ehr_upload_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/health_record.dart';
import '../services/ehr_service.dart';
import '../services/vault_service.dart';

/// Add a record: a title, notes and an optional photo of the report. It is encrypted with
/// the vault key on the phone, read back to check it, then uploaded.
class EHRUploadScreen extends StatefulWidget {
  const EHRUploadScreen({super.key});

  @override
  State<EHRUploadScreen> createState() => _EHRUploadScreenState();
}

class _EHRUploadScreenState extends State<EHRUploadScreen> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  Uint8List? _photo;
  String? _photoMime;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photo = bytes;
      _photoMime = file.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return setState(() => _error = 'Give the record a title, like "Blood test, Nov 2026".');
    if (_notes.text.trim().isEmpty && _photo == null) {
      return setState(() => _error = 'Add notes or a photo of the report.');
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || !VaultService.isUnlocked) {
      return setState(() => _error = 'Your vault is locked. Go back and unlock it.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = HealthRecord(
        title: title,
        notes: _notes.text.trim(),
        createdAt: DateTime.now(),
        photo: _photo,
        photoMime: _photoMime,
      );
      final blob = await VaultService.encryptRecord(record);
      // Check it opens again before it leaves the phone.
      final check = await VaultService.decryptRecord(blob);
      if (check.title != record.title || check.notes != record.notes) {
        throw StateError('verification failed');
      }
      await EHRService.upload(EHRService.newRecordPath(uid, record.createdAt), blob);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the record. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add record')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            enabled: !_busy,
            minLines: 4,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Results, doctor\'s advice, medicines…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_photo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_photo!, height: 220, fit: BoxFit.cover),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => setState(() => _photo = null),
              icon: const Icon(Icons.close),
              label: const Text('Remove photo'),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take photo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('From gallery'),
                  ),
                ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_outline),
            label: Text(_busy ? 'Encrypting…' : 'Encrypt and save'),
          ),
        ],
      ),
    );
  }
}
