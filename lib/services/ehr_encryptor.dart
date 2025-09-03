// lib/services/ehr_encryptor.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:image/image.dart' as img;

class EHREncryptor {
  static final List<int> MAGIC = utf8.encode('EHRSTEG1');
  static const int PBKDF2_ITERS = 200000;
  static const int SALT_LEN = 16;
  static const int NONCE_LEN = 12;
  static const int TAG_LEN = 16;

  static Future<Uint8List> buildStegoPng({
    required Uint8List coverPng,
    required String uuid,
    required Uint8List plaintext,
  }) async {
    final payload = await _buildEncryptedPayload(uuid: uuid, plaintext: plaintext);
    final stego = _embedLsb(coverPng: coverPng, payload: payload);
    return stego;
  }

  static Future<Uint8List> _buildEncryptedPayload({
    required String uuid,
    required Uint8List plaintext,
  }) async {
    final magic = Uint8List.fromList(MAGIC);
    final salt = _randomBytes(SALT_LEN);

    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: PBKDF2_ITERS,
      bits: 256,
    );
    final secretKey = await kdf.deriveKeyFromPassword(password: uuid, nonce: salt);

    final aes = AesGcm.with256bits();
    final nonce = aes.newNonce();
    final box = await aes.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: magic,
    );

    final clen = _u32be(box.cipherText.length);
    final out = BytesBuilder()
      ..add(magic)
      ..add(salt)
      ..add(nonce)
      ..add(clen)
      ..add(box.cipherText)
      ..add(Uint8List.fromList(box.mac.bytes));
    return out.toBytes();
  }

  static Uint8List _embedLsb({
    required Uint8List coverPng,
    required Uint8List payload,
  }) {
    final decoded = img.decodeImage(coverPng);
    if (decoded == null) {
      throw StateError('Cannot decode PNG cover image');
    }
    // Force RGBA to avoid palette/3-channel surprises
    final image = decoded.convert(numChannels: 4);

    // Header: MAGIC + 4-byte big-endian payload length
    final header = BytesBuilder()
      ..add(MAGIC)
      ..add(_u32be(payload.length));
    final headerBytes = header.toBytes();

    // MSB-first bit stream for header + payload
    final bits = <int>[];
    for (final list in [headerBytes, payload]) {
      for (final b in list) {
        for (int i = 7; i >= 0; i--) {
          bits.add((b >> i) & 1);
        }
      }
    }

    final capacityBits = image.width * image.height * 3;
    if (bits.length > capacityBits) {
      throw StateError('Cover too small: need ${bits.length} bits, have $capacityBits');
    }

    int bi = 0;
    for (int y = 0; y < image.height && bi < bits.length; y++) {
      for (int x = 0; x < image.width && bi < bits.length; x++) {
        final p = image.getPixel(x, y);
        int r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt(), a = p.a.toInt();
        if (bi < bits.length) r = (r & 0xFE) | bits[bi++];
        if (bi < bits.length) g = (g & 0xFE) | bits[bi++];
        if (bi < bits.length) b = (b & 0xFE) | bits[bi++];
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }

    return Uint8List.fromList(img.encodePng(image));
  }


  static Uint8List _u32be(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

  static Uint8List _randomBytes(int len) =>
      Uint8List.fromList(List.generate(len, (_) => Random.secure().nextInt(256)));
}
