import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../core/app_theme.dart';
import '../services/scanner_api.dart';
import '../services/scanner_pin.dart';
import '../services/scanner_staff_api.dart';
import '../services/scanner_offline.dart';
import 'scanner_session_details.dart';
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
  late final offline = ScannerOffline(api);
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
      await offline.restore();
      await api.configure();
      offline.anchorServerTime();
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
        Navigator.of(context).popUntil((route) => route.isFirst);
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
      if (fallback != null) { stage = fallback; }
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
    offline.anchorServerTime();
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
    if (offline.pendingCount > 0) throw StateError('Sync saved scans before signing out. Your scans have not been deleted.');
    await api.logout();
    session = null;
    stage = StaffStage.activation;
  });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock?.cancel();
    api.client.close();
    unawaited(offline.serial(offline.store.close));
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
        offline: offline,
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
          if (offline.pendingCount > 0 && stage == StaffStage.unavailable) OutlinedButton.icon(
            onPressed: busy ? null : () => operation(offline.sync), icon: const Icon(Icons.cloud_upload_outlined), label: Text('Recover ${offline.pendingCount} saved scans')),
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
            TextButton(onPressed: busy || offline.pendingCount > 0 ? null : () => setState(() => stage = StaffStage.activation), child: const Text('Recover with a new invitation')),
          ],
          if (stage == StaffStage.assignments) ...[
            if (offline.pendingCount > 0) OutlinedButton.icon(onPressed: busy ? null : () => operation(offline.sync),
              icon: const Icon(Icons.cloud_upload_outlined), label: Text('Sync ${offline.pendingCount} offline scans')),
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
            TextButton(onPressed: busy || offline.pendingCount > 0 ? null : () => setState(() => stage = StaffStage.activation), child: const Text('Use a new invitation')),
          ],
        ],
      ))),
    ))));
  }
}

class StaffScanView extends StatefulWidget {
  const StaffScanView({super.key, required this.api, required this.session, required this.staffName,
    required this.onExit, required this.onAccessLost, required this.offline});
  final ScannerStaffApi api;
  final Map<String, dynamic> session;
  final String staffName;
  final Future<void> Function() onExit;
  final void Function(String) onAccessLost;
  final ScannerOffline offline;

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
  bool offlineMode = false;
  Timer? heartbeatTimer;

