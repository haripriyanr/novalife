// lib/screens/ehr_upload_screen.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ehr_service.dart';
import '../services/hub_patients_service.dart';
import '../services/hub_jobs_service.dart';
import '../services/scan_share_service.dart';
import '../services/session_service.dart';
import '../main.dart' show hubDb;
import 'package:image/image.dart' as img;

class EHRUploadScreen extends StatefulWidget {
  final String? initialText;
  const EHRUploadScreen({super.key, this.initialText});
  @override
  State<EHRUploadScreen> createState() => _EHRUploadScreenState();
}

class _EHRUploadScreenState extends State<EHRUploadScreen> {
  Uint8List? _coverPng;
  String? _coverName;
  final _titleCtrl = TextEditingController(text: 'Lab Scan Report');
  final _textCtrl = TextEditingController();
  String _reportType = 'lab';
  List<Map<String, dynamic>> _patients = [];
  String? _selectedPatientId;
  bool _loadingPatients = true;
  bool _busy = false;
  bool _markWithFpga = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _textCtrl.text = widget.initialText!.trim();
    }
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() => _loadingPatients = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final myAbha = abhaOf(user);
      final myPid = patientIdOf(user);
      final list = await HubPatientsService.listPatients(
        excludeAbha: myAbha,
        excludePatientId: myPid,
      );
      if (!mounted) return;
      setState(() {
        _patients = list;
        if (_patients.isNotEmpty && _selectedPatientId == null) {
          _selectedPatientId = _patients.first['patient_id'] as String?;
        }
        _loadingPatients = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPatients = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickImage() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'PNG', 'JPG', 'JPEG'],
    );
    final file = files.isEmpty ? null : files.first;
    if (file == null) return;
    Uint8List bytes = await file.readAsBytes();
    String name = file.name;

    // Decode and ensure clinical watermark capacity & normalize clipped pixels
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      // RPP-QIM algorithm requires at least 512x512 spatial resolution
      // (1024 blocks of 8x8 in 1-level LL subband) with even dimensions.
      // Scaling to 512-768 px ensures fast UART transfer (< 90 KB in 8-bit grayscale PNG,
      // ~3-7 seconds over 115200 baud, well within the board's 25s timeout).
      final minDim = math.min(decoded.width, decoded.height);
      final maxDim = math.max(decoded.width, decoded.height);
      double scale = 1.0;
      if (minDim < 512) {
        scale = 512.0 / minDim;
      }
      if (maxDim * scale > 768) {
        scale = 768.0 / maxDim;
      }

      int newW = (decoded.width * scale).round();
      int newH = (decoded.height * scale).round();
      if (newW % 2 != 0) newW++;
      if (newH % 2 != 0) newH++;

      img.Image processed = decoded;
      if (newW != decoded.width || newH != decoded.height) {
        processed = img.copyResize(decoded, width: newW, height: newH, interpolation: img.Interpolation.cubic);
      }
      processed = img.grayscale(processed);

      // Intake amplitude normalization: lift pure black margins (< 16) to 16
      // so the placement blocks are not clipped/tainted out
      for (int y = 0; y < processed.height; y++) {
        for (int x = 0; x < processed.width; x++) {
          final p = processed.getPixel(x, y);
          if (p.r < 16) {
            processed.setPixelRgb(x, y, 16, 16, 16);
          }
        }
      }

      bytes = Uint8List.fromList(img.encodePng(processed, level: 6));
      name = '${name.split('.').first}.png';
    }

    setState(() {
      _coverPng = bytes;
      _coverName = name;
    });
    _toast('Prepared $name for marking');
  }

  void _useSyntheticCover() {
    final image = img.Image(width: 512, height: 512);
    for (int y = 0; y < 512; y++) {
      for (int x = 0; x < 512; x++) {
        final val = 20 + ((x * 37 + y * 53) % 200);
        image.setPixelRgb(x, y, val, val, val);
      }
    }
    final gray = img.grayscale(image);
    final pngBytes = Uint8List.fromList(img.encodePng(gray, level: 6));
    setState(() {
      _coverPng = pngBytes;
      _coverName = 'synthetic_phantom_512.png';
    });
    _toast('Generated 512×512 synthetic cover PNG (${(pngBytes.length / 1024).toStringAsFixed(1)} KB)');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAndUpload() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return _fail('Not authenticated');
    if (_selectedPatientId == null || _selectedPatientId!.isEmpty) {
      return _fail('Select a patient to assign this report');
    }
    if (_coverPng == null) return _fail('Pick or generate a PNG image');
    if (_textCtrl.text.trim().isEmpty) return _fail('Enter the report text');

    setState(() => _busy = true);
    try {
      final uuid = user.id;
      Uint8List imageBytes = _coverPng!;

      // 1. If FPGA marking requested, queue job for PL Enclave
      if (_markWithFpga && hubDb != null) {
        _toast('Queuing scan for FPGA hardware marking...');
        final qName = 'mark_${DateTime.now().millisecondsSinceEpoch}.png';
        final qPath = await HubJobsService.uploadJobScan(imageBytes, qName);
        var job = await HubJobsService.submitMarkImage(imagePath: qPath);
        final pos = await HubJobsService.queuePosition(job);
        if (mounted && pos > 0) {
          _toast('Queued for hardware watermark (#$pos in queue)...');
        }
        // The board moves ~100 KB each way over a 115200-baud ESP32 link (up to 60 s per transfer),
        // and the server re-queues a job that runs longer than 120 s, so wait past that.
        job = await HubJobsService.waitFor(job, timeout: const Duration(seconds: 180));
        if (job.status == HubJobStatus.done) {
          _toast('✅ Watermarked by FPGA PL Enclave!');
          // Download marked PNG produced by board.  Never fall back to the unmarked cover: an
          // unmarked upload would look marked and fail every later verification.
          final resultPath = job.markedResultPath.isNotEmpty ? job.markedResultPath : '$uuid/results/${job.id}.png';
          try {
            imageBytes = await hubDb!.storage.from('hub-jobs').download(resultPath);
          } catch (err) {
            throw HubJobsException('The board marked the scan but the marked image could not be downloaded '
                '($err). Aborting upload.');
          }
        } else if (job.status == HubJobStatus.failed) {
          throw HubJobsException('FPGA Watermarking failed: ${job.error ?? 'image unmarkable'}. Aborting upload.');
        } else {
          throw HubJobsException('FPGA Watermarking did not complete in time (status: ${job.status}). Aborting upload.');
        }
      }

      // 2. Upload scan to clinical repository
      final name = 'ehr_${DateTime.now().millisecondsSinceEpoch}.png';
      final path = '$uuid/$name';
      await EHRService.uploadReportBytes(
          fullPath: path, bytes: imageBytes, upsert: true);

      final sha256Hex = sha256.convert(imageBytes).toString();
      await HubPatientsService.recordLabUpload(
        patientId: _selectedPatientId!,
        title: _titleCtrl.text.trim().isEmpty
            ? 'Lab Scan Report'
            : _titleCtrl.text.trim(),
        body: _textCtrl.text.trim(),
        reportType: _reportType,
        imagePath: path,
        imageBytes: imageBytes.length,
        sha256: sha256Hex,
        issuedBy: uuid,
      );

      _toast('✅ Uploaded to $_selectedPatientId');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
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
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assign & Upload Scan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Patient Dropdown
          if (_loadingPatients)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedPatientId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Assign to Patient',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              items: _patients.map((p) {
                final pid = p['patient_id'] as String;
                final name = p['full_name'] as String;
                final abha = p['abha_id'] as String;
                return DropdownMenuItem<String>(
                  value: pid,
                  child: Text(
                    '$name ($pid • ABHA $abha)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _busy
                  ? null
                  : (val) => setState(() => _selectedPatientId = val),
            ),
          const SizedBox(height: 12),

          // Report Title & Type
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Report Title',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _reportType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'lab', child: Text('Lab')),
                    DropdownMenuItem(value: 'imaging', child: Text('Imaging')),
                    DropdownMenuItem(
                        value: 'clinical', child: Text('Clinical')),
                    DropdownMenuItem(
                        value: 'discharge', child: Text('Discharge')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _reportType = v ?? 'lab'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Image selection
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_coverName ?? 'Pick Scan (JPG / PNG)'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _useSyntheticCover,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Sample PNG'),
              ),
            ],
          ),
          if (_coverPng != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_coverPng!, height: 140, fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Share Selected Scan (WhatsApp / External)'),
              onPressed: () => ScanShareService.shareBytes(
                bytes: _coverPng!,
                fileName: _coverName ?? 'novalife_scan.png',
                text: 'NovaLife Radiology Scan from Lab Tech • Assigned to ${_selectedPatientId ?? "Patient"}',
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _textCtrl,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Report Text',
              hintText: 'Enter the clinical report text…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('FPGA Hardware Watermark', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Queue job for Zynq-7000 PL Enclave authentication'),
            secondary: const Icon(Icons.memory, color: Colors.blueAccent),
            value: _markWithFpga,
            onChanged: _busy ? null : (v) => setState(() => _markWithFpga = v),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _runAndUpload,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: Text(_busy
                ? 'Uploading…'
                : 'Upload • Assign to Patient'),
          ),
        ],
      ),
    );
  }
}
