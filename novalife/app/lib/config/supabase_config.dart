import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase connection config, read from the app's `.env` file (see `.env.example`).
///
/// Setup: `cp .env.example .env`, then put your project URL and anon key in `.env`.
/// A build-time override still works and wins over `.env`:
/// ```bash
/// flutter run \
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=your-anon-key
/// ```
/// No key or project URL is stored in the source code.
abstract final class SupabaseConfig {
  static const String _definedUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _definedKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String _fromEnv(String name) {
    try {
      return dotenv.maybeGet(name) ?? '';
    } catch (_) {
      return ''; // dotenv not loaded (e.g. in a unit test)
    }
  }

  /// Base URL of the Supabase instance.
  static String get url => _definedUrl.isNotEmpty ? _definedUrl : _fromEnv('SUPABASE_URL');

  /// Anon / publishable key for the instance above.
  static String get anonKey =>
      _definedKey.isNotEmpty ? _definedKey : _fromEnv('SUPABASE_ANON_KEY');

  /// Throws a readable error when the backend is not configured.
  static void checkConfigured() {
    if (url.isEmpty || anonKey.isEmpty || url.contains('YOUR-PROJECT-REF')) {
      throw StateError(
        'Supabase is not configured. Copy .env.example to .env and set SUPABASE_URL and '
        'SUPABASE_ANON_KEY (or pass them with --dart-define).',
      );
    }
  }
}
