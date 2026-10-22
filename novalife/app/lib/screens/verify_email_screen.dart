import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aether_ui/aether_ui.dart';
import '../main.dart';

class VerifyEmailScreen extends StatefulWidget {
  final User user;
  const VerifyEmailScreen({super.key, required this.user});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isResending = false;
  bool _isChecking = false;

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: widget.user.email,
      );
      if (mounted) {
        context.showSnackBar('Verification email resent to ${widget.user.email}');
      }
    } catch (e) {
      if (mounted) context.showSnackBar('Failed to resend: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _isChecking = true);
    try {
      final res = await supabase.auth.getUser();
      final u = res.user;
      if (u != null && u.emailConfirmedAt != null) {
        if (mounted) context.showSnackBar('Email verified — welcome!');
      } else {
        if (mounted) {
          context.showSnackBar(
              'Still not verified. Check inbox and tap link.',
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) context.showSnackBar('Refresh failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AetherSectionCard(
                isElevated: true,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary.withAlpha(30),
                        border: Border.all(color: colors.primary, width: 2),
                      ),
                      child: Icon(
                        Icons.mark_email_read,
                        size: 36,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Verify Your Email',
                      style: typography.titleLarge.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We sent a verification link to',
                      style: typography.bodyMedium.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.user.email ?? 'your email',
                      style: typography.bodyLarge.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Tap the link in your inbox to verify your email address. You must verify before entering the NovaLife clinical portal.',
                      textAlign: TextAlign.center,
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    AetherButton(
                      labelText: 'I Verified — Refresh',
                      icon: const Icon(Icons.refresh),
                      variant: AetherButtonVariant.primary,
                      size: AetherButtonSize.lg,
                      isExpanded: true,
                      isLoading: _isChecking,
                      onPressed: _isChecking ? null : _refresh,
                    ),
                    const SizedBox(height: 12),
                    AetherButton(
                      labelText: 'Resend Verification Email',
                      icon: const Icon(Icons.email_outlined),
                      variant: AetherButtonVariant.outline,
                      size: AetherButtonSize.md,
                      isExpanded: true,
                      isLoading: _isResending,
                      onPressed: _isResending ? null : _resend,
                    ),
                    const SizedBox(height: 16),
                    AetherButton(
                      labelText: 'Sign Out & Back to Login',
                      variant: AetherButtonVariant.text,
                      onPressed: () => supabase.auth.signOut(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
