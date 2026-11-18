import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/health_record.dart';
import 'ehr_service.dart';
import 'legacy_ehr.dart';

/// The user's record vault.
///
/// Each user has one random 256-bit vault key. Records are encrypted with it (AES-256-GCM).
/// The vault key itself is stored only in wrapped form: encrypted with a key derived from a
/// passphrase that the user chooses and that never leaves the phone (PBKDF2-HMAC-SHA256).
/// The wrapped key lives next to the records in storage, so the vault can be opened on a new
/// phone with the same passphrase. Neither the server nor anyone holding a file path can
/// read a record without that passphrase.
///
/// The unwrapped key is held in memory only, until [lock] or the app closes.
class VaultService {
  VaultService._();

  static const int minPassphraseLength = 8;
  static const int _kdfIterations = 310000;
  static const String _wrapFormat = 'novalife-vault-v1';
  static final List<int> _recordMagic = utf8.encode('NLREC001'); // 8 bytes

  static final _aes = AesGcm.with256bits();
  static SecretKey? _key;
  static String? _keyOwner;

  static SupabaseClient get _sb => Supabase.instance.client;

  static String get _uid {
    final user = _sb.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.id;
  }

  static bool get isUnlocked => _key != null && _keyOwner == _sb.auth.currentUser?.id;

  static void lock() {
    _key = null;
    _keyOwner = null;
  }

  /// Whether this user has already set a vault passphrase (on any device).
  static Future<bool> exists() async {
    final wrapped = await EHRService.downloadVaultKey(_uid);
    return wrapped != null;
  }

  /// First-time setup: creates the vault key and stores it wrapped with [passphrase].
  static Future<void> create(String passphrase) async {
    _checkPassphrase(passphrase);
    final uid = _uid;
    if (await EHRService.downloadVaultKey(uid) != null) {
      throw StateError('A vault already exists for this account. Unlock it instead.');
    }
    final vaultKey = await _aes.newSecretKey();
    final rng = Random.secure();
    final saltBytes = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    final wrapKey = await _deriveWrapKey(passphrase, saltBytes, _kdfIterations);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      await vaultKey.extractBytes(),
      secretKey: wrapKey,
      nonce: nonce,
      aad: utf8.encode('$_wrapFormat:$uid'),
    );
    final wrapped = jsonEncode({
      'format': _wrapFormat,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _kdfIterations,
      'salt': base64Encode(saltBytes),
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
    await EHRService.uploadVaultKey(uid, Uint8List.fromList(utf8.encode(wrapped)));
    _key = vaultKey;
    _keyOwner = uid;
  }

  /// Opens the vault. Returns false when the passphrase is wrong.
  static Future<bool> unlock(String passphrase) async {
    final uid = _uid;
    final raw = await EHRService.downloadVaultKey(uid);
    if (raw == null) throw StateError('No vault yet for this account.');
    final m = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    if (m['format'] != _wrapFormat) throw StateError('Unknown vault format.');
    final wrapKey = await _deriveWrapKey(
      passphrase,
      base64Decode(m['salt'] as String),
      m['iterations'] as int,
    );
    try {
      final keyBytes = await _aes.decrypt(
        SecretBox(
          base64Decode(m['ciphertext'] as String),
          nonce: base64Decode(m['nonce'] as String),
          mac: Mac(base64Decode(m['mac'] as String)),
        ),
        secretKey: wrapKey,
        aad: utf8.encode('$_wrapFormat:$uid'),
      );
      _key = SecretKey(keyBytes);
      _keyOwner = uid;
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    }
  }

  static Future<Uint8List> encryptRecord(HealthRecord record) => encryptWith(_requireKey(), _uid, record);

  static Future<HealthRecord> decryptRecord(Uint8List blob) => decryptWith(_requireKey(), _uid, blob);

  /// Record format: `NLREC001` | 12-byte nonce | ciphertext | 16-byte GCM tag. The owner's
  /// user ID is bound in as associated data, so a record copied into another account's
  /// folder will not open there.
  @visibleForTesting
  static Future<Uint8List> encryptWith(SecretKey key, String uid, HealthRecord record) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(record.toBytes(), secretKey: key, nonce: nonce, aad: _recordAad(uid));
    return Uint8List.fromList([..._recordMagic, ...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  @visibleForTesting
  static Future<HealthRecord> decryptWith(SecretKey key, String uid, Uint8List blob) async {
    final m = _recordMagic.length;
    if (blob.length < m + 12 + 16 || !_startsWith(blob, _recordMagic)) {
      throw const FormatException('Not a NovaLife record.');
    }
    final nonce = blob.sublist(m, m + 12);
    final cipherText = blob.sublist(m + 12, blob.length - 16);
    final mac = blob.sublist(blob.length - 16);
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: _recordAad(uid),
      );
      return HealthRecord.fromBytes(Uint8List.fromList(clear));
    } on SecretBoxAuthenticationError {
      throw const FormatException('This record could not be opened. It may be damaged.');
    }
  }

  /// Re-encrypts records saved by the first version of the app (key derived from the user
  /// ID, hidden inside a PNG) into the vault, then deletes the old file. A file is deleted
  /// only after its new copy has been uploaded and read back successfully.
  /// Returns how many records were moved.
  static Future<int> migrateLegacyRecords() async {
    final uid = _uid;
    var moved = 0;
    for (final path in await EHRService.listLegacyPaths()) {
      try {
        final stego = await EHRService.download(path);
        final text = utf8.decode(await LegacyEhr.extractAndDecrypt(stego, uid), allowMalformed: true);
        final record = HealthRecord(
          title: 'Imported record',
          notes: text,
          createdAt: EHRService.dateFromPath(path) ?? DateTime.now(),
        );
        final blob = await encryptRecord(record);
        final newPath = EHRService.newRecordPath(uid, record.createdAt);
        await EHRService.upload(newPath, blob);
        final check = await decryptRecord(await EHRService.download(newPath));
        if (check.notes != text) throw StateError('Read-back mismatch');
        await EHRService.delete(path);
        moved++;
      } catch (_) {
        // Leave the old file in place; it will be retried next time the vault opens.
      }
    }
    return moved;
  }

  // ---- helpers ----

  static void _checkPassphrase(String p) {
    if (p.length < minPassphraseLength) {
      throw ArgumentError('Use at least $minPassphraseLength characters.');
    }
  }

  static SecretKey _requireKey() {
    if (!isUnlocked) throw StateError('The vault is locked.');
    return _key!;
  }

  static List<int> _recordAad(String uid) => [..._recordMagic, ...utf8.encode(uid)];

  /// PBKDF2 is deliberately slow, so it runs off the UI thread.
  static Future<SecretKey> _deriveWrapKey(String passphrase, List<int> salt, int iterations) async {
    final bytes = await Isolate.run(() async {
      final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
      final k = await kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
      return k.extractBytes();
    });
    return SecretKey(bytes);
  }

  static bool _startsWith(List<int> data, List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }
}
