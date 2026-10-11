import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scanner_models.dart';

class StorageService {
  static const _tokenKey = 'scanner.token';
  static const _emailKey = 'scanner.email';
  static const _deviceIdKey = 'scanner.deviceId';
  static const _deviceNameKey = 'scanner.deviceName';
  static const _eventKey = 'scanner.activeEvent';
  static const _soundKey = 'scanner.sound';
  static const _hapticsKey = 'scanner.haptics';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String?> get token => _secure.read(key: _tokenKey);
  Future<void> saveSession(String token, String email) async {
    await _secure.write(key: _tokenKey, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email);
  }

  Future<String?> getEmail() async =>
      (await SharedPreferences.getInstance()).getString(_emailKey);
  Future<String?> getDeviceName() async =>
      (await SharedPreferences.getInstance()).getString(_deviceNameKey);
  Future<void> saveDeviceName(String value) async =>
      (await SharedPreferences.getInstance()).setString(_deviceNameKey, value);

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null) return existing;
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final value = 'flutter-${DateTime.now().millisecondsSinceEpoch}-$random';
    await prefs.setString(_deviceIdKey, value);
    return value;
  }

  Future<ScannerEvent?> getActiveEvent() async {
    final raw = (await SharedPreferences.getInstance()).getString(_eventKey);
    if (raw == null) return null;
    try {
      return ScannerEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActiveEvent(ScannerEvent event) async =>
      (await SharedPreferences.getInstance()).setString(
        _eventKey,
        jsonEncode(event.toJson()),
      );

  Future<bool> getSoundEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_soundKey) ?? true;

  Future<bool> getHapticsEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_hapticsKey) ?? true;

  Future<void> setSoundEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_soundKey, value);

  Future<void> setHapticsEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_hapticsKey, value);

  Future<void> clearSession() async {
    await _secure.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_eventKey);
  }

  Future<void> clear() async {
    await _secure.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_deviceNameKey);
    await prefs.remove(_eventKey);
  }
}
