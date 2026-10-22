import 'package:flutter/material.dart';

import 'password_policy.dart';

/// Live per-rule checklist shown under a password field. Rebuilds from the
/// current [password] (plus [email]/[username] for the identity rule), so the
/// caller only needs to call `setState` in the field's `onChanged`.
class PasswordRulesHint extends StatelessWidget {
  final String password;
  final String? email;
  final String? username;

  const PasswordRulesHint({
    super.key,
    required this.password,
    this.email,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    final checks = PasswordPolicy.checkAll(
      password,
      email: email,
      username: username,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pending = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, satisfied) in checks)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  satisfied ? Icons.check_circle : Icons.circle_outlined,
                  size: 14,
                  color: satisfied ? Colors.green : pending,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: satisfied ? Colors.green : pending,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
