import 'package:flutter/material.dart';

import '../models/health_record.dart';
import '../services/ehr_service.dart';
import '../services/vault_service.dart';

/// Opens one record: downloads the ciphertext and decrypts it with the vault key on the
/// phone. Pops `true` when the record is deleted.
class EHRReportView extends StatefulWidget {
  final String fullPath; // '<uid>/rec_<ms>.nlr'

  const EHRReportView({super.key, required this.fullPath});

  @override
  State<EHRReportView> createState() => _EHRReportViewState();
}

class _EHRReportViewState extends State<EHRReportView> {
  late Future<HealthRecord> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<HealthRecord> _load() async {
    if (!VaultService.isUnlocked) throw StateError('Your vault is locked. Go back and unlock it.');
    return VaultService.decryptRecord(await EHRService.download(widget.fullPath));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this record?'),
        content: const Text('It will be removed from your vault. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EHRService.delete(widget.fullPath);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not delete. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record'),
        actions: [IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: FutureBuilder<HealthRecord>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final e = snap.error;
            final msg = e is FormatException
                ? e.message
                : e is StateError
                    ? e.message
                    : 'Could not open this record. Check your connection and try again.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(msg, textAlign: TextAlign.center),
              ),
            );
          }
          final r = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(r.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                MaterialLocalizations.of(context).formatFullDate(r.createdAt),
                style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
              ),
              if (r.photo != null) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _openFullImage(r),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(r.photo!, fit: BoxFit.cover),
                  ),
                ),
              ],
              if (r.notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F2937) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(r.notes, style: const TextStyle(height: 1.45, fontSize: 15)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _openFullImage(HealthRecord r) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(child: Center(child: Image.memory(r.photo!, fit: BoxFit.contain))),
            ),
            Positioned(
              right: 12,
              top: 28,
              child: IconButton(
                tooltip: 'Close',
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
