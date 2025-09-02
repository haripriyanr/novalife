import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ehr_decryptor.dart';

class EHRReportView extends StatefulWidget {
  final String fullPath; // e.g. '<uuid>/report1.png'
  final bool isBucketPublic;

  const EHRReportView({
    super.key,
    required this.fullPath,
    this.isBucketPublic = false,
  });

  @override
  State<EHRReportView> createState() => _EHRReportViewState();
}

class _EHRReportViewState extends State<EHRReportView> {
  late Future<_Result> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAndDecrypt();
  }

  Future<_Result> _loadAndDecrypt() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not authenticated');
    }
    // Download stego image bytes from Storage
    final stego = await supabase.storage
        .from('medical-reports')
        .download(widget.fullPath); // [download example][10]

    // Extract + decrypt using UUID password
    final clear = await EHRDecryptor.extractAndDecrypt(
      stegoBytes: stego,
      uuid: user.id,
    );

    // Try UTF-8 text; fallback to bytes
    String? utf8Text;
    try {
      utf8Text = utf8.decode(clear);
    } catch (_) {
      utf8Text = null;
    }
    return _Result(stego: stego, clear: clear, text: utf8Text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const AutoSizeText('EHR Report', maxLines: 1),
        backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFF7C3AED),
      ),
      body: FutureBuilder<_Result>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to decrypt: ${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }

          final res = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Original stego image (zoom on tap)
                _sectionTitle('Report Image', isDark),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _openFullImage(res.stego),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      res.stego,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Decrypted content
                _sectionTitle('Decrypted Data', isDark),
                const SizedBox(height: 8),
                if (res.text != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2937) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SelectableText(
                      res.text!,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        height: 1.4,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2937) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      'Binary data (${res.clear.length} bytes).',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white : const Color(0xFF111827),
      ),
    );
  }

  void _openFullImage(Uint8List bytes) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(0),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Center(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 28,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Result {
  final Uint8List stego;
  final Uint8List clear;
  final String? text;
  _Result({required this.stego, required this.clear, required this.text});
}
