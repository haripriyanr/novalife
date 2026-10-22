/// Demo mode: when true, screens may fall back to the built-in sample data (`HubApiMockClient`).
///
/// It is OFF by default, so a missing or failing backend shows a clear error instead of fake
/// patients, reports or notes.  Turn it on only for demos without a backend:
/// `flutter run --dart-define=DEMO_MODE=true`.
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

/// Password of the demo accounts, supplied at build time (`--dart-define=DEMO_PASSWORD=...`); never stored in the source.
const String kDemoPassword = String.fromEnvironment('DEMO_PASSWORD');

/// A backend read/write that failed.  Carries a message that is safe to show to the user.
class HubDataException implements Exception {
  final String message;
  const HubDataException(this.message);
  @override
  String toString() => message;
}
