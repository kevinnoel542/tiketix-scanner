import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'scanner_staff_api.dart';
import 'scanner_offline_store.dart';

class ScannerOffline {
  ScannerOffline(this.api, {ScannerOfflineStore? store}) : store = store ?? ScannerOfflineStore();
  final ScannerStaffApi api;
  final ScannerOfflineStore store;
  final storage = const FlutterSecureStorage();
  final cipher = AesGcm.with256bits();
  Map<String, dynamic> state = {'packages': <String, dynamic>{}, 'queue': <dynamic>[], 'results': <dynamic>[]};
  final Stopwatch clock = Stopwatch();
  DateTime? anchor;
  Future<void> _tail = Future.value();

  Future<T> serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }

  Future<SecretKey> localKey() async {
    final existing = await storage.read(key: 'staff.offlineStorageKey');
    if (existing != null) return SecretKey(base64Decode(existing));
    final key = await cipher.newSecretKey();
    await storage.write(key: 'staff.offlineStorageKey', value: base64Encode(await key.extractBytes()));
    return key;
  }

  Future<void> restore() => serial(() async {
    final raw = await store.read();
    if (raw == null) return;
    final box = jsonDecode(raw) as Map;
    final clear = await cipher.decrypt(SecretBox(base64Decode(box['ciphertext'] as String),
      nonce: base64Decode(box['nonce'] as String), mac: Mac(base64Decode(box['tag'] as String))),
      secretKey: await localKey(), aad: utf8.encode('tiketix-scanner-local-v1'));
    state = Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map);
  });

  Future<void> persist(Map<String, dynamic> value) async {
    final box = await cipher.encrypt(utf8.encode(jsonEncode(value)), secretKey: await localKey(),
      aad: utf8.encode('tiketix-scanner-local-v1'));
    await store.write(jsonEncode({
      'ciphertext': base64Encode(box.cipherText), 'nonce': base64Encode(box.nonce), 'tag': base64Encode(box.mac.bytes),
    }));
    state = value;
  }

  void anchorServerTime() {
    anchor = DateTime.now().toUtc().add(api.serverOffset);
    clock..reset()..start();
  }

  DateTime get serverNow {
    if (anchor == null) throw StateError('Connect to TiketiX once after reopening the app before scanning offline.');
    return anchor!.add(clock.elapsed);
  }

  List<dynamic> get queue => state['queue'] as List;
  int get pendingCount => queue.length;
  List<dynamic> get results => state['results'] as List;

  Map<String, dynamic>? packageFor(int assignment) {
    final value = (state['packages'] as Map)['$assignment'];
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  Future<SimpleKeyPair> encryptionPair() async {
    final existing = await storage.read(key: 'staff.offlineEncryptionSeed');
    if (existing != null) return X25519().newKeyPairFromSeed(base64Decode(existing));
    final pair = await X25519().newKeyPair();
    await storage.write(key: 'staff.offlineEncryptionSeed', value: base64Encode(await pair.extractPrivateKeyBytes()));
    return pair;
  }

  Future<void> download() => serial(() async {
    if (api.configuration['offline_enabled'] != true) throw StateError('Offline scanning is not enabled.');
    final pair = await encryptionPair();
    final envelope = await api.request('/offline/package', body: {'encryption_key': base64Encode((await pair.extractPublicKey()).bytes)});
    final manifest = await decryptPackage(envelope, pair, api.configuration['offline_signing_key'] as String);
    if (manifest['device_id'] != api.credentials?['device_id']) throw StateError('Package belongs to another device.');
    final previous = packageFor(manifest['assignment_id'] as int);
    final used = <dynamic>{
      ...queue.map((scan) => scan['ticket_id']),
      ...((previous?['tickets'] as List?) ?? []).where((ticket) => ticket['checked_in'] == true).map((ticket) => ticket['id']),
    };
    manifest['tickets'] = (manifest['tickets'] as List).map((ticket) =>
      used.contains(ticket['id']) ? {...ticket as Map, 'checked_in': true} : ticket).toList();
    final next = Map<String, dynamic>.from(state);
    next['packages'] = {...state['packages'] as Map, '${manifest['assignment_id']}': manifest};
    await persist(next);
    anchorServerTime();
  });

  static Future<Map<String, dynamic>> decryptPackage(Map<String, dynamic> envelope, SimpleKeyPair pair, String signingKey) async {
    final id = envelope['package_id'] as String;
    final shared = await X25519().sharedSecretKey(keyPair: pair,
      remotePublicKey: SimplePublicKey(base64Decode(envelope['ephemeral_key'] as String), type: KeyPairType.x25519));
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(secretKey: shared,
      nonce: utf8.encode(id), info: utf8.encode('tiketix-offline-v1'));
    final clear = await AesGcm.with256bits().decrypt(SecretBox(base64Decode(envelope['ciphertext'] as String),
      nonce: base64Decode(envelope['nonce'] as String), mac: Mac(base64Decode(envelope['tag'] as String))),
      secretKey: key, aad: utf8.encode(id));
    final signed = jsonDecode(utf8.decode(clear)) as Map;
    final payload = signed['payload'] as String;
    final valid = await Ed25519().verify(utf8.encode(payload), signature: Signature(base64Decode(signed['signature'] as String),
      publicKey: SimplePublicKey(base64Decode(signingKey), type: KeyPairType.ed25519)));
    if (!valid) throw StateError('Offline package signature is invalid.');
    final manifest = Map<String, dynamic>.from(jsonDecode(utf8.decode(base64Decode(payload))) as Map);
    if (manifest['package_id'] != id || manifest['version'] != 1) throw StateError('Offline package version or ID is invalid.');
    return manifest;
  }

  Future<Map<String, dynamic>> scan(int assignment, String code, {bool confirm = false}) => serial(() async {
    final package = packageFor(assignment);
    if (package == null || package['device_id'] != api.credentials?['device_id']) throw StateError('No offline package for this assignment.');
    if (!DateTime.parse(package['expires_at'] as String).isAfter(serverNow)) throw StateError('Offline package expired. Reconnect before scanning.');
    final hash = await ScannerStaffApi.digest(code);
    final ticket = (package['tickets'] as List).cast<Map>().where((ticket) => ticket['token_hash'] == hash).firstOrNull;
    if (ticket == null) return {'status': 'INVALID_TOKEN', 'message': 'Ticket not in this offline package.', 'item_type': 'ticket'};
    final redeemed = ticket['checked_in'] == true || queue.any((scan) => scan['ticket_id'] == ticket['id']);
    if (redeemed) return {'status': 'ALREADY_CHECKED_IN', 'message': 'Already admitted on this device or package snapshot.'};
    if (confirm) {
      if (pendingCount >= 2000) throw StateError('Offline queue is full. Sync before admitting more tickets.');
      final record = {'scan_uuid': const Uuid().v4(), 'package_id': package['package_id'],
        'ticket_id': ticket['id'], 'scanned_at': serverNow.toIso8601String()};
      final next = Map<String, dynamic>.from(state);
      next['queue'] = [...queue, record];
      // Package and admission queue commit together before a positive gate result is shown.
      final packages = Map<String, dynamic>.from(state['packages'] as Map);
      packages['$assignment'] = {...package, 'tickets': (package['tickets'] as List).map((item) =>
        item['id'] == ticket['id'] ? {...item as Map, 'checked_in': true} : item).toList()};
      next['packages'] = packages;
      await persist(next);
    }
    return {'status': confirm ? 'OFFLINE_RECORDED' : 'PENDING_CONFIRMATION', 'item_type': 'ticket',
      'message': confirm ? 'Entry recorded offline. Awaiting sync.' : 'Valid in offline snapshot. Confirm entry.',
      'attendee': {'name': ticket['name'], 'role': ticket['type']}};
  });

  Future<void> sync() => serial(() async {
    while (queue.isNotEmpty) {
      final batch = queue.take(50).toList();
      final response = await api.request('/offline/sync', body: {'scans': batch}, refresh: false);
      final received = (response['results'] as List).cast<Map>();
      final submitted = batch.map((scan) => scan['scan_uuid']).toSet();
      final ids = received.map((record) => record['scan_uuid']).toSet();
      if (ids.length != batch.length || !ids.containsAll(submitted)) throw StateError('Incomplete sync receipt. The scans have been kept for retry.');
      final next = Map<String, dynamic>.from(state);
      next['queue'] = queue.where((scan) => !ids.contains(scan['scan_uuid'])).toList();
      next['results'] = [...received.map((result) => {...result, 'ticket_id': batch.firstWhere((scan) => scan['scan_uuid'] == result['scan_uuid'])['ticket_id']}), ...results].take(200).toList();
      final recorded = batch.map((scan) => scan['ticket_id']).toSet();
      next['packages'] = (state['packages'] as Map).map((id, package) => MapEntry(id, {...package as Map,
        'tickets': (package['tickets'] as List).map((ticket) => recorded.contains(ticket['id'])
          ? {...ticket as Map, 'checked_in': true} : ticket).toList()}));
      await persist(next);
    }
  });
}
