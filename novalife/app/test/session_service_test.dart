import 'package:flutter_test/flutter_test.dart';
import 'package:novalife/services/session_service.dart';

void main() {
  group('SessionService initialsOf tests', () {
    test('two word name returns first letter of both words', () {
      expect(initialsOf('Anjali Mehta'), equals('AM'));
      expect(initialsOf('Dr. Priya Nair'), equals('PN'));
      expect(initialsOf('Lab Tech'), equals('LT'));
    });

    test('single word name returns first two letters uppercase', () {
      expect(initialsOf('Admin'), equals('AD'));
      expect(initialsOf('Doctor'), equals('DO'));
      expect(initialsOf('P'), equals('PU'));
    });

    test('fallback to email prefix when name is null or empty', () {
      expect(initialsOf(null, fallbackEmail: 'doctor@syndrix.tech'), equals('DO'));
      expect(initialsOf('', fallbackEmail: 'lab@syndrix.tech'), equals('LA'));
      expect(initialsOf('   ', fallbackEmail: 'patient@syndrix.tech'), equals('PA'));
    });

    test('fallback to NL when both name and email are absent', () {
      expect(initialsOf(null), equals('NL'));
      expect(initialsOf(''), equals('NL'));
    });
  });

  group('SessionService role helpers', () {
    test('roleFromDb parses valid roles correctly', () {
      expect(roleFromDb('lab_tech'), equals(AppRole.labTech));
      expect(roleFromDb('doctor'), equals(AppRole.doctor));
      expect(roleFromDb('patient'), equals(AppRole.patient));
      expect(roleFromDb('unknown'), equals(AppRole.patient));
      expect(roleFromDb(null), equals(AppRole.patient));
    });

    test('roleToDb outputs database string representation', () {
      expect(roleToDb(AppRole.labTech), equals('lab_tech'));
      expect(roleToDb(AppRole.doctor), equals('doctor'));
      expect(roleToDb(AppRole.patient), equals('patient'));
    });

    test('roleLabel produces clean human readable titles', () {
      expect(roleLabel(AppRole.labTech), equals('Lab Tech'));
      expect(roleLabel(AppRole.doctor), equals('Doctor'));
      expect(roleLabel(AppRole.patient), equals('Patient'));
    });
  });
}
