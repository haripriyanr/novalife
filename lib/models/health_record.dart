import 'dart:convert';
import 'dart:typed_data';

/// One health record as the user sees it. It is serialised to JSON and encrypted as a
/// whole, so the title, notes and photo never reach storage in readable form.
class HealthRecord {
  final String title;
  final String notes;
  final DateTime createdAt;
  final Uint8List? photo;
  final String? photoMime;

  const HealthRecord({
    required this.title,
    required this.notes,
    required this.createdAt,
    this.photo,
    this.photoMime,
  });

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode({
        'v': 1,
        'title': title,
        'notes': notes,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (photo != null) 'photo': base64Encode(photo!),
        if (photoMime != null) 'photoMime': photoMime,
      })));

  static HealthRecord fromBytes(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final photo = map['photo'] as String?;
    return HealthRecord(
      title: (map['title'] as String?) ?? 'Untitled record',
      notes: (map['notes'] as String?) ?? '',
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      photo: photo == null ? null : base64Decode(photo),
      photoMime: map['photoMime'] as String?,
    );
  }
}
