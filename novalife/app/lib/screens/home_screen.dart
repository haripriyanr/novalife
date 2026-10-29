import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aether_ui/aether_ui.dart';
import '../services/theme_service.dart';
import '../services/session_service.dart';
import '../main.dart';
import 'profile_screen.dart';
import 'ehr_screen.dart';
import 'ehr_upload_screen.dart';
import 'doctor_search_screen.dart';
import 'scan_verify_screen.dart';
import 'patient_records_screen.dart';

class HomeScreen extends StatefulWidget {
  final ThemeService themeService;
  final AppRole role;
  final String? abhaId;

  const HomeScreen({
    super.key,
    required this.themeService,
    this.role = AppRole.labTech,
    this.abhaId,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _buildRoleScreens();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role || oldWidget.abhaId != widget.abhaId) {
      _buildRoleScreens();
      if (_currentIndex >= _screens.length) {
        _currentIndex = 0;
      }
    }
  }

  void _buildRoleScreens() {
    _screens = switch (widget.role) {
      AppRole.labTech => [
          const EHRUploadScreen(),
          const EHRScreen(isBucketPublic: true),
          const ScanVerifyScreen(),
          ProfileScreen(themeService: widget.themeService),
        ],
      AppRole.doctor => [
          const ScanVerifyScreen(),
          const EHRUploadScreen(),
          const DoctorSearchScreen(),
          ProfileScreen(themeService: widget.themeService),
        ],
      AppRole.patient => [
          PatientRecordsScreen(
            key: ValueKey(widget.abhaId ?? 'me'),
            abhaId: widget.abhaId,
          ),
          const ScanVerifyScreen(),
          ProfileScreen(themeService: widget.themeService),
        ],
    };
  }

  List<AetherNavigationItem> _getNavItems() {
    return switch (widget.role) {
      AppRole.labTech => const [
          AetherNavigationItem(
            icon: Icons.cloud_upload_outlined,
            activeIcon: Icons.cloud_upload,
            label: 'Upload',
          ),
          AetherNavigationItem(
            icon: Icons.medical_information_outlined,
            activeIcon: Icons.medical_information,
            label: 'Records',
          ),
          AetherNavigationItem(
            icon: Icons.verified_outlined,
            activeIcon: Icons.verified,
            label: 'Verify',
          ),
          AetherNavigationItem(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Settings',
          ),
        ],
      AppRole.doctor => const [
          AetherNavigationItem(
            icon: Icons.verified_outlined,
            activeIcon: Icons.verified,
            label: 'Verify',
          ),
          AetherNavigationItem(
            icon: Icons.cloud_upload_outlined,
            activeIcon: Icons.cloud_upload,
            label: 'Upload',
          ),
          AetherNavigationItem(
            icon: Icons.person_search_outlined,
            activeIcon: Icons.person_search,
            label: 'Patients',
          ),
          AetherNavigationItem(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Settings',
          ),
        ],
      AppRole.patient => const [
          AetherNavigationItem(
            icon: Icons.folder_shared_outlined,
            activeIcon: Icons.folder_shared,
            label: 'My Records',
          ),
          AetherNavigationItem(
            icon: Icons.verified_outlined,
            activeIcon: Icons.verified,
            label: 'Verify Scan',
          ),
          AetherNavigationItem(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Settings',
          ),
        ],
    };
  }

  String _getAppBarTitle() {
    return switch (widget.role) {
      AppRole.labTech => switch (_currentIndex) {
          0 => 'Mark & Upload Scan',
          1 => 'Patient Records',
          2 => 'Verify Scan Authenticity',
          3 => 'Profile & Settings',
          _ => 'NovaLife',
        },
      AppRole.doctor => switch (_currentIndex) {
          0 => 'Scan & Verify',
          1 => 'Mark & Upload Scan',
          2 => 'Doctor — Patient Lookup',
          3 => 'Profile & Settings',
          _ => 'NovaLife',
        },
      AppRole.patient => switch (_currentIndex) {
          0 => 'My Medical Records',
          1 => 'Verify Scan Authenticity',
          2 => 'Profile & Settings',
          _ => 'NovaLife',
        },
    };
  }

  Future<void> _handleSignOut() async {
    final shouldSignOut = await AetherAdaptiveDialog.show<bool>(
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

    if (shouldSignOut == true) {
      try {
        await supabase.auth.signOut();
        if (mounted) {
          context.showSnackBar('Successfully signed out');
        }
      } catch (error) {
        if (mounted) {
          context.showSnackBar('Error signing out: $error', isError: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final colors = context.aetherColors;
    final typography = context.aetherTypography;
    final user = hubDb?.auth.currentUser;
    final fullName = user?.userMetadata?['full_name'] as String?;

    return AetherResponsiveScaffold(
      backgroundColor: colors.background,
      header: AetherHeaderBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _getAppBarTitle(),
                overflow: TextOverflow.ellipsis,
                style: typography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AetherStatusBadge(
              label: roleLabel(widget.role),
              variant: AetherStatusVariant.info,
              style: AetherStatusStyle.subtle,
            ),
          ],
        ),
        actions: [
          // Theme Selector Toggle
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: AetherRadii.sm,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AetherRadii.sm,
                onTap: () => _showThemeSelector(context, themeService),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        themeService.themeIcon,
                        size: 18,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        themeService.themeDisplayName,
                        style: typography.labelSmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // User Avatar & Account Menu
          PopupMenuButton<String>(
            tooltip: 'Account & Settings',
            icon: AetherAvatarBadge(
              name: fullName ?? user?.email ?? 'NL',
              size: 32,
              statusDot: AetherStatusVariant.success,
            ),
            onSelected: (value) {
              if (value == 'profile') {
                setState(() => _currentIndex = _screens.length - 1);
              } else if (value == 'signout') {
                _handleSignOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20),
                    SizedBox(width: 8),
                    Text('Profile & Settings'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: colors.danger.base),
                    const SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: TextStyle(color: colors.danger.base),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      navigationItems: _getNavItems(),
      currentIndex: _currentIndex,
      onNavigationChanged: (index) => setState(() => _currentIndex = index),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
    );
  }

  // Theme Selection Modal
  Future<void> _showThemeSelector(
      BuildContext context, ThemeService themeService) async {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    await AetherBottomSheet.show(
      context,
      title: 'Choose Theme',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...AppThemeMode.values.map(
            (mode) => _buildThemeOption(
              context,
              themeService,
              mode,
              colors,
              typography,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    ThemeService themeService,
    AppThemeMode mode,
    AetherColors colors,
    AetherTypography typography,
  ) {
    final isSelected = themeService.currentThemeMode == mode;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? colors.primary.withAlpha(25) : colors.surfaceSubtle,
        borderRadius: AetherRadii.md,
        border: Border.all(
          color: isSelected ? colors.primary : colors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary : colors.surface,
            borderRadius: AetherRadii.sm,
          ),
          child: Icon(
            _getThemeIcon(mode),
            color: isSelected ? Colors.white : colors.textPrimary,
            size: 20,
          ),
        ),
        title: Text(
          _getThemeDisplayName(mode),
          style: typography.bodyMedium.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? colors.primary : colors.textPrimary,
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: colors.primary)
            : null,
        onTap: () {
          themeService.setThemeMode(mode);
          Navigator.pop(context);
          context.showSnackBar(
              'Switched to ${_getThemeDisplayName(mode)} theme');
        },
      ),
    );
  }

  IconData _getThemeIcon(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
      case AppThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  String _getThemeDisplayName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.system:
        return 'System';
    }
  }
}
