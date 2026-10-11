import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ScannerPin {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  final algorithm = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256);

  Future<bool> get configured async => await storage.read(key: 'staff.pin') != null;

  Future<void> create(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) throw ArgumentError('Use six digits.');
    final random = Random.secure();
    final salt = List<int>.generate(32, (_) => random.nextInt(256));
    final hash = await algorithm.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
    await storage.write(key: 'staff.pin', value: jsonEncode({'salt': base64Encode(salt),
      'hash': base64Encode(await hash.extractBytes()), 'attempts': 0}));
  }

  Future<bool> unlock(String pin) async {
    final raw = await storage.read(key: 'staff.pin');
    if (raw == null) return false;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final until = data['locked_until'] as int?;
    if (until != null && DateTime.now().millisecondsSinceEpoch < until) {
      throw StateError('Too many attempts. Wait before trying again.');
    }
    final hash = await algorithm.deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: base64Decode(data['salt'] as String));
    final expected = base64Decode(data['hash'] as String);
    final actual = await hash.extractBytes();
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < actual.length && i < expected.length; i++) { difference |= actual[i] ^ expected[i]; }
    final valid = difference == 0;
    final attempts = valid ? 0 : (data['attempts'] as int? ?? 0) + 1;
    data['attempts'] = attempts;
    if (attempts >= 5) data['locked_until'] = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;
    if (valid) data.remove('locked_until');
    await storage.write(key: 'staff.pin', value: jsonEncode(data));
    return valid;
  }

  Future<void> resetAfterActivation() => storage.delete(key: 'staff.pin');
}
