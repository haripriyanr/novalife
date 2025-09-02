import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';

import '../services/profile_service.dart';
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
  String _userEmail = 'no-email@novalife.app';
  String? _avatarUrl;
  bool _isUploadingImage = false;
  bool _isLoading = true;

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

      if (!mounted) return;
      setState(() {
        _displayName = (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : 'NovaLife User';
        _userEmail = (email != null && email.trim().isNotEmpty)
            ? email.trim()
            : 'no-email@novalife.app';
        _avatarUrl = avatar;
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

  Future<void> _showEditDisplayNameDialog() async {
    final controller = TextEditingController(
      text: _displayName == 'NovaLife User' ? '' : _displayName,
    );

    final newName = await _showInputDialog(
      title: 'Edit Display Name',
      fieldLabel: 'Display Name',
      controller: controller,
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
    final newEmail = await _showInputDialog(
      title: 'Change Email',
      fieldLabel: 'New Email',
      controller: controller,
      keyboardType: TextInputType.emailAddress,
    );
    if (newEmail == null || !mounted) return;

    try {
      await ProfileService.updateEmail(newEmail);
      if (!mounted) return;
      setState(() => _userEmail = newEmail);
      _showSnackBar('Email update requested! Check your inbox.',
          isError: false);
    } catch (e) {
      _showSnackBar('Failed to update email: $e', isError: true);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final newPwd = TextEditingController();
    final confirmPwd = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPwd,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPwd,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
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
              if (newPwd.text.length < 6) {
                _showSnackBarInDialog(
                    dialogContext, 'Password must be at least 6 characters');
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await ProfileService.updatePassword(newPwd.text);
      _showSnackBar('Password updated!', isError: false);
    } catch (e) {
      _showSnackBar('Failed to update password: $e', isError: true);
    }
  }

  Future<String?> _showInputDialog({
    required String title,
    required String fieldLabel,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          autofocus: true,
          decoration: InputDecoration(
            labelText: fieldLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              Navigator.pop(dialogContext, value.isNotEmpty ? value : null);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0B0B) : const Color(0xFFF6F7FB),
      // ✅ No AppBar, for a full-screen experience
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadUser,
        child: ListView(
          // ✅ Adjusted top padding for status bar
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          children: [
            const SizedBox(height: 20),
            _buildAvatar(),
            const SizedBox(height: 20),
            AutoSizeText(
              _displayName,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            AutoSizeText(
              _userEmail,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildActions(),
            const SizedBox(height: 40),
            const Text(
              'Made with love by NoveLife Team',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      // ✅ FAB for refresh action
      floatingActionButton: FloatingActionButton(
        onPressed: _loadUser,
        tooltip: 'Refresh Profile',
        child: _isLoading
            ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      alignment: Alignment.center,
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.purple.withAlpha(51),
          backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
          child: _avatarUrl == null
              ? const Icon(Icons.person, size: 60, color: Colors.purple)
              : null,
        ),
        if (_isUploadingImage)
          const Positioned.fill(
            child: CircleAvatar(
              backgroundColor: Colors.black45,
              child: CircularProgressIndicator(color: Colors.white),
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
                color: Colors.purple,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        _oneAction(
          icon: Icons.edit,
          label: 'Edit Display Name',
          onTap: _showEditDisplayNameDialog,
        ),
        const SizedBox(height: 12),
        _oneAction(
          icon: Icons.email,
          label: 'Change Email',
          onTap: _showChangeEmailDialog,
        ),
        const SizedBox(height: 12),
        _oneAction(
          icon: Icons.lock,
          label: 'Change Password',
          onTap: _showChangePasswordDialog,
        ),
      ],
    );
  }

  Widget _oneAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.purple,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
