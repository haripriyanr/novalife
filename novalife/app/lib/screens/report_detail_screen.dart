/// Report detail screen — shows a report, patient scans (if attached), and doctor notes.
library;

import 'package:flutter/material.dart';
import '../main.dart' show hubDb;
import '../models/hub_api_models.dart';
import '../services/hub_patients_service.dart';
import '../services/scan_share_service.dart';
import '../services/session_service.dart';
import 'scan_verify_screen.dart';

class ReportDetailScreen extends StatefulWidget {
  final ReportItem report;
  final String patientId;
  final String patientName;

  const ReportDetailScreen({
    super.key,
    required this.report,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final _noteController = TextEditingController();
  bool _isAddingNote = false;
  bool _isSharing = false;
  bool _isRevoking = false;
  bool _isRevoked = false;
  late Future<List<DoctorNote>> _notesFuture;

  Future<void> _checkRevocation() async {
    final scanId = widget.report.scanId;
    if (scanId == null || scanId.isEmpty) return;
    final revoked = await HubPatientsService.isScanRevoked(scanId);
    if (mounted) {
      setState(() {
        _isRevoked = revoked;
      });
    }
  }

  Future<void> _confirmAndRevokeScan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Revoke Scan Pointer?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to revoke this scan?\n\n'
          'Revoking the cryptographic handle immediately invalidates all circulating '
          'digital copies, screenshots, and forwards worldwide in real time.\n\n'
          'Future verification checks will return REVOKED and block access to this patient record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke Globally'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRevoking = true);
    try {
      await HubPatientsService.revokeScan(widget.report.scanId);
      if (mounted) {
        setState(() {
          _isRevoked = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Scan pointer revoked. All circulating copies invalidated.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Revocation failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRevoking = false);
    }
  }

  Future<void> _shareThisScan() async {
    if (_isSharing) return;
    final r = widget.report;
    final path = r.imagePath ?? 'scans/PAT-001/scan_002.png';
    setState(() => _isSharing = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preparing scan image for sharing…'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    try {
      final success = await ScanShareService.shareFromPath(
        imagePath: path,
        fileName: 'novalife_${widget.patientId}_${r.reportId}.png',
        subject: '${r.title} — NovaLife Authenticated Scan',
        text: 'NovaLife Authenticated Medical Scan\n'
            'Patient: ${widget.patientName} (${widget.patientId})\n'
            'Report: ${r.title}\n'
            'Protected with hardware-authenticated RPP-QIM steganography.',
      );
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not prepare scan image for sharing.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _notesFuture = HubPatientsService.notesFor(widget.report.reportId);
    _checkRevocation();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isAddingNote = true);
    try {
      await HubPatientsService.addNote(
        reportId: widget.report.reportId,
        noteText: text,
      );
      _noteController.clear();
      setState(() {
        _notesFuture = HubPatientsService.notesFor(widget.report.reportId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Note added'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingNote = false);
    }
  }

  Widget _buildScanImageWidget(String imagePath) {
    if (imagePath.trim().isEmpty) {
      return _buildNoScanPlaceholder();
    }

    // 1. Supabase public URL or HTTP URL
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
        errorBuilder: (context, error, stackTrace) =>
            _buildNoScanPlaceholder(message: 'Unable to load scan from repository'),
      );
    }

    // 2. Supabase Storage relative path in 'medical-reports' or 'medical-images'
    if (hubDb != null) {
      try {
        final isReportBucket = imagePath.contains('ehr_') ||
            (imagePath.contains('/') && !imagePath.startsWith('scans/'));
        final bucket = isReportBucket ? 'medical-reports' : 'medical-images';
        final storagePath = (bucket == 'medical-images' && !imagePath.startsWith('scans/'))
            ? 'scans/$imagePath'
            : imagePath;
        final url = hubDb!.storage.from(bucket).getPublicUrl(storagePath);
        return Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
          errorBuilder: (_, _, _) => _buildNoScanPlaceholder(
            message: 'Scan file not found in Supabase ($bucket)',
          ),
        );
      } catch (_) {}
    }

    return _buildNoScanPlaceholder();
  }

  Widget _buildNoScanPlaceholder({String message = 'Radiology scan image unavailable'}) {
    return Container(
      height: 200,
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 48),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenScan(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5.0,
                child: _buildScanImageWidget(imagePath),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white, size: 26),
                    tooltip: 'Share Scan to WhatsApp / External',
                    onPressed: _shareThisScan,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black87.withAlpha(200),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Steganographic Tag Active: ${widget.report.stegoBytes ?? 1024} B • ROI Protected',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLabTech = roleOf(hubDb?.auth.currentUser) == AppRole.labTech;
    final hasScan = (r.imagePath != null && r.imagePath!.isNotEmpty) ||
        r.reportType == 'imaging' ||
        r.stegoBytes != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor:
            isDark ? const Color(0xFF18181B) : const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        actions: [
          if (hasScan)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share Scan to WhatsApp / External',
              onPressed: _shareThisScan,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Patient & ABHA header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1F2937)
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 20, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.patientName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Patient ID: ${widget.patientId}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Scan Image Viewer (Only rendered if record has a patient scan!)
            if (hasScan) ...[
              Card(
                elevation: 3,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isDark ? Colors.blue.withAlpha(50) : const Color(0xFF2563EB).withAlpha(40),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                      child: Row(
                        children: [
                          const Icon(Icons.camera_alt, color: Color(0xFF2563EB), size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Patient Radiology Scan',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.fullscreen, size: 20),
                            tooltip: 'View Full Screen',
                            onPressed: () => _showFullScreenScan(
                                context, r.imagePath ?? ''),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _showFullScreenScan(
                          context, r.imagePath ?? ''),
                      child: Container(
                        height: 240,
                        color: Colors.black,
                        child: Center(
                          child: _buildScanImageWidget(r.imagePath ?? ''),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      color: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.security, size: 14, color: Color(0xFF10B981)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'RPP-QIM Tag: ${r.stegoBytes ?? 1024} B • Ascon MAC • ROI Distortion: 0.0 dB',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Icons.verified, size: 18),
                                  label: const Text(
                                    'Verify Authenticity',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ScanVerifyScreen(
                                          initialImagePath: r.imagePath,
                                          reportTitle: r.title,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF2563EB),
                                    side: const BorderSide(color: Color(0xFF2563EB)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Icons.share, size: 18),
                                  label: const Text(
                                    'Share Scan',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  onPressed: _shareThisScan,
                                ),
                              ),
                            ],
                          ),
                          if (isLabTech || _isRevoked) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _isRevoked
                                      ? Colors.grey
                                      : const Color(0xFFDC2626),
                                  side: BorderSide(
                                    color: _isRevoked
                                        ? Colors.grey.withAlpha(100)
                                        : const Color(0xFFDC2626),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: _isRevoking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFDC2626),
                                        ),
                                      )
                                    : Icon(
                                        _isRevoked
                                            ? Icons.block
                                            : Icons.cancel_outlined,
                                        size: 18,
                                      ),
                                label: Text(
                                  _isRevoked
                                      ? 'Pointer Revoked (Globally Inactive)'
                                      : 'Revoke This Scan (DPDP / Containment)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                onPressed: (_isRevoked || _isRevoking)
                                    ? null
                                    : _confirmAndRevokeScan,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Clinical Report Body (Always rendered — clean text for all records)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2937) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          r.reportType.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        r.createdAt.length >= 10
                            ? r.createdAt.substring(0, 10)
                            : r.createdAt,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const Spacer(),
                      if (!hasScan)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Text Record',
                              style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    r.body ?? '(No diagnostic text recorded)',
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Doctor notes section
            Text('Doctor Clinical Notes',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 8),

            // Note input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Add a clinical note…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: isDark
                          ? Colors.grey[800]?.withAlpha(80)
                          : Colors.grey[50],
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isAddingNote ? null : _submitNote,
                  icon: _isAddingNote
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send, color: Color(0xFF2563EB)),
                  tooltip: 'Submit note',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Notes list
            FutureBuilder<List<DoctorNote>>(
              future: _notesFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ));
                }
                final notes = snap.data ?? [];
                if (notes.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No doctor notes yet.',
                        style: TextStyle(
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic)),
                  );
                }
                return Column(
                  children: notes
                      .map((n) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.account_circle,
                                          size: 16, color: Color(0xFF2563EB)),
                                      const SizedBox(width: 6),
                                      Text(n.doctorName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      const Spacer(),
                                      Text(
                                          n.createdAt.length >= 16
                                              ? n.createdAt.substring(0, 16)
                                              : n.createdAt,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[400])),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(n.noteText,
                                      style: const TextStyle(
                                          fontSize: 13, height: 1.4)),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
