/// App roles: who may see and do what, plus user initials helper.
///
/// The role is chosen at signup and stored in the Supabase auth user's metadata
/// (`user_metadata.role`). The server enforces the same roles through RLS on the
/// hub tables; this client-side role only decides which screens exist. It never
/// grants access by itself.
///
/// Mapping to the database `user_role` enum: labTech -> 'lab_tech',
/// doctor -> 'doctor', patient -> 'patient'.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

enum AppRole { labTech, doctor, patient }

/// Role of a user given their raw metadata or database string.
AppRole roleFromDb(String? raw) {
  final clean = raw?.toString().toLowerCase().trim();
  return switch (clean) {
    'lab_tech' || 'labtech' || 'lab' => AppRole.labTech,
    'doctor' => AppRole.doctor,
    _ => AppRole.patient,
  };
}

/// Role of the signed-in user from their auth metadata. Unknown or missing
/// values fall back to [AppRole.patient] (least privilege).
AppRole roleOf(User? user) {
  return roleFromDb(user?.userMetadata?['role']?.toString());
}

/// Database role string for RLS-facing code.
String roleToDb(AppRole role) => switch (role) {
      AppRole.labTech => 'lab_tech',
      AppRole.doctor => 'doctor',
      AppRole.patient => 'patient',
    };

/// Display label for pickers and titles.
String roleLabel(AppRole role) => switch (role) {
      AppRole.labTech => 'Lab Tech',
      AppRole.doctor => 'Doctor',
      AppRole.patient => 'Patient',
    };

/// The ABHA id the user registered with (patients and clinical staff, may be null).
String? abhaOf(User? user) {
  final abha = user?.userMetadata?['abha_id']?.toString().trim();
  return (abha == null || abha.isEmpty) ? null : abha;
}

/// Known patient ID for a user based on metadata or standard demo ABHA IDs.
String? patientIdOf(User? user) {
  final meta = user?.userMetadata?['patient_id']?.toString().trim();
  if (meta != null && meta.isNotEmpty) return meta;
  final abha = abhaOf(user);
  return switch (abha) {
    '12345678901234' => 'PAT-001',
    '23456789012345' => 'PAT-002',
    '34567890123456' => 'PAT-003',
    _ => null,
  };
}

/// Computes a 2-letter uppercase avatar label from a display name or email.
/// Examples:
/// - "Anjali Mehta" -> "AM"
/// - "Dr. Priya Nair" -> "PN"
/// - "Lab Tech" -> "LT"
/// - "demo@syndrix.tech" -> "DE"
String initialsOf(String? nameOrEmail, {String? fallbackEmail}) {
  var raw = (nameOrEmail ?? '').trim();
  if (raw.isEmpty || raw.toLowerCase() == 'novalife user') {
    raw = (fallbackEmail ?? '').trim();
  }
  if (raw.isEmpty) return 'NL';

  if (raw.contains('@')) {
    raw = raw.split('@').first;
  }

  // Strip common honorific prefixes like "Dr." or "Mr."
  final cleaned = raw
      .replaceAll(RegExp(r'^(dr|mr|mrs|ms|prof)\.?\s+', caseSensitive: false), '')
      .trim();
  final source = cleaned.isEmpty ? raw : cleaned;

  final parts = source
      .split(RegExp(r'[\s._\-]+'))
      .where((p) => p.isNotEmpty)
      .toList();

  if (parts.length >= 2) {
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
  final word = parts.first;
  if (word.length >= 2) {
    return word.substring(0, 2).toUpperCase();
  }
  return '${word[0].toUpperCase()}U';
}
