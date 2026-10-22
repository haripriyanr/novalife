/// Shared password policy for signup + set/reset password screens.
///
/// Rules: minimum 10 chars, at least one upper-case, one lower-case, one digit
/// and one special character; the password must not equal the account's email
/// or username (case-insensitive, including the email local part); and it must
/// not be on a small denylist of common passwords (case-insensitive).
///
/// Use [validate] as a [FormFieldValidator] (returns the first failing rule)
/// and [PasswordRulesHint] for the live per-rule checklist.
class PasswordPolicy {
  static const int minLength = 10;

  /// Short denylist of common, guessable passwords. Compared case-insensitively
  /// against the candidate (exact match only — this is a floor, not a strength
  /// meter). Keep entries lowercase.
  static const List<String> commonPasswords = [
    'password',
    'password1',
    'password12',
    'password123',
    'password1234',
    'passw0rd123',
    '1234567890',
    '123456789',
    'qwerty123',
    'qwerty1234',
    'qwertyuiop',
    '1q2w3e4r5t',
    'letmein123',
    'welcome123',
    'welcome@123',
    'admin12345',
    'administrator1',
    'changeme123',
    'changeme@123',
    'novalife123',
    'novalife@123',
    'hospital123',
    'hospital@123',
    'doctor12345',
    'patient12345',
    'iloveyou123',
    'sunshine123',
    'football123',
    'superman123',
    'dragon12345',
    'master12345',
    'hello12345',
  ];

  static final RegExp _upper = RegExp(r'[A-Z]');
  static final RegExp _lower = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _special = RegExp(r'[^A-Za-z0-9]');

  /// Ordered (label, satisfied?) pairs used by both [failures] and the UI hint.
  static List<(String label, bool satisfied)> checkAll(
    String password, {
    String? email,
    String? username,
  }) {
    final lowered = password.toLowerCase();
    final emailLower = email?.trim().toLowerCase() ?? '';
    final userLower = username?.trim().toLowerCase() ?? '';
    final localPart = emailLower.contains('@')
        ? emailLower.split('@').first
        : emailLower;
    final isIdentity = password.isNotEmpty &&
        (lowered == emailLower ||
            (localPart.isNotEmpty && lowered == localPart) ||
            (userLower.isNotEmpty && lowered == userLower));
    return [
      ('Use at least $minLength characters', password.length >= minLength),
      ('Include an uppercase letter (A-Z)', _upper.hasMatch(password)),
      ('Include a lowercase letter (a-z)', _lower.hasMatch(password)),
      ('Include a digit (0-9)', _digit.hasMatch(password)),
      ('Include a special character (e.g. ! @ # ?)', _special.hasMatch(password)),
      ('Must not be your email or username', !isIdentity),
      (
        'Must not be a commonly used password',
        !commonPasswords.contains(lowered)
      ),
    ];
  }

  /// Every failing rule's message, in rule order. Empty means the password passes.
  static List<String> failures(
    String password, {
    String? email,
    String? username,
  }) {
    return [
      for (final (label, satisfied) in checkAll(
        password,
        email: email,
        username: username,
      ))
        if (!satisfied) label,
    ];
  }

  /// Form validator: null when the password passes, else the first failing rule.
  static String? validate(
    String? password, {
    String? email,
    String? username,
  }) {
    if (password == null || password.isEmpty) {
      return 'Please enter a password';
    }
    final failed = failures(password, email: email, username: username);
    return failed.isEmpty ? null : failed.first;
  }
}
