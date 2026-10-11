import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/scanner_models.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.code = 'API_ERROR',
    this.status,
    this.retryAfter,
  });

  final String message;
  final String code;
  final int? status;
  final Duration? retryAfter;

  bool get isAuthenticationFailure => status == 401;

  @override
  String toString() => message;
}

typedef SessionExpiredCallback = Future<void> Function();

class ScannerApi {
  ScannerApi(this.storage, {http.Client? client, this.onSessionExpired})
    : client = client ?? http.Client();

  final StorageService storage;
  final http.Client client;
  final SessionExpiredCallback? onSessionExpired;

  static const baseUrl = String.fromEnvironment('API_URL');
  static const _timeout = Duration(seconds: 15);

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) {
    if (!isConfigured) {
      throw const ApiException(
        'Start Flutter with --dart-define=API_URL=https://your-api.example.com',
        code: 'MISSING_API_URL',
      );
    }
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, String>? query,
    Object? body,
    bool auth = true,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Request-ID': _requestId(),
    };
    if (auth) {
      final token = await storage.token;
      if (token == null) {
        throw const ApiException(
          'Session missing. Sign in again.',
          code: 'AUTH_REQUIRED',
          status: 401,
        );
      }
      headers['Authorization'] = 'Bearer $token';
      headers['X-Scanner-Device'] = await storage.getDeviceId();
    }

    try {
      final request = http.Request(method, _uri(path, query))
        ..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(_timeout);
      final data = _decode(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = data['error'] is Map
            ? Map<String, dynamic>.from(data['error'] as Map)
            : <String, dynamic>{};
        final exception = ApiException(
          error['message']?.toString() ??
              data['message']?.toString() ??
              'Request failed (${response.statusCode}).',
          code: error['code']?.toString() ?? 'HTTP_ERROR',
          status: response.statusCode,
          retryAfter: _retryAfter(response.headers['retry-after']),
        );
        if (response.statusCode == 401) {
          await storage.clearSession();
          await onSessionExpired?.call();
        }
        throw exception;
      }
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Check the connection and retry.',
        code: 'TIMEOUT',
      );
    } on SocketException {
      throw const ApiException(
        'No connection to the TiketiX service.',
        code: 'NETWORK_ERROR',
      );
    } on http.ClientException {
      throw const ApiException(
        'The TiketiX service could not be reached.',
        code: 'NETWORK_ERROR',
      );
    } on FormatException {
      throw const ApiException(
        'The server returned an unreadable response.',
        code: 'INVALID_RESPONSE',
      );
    }
  }

  Future<Map<String, dynamic>> health() =>
      _request('/api/v1/scanner/health', auth: false);

  Future<void> login(String email, String password) async {
    final data = await _request(
      '/api/v1/scanner/auth/login',
      method: 'POST',
      auth: false,
      body: {'email': email, 'password': password},
    );
    final token = data['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw const ApiException(
        'The server returned an invalid login response.',
        code: 'INVALID_RESPONSE',
      );
    }
    await storage.saveSession(token, email);
  }

  Future<SessionInfo> session() async {
    final deviceId = await storage.getDeviceId();
    return SessionInfo.fromJson(
      await _request(
        '/api/v1/scanner/session/me',
        query: {'device_id': deviceId},
      ),
    );
  }

  Future<String> registerDevice(String name) async {
    final data = await _request(
      '/api/v1/scanner/devices/register',
      method: 'POST',
      body: {
        'device_id': await storage.getDeviceId(),
        'device_name': name,
        'platform': Platform.operatingSystem,
        'app_version': '1.0.0',
      },
    );
    await storage.saveDeviceName(name);
    return data['status']?.toString() ?? 'pending';
  }

  Future<List<ScannerEvent>> events() async {
    final data = await _request('/api/v1/scanner/events');
    final source = data['events'];
    return source is List
        ? source
              .whereType<Map>()
              .map((item) => ScannerEvent.fromJson(_asMap(item)))
              .toList()
        : [];
  }

  Future<ScannerEvent> event(int id) async {
    final data = await _request('/api/v1/scanner/events/$id');
    final event = _asMap(data['event']);
    event['stats'] = data['stats'];
    return ScannerEvent.fromJson(event);
  }

  Future<ScanResult> validate(String value, ScannerEvent event) =>
      _scan('/api/v1/scanner/validate', value, event);

  Future<ScanResult> checkIn(
    String value,
    ScannerEvent event, {
    String? entitlementId,
  }) => _scan(
    '/api/v1/scanner/check-in',
    value,
    event,
    entitlementId: entitlementId,
  );

  Future<ScanResult> _scan(
    String path,
    String value,
    ScannerEvent event, {
    String? entitlementId,
  }) async {
    final normalized = normalizeCode(value);
    final body = <String, dynamic>{
      'event_id': event.id,
      'device_id': await storage.getDeviceId(),
    };
    if (_uuid.hasMatch(normalized)) {
      body['ticket_id'] = normalized;
    } else {
      body['token'] = normalized;
    }
    if (entitlementId != null) body['entitlement_id'] = entitlementId;
    return ScanResult.fromJson(
      await _request(path, method: 'POST', body: body),
    );
  }

  Future<List<Attendee>> lookup(String query, ScannerEvent event) async {
    final data = await _request(
      '/api/v1/scanner/lookup',
      query: {'event_id': '${event.id}', 'query': query.trim()},
    );
    final source = data['results'];
    return source is List
        ? source
              .whereType<Map>()
              .map((item) => Attendee.fromJson(_asMap(item)))
              .toList()
        : [];
  }

  Future<AttendeePage> attendees(
    ScannerEvent event, {
    String? search,
    int page = 1,
  }) async {
    final query = {
      'event_id': '${event.id}',
      'page': '$page',
      'per_page': '50',
      if (search?.trim().isNotEmpty == true) 'search': search!.trim(),
    };
    return AttendeePage.fromJson(
      await _request('/api/v1/scanner/attendees', query: query),
    );
  }

  Future<EventStats> stats(ScannerEvent event) async => EventStats.fromJson(
    await _request('/api/v1/scanner/stats', query: {'event_id': '${event.id}'}),
  );

  Future<List<ScanHistoryItem>> history(ScannerEvent event) async {
    final data = await _request(
      '/api/v1/scanner/history',
      query: {'event_id': '${event.id}', 'limit': '100'},
    );
    final source = data['items'];
    return source is List
        ? source
              .whereType<Map>()
              .map((item) => ScanHistoryItem.fromJson(_asMap(item)))
              .toList()
        : [];
  }

  Future<SyncStatus> syncStatus(ScannerEvent event) async =>
      SyncStatus.fromJson(
        await _request(
          '/api/v1/scanner/sync/status',
          query: {'event_id': '${event.id}'},
        ),
      );

  Future<void> logout() async {
    try {
      await _request('/api/v1/scanner/auth/logout', method: 'POST');
    } catch (_) {
      // Local session cleanup must succeed even when the server is unreachable.
    }
    await storage.clear();
  }

  String normalizeCode(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      final parts = uri.pathSegments;
      final marker = parts.indexOf('t');
      if (marker >= 0 && marker + 1 < parts.length) return parts[marker + 1];
      return uri.queryParameters['token'] ?? trimmed;
    }
    return trimmed;
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Expected JSON object');
    return Map<String, dynamic>.from(decoded);
  }

  String _requestId() {
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return 'flutter-${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  Duration? _retryAfter(String? value) {
    final seconds = int.tryParse(value ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  Map<String, dynamic> _asMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
}
