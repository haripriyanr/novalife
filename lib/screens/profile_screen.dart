import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // ✅ Added for safe BuildContext usage
import 'package:image_picker/image_picker.dart';
import '../services/theme_service.dart';
import '../services/ai_service.dart';
import '../services/ai_settings_service.dart';
import '../services/model_path_service.dart';
import '../services/profile_service.dart';

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
  final AIService _aiService = AIService();
  AIModelSettings _settings = AIModelSettings();
  String _modelInfo = 'Loading...';
  bool _isLoading = true;

  // Profile data
  String? _userName;
  String? _userEmail;
  String? _avatarUrl;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadModelInfo();
    _loadUserProfile();
  }

  // ✅ Fixed: Removed unused 'profile' variable
  Future<void> _loadUserProfile() async {
    try {
      // Don't store the profile response if not used
      await ProfileService.getCurrentUserProfile();

      final userName = await ProfileService.getUserName();
      final userEmail = await ProfileService.getUserEmail();
      final avatarUrl = await ProfileService.getUserAvatar();

      if (mounted) {
        setState(() {
          _userName = userName;
          _userEmail = userEmail;
          _avatarUrl = avatarUrl;
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  // ✅ Fixed: Proper BuildContext handling across async gaps
  Future<void> _uploadProfileImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      if (!mounted) return; // ✅ Check mounted before setState

      setState(() {
        _isUploadingImage = true;
      });

      try {
        final uploadedUrl = await ProfileService.uploadProfileImage(pickedFile.path);

        if (!mounted) return; // ✅ Check mounted after async operation

        if (uploadedUrl != null) {
          setState(() {
            _avatarUrl = uploadedUrl;
          });

          // ✅ Use SchedulerBinding for safe context usage
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Profile image updated successfully!'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          });
        }
      } catch (e) {
        if (!mounted) return;

        // ✅ Use SchedulerBinding for safe error display
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to upload image: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
      } finally {
        if (mounted) {
          setState(() {
            _isUploadingImage = false;
          });
        }
      }
    }
  }

  // ✅ Fixed: Safe BuildContext handling in dialog
  Future<void> _showEditProfileDialog() async {
    if (!mounted) return;

    final nameController = TextEditingController(text: _userName);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = nameController.text.trim();
              Navigator.pop(dialogContext, newName.isNotEmpty ? newName : null);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Handle result after dialog closes
    if (result != null && mounted) {
      await ProfileService.saveUserName(result);
      setState(() {
        _userName = result;
      });
    }
  }

  Future<void> _loadSettings() async {
    try {
      _settings = await AISettingsService.loadSettings();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadModelInfo() async {
    try {
      final info = _aiService.getModelInfo();
      if (mounted) {
        setState(() {
          _modelInfo = info;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _modelInfo = 'Error loading model info: $e';
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      await AISettingsService.saveSettings(_settings);
      await _aiService.updateSettings(_settings);

      if (!mounted) return; // ✅ Check mounted before using context

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('AI settings saved successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving settings: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resetSettings() async {
    if (!mounted) return;

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset AI Settings'),
        content: const Text('Are you sure you want to reset all AI model settings to defaults?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (shouldReset == true && mounted) {
      await AISettingsService.resetToDefaults();
      await _loadSettings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI settings reset to defaults'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _changeModelFile() async {
    final selectedPath = await ModelPathService.pickModelFile();

    if (selectedPath != null && mounted) {
      await ModelPathService.saveModelPath(selectedPath);
      await _aiService.setModelPath(selectedPath);
      await _loadModelInfo();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Model file updated: ${selectedPath.split('/').last}'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Container(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // User Profile Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.purple.withAlpha(25),
                      Colors.purple.withAlpha(13),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.purple.withAlpha(77)),
                ),
                child: Column(
                  children: [
                    // Avatar and Basic Info
                    Row(
                      children: [
                        // Profile Avatar
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.purple.withAlpha(51),
                              backgroundImage: _avatarUrl != null
                                  ? NetworkImage(_avatarUrl!)
                                  : null,
                              child: _avatarUrl == null
                                  ? Icon(
                                Icons.person,
                                size: 40,
                                color: Colors.purple,
                              )
                                  : null,
                            ),
                            if (_isUploadingImage)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withAlpha(128),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _uploadProfileImage,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.purple,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 20),

                        // User Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _userName ?? 'NovaLife User',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _userEmail ?? 'No email set',
                                style: TextStyle(
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _showEditProfileDialog,
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text('Edit Profile'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Theme Quick Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black.withAlpha(51) : Colors.grey.withAlpha(51),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.purple.withAlpha(25),
                      ),
                      child: Icon(
                        widget.themeService.themeIcon,
                        color: Colors.purple,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Theme',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            '${widget.themeService.themeDisplayName} Mode',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Tap theme icon\nin header to change',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // AI Model Information Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.withAlpha(25),
                      Colors.blue.withAlpha(13),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.withAlpha(77)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue.withAlpha(51),
                          ),
                          child: const Icon(
                            Icons.smart_toy,
                            color: Color(0xFF2563EB),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI Model Information',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : const Color(0xFF1F2937),
                                ),
                              ),
                              Text(
                                'Powered by Cactus Framework',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Model Info Display
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _modelInfo,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: isDark ? Colors.white : Colors.black,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _changeModelFile,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Change Model File'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // AI Model Parameters
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black.withAlpha(51) : Colors.grey.withAlpha(51),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.tune,
                          color: Colors.green,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'AI Model Parameters',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _resetSettings,
                          icon: const Icon(Icons.restore),
                          tooltip: 'Reset to Defaults',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Temperature Setting
                    _buildSliderSetting(
                      'Temperature',
                      'Controls randomness (0.0 = focused, 1.0 = creative)',
                      _settings.temperature,
                      0.0,
                      1.0,
                      100,
                          (value) {
                        setState(() {
                          _settings.temperature = value;
                        });
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),

                    // Max Tokens Setting
                    _buildSliderSetting(
                      'Max Tokens',
                      'Maximum response length (128-2048)',
                      _settings.maxTokens.toDouble(),
                      128.0,
                      2048.0,
                      1920,
                          (value) {
                        setState(() {
                          _settings.maxTokens = value.round();
                        });
                      },
                      isDark: isDark,
                      isInteger: true,
                    ),
                    const SizedBox(height: 20),

                    // Context Size Setting
                    _buildSliderSetting(
                      'Context Size',
                      'Model memory size (1024-8192)',
                      _settings.contextSize.toDouble(),
                      1024.0,
                      8192.0,
                      7168,
                          (value) {
                        setState(() {
                          _settings.contextSize = value.round();
                        });
                      },
                      isDark: isDark,
                      isInteger: true,
                    ),
                    const SizedBox(height: 20),

                    // Top P Setting
                    _buildSliderSetting(
                      'Top P',
                      'Nucleus sampling (0.1-1.0)',
                      _settings.topP,
                      0.1,
                      1.0,
                      90,
                          (value) {
                        setState(() {
                          _settings.topP = value;
                        });
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),

                    // Top K Setting
                    _buildSliderSetting(
                      'Top K',
                      'Token selection diversity (1-100)',
                      _settings.topK.toDouble(),
                      1.0,
                      100.0,
                      99,
                          (value) {
                        setState(() {
                          _settings.topK = value.round();
                        });
                      },
                      isDark: isDark,
                      isInteger: true,
                    ),
                    const SizedBox(height: 20),

                    // System Prompt Setting
                    Text(
                      'System Prompt',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Default instructions for the AI model',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: _settings.systemPrompt),
                      onChanged: (value) {
                        _settings.systemPrompt = value;
                      },
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Enter system prompt...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey[700] : Colors.grey[50],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: const Text('Save AI Settings'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderSetting(
      String title,
      String description,
      double value,
      double min,
      double max,
      int divisions,
      Function(double) onChanged, {
        required bool isDark,
        bool isInteger = false,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withAlpha(77)),
              ),
              child: Text(
                isInteger ? value.round().toString() : value.toStringAsFixed(2),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: Colors.green,
          inactiveColor: Colors.green.withAlpha(77),
        ),
      ],
    );
  }
}
