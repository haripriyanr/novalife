// lib/screens/ehr_upload_screen.dart
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

  Future<void> _pickPng() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    final file = files.isEmpty ? null : files.first;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _coverPng = bytes;
      _coverName = file.name;
    });
    _toast('Picked ${_coverName!}');
  }

  void _useSyntheticCover() {
    final image = img.Image(width: 256, height: 256);
    for (int y = 0; y < 256; y++) {
      for (int x = 0; x < 256; x++) {
        image.setPixelRgb(x, y, (x * 37 + y) & 0xFF, (y * 53 + x) & 0xFF,
            ((x ^ y) * 19) & 0xFF);
      }
    }
    final pngBytes = Uint8List.fromList(img.encodePng(image));
    setState(() {
      _coverPng = pngBytes;
      _coverName = 'synthetic_phantom_256.png';
    });
    _toast('Generated 256×256 synthetic cover PNG');
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
        try {
          job = await HubJobsService.waitFor(job, timeout: const Duration(seconds: 45));
          if (job.status == HubJobStatus.done) {
            _toast('✅ Watermarked by FPGA PL Enclave!');
          }
        } catch (qe) {
          _toast('Board queue notice: $qe (proceeding with ledger record)');
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
                  onPressed: _busy ? null : _pickPng,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_coverName ?? 'Pick PNG'),
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
