/// Doctor search screen — search patients by ABHA ID or name and open their records.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/hub_patients_service.dart';
import '../services/session_service.dart';
import 'report_list_screen.dart';

class DoctorSearchScreen extends StatefulWidget {
  const DoctorSearchScreen({super.key});

  @override
  State<DoctorSearchScreen> createState() => _DoctorSearchScreenState();
}

class _DoctorSearchScreenState extends State<DoctorSearchScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _allPatients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final myAbha = abhaOf(user);
      final myPid = patientIdOf(user);
      final list = await HubPatientsService.listPatients(
        excludeAbha: myAbha,
        excludePatientId: myPid,
      );
      if (mounted) {
        setState(() {
          _allPatients = list;
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

  List<Map<String, dynamic>> get _filteredPatients {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _allPatients;
    return _allPatients.where((p) {
      final name = (p['full_name']?.toString() ?? '').toLowerCase();
      final abha = (p['abha_id']?.toString() ?? '').toLowerCase();
      final pid = (p['patient_id']?.toString() ?? '').toLowerCase();
      return name.contains(q) || abha.contains(q) || pid.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredPatients;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by patient name or 14-digit ABHA ID…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Failed to load patients: $_error'),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadPatients,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPatients,
                        child: filtered.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 120),
                                  Center(
                                    child: Text('No matching patients found'),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  final p = filtered[i];
                                  final gender = p['gender'] as String? ?? '?';
                                  final icon = gender == 'M'
                                      ? Icons.man
                                      : gender == 'F'
                                          ? Icons.woman
                                          : Icons.person;
                                  final name =
                                      p['full_name']?.toString() ?? 'Unknown';
                                  final abha =
                                      p['abha_id']?.toString() ?? 'N/A';
                                  final pid =
                                      p['patient_id']?.toString() ?? 'PAT-001';
                                  return Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: const Color(0xFF2563EB)
                                            .withAlpha(30),
                                        child: Icon(icon,
                                            color: const Color(0xFF2563EB)),
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('ABHA: $abha',
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                          Text(
                                            'ID: $pid  •  DOB: ${p['dob'] ?? 'N/A'}  •  ${p['phone'] ?? ''}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                                      isThreeLine: true,
                                      trailing:
                                          const Icon(Icons.chevron_right),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ReportListScreen(
                                              patientId: pid,
                                              patientName: name,
                                              abhaId: abha,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
