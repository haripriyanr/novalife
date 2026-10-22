/// Patient list screen — shows all patients from the HUB vault.
///
/// Tap a patient to navigate to their report list.
library;

import 'package:flutter/material.dart';
import '../services/hub_patients_service.dart';
import 'report_list_screen.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = HubPatientsService.listPatients();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        backgroundColor: isDark ? const Color(0xFF18181B) : const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final patients = snap.data ?? [];
          if (patients.isEmpty) {
            return const Center(child: Text('No patients in vault'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: patients.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = patients[i];
              final gender = p['gender'] as String? ?? '?';
              final icon = gender == 'M' ? Icons.man : gender == 'F' ? Icons.woman : Icons.person;
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF2563EB).withAlpha(30),
                    child: Icon(icon, color: const Color(0xFF2563EB)),
                  ),
                  title: Text(
                    p['full_name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ABHA: ${p['abha_id']}', style: const TextStyle(fontSize: 12)),
                      Text('DOB: ${p['dob']}  •  ${p['phone']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportListScreen(
                          patientId: p['patient_id'] as String,
                          patientName: p['full_name'] as String,
                          abhaId: p['abha_id'] as String,
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
