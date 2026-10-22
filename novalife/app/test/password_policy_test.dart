import 'package:flutter_test/flutter_test.dart';
import 'package:novalife/auth/password_policy.dart';

void main() {
  group('PasswordPolicy', () {
    test('accepts a strong password', () {
      expect(PasswordPolicy.validate('Str0ng!Care9'), isNull);
      expect(
        PasswordPolicy.failures(
          'Str0ng!Care9',
          email: 'a@b.com',
          username: 'Some Name',
        ),
        isEmpty,
      );
    });

    test('rejects empty password', () {
      expect(PasswordPolicy.validate(''), 'Please enter a password');
      expect(PasswordPolicy.validate(null), 'Please enter a password');
    });

    test('rejects short password', () {
      expect(
        PasswordPolicy.validate('Aa1!bcde'),
        contains('at least 10 characters'),
      );
    });

    test('rejects missing uppercase', () {
      expect(
        PasswordPolicy.validate('str0ng!care9'),
        contains('uppercase'),
      );
    });

    test('rejects missing lowercase', () {
      expect(
        PasswordPolicy.validate('STR0NG!CARE9'),
        contains('lowercase'),
      );
    });

    test('rejects missing digit', () {
      expect(
        PasswordPolicy.validate('Strong!Caree'),
        contains('digit'),
      );
    });

    test('rejects missing special character', () {
      expect(
        PasswordPolicy.validate('Str0ngCare99'),
        contains('special'),
      );
    });

    test('rejects password equal to email or username', () {
      expect(
        PasswordPolicy.validate(
          'Str0ng!Care9',
          email: 'Str0ng!Care9',
        ),
        contains('email or username'),
      );
      expect(
        PasswordPolicy.validate(
          'Str0ng!Care9',
          username: 'str0ng!care9',
        ),
        contains('email or username'),
      );
      // Email local part counts as identity too.
      expect(
        PasswordPolicy.validate(
          'labtech42',
          email: 'labtech42@hospital.in',
        ),
        isNotNull,
      );
    });

    test('rejects denylisted common passwords', () {
      // These entries satisfy every other rule, so the denylist is the
      // reason they fail.
      for (final common in ['Welcome@123', 'Hospital@123', 'Novalife@123']) {
        expect(
          PasswordPolicy.commonPasswords,
          contains(common.toLowerCase()),
        );
        expect(
          PasswordPolicy.validate(common),
          contains('commonly used'),
          reason: '$common should be denylisted',
        );
      }
      // Case-insensitive denylist match ('WelcomE@123' keeps upper+lower
      // so the denylist — not a charset rule — is the reason it fails).
      expect(
        PasswordPolicy.validate('WelcomE@123'),
        contains('commonly used'),
      );
    });

    test('validator returns first failing rule only', () {
      final failures = PasswordPolicy.failures('abc');
      expect(failures.length, greaterThan(1));
      expect(PasswordPolicy.validate('abc'), failures.first);
    });

    test('checkAll reports seven rules', () {
      expect(PasswordPolicy.checkAll('Str0ng!Care9').length, 7);
      expect(
        PasswordPolicy.checkAll('x').where((r) => r.$2).length,
        lessThan(7),
      );
    });
  });
}
