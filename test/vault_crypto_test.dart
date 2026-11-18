import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novalife/models/health_record.dart';
import 'package:novalife/services/legacy_ehr.dart';
import 'package:novalife/services/vault_service.dart';

import 'legacy_encryptor_fixture.dart';

void main() {
  const uid = '6f1c2a9e-0000-4000-8000-000000000001';

  test('a record round-trips through the vault format, photo included', () async {
    final key = await AesGcm.with256bits().newSecretKey();
    final record = HealthRecord(
      title: 'Blood test',
      notes: 'HbA1c 5.6%. Recheck in 6 months.',
      createdAt: DateTime.utc(2026, 11, 18, 9, 30),
      photo: Uint8List.fromList(List.generate(500, (i) => i % 256)),
      photoMime: 'image/jpeg',
    );
    final blob = await VaultService.encryptWith(key, uid, record);
    expect(utf8.decode(blob.sublist(0, 8)), 'NLREC001');
    expect(utf8.decode(blob, allowMalformed: true).contains('HbA1c'), isFalse);

    final back = await VaultService.decryptWith(key, uid, blob);
    expect(back.title, record.title);
    expect(back.notes, record.notes);
    expect(back.createdAt.toUtc(), record.createdAt);
    expect(back.photo, record.photo);
  });

  test('a record does not open with another key or in another account', () async {
    final key = await AesGcm.with256bits().newSecretKey();
    final blob = await VaultService.encryptWith(
      key,
      uid,
      HealthRecord(title: 't', notes: 'n', createdAt: DateTime.now()),
    );
    final otherKey = await AesGcm.with256bits().newSecretKey();
    await expectLater(VaultService.decryptWith(otherKey, uid, blob), throwsFormatException);
    await expectLater(VaultService.decryptWith(key, 'someone-else', blob), throwsFormatException);
  });

  test('a tampered record is rejected', () async {
    final key = await AesGcm.with256bits().newSecretKey();
    final blob = await VaultService.encryptWith(
      key,
      uid,
      HealthRecord(title: 't', notes: 'n', createdAt: DateTime.now()),
    );
    blob[20] ^= 0x01;
    await expectLater(VaultService.decryptWith(key, uid, blob), throwsFormatException);
  });

  test('records saved by the first version can still be read for migration', () async {
    final cover = Uint8List.fromList(img.encodePng(img.Image(width: 64, height: 64)));
    const text = 'Old record: BP 120/80';
    final stego = await EHREncryptor.buildStegoPng(
      coverPng: cover,
      uuid: uid,
      plaintext: Uint8List.fromList(utf8.encode(text)),
    );
    final clear = await LegacyEhr.extractAndDecrypt(stego, uid);
    expect(utf8.decode(clear), text);
  });
}
