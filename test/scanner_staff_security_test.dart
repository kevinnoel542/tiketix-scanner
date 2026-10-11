import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ticketx_scanner/services/scanner_pin.dart';
import 'package:ticketx_scanner/services/scanner_staff_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('device signatures are valid Ed25519 signatures and cannot sign another payload', () async {
    final api = ScannerStaffApi();
    final key = SimplePublicKey(base64Decode(await api.publicKey()), type: KeyPairType.ed25519);
    final signature = Signature(base64Decode(await api.sign('scanner-proof')), publicKey: key);
    expect(await Ed25519().verify(utf8.encode('scanner-proof'), signature: signature), isTrue);
    expect(await Ed25519().verify(utf8.encode('altered-proof'), signature: signature), isFalse);
    expect(await ScannerStaffApi.digest('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('installation signing key survives service restart', () async {
    final first = await ScannerStaffApi().publicKey();
    expect(await ScannerStaffApi().publicKey(), first);
  });

  test('PIN is hashed, rejects incorrect codes and locks after repeated attempts', () async {
    final pin = ScannerPin();
    await pin.create('438921');
    expect(await pin.configured, isTrue);
    expect(await pin.unlock('438921'), isTrue);
    final raw = await pin.storage.read(key: 'staff.pin');
    expect(raw, isNot(contains('438921')));
    for (var i = 0; i < 5; i++) { expect(await pin.unlock('111111'), isFalse); }
    expect(() => pin.unlock('438921'), throwsStateError);
  });

  test('credential pair is persisted together and survives service restart', () async {
    final api = ScannerStaffApi(client: MockClient((_) async => http.Response('{}', 200)));
    final credentials = {'access_token': 'access', 'refresh_token': 'refresh',
      'expires_at': '2099-01-01T00:00:00Z', 'device_id': 'device'};
    await api.saveCredentials(credentials);
    final restored = ScannerStaffApi();
    await restored.restore();
    expect(restored.credentials, credentials);
    expect(restored.sessionToken, isNull);
  });
}