  @override
  void initState() {
    super.initState();
    heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (busy) return;
      try {
        if (widget.offline.pendingCount > 0) await widget.offline.sync();
        await widget.api.heartbeat(widget.offline.pendingCount, offlineMode);
        if (mounted) setState(() {});
      } on ApiException catch (failure) {
        if (mounted && (failure.status == 401 || ['DEVICE_REVOKED', 'SCANNER_SESSION_EXPIRED'].contains(failure.code))) widget.onAccessLost(failure.message);
      } catch (_) { /* Connectivity loss does not grant offline permission. */ }
    });
  }

  Future<void> activity() async {
    if (busy || offlineMode) return;
    try { await camera.stop(); } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScannerSessionDetails(
      api: widget.api, supervisor: widget.session['role'] == 'gate_supervisor')));
    if (mounted && result == null && error == null) await resumeCamera();
  }

  Future<void> resumeCamera() async {
    try { await camera.start(); } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camera unavailable. Enter a ticket code instead.')));
    }
  }

  Future<void> offlineAction(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) {
        final reviews = widget.offline.results.where((result) => result['status'] == 'REVIEW_REQUIRED').length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reviews > 0
          ? '$reviews saved scans require organizer review. Sync receipts are available below.' : 'Offline data updated.')));
      }
    } catch (failure) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure is ApiException ? failure.message : failure is StateError ? failure.message.toString() : 'Offline action failed. Your saved scans have been kept.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggleOffline(bool enabled) async {
    if (busy) return;
    if (enabled) {
      final package = widget.offline.packageFor(widget.session['assignment_id'] as int);
      if (package == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download this event package while connected first.')));
        return;
      }
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Start offline scanning?'),
        content: Text('${package['event_name']}\n${package['gate']}\n\nEntry only. Included items require online scanning. Different offline phones cannot detect each other’s duplicate entries. Access expires at ${package['expires_at']}.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay online')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start offline'))],
      ));
      if (confirmed != true || !mounted) return;
    }
    setState(() => offlineMode = enabled);
  }

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
      final response = offlineMode
        ? await widget.offline.scan(widget.session['assignment_id'] as int, pendingCode!, confirm: pendingConfirmation)
        : await widget.api.scan(pendingId!, pendingCode!, confirm: pendingConfirmation, entitlement: pendingEntitlement);
      if (!mounted) return;
      setState(() { result = response; lastCode = code; lastScan = DateTime.now(); pendingId = null; });
      if (['CHECKED_IN', 'OFFLINE_RECORDED'].contains(response['status'])) await HapticFeedback.mediumImpact();
    } on ApiException catch (failure) {
      if (!mounted) return;
      if (failure.status == 401 || ['DEVICE_REVOKED', 'SCANNER_SESSION_EXPIRED'].contains(failure.code)) {
        widget.onAccessLost(failure.message);
        return;
      }
      if (mounted) setState(() => error = failure.message);
    } catch (failure) {
      if (mounted) setState(() => error = failure is StateError ? failure.message.toString() : 'Scan could not be completed. Please retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> nextScan() async {
    if (pendingId != null && pendingConfirmation && !offlineMode) {
      final leave = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Admission is not confirmed'), content: const Text('The server may have received this scan. Retry the same scan to check its result before admitting this guest.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep scan')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Return without admitting'))],
      ));
      if (leave != true || !mounted) return;
    }
    setState(() { result = null; error = null; pendingId = null; pendingCode = null; });
    await resumeCamera();
  }

  @override
  void dispose() {
    heartbeatTimer?.cancel();
    camera.dispose();
    manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.session['event'] as Map;
    final success = ['CHECKED_IN', 'OFFLINE_RECORDED'].contains(result?['status']);
    final ready = result?['status'] == 'PENDING_CONFIRMATION';
    final color = success ? AppColors.success : ready ? AppColors.primary : AppColors.danger;
    return PopScope(canPop: false, child: Scaffold(
      appBar: AppBar(title: Text(event['title'] as String), actions: [
        IconButton(tooltip: 'Event activity', onPressed: busy || offlineMode ? null : activity, icon: const Icon(Icons.people_outline)),
        IconButton(tooltip: 'Exit scanner', onPressed: busy ? null : widget.onExit, icon: const Icon(Icons.close)),
      ]), body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.session['gate']} · ${widget.staffName}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6), Text(offlineMode ? 'Offline · ${widget.offline.pendingCount} scans awaiting sync' : 'Online scanning',
            style: TextStyle(color: offlineMode ? AppColors.warning : AppColors.muted)),
          if (widget.api.configuration['offline_enabled'] == true) ...[
            SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Offline entry'), value: offlineMode,
              onChanged: busy || result != null || error != null ? null : toggleOffline),
            Row(children: [
              IconButton(tooltip: 'Download offline package', onPressed: busy || offlineMode ? null : () => offlineAction(widget.offline.download), icon: const Icon(Icons.download_outlined)),
              IconButton(tooltip: 'Sync saved scans', onPressed: busy || widget.offline.pendingCount == 0 ? null : () => offlineAction(widget.offline.sync), icon: const Icon(Icons.cloud_upload_outlined)),
              if (widget.offline.pendingCount > 0) Text('${widget.offline.pendingCount} awaiting sync'),
            ]),
            if (widget.offline.results.isNotEmpty) ExpansionTile(title: const Text('Offline sync receipts'), children: [
              for (final receipt in widget.offline.results.take(20)) ListTile(
                leading: Icon(receipt['status'] == 'CHECKED_IN' ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                  color: receipt['status'] == 'CHECKED_IN' ? AppColors.success : AppColors.warning),
                title: Text(receipt['message'] as String), subtitle: Text(receipt['ticket_id']?.toString() ?? '')),
            ]),
          ],
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
                icon: const Icon(Icons.check), label: Text(result!['item_type'] == 'add_on' ? 'Confirm redemption' : 'Confirm entry')),
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
            IconButton(tooltip: 'Toggle torch', onPressed: busy ? null : () async {
              try { await camera.toggleTorch(); } catch (_) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Torch is unavailable on this device.')));
              }
            }, icon: const Icon(Icons.flashlight_on_outlined)),
          ],
        ],
      ))),
    ));
  }
}
