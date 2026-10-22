import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aether_ui/aether_ui.dart';

import '../services/hub_jobs_service.dart';
import '../auth/password_policy.dart';
import '../auth/password_rules_hint.dart';
import '../services/profile_service.dart';
import '../services/session_service.dart';
import '../services/theme_service.dart';

class ProfileScreen extends StatefulWidget {
  final ThemeService themeService;

  const ProfileScreen({
    super.key,
    required this.themeService,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _displayName = 'NovaLife User';
  String _userEmail = '';
  String? _avatarUrl;
  AppRole _role = AppRole.labTech;
  String? _abhaId;
  bool _isUploadingImage = false;
  bool _isLoading = true;
  String? _hubStatusText;
  bool _checkingHub = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    if (!mounted) return;
    if (!_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final name = await ProfileService.getDisplayName();
      final email = await ProfileService.getUserEmail();
      final avatar = await ProfileService.getAvatarUrl();
      final user = ProfileService.currentUser;

      if (!mounted) return;
      setState(() {
        _displayName = (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : 'NovaLife User';
        _userEmail = (email != null && email.trim().isNotEmpty)
            ? email.trim()
            : '';
        _avatarUrl = (avatar != null && avatar.trim().isNotEmpty)
            ? avatar.trim()
            : null;
        _role = roleOf(user);
        _abhaId = abhaOf(user);
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Failed to load profile: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _uploadAvatar() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 768,
      maxHeight: 768,
      imageQuality: 85,
    );
    if (pickedFile == null || !mounted) return;

    setState(() => _isUploadingImage = true);

    try {
      final url = await ProfileService.uploadAvatarFixed(
        imagePath: pickedFile.path,
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
      });
      _showSnackBar('Profile image updated!', isError: false);
    } catch (e) {
      _showSnackBar('Failed to upload image: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  Future<void> _resetToInitialsAvatar() async {
    setState(() => _isUploadingImage = true);
    try {
      await ProfileService.clearAvatarUrl();
      if (!mounted) return;
      setState(() => _avatarUrl = null);
      _showSnackBar('Reverted to 2-letter initials avatar', isError: false);
    } catch (e) {
      _showSnackBar('Failed to reset avatar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _showEditDisplayNameDialog() async {
    final controller = TextEditingController(
      text: _displayName == 'NovaLife User' ? '' : _displayName,
    );

    final newName = await AetherAdaptiveDialog.show<String>(
      context,
      title: const Text('Edit Display Name'),
      content: AetherTextField(
        controller: controller,
        label: 'Display Name',
        hintText: 'Dr. Jane Doe',
        autofocus: true,
      ),
      actions: [
        AetherDialogAction.cancel(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AetherDialogAction.primary(
          label: 'Save',
          onPressed: () {
            final val = controller.text.trim();
            Navigator.pop(context, val.isNotEmpty ? val : null);
          },
        ),
      ],
    );

    if (newName == null || !mounted) return;
    final finalName = newName.trim().isEmpty ? 'NovaLife User' : newName.trim();

    try {
      await ProfileService.saveDisplayName(finalName);
      if (!mounted) return;
      setState(() => _displayName = finalName);
      _showSnackBar('Display name updated!', isError: false);
    } catch (e) {
      _showSnackBar('Failed to update display name: $e', isError: true);
    }
  }

  Future<void> _showChangeEmailDialog() async {
    final controller = TextEditingController(text: _userEmail);
    final newEmail = await AetherAdaptiveDialog.show<String>(
      context,
      title: const Text('Change Email'),
      content: AetherTextField(
        controller: controller,
        label: 'New Email Address',
        hintText: 'name@example.com',
        keyboardType: TextInputType.emailAddress,
        autofocus: true,
      ),
      actions: [
        AetherDialogAction.cancel(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AetherDialogAction.primary(
          label: 'Save',
          onPressed: () {
            final val = controller.text.trim();
            Navigator.pop(context, val.isNotEmpty ? val : null);
          },
        ),
      ],
    );

    if (newEmail == null || !mounted) return;

    try {
      await ProfileService.updateEmail(newEmail);
      if (!mounted) return;
      setState(() => _userEmail = newEmail);
      _showSnackBar(
        'Email update requested! Check your inbox to confirm.',
        isError: false,
      );
    } catch (e) {
      _showSnackBar('Failed to update email: $e', isError: true);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final newPwd = TextEditingController();
    final confirmPwd = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AetherTextField(
                  controller: newPwd,
                  isPassword: true,
                  label: 'New Password',
                  hintText: 'Enter new password',
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                PasswordRulesHint(
                  password: newPwd.text,
                  email: _userEmail,
                  username: _displayName,
                ),
                const SizedBox(height: 12),
                AetherTextField(
                  controller: confirmPwd,
                  isPassword: true,
                  label: 'Confirm New Password',
                  hintText: 'Re-enter new password',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (newPwd.text != confirmPwd.text) {
                  _showSnackBarInDialog(dialogContext, 'Passwords do not match');
                  return;
                }
                final policyError = PasswordPolicy.validate(
                  newPwd.text,
                  email: _userEmail,
                  username: _displayName,
                );
                if (policyError != null) {
                  _showSnackBarInDialog(dialogContext, policyError);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await ProfileService.updatePassword(newPwd.text);
      _showSnackBar('Password updated successfully!', isError: false);
    } catch (e) {
      _showSnackBar('Failed to update password: $e', isError: true);
    }
  }

  Future<void> _sendMagicLinkToSelf() async {
    if (_userEmail.isEmpty) {
      _showSnackBar('No email found for current user', isError: true);
      return;
    }
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: _userEmail);
      _showSnackBar('Magic sign-in link sent to $_userEmail!', isError: false);
    } catch (e) {
      _showSnackBar('Could not send magic link: $e', isError: true);
    }
  }

  Future<void> _checkFpgaHubStatus() async {
    setState(() => _checkingHub = true);
    try {
      final jobs = await HubJobsService.recentJobs(limit: 5);
      final active = jobs.where((j) => !j.finished).length;
      final last = jobs.isEmpty ? null : jobs.first;
      setState(() {
        _hubStatusText = jobs.isEmpty
            ? 'No jobs yet. Verification and marking run on the board through the cloud queue.'
            : '$active job(s) waiting or running • last: ${last!.kind} ${last.status.name}'
                '${last.verdict != null ? ' (${last.verdict})' : ''}';
      });
    } catch (e) {
      setState(() => _hubStatusText = 'Cloud queue not reachable: $e');
    } finally {
      if (mounted) setState(() => _checkingHub = false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  void _showSnackBarInDialog(BuildContext dialogContext, String message) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(dialogContext).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    });
  }

  Future<void> _handleLogout() async {
    final confirm = await AetherAdaptiveDialog.show<bool>(
      context,
      semantic: AetherStatusVariant.danger,
      leadingIcon: const Icon(Icons.logout, color: Colors.red),
      title: const Text('Sign Out'),
      content: const Text('Are you sure you want to sign out of NovaLife?'),
      actions: [
        AetherDialogAction.cancel(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context, false),
        ),
        AetherDialogAction.destructive(
          label: 'Sign Out',
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.auth.signOut();
      try {
        await ProfileService.clearHubSession();
      } catch (_) {}
      if (!mounted) return;
      _showSnackBar('Signed out', isError: false);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Sign out failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Scaffold(
      backgroundColor: colors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUser,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                children: [
                  _buildAvatar(colors, typography),
                  const SizedBox(height: 16),
                  AutoSizeText(
                    _displayName,
                    style: typography.titleLarge.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  AutoSizeText(
                    _userEmail,
                    style: typography.bodyMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      AetherStatusBadge(
                        label: 'Role: ${roleLabel(_role)}',
                        variant: AetherStatusVariant.info,
                        style: AetherStatusStyle.subtle,
                        icon: const Icon(Icons.verified_user, size: 14),
                      ),
                      if (_abhaId != null && _abhaId!.isNotEmpty)
                        AetherStatusBadge(
                          label: 'ABHA: $_abhaId',
                          variant: AetherStatusVariant.success,
                          style: AetherStatusStyle.subtle,
                          icon: const Icon(Icons.badge, size: 14),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildThemeCard(colors, typography),
                  const SizedBox(height: 16),
                  _buildHubCard(colors, typography),
                  const SizedBox(height: 16),
                  _buildActions(colors, typography),
                  const SizedBox(height: 28),
                  Text(
                    'NovaLife • Syndrix Health Security',
                    style: typography.labelSmall.copyWith(
                      fontStyle: FontStyle.italic,
                      color: colors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadUser,
        tooltip: 'Refresh Profile',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildAvatar(AetherColors colors, AetherTypography typography) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            AetherAvatarBadge(
              name: _displayName,
              imageUrl: _avatarUrl,
              size: 100,
              statusDot: AetherStatusVariant.success,
            ),
            if (_isUploadingImage)
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _uploadAvatar,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
        if (_avatarUrl != null) ...[
          const SizedBox(height: 8),
          AetherButton(
            labelText: 'Reset to Initials Avatar',
            icon: const Icon(Icons.restore, size: 16),
            variant: AetherButtonVariant.text,
            size: AetherButtonSize.sm,
            onPressed: _resetToInitialsAvatar,
          ),
        ],
      ],
    );
  }

  Widget _buildThemeCard(AetherColors colors, AetherTypography typography) {
    return AetherSectionCard(
      title: 'Appearance',
      subtitle: 'Customize light, dark, or system theme',
      leadingIcon: const Icon(Icons.palette_outlined),
      child: SegmentedButton<AppThemeMode>(
        segments: const [
          ButtonSegment(
            value: AppThemeMode.light,
            icon: Icon(Icons.light_mode, size: 18),
            label: Text('Light'),
          ),
          ButtonSegment(
            value: AppThemeMode.dark,
            icon: Icon(Icons.dark_mode, size: 18),
            label: Text('Dark'),
          ),
          ButtonSegment(
            value: AppThemeMode.system,
            icon: Icon(Icons.brightness_auto, size: 18),
            label: Text('System'),
          ),
        ],
        selected: {widget.themeService.currentThemeMode},
        onSelectionChanged: (selection) {
          widget.themeService.setThemeMode(selection.first);
          setState(() {});
        },
      ),
    );
  }

  Widget _buildHubCard(AetherColors colors, AetherTypography typography) {
    return AetherSectionCard(
      title: 'Zynq-7010 FreeRTOS Enclave Hub',
      leadingIcon: Icon(Icons.memory, color: colors.primary),
      headerAction: AetherButton(
        labelText: 'Ping',
        icon: const Icon(Icons.network_check, size: 16),
        variant: AetherButtonVariant.secondary,
        size: AetherButtonSize.sm,
        isLoading: _checkingHub,
        onPressed: _checkingHub ? null : _checkFpgaHubStatus,
      ),
      child: _hubStatusText != null
          ? Text(
              _hubStatusText!,
              style: typography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            )
          : Text(
              'Hardware watermark status and cloud queue connectivity.',
              style: typography.bodySmall.copyWith(
                color: colors.textMuted,
              ),
            ),
    );
  }

  Widget _buildActions(AetherColors colors, AetherTypography typography) {
    return AetherSectionCard(
      title: 'Account Settings',
      leadingIcon: const Icon(Icons.manage_accounts_outlined),
      child: Column(
        children: [
          AetherButton(
            labelText: 'Edit Display Name',
            icon: const Icon(Icons.edit_outlined),
            variant: AetherButtonVariant.secondary,
            isExpanded: true,
            onPressed: _showEditDisplayNameDialog,
          ),
          const SizedBox(height: 10),
          AetherButton(
            labelText: 'Change Email',
            icon: const Icon(Icons.email_outlined),
            variant: AetherButtonVariant.secondary,
            isExpanded: true,
            onPressed: _showChangeEmailDialog,
          ),
          const SizedBox(height: 10),
          AetherButton(
            labelText: 'Change Password',
            icon: const Icon(Icons.lock_outline),
            variant: AetherButtonVariant.secondary,
            isExpanded: true,
            onPressed: _showChangePasswordDialog,
          ),
          const SizedBox(height: 10),
          AetherButton(
            labelText: 'Send Magic Sign-In Link to Email',
            icon: const Icon(Icons.link),
            variant: AetherButtonVariant.secondary,
            isExpanded: true,
            onPressed: _sendMagicLinkToSelf,
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          AetherButton(
            labelText: 'Sign Out',
            icon: const Icon(Icons.logout),
            variant: AetherButtonVariant.danger,
            size: AetherButtonSize.lg,
            isExpanded: true,
            onPressed: _handleLogout,
          ),
        ],
      ),
    );
  }
}
