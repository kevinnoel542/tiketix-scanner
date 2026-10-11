import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ticketx_scanner/services/scanner_offline.dart';
import 'package:ticketx_scanner/services/scanner_staff_api.dart';
import 'package:ticketx_scanner/services/scanner_offline_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory temporary;
  late ScannerOfflineStore store;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('scanner-offline-test-');
    store = ScannerOfflineStore(factory: databaseFactoryFfi, path: '${temporary.path}/state.db');
  });
  tearDown(() async { await store.close(); await temporary.delete(recursive: true); });

  ScannerOffline fixture() {
    final api = ScannerStaffApi()..credentials = {'device_id': 'device'};
    final offline = ScannerOffline(api, store: store)..anchorServerTime();
    offline.state['packages'] = {'1': {'package_id': 'package', 'device_id': 'device',
      'assignment_id': 1, 'expires_at': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
      'tickets': [{'id': 'ticket', 'name': 'Test guest', 'type': 'General', 'checked_in': false,
        'token_hash': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}]}};
    return offline;
  }

  test('offline admission saves an encrypted durable record before showing success', () async {
    final offline = fixture();
    expect((await offline.scan(1, 'abc'))['status'], 'PENDING_CONFIRMATION');
    expect((await offline.scan(1, 'abc', confirm: true))['status'], 'OFFLINE_RECORDED');
    expect(offline.pendingCount, 1);
    expect((await offline.scan(1, 'abc', confirm: true))['status'], 'ALREADY_CHECKED_IN');
    expect(offline.pendingCount, 1);
    final raw = (await store.read())!;
    expect(raw, isNot(contains('Test guest')));
    expect(raw, isNot(contains('scan_uuid')));
    await store.close();
    store = ScannerOfflineStore(factory: databaseFactoryFfi, path: '${temporary.path}/state.db');
    final restored = ScannerOffline(offline.api, store: store);
    await restored.restore();
    expect(restored.pendingCount, 1);
    expect(restored.queue.first['scan_uuid'], offline.queue.first['scan_uuid']);
    expect(() => restored.scan(1, 'abc'), throwsStateError);
  });

  test('offline package rejects wrong event, unknown tickets and expired access', () async {
    final offline = fixture();
    expect(() => offline.scan(2, 'abc'), throwsStateError);
    expect((await offline.scan(1, 'unknown'))['status'], 'INVALID_TOKEN');
    (offline.state['packages'] as Map)['1']['expires_at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String();
    expect(() => offline.scan(1, 'abc'), throwsStateError);
    expect(offline.pendingCount, 0);
  });

  test('simultaneous offline scans cannot admit the same ticket twice', () async {
    final offline = fixture();
    final results = await Future.wait([offline.scan(1, 'abc', confirm: true), offline.scan(1, 'abc', confirm: true)]);
    expect(results.map((result) => result['status']).toList(), ['OFFLINE_RECORDED', 'ALREADY_CHECKED_IN']);
    expect(offline.pendingCount, 1);
  });

  test('package cryptography checks encryption, signature and package identity', () async {
    final pair = await X25519().newKeyPair();
    final sender = await X25519().newKeyPair();
    final signing = await Ed25519().newKeyPair();
    final public = base64Encode((await signing.extractPublicKey()).bytes);
    const id = 'fixture-package';
    final payload = base64Encode(utf8.encode(jsonEncode({'version': 1, 'package_id': id})));
    final signature = base64Encode((await Ed25519().sign(utf8.encode(payload), keyPair: signing)).bytes);
    final shared = await X25519().sharedSecretKey(keyPair: sender, remotePublicKey: await pair.extractPublicKey());
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(secretKey: shared,
      nonce: utf8.encode(id), info: utf8.encode('tiketix-offline-v1'));
    final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode({'payload': payload, 'signature': signature})), secretKey: key, aad: utf8.encode(id));
    final envelope = {'package_id': id, 'ephemeral_key': base64Encode((await sender.extractPublicKey()).bytes),
      'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'tag': base64Encode(box.mac.bytes)};
    expect((await ScannerOffline.decryptPackage(envelope, pair, public))['package_id'], id);
    final wrongDevice = await X25519().newKeyPair();
    expect(() => ScannerOffline.decryptPackage(envelope, wrongDevice, public), throwsA(isA<SecretBoxAuthenticationError>()));
    final wrongSigning = base64Encode((await (await Ed25519().newKeyPair()).extractPublicKey()).bytes);
    expect(() => ScannerOffline.decryptPackage(envelope, pair, wrongSigning), throwsStateError);
    envelope['package_id'] = 'different-package';
    expect(() => ScannerOffline.decryptPackage(envelope, pair, public), throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('tampered local queue fails authentication rather than loading forged scans', () async {
    final offline = fixture();
    await offline.scan(1, 'abc', confirm: true);
    final box = jsonDecode((await store.read())!) as Map;
    final bytes = base64Decode(box['ciphertext'] as String);
    bytes[0] ^= 1;
    box['ciphertext'] = base64Encode(bytes);
    await store.write(jsonEncode(box));
    expect(() => ScannerOffline(offline.api, store: store).restore(), throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('decrypts and verifies a package generated by the real Laravel service', () async {
    final vector = jsonDecode(await File('test/fixtures/php_offline_package.json').readAsString()) as Map;
    final pair = await X25519().newKeyPairFromSeed(base64Decode(vector['device_private_key'] as String));
    final manifest = await ScannerOffline.decryptPackage(Map<String, dynamic>.from(vector['envelope'] as Map), pair, vector['signing_key'] as String);
    expect(manifest['version'], 1);
    expect((manifest['tickets'] as List).first['name'], 'John Attendee');
    expect((manifest['tickets'] as List).first['token_hash'], hasLength(64));
  });
}
