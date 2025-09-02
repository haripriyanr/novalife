import 'dart:typed_data';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:image/image.dart' as img;

class EHRDecryptor {
  static final MAGIC = utf8.encode('EHRSTEG1');
  static const PBKDF2_ITERS = 200000;
  static const SALT_LEN = 16;
  static const NONCE_LEN = 12;
  static const TAG_LEN = 16;

  static (_Pixels px, int width, int height) _decodeRgba(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Unsupported image format or corrupt image.');
    }
    final raw = decoded.getBytes(order: img.ChannelOrder.rgba);
    final rgba = Uint8List.fromList(raw); // List<int> -> Uint8List
    return (_Pixels(rgba), decoded.width, decoded.height);
  } // [7][1]

  static Uint8List extractLsb(Uint8List stegoBytes) {
    final (px, w, h) = _decodeRgba(stegoBytes);
    final channels = 4;
    final totalPixels = (px.bytes.length ~/ channels);

    final headerByteLen = MAGIC.length + 4;
    final needHeaderBits = headerByteLen * 8;

    final headerBits = <int>[];
    int written = 0;
    for (int i = 0; i < totalPixels && written < needHeaderBits; i++) {
      final base = i * channels;
      for (int ch = 0; ch < 3 && written < needHeaderBits; ch++) {
        headerBits.add(px.bytes[base + ch] & 1);
        written++;
      }
    }
    final header = _bytesFromBits(headerBits);
    if (!_startsWith(header, MAGIC)) {
      throw StateError('No valid EHR payload in image (bad MAGIC).');
    }
    final plen = _readUint32BE(header, MAGIC.length);

    final payloadBitsNeeded = plen * 8;
    final consumedChannels = needHeaderBits;
    final startPixel = consumedChannels ~/ 3;
    final startChannelOffset = consumedChannels % 3;

    final payloadBits = <int>[];
    for (int i = startPixel; i < totalPixels && payloadBits.length < payloadBitsNeeded; i++) {
      final base = i * channels;
      final chStart = (i == startPixel) ? startChannelOffset : 0;
      for (int ch = chStart; ch < 3 && payloadBits.length < payloadBitsNeeded; ch++) {
        payloadBits.add(px.bytes[base + ch] & 1);
      }
    }
    return _bytesFromBits(payloadBits);
  } // [7]

  static Future<Uint8List> decryptBlobWithUuid(String uuid, Uint8List blob) async {
    if (!_startsWith(blob, MAGIC)) {
      throw StateError('Invalid stego payload (decrypt: bad MAGIC).');
    }
    int p = MAGIC.length;
    final salt = blob.sublist(p, p + SALT_LEN); p += SALT_LEN;
    final nonce = blob.sublist(p, p + NONCE_LEN); p += NONCE_LEN;
    final clen = _readUint32BE(blob, p); p += 4;
    final ciphertext = blob.sublist(p, p + clen); p += clen;
    final tag = blob.sublist(p, p + TAG_LEN);

    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: PBKDF2_ITERS,
      bits: 256,
    );
    final secretKey = await kdf.deriveKeyFromPassword(
      password: uuid,
      nonce: salt,
    ); // [11]

    final aes = AesGcm.with256bits();
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(tag));
    final clear = await aes.decrypt(secretBox, secretKey: secretKey, aad: MAGIC);
    return Uint8List.fromList(clear);
  } // [12][11]

  static Future<Uint8List> extractAndDecrypt({
    required Uint8List stegoBytes,
    required String uuid,
  }) async {
    final payload = extractLsb(stegoBytes);
    final clear = await decryptBlobWithUuid(uuid, payload);
    return clear;
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

class _Pixels {
  final Uint8List bytes;
  _Pixels(this.bytes);
}
