/// Patient records screen — displays only the signed-in patient's own reports.
library;

import 'package:flutter/material.dart';
import '../main.dart' show hubDb;
import '../models/hub_api_models.dart';
import '../services/hub_patients_service.dart';
import '../services/scan_share_service.dart';
import '../services/session_service.dart';
import 'report_detail_screen.dart';

class PatientRecordsScreen extends StatefulWidget {
  final String? abhaId;

  const PatientRecordsScreen({super.key, this.abhaId});

  @override
  State<PatientRecordsScreen> createState() => _PatientRecordsScreenState();
}

class _PatientRecordsScreenState extends State<PatientRecordsScreen> {
  ReportsResponse? _reportsResp;
  String _patientName = 'My Records';
  String _patientId = 'PAT-001';
  String _abhaDisplay = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOwnRecords();
  }

  Future<void> _loadOwnRecords() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String? resolvedPatientId;
      String? resolvedAbha = widget.abhaId;
      final db = hubDb;
      final user = db?.auth.currentUser;

      if (user != null) {
        final fullName = user.userMetadata?['full_name']?.toString();
        if (fullName != null && fullName.isNotEmpty) {
          _patientName = fullName;
        }
        resolvedAbha ??= abhaOf(user);
        resolvedPatientId ??= patientIdOf(user);
        // 1. Try hub_identity_links for explicit patient_id mapping
        try {
          final link = await db!
              .from('hub_identity_links')
              .select('patient_id')
              .eq('auth_uid', user.id)
              .maybeSingle();
          final linkedId = link?['patient_id'] as String?;
          if (linkedId != null && linkedId.isNotEmpty) {
            resolvedPatientId = linkedId;
          }
        } catch (_) {}
      }

      // 2. Try resolving by ABHA ID if not linked yet
      if (resolvedPatientId == null &&
          resolvedAbha != null &&
          resolvedAbha.isNotEmpty) {
        resolvedPatientId =
            await HubPatientsService.patientIdForAbha(resolvedAbha);
      }

      // 3. Fallback to PAT-001 for demo patient accounts
      resolvedPatientId ??= 'PAT-001';
      resolvedAbha ??= '12345678901234';

      final resp = await HubPatientsService.reportsFor(
        resolvedPatientId,
        patientName: _patientName,
        abhaId: resolvedAbha,
      );

      if (mounted) {
        setState(() {
          _patientId = resolvedPatientId!;
          _abhaDisplay = resp.abhaId ?? resolvedAbha!;
          _reportsResp = resp;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  IconData _typeIcon(String type) => switch (type) {
        'lab' => Icons.science,
        'imaging' => Icons.radio,
        'clinical' => Icons.medical_services,
        'discharge' => Icons.local_hospital,
        _ => Icons.description,
      };

  Color _typeColor(String type) => switch (type) {
        'lab' => const Color(0xFF10B981),
        'imaging' => const Color(0xFF8B5CF6),
        'clinical' => const Color(0xFFF59E0B),
        'discharge' => const Color(0xFFEF4444),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reports = _reportsResp?.reports ?? const <ReportItem>[];

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Could not load records: $_error'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadOwnRecords,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadOwnRecords,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1F2937)
                              : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFF2563EB),
                              child: Icon(Icons.badge_outlined,
                                  color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _patientName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Patient ID: $_patientId  •  ABHA: $_abhaDisplay',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (reports.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            children: [
                              Icon(Icons.folder_off,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              const Text('No medical records found'),
                            ],
                          ),
                        )
                      else
                        ...reports.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      _typeColor(r.reportType).withAlpha(30),
                                  child: Icon(
                                    _typeIcon(r.reportType),
                                    color: _typeColor(r.reportType),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  r.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text(
                                      r.body ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _typeColor(r.reportType)
                                                .withAlpha(25),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            r.reportType,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: _typeColor(r.reportType),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          r.createdAt.length >= 10
                                              ? r.createdAt.substring(0, 10)
                                              : r.createdAt,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[400],
                                          ),
                                        ),
                                        if (r.imagePath != null ||
                                            r.reportType == 'imaging' ||
                                            r.stegoBytes != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withAlpha(20),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.image,
                                                    size: 10,
                                                    color: Color(0xFF2563EB)),
                                                SizedBox(width: 3),
                                                Text(
                                                  'Scan',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFF2563EB),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (r.imagePath != null ||
                                        r.reportType == 'imaging' ||
                                        r.stegoBytes != null)
                                      IconButton(
                                        icon: const Icon(Icons.share_outlined,
                                            size: 20, color: Color(0xFF2563EB)),
                                        tooltip: 'Share Scan to WhatsApp / External',
                                        onPressed: () {
                                          ScanShareService.shareFromPath(
                                            imagePath: r.imagePath ?? 'scans/PAT-001/scan_002.png',
                                            fileName: 'novalife_${_patientId}_${r.reportId}.png',
                                            subject: '${r.title} — NovaLife Authenticated Scan',
                                            text: 'NovaLife Authenticated Medical Scan\n'
                                                'Patient: $_patientName ($_patientId)\n'
                                                'Report: ${r.title}\n'
                                                'Protected with hardware-authenticated RPP-QIM steganography.',
                                          );
                                        },
                                      ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ReportDetailScreen(
                                        report: r,
                                        patientId: _patientId,
                                        patientName: _patientName,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
