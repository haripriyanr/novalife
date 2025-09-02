import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:image/image.dart' as img;

class EHRDecryptor {
  static final MAGIC = utf8.encode('EHRSTEG1'); // 8 bytes
  static const PBKDF2_ITERS = 200000;
  static const SALT_LEN = 16;
  static const NONCE_LEN = 12;
  static const TAG_LEN = 16;

  // Corrected LSB Extraction
  static Uint8List extractLsb(Uint8List stegoBytes) {
    final decoded = img.decodeImage(stegoBytes);
    if (decoded == null) {
      throw StateError('Cannot decode image. Unsupported format or corrupt data.');
    }

    // Flatten all RGB channel values into a single list, matching Python's approach
    final rgbChannels = <int>[];
    for (int y = 0; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        rgbChannels.add(pixel.r.toInt());
        rgbChannels.add(pixel.g.toInt());
        rgbChannels.add(pixel.b.toInt());
      }
    }

    print('Total RGB channels extracted: ${rgbChannels.length}');

    // 1. Read the header bits to find the payload length
    final headerByteLen = MAGIC.length + 4;
    final needHeaderBits = headerByteLen * 8;
    if (rgbChannels.length < needHeaderBits) {
      throw StateError('Image is too small to contain a header.');
    }

    final headerBits = <int>[];
    for (int i = 0; i < needHeaderBits; i++) {
      headerBits.add(rgbChannels[i] & 1);
    }

    final header = _bytesFromBits(headerBits);
    if (!_startsWith(header, MAGIC)) {
      throw StateError('No valid EHR payload in image (bad MAGIC).');
    }

    final payloadLen = _readUint32BE(header, MAGIC.length);
    print('Payload length from header: $payloadLen');

    // 2. Read the payload bits, starting right after the header
    final payloadBitsNeeded = payloadLen * 8;
    if (rgbChannels.length < needHeaderBits + payloadBitsNeeded) {
      throw StateError('Image does not contain enough data for the expected payload.');
    }

    final payloadBits = <int>[];
    for (int i = 0; i < payloadBitsNeeded; i++) {
      payloadBits.add(rgbChannels[needHeaderBits + i] & 1);
    }

    return _bytesFromBits(payloadBits);
  }

  // Decrypt with added debug prints
  static Future<Uint8List> decryptBlobWithUuid(String uuid, Uint8List blob) async {
    print('=== DECRYPT DEBUG ===');
    print('UUID (password): $uuid');
    print('Blob length: ${blob.length}');

    final magic = MAGIC;
    if (!_startsWith(blob, magic)) {
      throw StateError('Invalid payload: MAGIC mismatch.');
    }

    int p = magic.length;
    final salt = blob.sublist(p, p + SALT_LEN); p += SALT_LEN;
    final nonce = blob.sublist(p, p + NONCE_LEN); p += NONCE_LEN;
    final clen = _readUint32BE(blob, p); p += 4;
    final ciphertext = blob.sublist(p, p + clen); p += clen;
    final tag = blob.sublist(p, p + TAG_LEN);

    print('Salt (hex): ${_hexEncode(salt)}');
    print('Nonce (hex): ${_hexEncode(nonce)}');
    print('Clen: $clen');
    print('Ciphertext (first 32 bytes): ${_hexEncode(ciphertext.take(32).toList())}');
    print('Tag (hex): ${_hexEncode(tag)}');
    print('AAD (MAGIC): ${String.fromCharCodes(magic)}');

    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: PBKDF2_ITERS,
      bits: 256,
    );
    final secretKey = await kdf.deriveKeyFromPassword(
      password: uuid,
      nonce: salt,
    );

    final keyBytes = await secretKey.extractBytes();
    print('Derived key (hex): ${_hexEncode(Uint8List.fromList(keyBytes))}');

    final aes = AesGcm.with256bits();
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(tag));

    try {
      final clear = await aes.decrypt(secretBox, secretKey: secretKey, aad: magic);
      print('=== DECRYPT SUCCESS ===');
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError catch (e) {
      print('=== MAC AUTHENTICATION FAILED ===');
      print('Error: $e');
      throw StateError('MAC verification failed. Check debug output.');
    }
  }

  static Future<Uint8List> extractAndDecrypt({
    required Uint8List stegoBytes,
    required String uuid,
  }) async {
    final payload = extractLsb(stegoBytes);
    final clear = await decryptBlobWithUuid(uuid, payload);
    return clear;
  }

  static String _hexEncode(Iterable<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  static bool _startsWith(Uint8List data, List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }

  static int _readUint32BE(List<int> b, int offset) {
    return (b[offset] << 24) | (b[offset + 1] << 16) | (b[offset + 2] << 8) | b[offset + 3];
  }

  static Uint8List _bytesFromBits(List<int> bits) {
    final out = Uint8List((bits.length / 8).floor());
    int oi = 0;
    for (int i = 0; i + 7 < bits.length; i += 8) {
      int v = 0;
      for (int j = 0; j < 8; j++) {
        v = (v << 1) | (bits[i + j] & 1);
      }
      out[oi++] = v;
    }
    return out;
  }
}
