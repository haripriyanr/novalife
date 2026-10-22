import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aether_ui/aether_ui.dart';
import '../main.dart';
import '../auth/password_policy.dart';
import '../auth/password_rules_hint.dart';
import '../services/session_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _abhaController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  AppRole _selectedRole = AppRole.patient;
  bool _isLoading = false;
  bool _acceptTerms = false;

  String? _nameError;
  String? _emailError;
  String? _abhaError;
  String? _passwordError;
  String? _confirmError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _abhaController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  bool _validate() {
    bool valid = true;
    setState(() {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        _nameError = 'Please enter your full name';
        valid = false;
      } else {
        _nameError = null;
      }

      final email = _emailController.text.trim();
      if (email.isEmpty) {
        _emailError = 'Please enter your email';
        valid = false;
      } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        _emailError = 'Please enter a valid email';
        valid = false;
      } else {
        _emailError = null;
      }

      final abha = _abhaController.text.trim();
      if (_selectedRole == AppRole.patient) {
        if (abha.isEmpty) {
          _abhaError = 'Please enter your ABHA ID';
          valid = false;
        } else if (!RegExp(r'^\d{14}$').hasMatch(abha)) {
          _abhaError = 'ABHA must be 14 digits';
          valid = false;
        } else {
          _abhaError = null;
        }
      } else if (abha.isNotEmpty) {
        if (!RegExp(r'^\d{14}$').hasMatch(abha)) {
          _abhaError = 'ABHA must be 14 digits';
          valid = false;
        } else {
          _abhaError = null;
        }
      } else {
        _abhaError = null;
      }

      final pass = _passwordController.text;
      if (pass.isEmpty) {
        _passwordError = 'Please enter your password';
        valid = false;
      } else {
        final policyError = PasswordPolicy.validate(
          pass,
          email: email,
          username: name,
        );
        if (policyError != null) {
          _passwordError = policyError;
          valid = false;
        } else {
          _passwordError = null;
        }
      }

      final confirm = _confirmPasswordController.text;
      if (confirm.isEmpty) {
        _confirmError = 'Please confirm your password';
        valid = false;
      } else if (confirm != pass) {
        _confirmError = 'Passwords do not match';
        valid = false;
      } else {
        _confirmError = null;
      }
    });
    return valid;
  }

  Future<void> _handleSignUp() async {
    if (!_validate()) return;

    if (!_acceptTerms) {
      context.showSnackBar('Please accept the terms and conditions',
          isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {
          'full_name': _nameController.text.trim(),
          'role': roleToDb(_selectedRole),
          if (_abhaController.text.trim().isNotEmpty)
            'abha_id': _abhaController.text.trim(),
        },
      );

      if (response.user != null && mounted) {
        context.showSnackBar(
          'Welcome to NovaLife! (${roleLabel(_selectedRole)}) account created.',
        );
        Navigator.pop(context);
      }
    } on AuthException catch (error) {
      if (mounted) {
        context.showSnackBar(error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        context.showSnackBar('An unexpected error occurred: $error',
            isError: true);
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
          'Create Account',
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
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AetherSectionCard(
                  isElevated: true,
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Text(
                        'Join NovaLife',
                        style: typography.titleLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select your clinical role and create your account',
                        textAlign: TextAlign.center,
                        style: typography.bodyMedium.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Clinical Role',
                          style: typography.labelMedium.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      AetherChoiceChipGroup<AppRole>(
                        items: AppRole.values
                            .map((role) => AetherChoiceChipItem(
                                  value: role,
                                  label: roleLabel(role),
                                ))
                            .toList(),
                        selectedValue: _selectedRole,
                        onSelected: (role) =>
                            setState(() => _selectedRole = role),
                      ),
                      const SizedBox(height: 16),

                      AetherTextField(
                        controller: _nameController,
                        label: 'Full Name',
                        hintText: 'Dr. Jane Doe',
                        prefixIcon: const Icon(Icons.person_outline),
                        errorText: _nameError,
                        onChanged: (_) {
                          if (_nameError != null) {
                            setState(() => _nameError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      AetherTextField(
                        controller: _emailController,
                        label: 'Email Address',
                        hintText: 'doctor@syndrix.tech',
                        prefixIcon: const Icon(Icons.email_outlined),
                        keyboardType: TextInputType.emailAddress,
                        errorText: _emailError,
                        onChanged: (_) {
                          if (_emailError != null) {
                            setState(() => _emailError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      AetherTextField(
                        controller: _abhaController,
                        label: _selectedRole == AppRole.patient
                            ? 'ABHA ID (14 digits) *'
                            : 'ABHA ID (Optional - 14 digits)',
                        helperText: _selectedRole == AppRole.patient
                            ? 'Required for Patient records'
                            : 'Optional personal health record ID',
                        hintText: '91234567890001',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        keyboardType: TextInputType.number,
                        errorText: _abhaError,
                        onChanged: (_) {
                          if (_abhaError != null) {
                            setState(() => _abhaError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      AetherTextField(
                        controller: _passwordController,
                        label: 'Password',
                        hintText: 'Enter secure password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        isPassword: true,
                        errorText: _passwordError,
                        onChanged: (_) {
                          if (_passwordError != null) {
                            setState(() => _passwordError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      PasswordRulesHint(
                        password: _passwordController.text,
                        email: _emailController.text,
                        username: _nameController.text,
                      ),
                      const SizedBox(height: 14),

                      AetherTextField(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        hintText: 'Re-enter password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        isPassword: true,
                        errorText: _confirmError,
                        onChanged: (_) {
                          if (_confirmError != null) {
                            setState(() => _confirmError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Checkbox(
                            value: _acceptTerms,
                            onChanged: (value) {
                              setState(() {
                                _acceptTerms = value ?? false;
                              });
                            },
                            activeColor: colors.primary,
                          ),
                          Expanded(
                            child: Text(
                              'I agree to the Terms of Service and Privacy Policy',
                              style: typography.bodySmall.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      AetherButton(
                        labelText: 'Create Account',
                        variant: AetherButtonVariant.primary,
                        size: AetherButtonSize.lg,
                        isExpanded: true,
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _handleSignUp,
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: typography.bodyMedium.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Sign In',
                              style: typography.labelLarge.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
