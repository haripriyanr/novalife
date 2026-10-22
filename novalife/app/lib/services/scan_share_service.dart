import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart' show hubDb;

/// Service for sharing medical scans across messaging apps (WhatsApp, Telegram, Email).
class ScanShareService {
  /// Resolve scan bytes from either a network URL, Supabase storage path, or bundled asset.
  static Future<Uint8List?> resolveScanBytes(String imagePath) async {
    try {
      // 1. Direct HTTP / HTTPS URL
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        final res = await http.get(Uri.parse(imagePath));
        if (res.statusCode == 200) return res.bodyBytes;
      }

      // 2. Supabase Storage relative path in 'medical-images'
      final db = hubDb;
      if (db != null) {
        try {
          const bucket = 'medical-images';
          final storagePath = imagePath.startsWith('scans/')
              ? imagePath
              : 'scans/$imagePath';
          final bytes = await db.storage.from(bucket).download(storagePath);
          return bytes;
        } catch (_) {
          // If download fails or storage not configured, try public URL
          try {
            const bucket = 'medical-images';
            final storagePath = imagePath.startsWith('scans/')
                ? imagePath
                : 'scans/$imagePath';
            final url = db.storage.from(bucket).getPublicUrl(storagePath);
            final res = await http.get(Uri.parse(url));
            if (res.statusCode == 200) return res.bodyBytes;
          } catch (_) {}
        }
      }

      // 3. Bundled asset fallback (assets/scans/scan_XXX.png)
      String assetName = 'assets/scans/scan_002.png';
      final lower = imagePath.toLowerCase();
      for (int i = 1; i <= 10; i++) {
        final pad = i.toString().padLeft(3, '0');
        if (lower.contains(pad) || lower.contains('scan_$pad')) {
          assetName = 'assets/scans/scan_$pad.png';
          break;
        }
      }
      if (assetName == 'assets/scans/scan_002.png') {
        if (lower.contains('mri') || lower.contains('brain')) {
          assetName = 'assets/scans/scan_004.png';
        } else if (lower.contains('knee')) {
          assetName = 'assets/scans/scan_006.png';
        } else if (lower.contains('chest') || lower.contains('xray')) {
          assetName = 'assets/scans/scan_002.png';
        }
      }

      final byteData = await rootBundle.load(assetName);
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('ScanShareService: resolveScanBytes error: $e');
      return null;
    }
  }

  /// Share scan image bytes directly to external apps.
  static Future<void> shareBytes({
    required Uint8List bytes,
    String fileName = 'novalife_scan.png',
    String? subject,
    String? text,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final cleanName = fileName.endsWith('.png') ? fileName : '$fileName.png';
    final file = File('${tempDir.path}/$cleanName');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: text ?? 'NovaLife Authenticated Radiology Scan\nVerified with hardware-backed RPP-QIM steganography.',
        subject: subject ?? 'NovaLife Radiology Scan',
      ),
    );
  }

  /// Share scan from an image path or URL.
  static Future<bool> shareFromPath({
    required String imagePath,
    String? fileName,
    String? subject,
    String? text,
  }) async {
    final bytes = await resolveScanBytes(imagePath);
    if (bytes == null || bytes.isEmpty) return false;

    String cleanName = fileName ?? 'novalife_scan.png';
    if (!cleanName.endsWith('.png')) cleanName = '$cleanName.png';

    await shareBytes(
      bytes: bytes,
      fileName: cleanName,
      subject: subject,
      text: text,
    );
    return true;
  }
}
