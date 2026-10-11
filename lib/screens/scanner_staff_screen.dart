import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../core/app_theme.dart';
import '../services/scanner_api.dart';
import '../services/scanner_pin.dart';
import '../services/scanner_staff_api.dart';
import '../widgets/brand.dart';

enum StaffStage { loading, activation, otp, createPin, locked, assignments, scanning, unavailable }

class ScannerStaffScreen extends StatefulWidget {
  const ScannerStaffScreen({super.key});

  @override
  State<ScannerStaffScreen> createState() => _ScannerStaffScreenState();
}

class _ScannerStaffScreenState extends State<ScannerStaffScreen> with WidgetsBindingObserver {
  final api = ScannerStaffApi();
  final pin = ScannerPin();
  final invitation = TextEditingController();
  final phone = TextEditingController();
  final code = TextEditingController();
  final deviceName = TextEditingController(text: 'Gate phone');
  final pinValue = TextEditingController();
  final confirmation = TextEditingController();
  StaffStage stage = StaffStage.loading;
  bool busy = false;
  String? error;
  String? challenge;
  String staffName = '';
  Map<String, dynamic>? session;
  List<Map<String, dynamic>> assignments = [];
  DateTime? resendAt;
  Timer? clock;
  bool backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    boot();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && stage == StaffStage.otp) setState(() {});
    });
  }

  Future<void> boot() async {
    await operation(() async {
      await api.restore();
      await api.configure();
      stage = api.credentials == null ? StaffStage.activation : StaffStage.locked;
    }, fallback: StaffStage.unavailable);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) backgrounded = false;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      backgrounded = true;
      if (api.credentials != null && (stage == StaffStage.scanning || stage == StaffStage.assignments)) {
        pinValue.clear();
        setState(() => stage = StaffStage.locked);
      }
    }
  }

  Future<void> operation(Future<void> Function() task, {StaffStage? fallback}) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await task();
    } on ApiException catch (failure) {
      error = failure.message;
      if (failure.status == 401 || failure.code == 'DEVICE_REVOKED') {
        api.sessionToken = null;
        session = null;
        stage = StaffStage.unavailable;
      } else if (fallback != null) {
        stage = fallback;
      }
    } catch (failure) {
      error = failure is StateError ? failure.message.toString() : 'This action could not be completed. Please retry.';
      if (fallback != null) stage = fallback;
    } finally {
      if (mounted) setState(() {
        busy = false;
        if (backgrounded && (stage == StaffStage.assignments || stage == StaffStage.scanning)) {
          stage = StaffStage.locked;
        }
      });
    }
  }

  Future<void> sendCode() => operation(() async {
    challenge = await api.startActivation(invitation.text, phone.text);
    resendAt = DateTime.now().add(const Duration(seconds: 60));
    code.clear();
    stage = StaffStage.otp;
  });

  Future<void> verifyCode() => operation(() async {
    await api.verifyActivation(challenge!, code.text, deviceName.text);
    await pin.resetAfterActivation();
    pinValue.clear();
    confirmation.clear();
    stage = StaffStage.createPin;
  });

  Future<void> savePin() => operation(() async {
    if (!RegExp(r'^\d{6}$').hasMatch(pinValue.text) || pinValue.text != confirmation.text) {
      throw StateError('Enter matching six-digit PINs.');
    }
    await pin.create(pinValue.text);
    pinValue.clear();
    confirmation.clear();
    await loadAssignments();
  });

  Future<void> unlock() => operation(() async {
    if (!await pin.configured) {
      stage = StaffStage.createPin;
      return;
    }
    if (!await pin.unlock(pinValue.text)) throw StateError('Incorrect scanner PIN.');
    pinValue.clear();
    await api.configure();
    // Resume checks current authority before restoring a camera session.
    await loadAssignments();
  });

  Future<void> loadAssignments() async {
    api.sessionToken = null;
    session = null;
    final profile = await api.profile();
    staffName = (profile['staff'] as Map)['name'] as String;
    assignments = (profile['events'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
    stage = StaffStage.assignments;
  }

  Future<void> start(Map<String, dynamic> assignment) => operation(() async {
    session = await api.startSession(assignment['assignment_id'] as int);
    stage = StaffStage.scanning;
  });

  Future<void> stop() => operation(() async {
    await api.endSession();
    await loadAssignments();
  });

  Future<void> signOut() => operation(() async {
    await api.logout();
    session = null;
    stage = StaffStage.activation;
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock?.cancel();
    api.client.close();
    for (final field in [invitation, phone, code, deviceName, pinValue, confirmation]) { field.dispose(); }
    super.dispose();
  }

  Widget field(TextEditingController controller, String label, {bool secret = false, bool numeric = false, int? length, List<String>? autofill}) =>
      Padding(padding: const EdgeInsets.only(bottom: 14), child: TextField(
        controller: controller, enabled: !busy, obscureText: secret,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        maxLength: length, autofillHints: autofill,
        inputFormatters: numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: label, counterText: ''),
      ));

  Widget button(String label, IconData icon, Future<void> Function() action) =>
      FilledButton.icon(onPressed: busy ? null : action, icon: Icon(icon), label: Text(label));

  @override
  Widget build(BuildContext context) {
    if (stage == StaffStage.scanning && session != null) {
      return StaffScanView(api: api, session: session!, staffName: staffName, onExit: stop,
        onAccessLost: (message) { setState(() { error = message; stage = StaffStage.unavailable; }); });
    }
    final title = switch (stage) {
      StaffStage.activation => 'Activate scanner access', StaffStage.otp => 'Verify your phone',
      StaffStage.createPin => 'Create scanner PIN', StaffStage.locked => 'Unlock scanner',
      StaffStage.assignments => 'Your assigned events', StaffStage.unavailable => 'Scanner unavailable',
      _ => 'TiketiX Scanner',
    };
    return Scaffold(appBar: AppBar(title: const Text('TiketiX Scanner'), actions: [
      if (api.credentials != null) IconButton(onPressed: busy ? null : signOut, icon: const Icon(Icons.logout), tooltip: 'Sign out'),
    ]), body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: AutofillGroup(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const TicketXBrand(), const SizedBox(height: 24),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          if (error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(error!, style: const TextStyle(color: AppColors.danger))),
          if (busy) const Padding(padding: EdgeInsets.only(bottom: 16), child: LinearProgressIndicator()),
          if (stage == StaffStage.activation) ...[
            field(invitation, 'Invitation code'), field(phone, 'Phone number', numeric: true),
            field(deviceName, 'Device name'), button('Send verification code', Icons.sms_outlined, sendCode),
          ],
          if (stage == StaffStage.otp) ...[
            Text('Enter the code sent to ${phone.text}.'), const SizedBox(height: 14),
            field(code, 'Verification code', numeric: true, length: 6, autofill: [AutofillHints.oneTimeCode]),
            button('Verify and activate', Icons.verified_user_outlined, verifyCode),
            TextButton(onPressed: busy || (resendAt != null && resendAt!.isAfter(DateTime.now())) ? null : sendCode,
              child: Text(resendAt != null && resendAt!.isAfter(DateTime.now()) ? 'Resend in ${resendAt!.difference(DateTime.now()).inSeconds + 1}s' : 'Resend code')),
            TextButton(onPressed: busy ? null : () => setState(() => stage = StaffStage.activation), child: const Text('Change invitation or phone')),
          ],
          if (stage == StaffStage.createPin) ...[
            field(pinValue, 'Six-digit scanner PIN', secret: true, numeric: true, length: 6),
            field(confirmation, 'Confirm PIN', secret: true, numeric: true, length: 6),
            button('Save PIN', Icons.lock_outline, savePin),
          ],
          if (stage == StaffStage.locked) ...[
            field(pinValue, 'Scanner PIN', secret: true, numeric: true, length: 6),
            button('Unlock', Icons.lock_open_outlined, unlock),
            TextButton(onPressed: busy ? null : () => setState(() => stage = StaffStage.activation), child: const Text('Recover with a new invitation')),
          ],
          if (stage == StaffStage.assignments) ...[
            Text(staffName, style: const TextStyle(color: AppColors.muted)), const SizedBox(height: 12),
            if (assignments.isEmpty) const Text('No active event assignments. Contact your organizer.'),
            for (final assignment in assignments) Padding(padding: const EdgeInsets.only(bottom: 12), child: ListTile(
              tileColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppColors.border)),
              title: Text((assignment['event'] as Map)['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${assignment['gate']}\n${assignment['starts_at']} → ${assignment['ends_at']}'),
              isThreeLine: true, trailing: IconButton(tooltip: assignment['can_start'] == true ? 'Start scanning' : 'Shift not active',
                onPressed: busy || assignment['can_start'] != true ? null : () => start(assignment), icon: const Icon(Icons.qr_code_scanner)),
            )),
            OutlinedButton.icon(onPressed: busy ? null : () => operation(loadAssignments), icon: const Icon(Icons.refresh), label: const Text('Refresh assignments')),
          ],
          if (stage == StaffStage.unavailable) ...[
            button('Retry connection', Icons.refresh, boot),
            TextButton(onPressed: busy ? null : () => setState(() => stage = StaffStage.activation), child: const Text('Use a new invitation')),
          ],
        ],
      ))),
    ))));
  }
}

