import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:aether_ui/aether_ui.dart';

import 'services/theme_service.dart';
import 'services/session_service.dart';
import 'config/supabase_config.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/home_screen.dart';

/// Backend client. Null when the Supabase instance is not configured or its
/// initialisation failed — the app still starts and says so instead of hanging
/// on the launch splash. Every screen that needs the backend must check this
/// (or is only reachable when it is non-null) rather than touching it blindly.
SupabaseClient? hubDb;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hide system top status bar
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom],
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  String? configError;
  try {
    await dotenv.load(fileName: '.env', isOptional: true);
    SupabaseConfig.checkConfigured();
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
    hubDb = Supabase.instance.client;
  } catch (e) {
    // Never die before runApp: a missing backend is a message, not a hang.
    configError = e.toString();
  }

  final themeService = ThemeService();
  try {
    await themeService.initialize();
  } catch (e) {
    debugPrint('ThemeService init failed: $e');
  }

  runApp(NovaLifeApp(themeService: themeService, configError: configError));
}

/// Backwards-compatible accessor for code paths that only run when the backend
/// is configured. Throws a clear error instead of a null crash if misused.
SupabaseClient get supabase {
  final db = hubDb;
  if (db == null) {
    throw StateError(
      'Backend not configured. Rebuild with --dart-define=SUPABASE_URL=... '
      '--dart-define=SUPABASE_ANON_KEY=...',
    );
  }
  return db;
}

class NovaLifeApp extends StatefulWidget {
  final ThemeService themeService;

  /// Why the backend is unavailable, or null when it initialised fine.
  final String? configError;

  const NovaLifeApp(
      {super.key, required this.themeService, this.configError});

  @override
  State<NovaLifeApp> createState() => _NovaLifeAppState();
}

class _NovaLifeAppState extends State<NovaLifeApp> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _authSubscription;
  User? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyImmersiveMode();
    _requestFilePermissions();
    _initializeAuth();
  }

  void _applyImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyImmersiveMode();
    }
  }

  Future<void> _requestFilePermissions() async {
    try {
      // Storage permissions: photos (Android 13+ / API 33+) and storage (Android <= 12)
      final photosStatus = await Permission.photos.status;
      if (!photosStatus.isGranted && !photosStatus.isPermanentlyDenied) {
        await Permission.photos.request();
      }
      final storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted && !storageStatus.isPermanentlyDenied) {
        await Permission.storage.request();
      }
    } catch (e) {
      debugPrint('Permission request error: $e');
    }
  }

  Future<void> _initializeAuth() async {
    // No backend: the error screen is shown instead; nothing to subscribe to.
    if (widget.configError != null || hubDb == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // Restore persisted session from Supabase local storage
    _user = supabase.auth.currentUser;

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _user = data.session?.user;
        });
      }
    });

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.themeService,
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          final isDark = themeService.isDarkMode;
          final aetherTheme =
              isDark ? AetherThemeData.dark() : AetherThemeData.light();
          return AetherTheme(
            data: aetherTheme,
            child: MaterialApp(
              title: 'NovaLife - AI Medical Assistant',
              theme: themeService.lightTheme,
              darkTheme: themeService.darkTheme,
              themeMode: themeService.themeMode,
              debugShowCheckedModeBanner: false,
              home: widget.configError != null
                  ? _ConfigErrorScreen(message: widget.configError!)
                  : _isLoading
                      ? SplashScreen(themeService: themeService)
                      : _user == null
                          ? const LoginScreen()
                          : _user!.emailConfirmedAt == null
                              ? VerifyEmailScreen(user: _user!)
                              : HomeScreen(
                                  key: ValueKey('${_user!.id}:${roleOf(_user)}'),
                                  themeService: themeService,
                                  role: roleOf(_user),
                                  abhaId: abhaOf(_user),
                                ),
              builder: (context, child) {
                return AetherTheme(
                  data: aetherTheme,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(1.0),
                    ),
                    child: child!,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}


/// Shown instead of the whole app when the backend never initialised: the
/// alternative used to be dying before runApp(), which leaves the Android
/// launch splash on screen forever and looks like a hang.
class _ConfigErrorScreen extends StatelessWidget {
  final String message;

  const _ConfigErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 64, color: Color(0xFF2563EB)),
                const SizedBox(height: 24),
                const Text(
                  'Backend not configured',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                const Text(
                  'Rebuild the app with:\n'
                  '--dart-define=SUPABASE_URL=...\n'
                  '--dart-define=SUPABASE_ANON_KEY=...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ✅ Extension to fix showSnackBar errors
extension ContextExtension on BuildContext {
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(this).colorScheme.error
            : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void showLoadingSnackBar(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
