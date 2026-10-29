import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/demo_mode.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crypto/crypto.dart';

import '../services/hub_jobs_service.dart';
import '../services/scan_share_service.dart';
import '../main.dart';

/// Scan-and-verify screen: pick an image (from gallery, camera, or passed from
/// a patient record), verify its RPP-QIM tag and Ascon MAC authenticity
/// against the Hub Enclave and Supabase Trust Ledger, and display the audit verdict.
class ScanVerifyScreen extends StatefulWidget {

  /// Development hook: when set, shown as footnote.
  final String? devNote;

  /// Pre-loaded scan image path or URL (e.g. from a report detail card).
  final String? initialImagePath;

  /// Pre-loaded scan raw bytes.
  final Uint8List? initialImageBytes;

  /// Name of the record or scan being verified.
  final String? reportTitle;

  const ScanVerifyScreen({
    super.key,
    this.devNote,
    this.initialImagePath,
    this.initialImageBytes,
    this.reportTitle,
  });

  @override
  State<ScanVerifyScreen> createState() => _ScanVerifyScreenState();
}

class _ScanVerifyScreenState extends State<ScanVerifyScreen> {
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  bool _busy = false;
  String? _result;
  String? _handle;
  bool _verified = false;
  String? _error;
  String? _sha256Hex;
  Map<String, dynamic>? _auditDetails;

  @override
  void initState() {
    super.initState();
    _loadInitialImage();
  }