class StaffScanView extends StatefulWidget {
  const StaffScanView({super.key, required this.api, required this.session, required this.staffName,
    required this.onExit, required this.onAccessLost});
  final ScannerStaffApi api;
  final Map<String, dynamic> session;
  final String staffName;
  final Future<void> Function() onExit;
  final void Function(String) onAccessLost;

  @override
  State<StaffScanView> createState() => _StaffScanViewState();
}

class _StaffScanViewState extends State<StaffScanView> {
  final camera = MobileScannerController(autoStart: true);
  final manual = TextEditingController();
  bool busy = false;
  String? error;
  String? pendingCode;
  String? pendingId;
  bool pendingConfirmation = false;
  String? pendingEntitlement;
  Map<String, dynamic>? result;
  String? lastCode;
  DateTime? lastScan;

  String normalize(String value) {
    final uri = Uri.tryParse(value);
    return uri?.queryParameters['token'] ?? value.trim();
  }

  Future<void> scan(String value, {bool confirm = false, String? entitlement, bool retry = false}) async {
    if (busy || !mounted) return;
    final code = normalize(value);
    if (!confirm && !retry && code == lastCode && lastScan != null && DateTime.now().difference(lastScan!) < const Duration(seconds: 3)) return;
    if (code.isEmpty) return;
    setState(() { busy = true; error = null; });
    if (!retry) {
      pendingCode = code; pendingId = const Uuid().v4();
      pendingConfirmation = confirm; pendingEntitlement = entitlement;
    }
    try {
      try { await camera.stop(); } catch (_) { /* Manual lookup does not require a running camera. */ }
      final response = await widget.api.scan(pendingId!, pendingCode!, confirm: pendingConfirmation, entitlement: pendingEntitlement);
      if (!mounted) return;
      setState(() { result = response; lastCode = code; lastScan = DateTime.now(); pendingId = null; });
      if (response['status'] == 'CHECKED_IN') await HapticFeedback.mediumImpact();
    } on ApiException catch (failure) {
      if (!mounted) return;
      if (failure.status == 401 || ['DEVICE_REVOKED', 'SCANNER_SESSION_EXPIRED'].contains(failure.code)) {
        widget.onAccessLost(failure.message);
        return;
      }
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> nextScan() async {
    setState(() { result = null; error = null; pendingId = null; pendingCode = null; });
    await camera.start();
  }

  @override
  void dispose() {
    camera.dispose();
    manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.session['event'] as Map;
    final success = result?['status'] == 'CHECKED_IN';
    final ready = result?['status'] == 'PENDING_CONFIRMATION';
    final color = success ? AppColors.success : ready ? AppColors.primary : AppColors.danger;
    return PopScope(canPop: false, child: Scaffold(
      appBar: AppBar(title: Text(event['title'] as String), actions: [
        IconButton(tooltip: 'Exit scanner', onPressed: busy ? null : widget.onExit, icon: const Icon(Icons.close)),
      ]), body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.session['gate']} · ${widget.staffName}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6), const Text('Online scanning', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          if (result == null && error == null) AspectRatio(aspectRatio: 1, child: ClipRRect(
            borderRadius: BorderRadius.circular(8), child: MobileScanner(controller: camera,
              onDetect: (capture) { final value = capture.barcodes.firstOrNull?.rawValue; if (value != null) scan(value); },
              errorBuilder: (_, failure) => Center(child: Text('Camera unavailable: ${failure.errorCode.name}. Allow camera access or enter the ticket code.')),
            ),
          )),
          if (busy) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator()),
          if (result != null) ...[
            Icon(success ? Icons.check_circle_outline : ready ? Icons.confirmation_number_outlined : Icons.cancel_outlined, size: 56, color: color),
            const SizedBox(height: 10), Text(result!['message'] as String, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color)),
            const SizedBox(height: 10), Text((result!['attendee'] as Map?)?['name']?.toString() ?? '', textAlign: TextAlign.center),
            if (ready) ...[
              const SizedBox(height: 18), FilledButton.icon(onPressed: busy ? null : () => scan(pendingCode!, confirm: true),
                icon: const Icon(Icons.check), label: const Text('Confirm entry')),
              for (final item in ((result!['event_pass'] as Map?)?['included_items'] as List? ?? []))
                if (item['staff_redemption'] == true && item['status'] == 'active') Padding(padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(onPressed: busy ? null : () => scan(pendingCode!, confirm: true, entitlement: item['id'] as String),
                    child: Text('Redeem ${item['name']}'))),
            ],
            const SizedBox(height: 12), OutlinedButton.icon(onPressed: busy ? null : nextScan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan next ticket')),
          ],
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: AppColors.danger)), const SizedBox(height: 12),
            FilledButton.icon(onPressed: busy ? null : () => scan(pendingCode!, retry: true), icon: const Icon(Icons.refresh), label: const Text('Retry same scan')),
            const SizedBox(height: 8), OutlinedButton(onPressed: busy ? null : nextScan, child: const Text('Return to scanner')),
          ],
          if (result == null && error == null) ...[
            const SizedBox(height: 14), TextField(controller: manual, decoration: const InputDecoration(labelText: 'Ticket code')),
            const SizedBox(height: 10), OutlinedButton.icon(onPressed: busy ? null : () => scan(manual.text), icon: const Icon(Icons.search), label: const Text('Validate code')),
            IconButton(tooltip: 'Toggle torch', onPressed: camera.toggleTorch, icon: const Icon(Icons.flashlight_on_outlined)),
          ],
        ],
      ))),
    ));
  }
}
