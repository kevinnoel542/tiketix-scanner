import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'scanner_api.dart';

class ScannerStaffApi {
  ScannerStaffApi({http.Client? client}) : client = client ?? http.Client();

  final http.Client client;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  static const baseUrl = String.fromEnvironment('API_URL');
  static const version = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  Map<String, dynamic>? credentials;
  String? sessionToken;
  Duration serverOffset = Duration.zero;
  Map<String, dynamic> configuration = {};
  Future<void>? _refreshing;

  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || !base.hasAuthority ||
        (base.scheme != 'https' && (kReleaseMode || base.scheme != 'http')) ||
        base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment ||
        (base.path.isNotEmpty && base.path != '/')) {
      throw const ApiException('Configure a valid HTTPS API origin.', code: 'API_CONFIGURATION');
    }
    return base.replace(path: '/api/v2/scanner$path', queryParameters: query);
  }

  Future<void> restore() async {
    final raw = await storage.read(key: 'staff.credentials');
    if (raw != null) credentials = Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<SimpleKeyPair> keyPair() async {
    final seed = await storage.read(key: 'staff.signingSeed');
    if (seed != null) return Ed25519().newKeyPairFromSeed(base64Decode(seed));
    final pair = await Ed25519().newKeyPair();
    await storage.write(key: 'staff.signingSeed', value: base64Encode(await pair.extractPrivateKeyBytes()));
    return pair;
  }

  Future<String> publicKey() async => base64Encode((await (await keyPair()).extractPublicKey()).bytes);

  Future<String> sign(String message) async => base64Encode(
    (await Ed25519().sign(utf8.encode(message), keyPair: await keyPair())).bytes,
  );

  static Future<String> digest(String value) async =>
      (await Sha256().hash(utf8.encode(value))).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  Future<Map<String, dynamic>> request(String path, {
    Map<String, dynamic>? body, bool authenticated = true, bool refresh = true,
    Map<String, String>? query,
  }) async {
    if (authenticated && refresh && credentials != null &&
        DateTime.parse(credentials!['expires_at'] as String).isBefore(DateTime.now().toUtc().add(serverOffset).add(const Duration(seconds: 30)))) {
      await refreshCredentials();
    }
    final target = uri(path, query);
    final method = body == null ? 'GET' : 'POST';
    final encoded = body == null ? '' : jsonEncode(body);
    final headers = <String, String>{'Accept': 'application/json', 'Content-Type': 'application/json',
      'X-Scanner-Version': version};
    if (authenticated) {
      if (credentials == null) throw const ApiException('Activate scanner access first.', status: 401, code: 'AUTH_REQUIRED');
      final token = credentials!['access_token'] as String;
      final timestamp = (DateTime.now().toUtc().add(serverOffset).millisecondsSinceEpoch ~/ 1000).toString();
      final nonce = const Uuid().v4();
      final useSession = !path.startsWith('/auth/') && path != '/offline/sync';
      final session = useSession ? sessionToken ?? '' : '';
      final proof = [method, '${target.path}${target.hasQuery ? '?${target.query}' : ''}', timestamp, nonce, await digest(encoded), await digest(token), await digest(session)].join('\n');
      headers.addAll({'Authorization': 'Bearer $token', 'X-Scanner-Timestamp': timestamp,
        'X-Scanner-Nonce': nonce, 'X-Scanner-Signature': await sign(proof)});
      if (sessionToken != null && useSession) headers['X-Scanner-Session'] = sessionToken!;
    }
    try {
      final response = await (() async {
        final request = http.Request(method, target)..headers.addAll(headers);
        if (body != null) request.body = encoded;
        return http.Response.fromStream(await client.send(request));
      })().timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Expected JSON object');
      final data = decoded;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = data['error'] as Map?;
        throw ApiException(error?['message']?.toString() ?? data['message']?.toString() ?? 'Scanner request failed.',
          code: error?['code']?.toString() ?? 'HTTP_ERROR', status: response.statusCode);
      }
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('Connection timed out. A scan may still have reached the server; retry the same scan.', code: 'TIMEOUT');
    } on SocketException {
      throw const ApiException('No connection. Online scanning is unavailable.', code: 'NETWORK_ERROR');
    } on http.ClientException {
      throw const ApiException('TiketiX could not be reached.', code: 'NETWORK_ERROR');
    } on FormatException {
      throw const ApiException('The server response could not be read.', code: 'INVALID_RESPONSE');
    }
  }

  Future<void> configure() async {
    final config = await request('/config', authenticated: false);
    configuration = config;
    serverOffset = DateTime.parse(config['server_time'] as String).difference(DateTime.now().toUtc());
    final minimum = (config['minimum_version'] as String).split('.').map(int.parse).toList();
    final current = version.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (current[i] > minimum[i]) break;
      if (current[i] < minimum[i]) throw const ApiException('Update TiketiX Scanner before continuing.', code: 'UPDATE_REQUIRED');
    }
  }

  Future<String> startActivation(String invitation, String phone) async =>
      (await request('/activation/start', authenticated: false, body: {'invitation': invitation.trim(), 'phone': phone.trim()}))['challenge_id'] as String;

  Future<void> verifyActivation(String challenge, String code, String deviceName) async {
    final public = await publicKey();
    final data = await request('/activation/verify', authenticated: false, body: {
      'challenge_id': challenge, 'code': code.trim(), 'device_name': deviceName.trim(), 'public_key': public,
      'signature': await sign('activate\n$challenge\n$public'),
    });
    await saveCredentials(data);
  }

  Future<void> saveCredentials(Map<String, dynamic> value) async {
    await storage.write(key: 'staff.credentials', value: jsonEncode(value));
    credentials = value;
  }

  Future<void> refreshCredentials() async {
    if (_refreshing != null) return _refreshing;
    final operation = (() async {
      final data = await request('/auth/refresh', body: {'refresh_token': credentials!['refresh_token']}, refresh: false);
      await saveCredentials(data);
    })();
    _refreshing = operation;
    try { await operation; } finally { _refreshing = null; }
  }

  Future<Map<String, dynamic>> profile() => request('/me');
  Future<Map<String, dynamic>> history() => request('/session/history');
  Future<Map<String, dynamic>> stats() => request('/session/stats');
  Future<Map<String, dynamic>> attendees({String search = '', int page = 1}) =>
      request('/session/attendees', query: {'search': search, 'page': '$page'});
  Future<Map<String, dynamic>> gateStaff() => request('/gate/staff');
  Future<Map<String, dynamic>> gateAction(int assignment, String action, {String? device, String? gate}) =>
      request('/gate/action', body: {'assignment_id': assignment, 'action': action, 'device_id': ?device, 'gate': ?gate});
  Future<void> heartbeat(int pending, bool offline) async {
    await request('/session/heartbeat', body: {'pending_scans': pending, 'mode': offline ? 'offline' : 'online'});
  }

  Future<Map<String, dynamic>> startSession(int assignment) async {
    sessionToken = null;
    final data = await request('/sessions/start', body: {'assignment_id': assignment});
    sessionToken = data['session_token'] as String;
    return data;
  }

  Future<void> endSession() async {
    if (sessionToken != null) await request('/sessions/end', body: {});
    sessionToken = null;
  }

  Future<void> logout() async {
    if (credentials != null) await request('/auth/logout', body: {});
    await storage.delete(key: 'staff.credentials');
    credentials = null;
    sessionToken = null;
  }

  Future<Map<String, dynamic>> scan(String id, String code, {bool confirm = false, String? entitlement}) =>
      request('/scan', body: {'scan_uuid': id, 'action': confirm ? 'check-in' : 'validate', 'token': code,
        'entitlement_id': ?entitlement});
}
