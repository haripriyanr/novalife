// lib/screens/ehr_screen.dart
import 'package:flutter/material.dart';

import '../services/ehr_service.dart';
import '../services/vault_service.dart';
import 'ehr_report_view.dart';
import 'ehr_upload_screen.dart';

/// Health records: a passphrase-locked vault. First visit sets the passphrase; later visits
/// unlock it. Once open, records are listed by date and decrypted only when opened.
class EHRScreen extends StatefulWidget {
  const EHRScreen({super.key});

  @override
  State<EHRScreen> createState() => _EHRScreenState();
}

enum _Gate { checking, setup, locked, open, error }

class _EHRScreenState extends State<EHRScreen> {
  _Gate _gate = _Gate.checking;
  String? _error;
  Future<List<String>>? _records;

  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _gate = _Gate.checking);
    try {
      if (VaultService.isUnlocked) return _open();
      final exists = await VaultService.exists();
      if (mounted) setState(() => _gate = exists ? _Gate.locked : _Gate.setup);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gate = _Gate.error;
        _error = 'Could not reach your records. Check your connection and try again.';
      });
    }
  }

  void _open() {
    setState(() {
      _gate = _Gate.open;
      _records = EHRService.listRecordPaths();
    });
  }

  Future<void> _submit() async {
    final pass = _pass.text;
    setState(() => _formError = null);
    if (_gate == _Gate.setup) {
      if (pass.length < VaultService.minPassphraseLength) {
        return setState(() => _formError = 'Use at least ${VaultService.minPassphraseLength} characters.');
      }
      if (pass != _confirm.text) return setState(() => _formError = 'The two passphrases do not match.');
    }
    setState(() => _busy = true);
    try {
      if (_gate == _Gate.setup) {
        await VaultService.create(pass);
      } else if (!await VaultService.unlock(pass)) {
        return setState(() => _formError = 'That passphrase is not right.');
      }
      _pass.clear();
      _confirm.clear();
      final moved = await VaultService.migrateLegacyRecords();
      if (!mounted) return;
      if (moved > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Moved $moved older ${moved == 1 ? 'record' : 'records'} into your vault.'),
        ));
      }
      _open();
    } catch (e) {
      setState(() => _formError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _lock() {
    VaultService.lock();
    setState(() => _gate = _Gate.locked);
  }

  Future<void> _refresh() async {
    setState(() => _records = EHRService.listRecordPaths());
    try {
      await _records;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0B0B) : const Color(0xFFF6F7FB),
      body: SafeArea(child: _body(isDark)),
      floatingActionButton: _gate == _Gate.open
          ? FloatingActionButton.extended(
              heroTag: 'add_ehr_fab',
              onPressed: () async {
                final added = await Navigator.of(context).push<bool?>(
                  MaterialPageRoute(builder: (_) => const EHRUploadScreen()),
                );
                if (added == true) await _refresh();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add record'),
            )
          : null,
    );
  }

  Widget _body(bool isDark) {
    switch (_gate) {
      case _Gate.checking:
        return const Center(child: CircularProgressIndicator());
      case _Gate.error:
        return _message(Icons.cloud_off_outlined, _error!, action: ('Try again', _check));
      case _Gate.setup:
      case _Gate.locked:
        return _passphraseForm(isDark);
      case _Gate.open:
        return _list(isDark);
    }
  }

  Widget _passphraseForm(bool isDark) {
    final setup = _gate == _Gate.setup;
    final muted = isDark ? Colors.white60 : Colors.black54;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(setup ? Icons.shield_outlined : Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  setup ? 'Protect your health records' : 'Unlock your records',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  setup
                      ? 'Choose a passphrase. Your records are encrypted on this phone with it '
                          'before they are uploaded, so only you can read them. Not even NovaLife can.'
                      : 'Enter your records passphrase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.4),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  enabled: !_busy,
                  autofillHints: [setup ? AutofillHints.newPassword : AutofillHints.password],
                  textInputAction: setup ? TextInputAction.next : TextInputAction.done,
                  onSubmitted: (_) => setup ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show' : 'Hide',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (setup) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Type it again',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Write it down somewhere safe. If you forget it, your records cannot be recovered. '
                      'That is what keeps them private.',
                      style: TextStyle(height: 1.35),
                    ),
                  ),
                ],
                if (_formError != null) ...[
                  const SizedBox(height: 12),
                  Text(_formError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(setup ? 'Create vault' : 'Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(bool isDark) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<String>>(
        future: _records,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _message(Icons.cloud_off_outlined, 'Could not load your records.',
                action: ('Try again', _refresh));
          }
          final items = snap.data ?? const [];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Health records', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(tooltip: 'Lock', icon: const Icon(Icons.lock_outline), onPressed: _lock),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Encrypted on this phone. Only your passphrase opens them.',
                style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: _message(Icons.folder_open_outlined,
                      'No records yet. Add a lab report, prescription or note to keep it in one safe place.'),
                )
              else
                for (final path in items) _tile(path, isDark),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(String path, bool isDark) {
    final date = EHRService.dateFromPath(path);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? const Color(0xFF18181B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
        title: Text(date == null ? 'Record' : _formatDate(date)),
        subtitle: const Text('Tap to open'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final deleted = await Navigator.of(context).push<bool?>(
            MaterialPageRoute(builder: (_) => EHRReportView(fullPath: path)),
          );
          if (deleted == true) await _refresh();
        },
      ),
    );
  }

  Widget _message(IconData icon, String text, {(String, VoidCallback)? action}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: isDark ? Colors.white38 : Colors.black38),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: action.$2, child: Text(action.$1)),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, $h:$m ${d.hour < 12 ? 'am' : 'pm'}';
}
