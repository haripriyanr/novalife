import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../main.dart';
import 'ai_chat_screen.dart';
import 'profile_screen.dart';
import 'ocr_screen.dart';
import 'voice_screen.dart';

class HomeScreen extends StatefulWidget {
  final ThemeService themeService;

  const HomeScreen({super.key, required this.themeService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const AIChatScreen(),
      const OCRScreen(),
      const VoiceScreen(),
      ProfileScreen(themeService: widget.themeService),
    ];
  }

  Future<void> _handleSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      try {
        await supabase.auth.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully signed out')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error signing out: $error')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        elevation: 0,
        actions: [
          // ✅ Theme Toggle Button (Restored)
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withAlpha(25)
                  : Colors.black.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showThemeSelector(context, themeService),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        themeService.themeIcon,
                        size: 20,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        themeService.themeDisplayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // User Profile & Sign Out
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'profile') {
                setState(() => _currentIndex = 3);
              } else if (value == 'signout') {
                _handleSignOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, size: 20),
                    SizedBox(width: 8),
                    Text('Profile'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Sign Out', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2563EB),
        unselectedItemColor: isDark ? Colors.grey[400] : Colors.grey[600],
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'AI Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt_outlined),
            activeIcon: Icon(Icons.camera_alt),
            label: 'OCR Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic_none),
            activeIcon: Icon(Icons.mic),
            label: 'Voice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentIndex) {
      case 0: return 'AI Assistant';
      case 1: return 'OCR Scanner';
      case 2: return 'Voice Assistant';
      case 3: return 'Profile';
      default: return 'NovaLife';
    }
  }

  // ✅ Theme Selection Modal (Restored)
  Future<void> _showThemeSelector(BuildContext context, ThemeService themeService) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[600] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Choose Theme',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 24),

            ...AppThemeMode.values.map((mode) => _buildThemeOption(
              context, themeService, mode, isDark,
            )),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(BuildContext context, ThemeService themeService,
      AppThemeMode mode, bool isDark) {
    final isSelected = themeService.currentThemeMode == mode;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF2563EB).withAlpha(25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? const Color(0xFF2563EB)
              : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2563EB)
                : (isDark ? Colors.grey[700] : Colors.grey[200]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getThemeIcon(mode),
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.grey[300] : Colors.grey[600]),
            size: 20,
          ),
        ),
        title: Text(
          _getThemeDisplayName(mode),
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? const Color(0xFF2563EB)
                : (isDark ? Colors.white : Colors.black),
          ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Color(0xFF2563EB))
            : null,
        onTap: () {
          themeService.setThemeMode(mode);
          Navigator.pop(context);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(_getThemeIcon(mode), color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('Switched to ${_getThemeDisplayName(mode)} theme'),
                ],
              ),
              backgroundColor: const Color(0xFF2563EB),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  IconData _getThemeIcon(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light: return Icons.light_mode;
      case AppThemeMode.dark: return Icons.dark_mode;
      case AppThemeMode.system: return Icons.brightness_auto;
    }
  }

  String _getThemeDisplayName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light: return 'Light';
      case AppThemeMode.dark: return 'Dark';
      case AppThemeMode.system: return 'System';
    }
  }
}
