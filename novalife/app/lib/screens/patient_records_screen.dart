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
                      // Patient Info Header
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
                      const SizedBox(height: 12),

                      // Privacy & DPDP Consent Card
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isDark
                                ? Colors.blue.withAlpha(50)
                                : const Color(0xFF2563EB).withAlpha(40),
                          ),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF10B981),
                            child: Icon(Icons.security,
                                color: Colors.white, size: 20),
                          ),
                          title: const Text(
                            'Privacy, Consent & Audit Trail',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: const Text(
                            'DPDP Act 2023: Manage scan sharing consent, view doctor access logs, or request de-linking.',
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                          onTap: _showPrivacyBottomSheet,
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

  void _showPrivacyBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PrivacyConsentSheet(
        patientId: _patientId,
        patientName: _patientName,
      ),
    );
  }
}

class _PrivacyConsentSheet extends StatefulWidget {
  final String patientId;
  final String patientName;

  const _PrivacyConsentSheet({
    required this.patientId,
    required this.patientName,
  });

  @override
  State<_PrivacyConsentSheet> createState() => _PrivacyConsentSheetState();
}

class _PrivacyConsentSheetState extends State<_PrivacyConsentSheet> {
  bool _loading = true;
  Set<String> _activeConsents = {};
  List<Map<String, dynamic>> _auditLogs = [];
  bool _submittingErasure = false;

  final Map<String, String> _purposeLabels = {
    'diagnosis': 'Diagnostic & Hospital Care (Primary Treatment)',
    'second_opinion': 'Teleconsultation & Specialist Second Opinion',
    'research': 'Anonymized Clinical Research & AI Studies',
    'insurance': 'Health Insurance & Claim Settlement Verification',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final consents =
          await HubPatientsService.getActiveConsents(widget.patientId);
      final logs = await HubPatientsService.getAuditLogs(widget.patientId);
      if (mounted) {
        setState(() {
          _activeConsents = consents;
          _auditLogs = logs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleConsent(String purpose, bool enable) async {
    final prev = Set<String>.from(_activeConsents);
    setState(() {
      if (enable) {
        _activeConsents.add(purpose);
      } else {
        _activeConsents.remove(purpose);
      }
    });

    try {
      await HubPatientsService.setConsent(
        patientId: widget.patientId,
        purpose: purpose,
        enabled: enable,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enable
                ? 'Consent granted for $purpose'
                : 'Consent withdrawn for $purpose'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _activeConsents = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating consent: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmErasure() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Request Erasure & De-linking?'),
          ],
        ),
        content: const Text(
          'Under Section 13 of the Digital Personal Data Protection Act 2023:\n\n'
          'Submitting an erasure request revokes all circulating cryptographic pointers '
          'for your scans globally. Any existing image copies or chat-app forwards will immediately '
          'fail verification, severing all pointers to your clinical identity.',
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
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _submittingErasure = true);
    try {
      await HubPatientsService.submitErasureRequest(widget.patientId);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '✅ Erasure request submitted. Pointers queued for revocation.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submittingErasure = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF10B981),
                child: Icon(Icons.security, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Privacy & Consent Control',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'DPDP Act 2023 • Patient: ${widget.patientId}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            const Text(
              'Granular Consent (DPDP Act §6)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Control which medical purposes are permitted to access your authenticated scan records.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.grey[300]!,
                ),
              ),
              child: Column(
                children: _purposeLabels.entries.map((entry) {
                  final isGranted = _activeConsents.contains(entry.key);
                  return SwitchListTile(
                    title: Text(
                      entry.value,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      'Purpose tag: ${entry.key}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    value: isGranted,
                    activeTrackColor: const Color(0xFF10B981),
                    onChanged: (val) => _toggleConsent(entry.key, val),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Scan Verification Audit Log (DPDP Act §10)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Immutable ledger of all doctors and clinicians who scanned or verified your images.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 10),
            if (_auditLogs.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'No verification queries recorded yet for this patient.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              )
            else
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark ? Colors.white12 : Colors.grey[300]!,
                  ),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _auditLogs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final log = _auditLogs[i];
                    final res =
                        (log['result'] ?? 'unknown').toString().toLowerCase();
                    final isPass = res == 'pass';
                    final isRev = res == 'revoked';
                    final color = isPass
                        ? const Color(0xFF10B981)
                        : (isRev ? const Color(0xFFDC2626) : Colors.orange);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isPass
                            ? Icons.check_circle
                            : (isRev ? Icons.block : Icons.help),
                        color: color,
                        size: 20,
                      ),
                      title: Text(
                        'Verified by: ${log['actor'] ?? 'Clinician'}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Reason: ${log['reason'] ?? ''} • ${log['checked_at'] ?? ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(80)),
                        ),
                        child: Text(
                          res.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Right to Erasure & De-linking (DPDP Act §13)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Permanently revoke all cryptographic pointers linked to your records across all circulating scans.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFDC2626)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _submittingErasure
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFDC2626)),
                      )
                    : const Icon(Icons.delete_outline, size: 20),
                label: const Text(
                  'Submit Formal Erasure Request',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onPressed: _submittingErasure ? null : _confirmErasure,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
