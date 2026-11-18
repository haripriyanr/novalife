import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:image/image.dart' as img;

/// Reads records saved by the first version of NovaLife: AES-GCM with a key derived from the
/// user ID, hidden in the low bits of a PNG. That scheme was not private (the user ID is also
/// the storage folder name), so it is kept only to move old records into the vault.
/// Nothing new is ever written in this format.
class LegacyEhr {
  LegacyEhr._();

  static final List<int> _magic = utf8.encode('EHRSTEG1');
  static const int _iterations = 200000;
  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _tagLen = 16;

  static Future<Uint8List> extractAndDecrypt(Uint8List stegoPng, String uid) async {
    final blob = _extractLsb(stegoPng);
    if (!_startsWith(blob, _magic)) throw const FormatException('Not a legacy record');
    var p = _magic.length;
    final salt = blob.sublist(p, p += _saltLen);
    final nonce = blob.sublist(p, p += _nonceLen);
    final clen = _u32(blob, p);
    p += 4;
    final cipherText = blob.sublist(p, p += clen);
    final tag = blob.sublist(p, p + _tagLen);
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256)
        .deriveKeyFromPassword(password: uid, nonce: salt);
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
      secretKey: key,
      aad: _magic,
    );
    return Uint8List.fromList(clear);
  }

  static Uint8List _extractLsb(Uint8List png) {
    final image = img.decodeImage(png);
    if (image == null) throw const FormatException('Cannot decode image');
    final bits = <int>[];
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        bits
          ..add(px.r.toInt() & 1)
          ..add(px.g.toInt() & 1)
          ..add(px.b.toInt() & 1);
      }
    }
    final headerLen = _magic.length + 4;
    if (bits.length < headerLen * 8) throw const FormatException('Image too small');
    final header = _bytes(bits, 0, headerLen);
    if (!_startsWith(header, _magic)) throw const FormatException('No legacy record in image');
    final len = _u32(header, _magic.length);
    if (bits.length < (headerLen + len) * 8) throw const FormatException('Truncated record');
    return _bytes(bits, headerLen * 8, len);
  }

  static Uint8List _bytes(List<int> bits, int startBit, int count) {
    final out = Uint8List(count);
    for (var i = 0; i < count; i++) {
      var v = 0;
      for (var j = 0; j < 8; j++) {
        v = (v << 1) | bits[startBit + i * 8 + j];
      }
      out[i] = v;
    }
    return out;
  }

  static int _u32(List<int> b, int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static bool _startsWith(List<int> data, List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }
}