  Future<void> _loadInitialImage() async {
    if (widget.initialImageBytes != null) {
      setState(() {
        _imageBytes = widget.initialImageBytes;
        _sha256Hex = sha256.convert(_imageBytes!).toString();
      });
      return;
    }

    final path = widget.initialImagePath;
    if (path != null && path.trim().isNotEmpty) {
      setState(() => _busy = true);
      try {
        Uint8List? bytes;

        // 1. Full HTTP or HTTPS URL
        if (path.startsWith('http://') || path.startsWith('https://')) {
          try {
            final res = await http.get(Uri.parse(path)).timeout(const Duration(seconds: 8));
            if (res.statusCode == 200) bytes = res.bodyBytes;
          } catch (_) {}
        }

        // 2. Supabase storage relative path (medical-reports vs medical-images)
        if (bytes == null && hubDb != null) {
          try {
            final isReport = path.contains('ehr_') || (path.contains('/') && !path.startsWith('scans/'));
            final bucket = isReport ? 'medical-reports' : 'medical-images';
            final storagePath = (bucket == 'medical-images' && !path.startsWith('scans/')) ? 'scans/$path' : path;
            try {
              bytes = await hubDb!.storage.from(bucket).download(storagePath);
            } catch (_) {
              final url = hubDb!.storage.from(bucket).getPublicUrl(storagePath);
              final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
              if (res.statusCode == 200) bytes = res.bodyBytes;
            }
          } catch (_) {}
        }

        if (mounted) {
          setState(() {
            _imageBytes = bytes;
            if (bytes != null) {
              _sha256Hex = sha256.convert(bytes).toString();
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading initial verification image from Supabase: $e');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _sha256Hex = sha256.convert(bytes).toString();
          _result = null;
          _handle = null;
          _verified = false;
          _error = null;
          _auditDetails = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Failed to load image: $e');
    }
  }

  /// Verify through the board: the image goes to private storage, a `verify_image` job is queued, the
  /// board's PL enclave checks the tag and the server checks the handle.  The verdict comes ONLY from
  /// that job: a matching file hash or a timeout never turns into "verified".
  Future<void> _verify() async {
    final bytes = _imageBytes;
    if (bytes == null) return;

    setState(() {
      _busy = true;
      _result = null;
      _handle = null;
      _verified = false;
      _error = null;
      _auditDetails = null;
    });

    try {
      if (hubDb == null || hubDb!.auth.currentUser == null) {
        throw const HubDataException('Sign in first: verification runs through your account.');
      }
      final currentHash = _sha256Hex ?? sha256.convert(bytes).toString();
      final filename = 'verify_${DateTime.now().millisecondsSinceEpoch}.png';
      final storagePath = await HubJobsService.uploadJobScan(bytes, filename);
      var job = await HubJobsService.submitVerifyImage(imagePath: storagePath);
      final pos = await HubJobsService.queuePosition(job);
      if (mounted && pos > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Waiting for the board: $pos job(s) ahead of yours.')),
        );
      }
      job = await HubJobsService.waitFor(job, timeout: const Duration(seconds: 120));

      final verdict = job.verdict; // pass | fail | revoked | unknown (set by the server)
      final res = job.result ?? const <String, dynamic>{};
      // A handle means something only when the PL accepted the tag's MAC; on a failed check the
      // board still reports the bits it decoded, which are noise.
      final tagGenuine = verdict == 'pass' || verdict == 'revoked' || verdict == 'unknown';
      final handle = tagGenuine ? res['handle']?.toString() : null;
      final (verified, headline) = switch (verdict) {
        'pass' => (true, 'Authentic: the tag is genuine and the record is live'),
        'revoked' => (false, 'Revoked: this record was withdrawn'),
        'unknown' => (false, 'The tag is genuine but the record is not registered here'),
        'fail' => (false, 'Not verified: no valid tag was found in this image'),
        _ => (false, job.status == HubJobStatus.failed
            ? 'Not verified: ${job.error ?? 'the board could not read a valid tag'}'
            : 'No verdict was returned'),
      };
      setState(() {
        _verified = verified;
        _handle = handle;
        _result = headline;
        _auditDetails = {
          'status': verified ? 'VALID' : 'NOT VERIFIED',
          'channel': 'Zynq PL enclave via the cloud queue (job ${job.id.substring(0, 8)})',
          'hash': currentHash,
          'plCycles': ?res['pl_cycles'],
          'verdict': ?verdict,
        };
      });
    } on HubDataException catch (e) {
      setState(() => _error = e.message);
    } on HubJobsException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Verification could not be completed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareCurrentImage() async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing scan image…'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    await ScanShareService.shareBytes(
      bytes: bytes,
      fileName: 'novalife_scan_auth.png',
      subject: 'NovaLife Authenticated Medical Scan',
      text: _verified
          ? 'NovaLife Authenticated Radiology Scan\n'
            'Status: Authenticated & Integrity Verified (Zynq-7000 FPGA Enclave)\n'
            'Tag Handle: ${_auditDetails?['tag_handle'] ?? 'Active'}\n'
            'Survives chat-app compression with exact 128-bit payload recovery.'
          : 'NovaLife Medical Radiology Scan',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan & Verify Authenticity'),
        backgroundColor:
            isDark ? const Color(0xFF18181B) : const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        actions: [
          if (_imageBytes != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share Scan to WhatsApp / External',
              onPressed: _shareCurrentImage,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Target report header if verifying a specific record
            if (widget.reportTitle != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF3B82F6).withAlpha(80)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, color: Color(0xFF2563EB), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Target Record: ${widget.reportTitle}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Scan Preview Container
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.black87,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _verified
                      ? const Color(0xFF10B981)
                      : (_result != null ? Colors.red : Colors.grey.withAlpha(60)),
                  width: _result != null ? 2.0 : 1.0,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Center(
                  child: _imageBytes != null
                      ? Image.memory(
                          _imageBytes!,
                          fit: BoxFit.contain,
                          height: 250,
                          width: double.infinity,
                        )
                      : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_search_outlined,
                                  size: 56,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No medical scan loaded',
                                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Choose an option below to authenticate',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                ),
                              ],
                            ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Pick Image Buttons (Gallery & Camera)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Upload Photo', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Take Photo', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Main Verify Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_busy || _imageBytes == null) ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.verified, size: 20),
                label: Text(
                  _busy ? 'Authenticating Scan...' : 'Verify Scan Authenticity',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Verification Result Card
            if (_auditDetails != null) ...[
              Card(
                elevation: 3,
                color: _verified
                    ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5))
                    : (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEF2F2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: _verified ? const Color(0xFF10B981) : Colors.red,
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _verified ? Icons.check_circle : Icons.cancel,
                            color: _verified ? const Color(0xFF10B981) : Colors.red,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _verified
                                      ? 'AUTHENTIC & INTEGRITY VERIFIED'
                                      : 'UNAUTHENTICATED / UNTRUSTED',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    letterSpacing: 0.5,
                                    color: _verified
                                        ? (isDark ? Colors.green[300] : const Color(0xFF047857))
                                        : (isDark ? Colors.red[300] : Colors.red[800]),
                                  ),
                                ),
                                Text(
                                  _result ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.grey[300] : Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildAuditRow('Record handle', _handle ?? 'not read', isDark),
                      if (_auditDetails!['plCycles'] != null)
                        _buildAuditRow('Hardware check', '${_auditDetails!['plCycles']} PL clock cycles', isDark),
                      _buildAuditRow('Verification Channel', _auditDetails!['channel'] ?? 'N/A', isDark),
                      _buildAuditRow('Verdict', _auditDetails!['verdict']?.toString() ?? 'none', isDark),
                      const SizedBox(height: 6),
                      Text(
                        'SHA-256 Fingerprint:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        _auditDetails!['hash'] ?? '',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _verified
                                ? const Color(0xFF10B981)
                                : (isDark ? Colors.white70 : Colors.black87),
                            side: BorderSide(
                              color: _verified
                                  ? const Color(0xFF10B981)
                                  : (isDark ? Colors.white30 : Colors.black26),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text(
                            'Share Verified Scan (WhatsApp / External)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          onPressed: _shareCurrentImage,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_error != null) ...[
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Explanatory note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.devNote ??
                    'NovaLife Steganographic Authentication: The image contains a reversible, '
                    'tamper-evident RPP-QIM payload embedded in the 5/3 IWT LL band with Ascon AEAD. '
                    'Verification proves origin authenticity, zero diagnostic ROI alteration, and clinical ownership.',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuditRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
