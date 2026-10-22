import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aether_ui/aether_ui.dart';
import '../main.dart';

class MagicLinkScreen extends StatefulWidget {
  const MagicLinkScreen({super.key});

  @override
  State<MagicLinkScreen> createState() => _MagicLinkScreenState();
}

class _MagicLinkScreenState extends State<MagicLinkScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _linkSent = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _validate() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Please enter your email');
      return false;
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      setState(() => _emailError = 'Please enter a valid email');
      return false;
    }
    setState(() => _emailError = null);
    return true;
  }

  Future<void> _sendMagicLink() async {
    if (!_validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await supabase.auth.signInWithOtp(
        email: _emailController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _linkSent = true;
        });
        context.showSnackBar('Magic link sent! Check your email.');
      }
    } on AuthException catch (error) {
      if (mounted) {
        context.showSnackBar(error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        context.showSnackBar('Failed to send magic link', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          'Magic Link Sign In',
          style: typography.titleLarge.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AetherSectionCard(
                isElevated: true,
                padding: const EdgeInsets.all(32),
                child: _linkSent ? _buildSuccessView() : _buildFormView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Column(
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
            Icons.link,
            size: 36,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Passwordless Sign In',
          style: typography.titleLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your email address and we will send a secure sign-in link directly to your inbox.',
          textAlign: TextAlign.center,
          style: typography.bodyMedium.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        AetherTextField(
          controller: _emailController,
          label: 'Email Address',
          hintText: 'doctor@syndrix.tech',
          prefixIcon: const Icon(Icons.email_outlined),
          keyboardType: TextInputType.emailAddress,
          errorText: _emailError,
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
        ),
        const SizedBox(height: 24),
        AetherButton(
          labelText: 'Send Magic Link',
          icon: const Icon(Icons.send),
          variant: AetherButtonVariant.primary,
          size: AetherButtonSize.lg,
          isExpanded: true,
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _sendMagicLink,
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.success.base.withAlpha(30),
            border: Border.all(color: colors.success.base, width: 2),
          ),
          child: Icon(
            Icons.mark_email_read,
            size: 36,
            color: colors.success.base,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Check Your Email',
          style: typography.titleLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We sent a magic sign-in link to:',
          textAlign: TextAlign.center,
          style: typography.bodyMedium.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _emailController.text,
          textAlign: TextAlign.center,
          style: typography.bodyLarge.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Click the link in your email to authenticate and enter NovaLife immediately.',
          textAlign: TextAlign.center,
          style: typography.bodySmall.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        AetherButton(
          labelText: 'Back to Sign In',
          variant: AetherButtonVariant.primary,
          size: AetherButtonSize.lg,
          isExpanded: true,
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(height: 12),
        AetherButton(
          labelText: 'Send Another Link',
          variant: AetherButtonVariant.text,
          onPressed: () => setState(() => _linkSent = false),
        ),
      ],
    );
  }
}
