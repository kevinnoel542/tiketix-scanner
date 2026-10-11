import 'package:flutter/foundation.dart';

import '../models/scanner_models.dart';
import '../services/scanner_api.dart';
import '../services/storage_service.dart';

enum AppStage {
  loading,
  signedOut,
  deviceSetup,
  blocked,
  noAccess,
  ready,
  error,
}

class AppController extends ChangeNotifier {
  AppController() : storage = StorageService() {
    api = ScannerApi(storage, onSessionExpired: _expireSession);
  }

  final StorageService storage;
  late final ScannerApi api;

  AppStage stage = AppStage.loading;
  String? email;
  String? userName;
  String? message;
  String deviceStatus = 'unregistered';
  ScannerEvent? activeEvent;
  bool soundEnabled = true;
  bool hapticsEnabled = true;
  bool previewMode = false;

  bool get signedIn => stage != AppStage.signedOut && stage != AppStage.loading;

  Future<void> initialize() async {
    stage = AppStage.loading;
    notifyListeners();
    soundEnabled = await storage.getSoundEnabled();
    hapticsEnabled = await storage.getHapticsEnabled();
    await storage.clearSession();
    email = null;
    userName = null;
    activeEvent = null;
    deviceStatus = 'unregistered';
    previewMode = false;
    message = null;
    stage = AppStage.signedOut;
    notifyListeners();
  }

  Future<void> login(String value, String password) async {
    await api.login(value, password);
    email = value;
    await refreshSession(showConnectionError: true);
  }

  void enterPreviewMode() {
    previewMode = true;
    email = 'preview@tiketix.local';
    userName = 'Preview operator';
    deviceStatus = 'approved';
    activeEvent = ScannerEvent(
      id: 12,
      title: 'Kuku Festival',
      venue: 'City Mall',
      city: 'Dar es Salaam',
      status: 'published',
      startAt: DateTime.now().add(const Duration(days: 2)),
      total: 1000,
      checkedIn: 240,
      pending: 760,
    );
    stage = AppStage.ready;
    notifyListeners();
  }

  Future<void> refreshSession({bool showConnectionError = false}) async {
    try {
      final session = await api.session();
      email = session.email ?? email;
      userName = session.name;
      deviceStatus = session.deviceStatus;
      message = null;
      if (!session.eventAccess) {
        stage = AppStage.noAccess;
      } else if (session.deviceStatus == 'blocked') {
        stage = AppStage.blocked;
      } else if (session.deviceStatus != 'approved') {
        stage = AppStage.deviceSetup;
      } else if (!session.permissions.contains('scan.validate')) {
        message = 'Your account does not have ticket validation permission.';
        stage = AppStage.noAccess;
      } else {
        stage = AppStage.ready;
      }
    } on ApiException catch (error) {
      if (error.isAuthenticationFailure || error.code == 'AUTH_REQUIRED') {
        await _expireSession();
        return;
      }
      if (showConnectionError) {
        message = error.message;
        stage = AppStage.error;
      }
    }
    notifyListeners();
  }

  Future<void> registerDevice(String name) async {
    deviceStatus = await api.registerDevice(name);
    await refreshSession(showConnectionError: true);
  }

  Future<void> selectEvent(ScannerEvent event) async {
    activeEvent = event;
    await storage.saveActiveEvent(event);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    soundEnabled = value;
    await storage.setSoundEnabled(value);
    notifyListeners();
  }

  Future<void> setHapticsEnabled(bool value) async {
    hapticsEnabled = value;
    await storage.setHapticsEnabled(value);
    notifyListeners();
  }

  Future<void> logout() async {
    if (!previewMode) await api.logout();
    email = null;
    userName = null;
    activeEvent = null;
    deviceStatus = 'unregistered';
    previewMode = false;
    stage = AppStage.signedOut;
    notifyListeners();
  }

  Future<void> _expireSession() async {
    await storage.clearSession();
    email = null;
    userName = null;
    activeEvent = null;
    message = 'Your session expired. Sign in again.';
    stage = AppStage.signedOut;
    notifyListeners();
  }
}
