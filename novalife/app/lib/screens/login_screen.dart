import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aether_ui/aether_ui.dart';
import '../main.dart';
import '../auth/password_policy.dart';
import '../auth/password_rules_hint.dart';
import '../services/session_service.dart';
import 'magic_link_screen.dart';
import '../config/demo_mode.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _abhaController = TextEditingController();
  final _confirmController = TextEditingController();

  AppRole _selectedRole = AppRole.patient;
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _acceptTerms = false;

  String? _emailError;
  String? _passwordError;
  String? _nameError;
  String? _abhaError;
  String? _confirmError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
    _loadSavedCredentials();
    if (kDemoMode && kDemoPassword.isNotEmpty) {
      _emailController.text = 'doctor@syndrix.tech';
      _passwordController.text = kDemoPassword;
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email');
      final savedRole = prefs.getString('saved_role');
      if (mounted) {
        if (savedEmail != null && savedEmail.isNotEmpty && _emailController.text.isEmpty) {
          setState(() {
            _emailController.text = savedEmail;
          });
        }
        if (savedRole != null && savedRole.isNotEmpty) {
          setState(() {
            _selectedRole = roleFromDb(savedRole);
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _abhaController.dispose();
    _confirmController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  bool _validateSignIn() {
    bool valid = true;
    setState(() {
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

      if (_passwordController.text.isEmpty) {
        _passwordError = 'Please enter your password';
        valid = false;
      } else {
        _passwordError = null;
      }
    });
    return valid;
  }

  bool _validateSignUp() {
    bool valid = true;
    setState(() {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        _nameError = 'Please enter your full name';
        valid = false;
      } else {
        _nameError = null;
      }

      final abha = _abhaController.text.trim();
      if (_selectedRole == AppRole.patient) {
        if (abha.isEmpty) {
          _abhaError = 'Please enter ABHA ID';
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

      final confirm = _confirmController.text;
      if (confirm.isEmpty) {
        _confirmError = 'Please confirm password';
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

  Future<void> _handleSignIn() async {
    if (!_validateSignIn()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null && mounted) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_email', _emailController.text.trim());
          await prefs.setString('saved_role', roleToDb(_selectedRole));
        } catch (_) {}
        if (mounted) {
          context.showSnackBar('Welcome back! Successfully signed in.');
        }
      }
    } on AuthException catch (error) {
      if (mounted) {
        context.showSnackBar(error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        context.showSnackBar('An unexpected error occurred', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSignUp() async {
    if (!_validateSignUp()) return;
    if (!_acceptTerms) {
      context.showSnackBar('Please accept Terms and Privacy', isError: true);
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
        if (response.user!.emailConfirmedAt == null) {
          context.showSnackBar(
            'Account created! Check inbox to verify email before entering app.',
          );
        } else {
          context.showSnackBar(
            'Welcome to NovaLife! (${roleLabel(_selectedRole)}) account created.',
          );
        }
      }
    } on AuthException catch (error) {
      if (mounted) {
        context.showSnackBar(error.message, isError: true);
      }
    } catch (error) {
      if (mounted) {
        context.showSnackBar('An unexpected error occurred', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleMagicLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MagicLinkScreen()),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await supabase.auth.signInWithOtp(
        email: email,
      );

      if (mounted) {
        context.showSnackBar('Check your email ($email) for the login link!');
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

  void _quickFillDemo(String email) {
    setState(() {
      _isSignUp = false;
      _emailController.text = email;
      _passwordController.text = kDemoPassword;
      _emailError = null;
      _passwordError = null;
    });
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
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AetherSectionCard(
                    isElevated: true,
                    padding: const EdgeInsets.all(28),
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
                            Icons.healing,
                            color: colors.primary,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'NovaLife',
                          style: typography.titleLarge.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isSignUp ? 'Create your clinical account' : 'Welcome back to your clinical portal',
                          style: typography.bodyMedium.copyWith(
                            color: colors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        if (_isSignUp) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Select Clinical Role',
                              style: typography.labelMedium.copyWith(color: colors.textSecondary),
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
                            onSelected: (role) => setState(() => _selectedRole = role),
                          ),
                          const SizedBox(height: 16),
                          AetherTextField(
                            controller: _nameController,
                            label: 'Full Name',
                            hintText: 'Dr. Jane Doe',
                            prefixIcon: const Icon(Icons.person_outline),
                            errorText: _nameError,
                            onChanged: (_) {
                              if (_nameError != null) setState(() => _nameError = null);
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
                                : 'Optional personal health ID',
                            hintText: '91234567890001',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            keyboardType: TextInputType.number,
                            errorText: _abhaError,
                            onChanged: (_) {
                              if (_abhaError != null) setState(() => _abhaError = null);
                            },
                          ),
                          const SizedBox(height: 14),
                        ],

                        AetherTextField(
                          controller: _emailController,
                          label: 'Email Address',
                          hintText: 'doctor@syndrix.tech',
                          prefixIcon: const Icon(Icons.email_outlined),
                          keyboardType: TextInputType.emailAddress,
                          errorText: _emailError,
                          onChanged: (_) {
                            setState(() {
                              if (_emailError != null) _emailError = null;
                            });
                          },
                        ),
                        const SizedBox(height: 14),

                        AetherTextField(
                          controller: _passwordController,
                          label: _isSignUp ? 'Create Password' : 'Password',
                          hintText: 'Enter secure password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          isPassword: true,
                          errorText: _passwordError,
                          onChanged: (_) {
                            setState(() {
                              if (_passwordError != null) _passwordError = null;
                            });
                          },
                        ),

                        if (_isSignUp) ...[
                          const SizedBox(height: 8),
                          PasswordRulesHint(
                            password: _passwordController.text,
                            email: _emailController.text,
                            username: _nameController.text,
                          ),
                          const SizedBox(height: 14),
                          AetherTextField(
                            controller: _confirmController,
                            label: 'Confirm Password',
                            hintText: 'Re-enter password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            isPassword: true,
                            errorText: _confirmError,
                            onChanged: (_) {
                              if (_confirmError != null) setState(() => _confirmError = null);
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Checkbox(
                                value: _acceptTerms,
                                onChanged: (v) =>
                                    setState(() => _acceptTerms = v ?? false),
                                activeColor: colors.primary,
                              ),
                              Expanded(
                                child: Text(
                                  'I agree to Terms of Service & Privacy Policy',
                                  style: typography.bodySmall.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 20),

                        AetherButton(
                          labelText: _isSignUp ? 'Create Account' : 'Sign In',
                          variant: AetherButtonVariant.primary,
                          size: AetherButtonSize.lg,
                          isExpanded: true,
                          isLoading: _isLoading,
                          onPressed: _isLoading
                              ? null
                              : (_isSignUp ? _handleSignUp : _handleSignIn),
                        ),

                        if (!_isSignUp) ...[
                          const SizedBox(height: 12),
                          AetherButton(
                            labelText: 'Send Magic Link',
                            icon: const Icon(Icons.email_outlined),
                            variant: AetherButtonVariant.outline,
                            size: AetherButtonSize.md,
                            isExpanded: true,
                            isLoading: _isLoading,
                            onPressed: _isLoading ? null : _handleMagicLink,
                          ),
                          if (kDemoMode && kDemoPassword.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Demo Credentials',
                              style: typography.labelSmall.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: [
                                AetherButton(
                                  labelText: 'Lab Tech',
                                  variant: AetherButtonVariant.secondary,
                                  size: AetherButtonSize.sm,
                                  onPressed: () =>
                                      _quickFillDemo('lab@syndrix.tech'),
                                ),
                                AetherButton(
                                  labelText: 'Doctor',
                                  variant: AetherButtonVariant.secondary,
                                  size: AetherButtonSize.sm,
                                  onPressed: () =>
                                      _quickFillDemo('doctor@syndrix.tech'),
                                ),
                                AetherButton(
                                  labelText: 'Patient',
                                  variant: AetherButtonVariant.secondary,
                                  size: AetherButtonSize.sm,
                                  onPressed: () =>
                                      _quickFillDemo('patient@syndrix.tech'),
                                ),
                              ],
                            ),
                          ],
                        ],

                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isSignUp
                                  ? 'Already have an account? '
                                  : "Don't have an account? ",
                              style: typography.bodyMedium.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        _isSignUp = !_isSignUp;
                                        _nameController.clear();
                                        _emailError = null;
                                        _passwordError = null;
                                        _nameError = null;
                                        _abhaError = null;
                                        _confirmError = null;
                                      });
                                    },
                              child: Text(
                                _isSignUp ? 'Sign In' : 'Sign Up',
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
      ),
    );
  }
}
