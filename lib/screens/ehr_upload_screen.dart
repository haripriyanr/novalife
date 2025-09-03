// lib/screens/ehr_upload_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ehr_encryptor.dart';
import '../services/ehr_service.dart';
import '../services/ehr_decryptor.dart';
import 'package:image/image.dart' as img;

class EHRUploadScreen extends StatefulWidget {
  const EHRUploadScreen({Key? key}) : super(key: key);
  @override
  State<EHRUploadScreen> createState() => _EHRUploadScreenState();
}

class _EHRUploadScreenState extends State<EHRUploadScreen> {
  Uint8List? _coverPng;
  String? _coverName;
  final _textCtrl = TextEditingController();
  bool _busy = false;

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickPng() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['png'], withData: true,
    );
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
    setState(() {
      _coverPng = res.files.first.bytes!;
      _coverName = res.files.first.name;
    });
    _toast('🖼️ Picked ${_coverName!}');
  }

  @override
  void dispose() { _textCtrl.dispose(); super.dispose(); }

  Future<void> _runAndUpload() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return _fail('Not authenticated');
    if (_coverPng == null) return _fail('Pick a PNG cover image');
    if (_textCtrl.text.trim().isEmpty) return _fail('Enter text to hide');

    setState(() => _busy = true);
    try {
      final uuid = user.id;
      final clear = Uint8List.fromList(utf8.encode(_textCtrl.text));
      print('🧪 PRECHECK START');
      print('🔑 UUID: $uuid');
      print('📝 Clear bytes: ${clear.length}');

      // 1) Encrypt + embed
      print('🔐 Encrypt + embed…');
      final stego = await EHREncryptor.buildStegoPng(
        coverPng: _coverPng!, uuid: uuid, plaintext: clear,
      );
      print('🧵 Stego bytes: ${stego.length}');

      // 2) Local header peek (same logic shape as decryptor) for better error text
      print('🔎 Header peek…');
      final headerInfo = _peekHeader(stego);
      print('📛 MAGIC: ${headerInfo.magicAscii}  ok=${headerInfo.magicOk}');
      print('📦 payloadLen: ${headerInfo.payloadLen}');
      if (!headerInfo.magicOk) {
        return _fail('Bad header MAGIC; saw: ${headerInfo.magicAscii}');
      }

      // 3) Full decrypt via your EHRDecryptor
      print('🔓 Decrypt round‑trip…');
      Uint8List roundTrip;
      try {
        roundTrip = await EHRDecryptor.extractAndDecrypt(stegoBytes: stego, uuid: uuid);
      } catch (e) {
        return _fail('Decrypt failed: $e');
      }

      // 4) Compare
      final same = _bytesEqual(roundTrip, clear);
      print('🟢 Round‑trip match: $same');
      if (!same) {
        return _fail('Round‑trip mismatch; got ${_previewUtf8(roundTrip)}');
      }

      // 5) Upload
      final name = 'ehr_${DateTime.now().millisecondsSinceEpoch}.png';
      final path = '${uuid}/$name';
      await EHRService.uploadReportBytes(fullPath: path, bytes: stego, upsert: true);
      _toast('✅ Uploaded: $name');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _fail('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String msg) {
    _toast('❌ $msg');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload failed'),
        content: Text(msg),
        actions: [ TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')) ],
      ),
    );
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
    return true;
  }

  String _previewUtf8(Uint8List data, {int max = 80}) {
    try { final s = utf8.decode(data, allowMalformed: true);
    return s.length <= max ? s : '${s.substring(0, max)}…';
    } catch (_) { return '«non‑UTF8 ${data.length} bytes»'; }
  }

  // Debug helper: read first 12 bytes from LSB stream and parse header
  _Header _peekHeader(Uint8List stego) {
    final im = img.decodeImage(stego);
    if (im == null) throw StateError('Cannot decode stego PNG');
    final magic = utf8.encode('EHRSTEG1');
    final needBits = (magic.length + 4) * 8;
    final rgb = <int>[];

    outer:
    for (int y = 0; y < im.height; y++) {
      for (int x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        rgb.add(p.r.toInt());
        rgb.add(p.g.toInt());
        rgb.add(p.b.toInt());
        if (rgb.length * 1 >= needBits) break outer; // one LSB per channel
      }
    }
    final headerBits = <int>[];
    for (int i = 0; i < needBits; i++) headerBits.add(rgb[i] & 1);
    final headerBytes = _bytesFromBits(headerBits);
    final magicOk = headerBytes.length >= magic.length &&
        List.generate(magic.length, (i) => headerBytes[i] == magic[i]).every((v) => v);
    final magicAscii = String.fromCharCodes(headerBytes.take(magic.length));
    final payloadLen = _readU32BE(headerBytes, magic.length);
    return _Header(magicOk, magicAscii, payloadLen);
  }

  Uint8List _bytesFromBits(List<int> bits) {
    final out = Uint8List((bits.length / 8).floor());
    int oi = 0;
    for (int i = 0; i + 7 < bits.length; i += 8) {
      int v = 0;
      for (int j = 0; j < 8; j++) v = (v << 1) | (bits[i + j] & 1);
      out[oi++] = v;
    }
    return out;
  }

  int _readU32BE(List<int> b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Encrypted Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _busy ? null : _pickPng,
            icon: const Icon(Icons.image_outlined),
            label: Text(_coverName ?? 'Pick PNG'),
          ),
          if (_coverPng != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_coverPng!, height: 160, fit: BoxFit.contain),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _textCtrl, minLines: 4, maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Text to hide', hintText: 'Enter UTF‑8 text…', border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _runAndUpload,
            icon: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified),
            label: Text(_busy ? 'Checking…' : 'Encrypt • Verify • Upload'),
          ),
        ],
      ),
    );
  }
}

class _Header {
  final bool magicOk;
  final String magicAscii;
  final int payloadLen;
  _Header(this.magicOk, this.magicAscii, this.payloadLen);
}
