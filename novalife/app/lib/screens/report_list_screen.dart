/// Report list screen — all reports for a single patient.
///
/// Tap a report to see its detail view with doctor notes.
library;

import 'package:flutter/material.dart';
import '../models/hub_api_models.dart';
import '../services/hub_patients_service.dart';
import '../services/scan_share_service.dart';
import 'report_detail_screen.dart';

class ReportListScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String abhaId;

  const ReportListScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.abhaId,
  });

  @override
  State<ReportListScreen> createState() => _ReportListScreenState();
}

class _ReportListScreenState extends State<ReportListScreen> {
  late Future<ReportsResponse> _future;

  @override
  void initState() {
    super.initState();
    _future = HubPatientsService.reportsFor(widget.patientId);
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

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.patientName} — Reports'),
        backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<ReportsResponse>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final resp = snap.data!;
          if (resp.reports.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  const Text('No reports for this patient'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: resp.reports.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = resp.reports[i];
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _typeColor(r.reportType).withAlpha(30),
                    child: Icon(_typeIcon(r.reportType), color: _typeColor(r.reportType), size: 20),
                  ),
                  title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        r.body ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _typeColor(r.reportType).withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(r.reportType, style: TextStyle(fontSize: 10, color: _typeColor(r.reportType))),
                          ),
                          Text(r.createdAt.length >= 10 ? r.createdAt.substring(0, 10) : r.createdAt, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                          if (r.imagePath != null || r.reportType == 'imaging' || r.stegoBytes != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withAlpha(20),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image, size: 10, color: Color(0xFF2563EB)),
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
                              fileName: 'novalife_${widget.patientId}_${r.reportId}.png',
                              subject: '${r.title} — NovaLife Authenticated Scan',
                              text: 'NovaLife Authenticated Medical Scan\n'
                                  'Patient: ${widget.patientName} (${widget.patientId})\n'
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
                          patientId: widget.patientId,
                          patientName: widget.patientName,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
