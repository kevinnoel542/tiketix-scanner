import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_theme.dart';
import '../models/scanner_models.dart';
import '../services/scanner_api.dart';
import '../state/app_controller.dart';
import '../widgets/brand.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.controller,
    required this.isActive,
  });

  final AppController controller;
  final bool isActive;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  final manual = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      widget.isActive ? _startCamera() : scanner.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive && !busy) {
      _startCamera();
    } else if (state != AppLifecycleState.resumed) {
      scanner.stop();
    }
  }

  Future<void> _startCamera() async {
    try {
      await scanner.start();
    } catch (_) {
      // The scanner widget reports camera failures in its own error state.
    }
  }

  Future<void> process(String value) async {
    final event = widget.controller.activeEvent;
    if (busy || value.trim().isEmpty || event == null) return;

    setState(() => busy = true);
    await scanner.stop();
    try {
      var result = widget.controller.previewMode
          ? _previewValidation()
          : await widget.controller.api.validate(value, event);
      await _feedback(result);

      while (mounted) {
        final action = await _showResult(result);
        if (action == null) break;
        result = widget.controller.previewMode
            ? _previewCheckIn(action)
            : await widget.controller.api.checkIn(
                value,
                event,
                entitlementId: action == _admissionAction ? null : action,
              );
        await _feedback(result);
      }
    } on ApiException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (widget.isActive) await _startCamera();
      }
    }
  }

  ScanResult _previewValidation() => const ScanResult(
    status: 'PENDING_CONFIRMATION',
    severity: 'info',
    message: 'Preview ticket valid. Confirm the next action.',
    attendee: Attendee(
      id: 'preview-1',
      name: 'Amina Yusuf',
      ticketId: 'preview-ticket',
      role: 'VIP',
    ),
    eventPass: EventPass(
      admission: Entitlement(
        name: 'VIP admission',
        status: 'active',
        isAdmission: true,
      ),
      items: [
        Entitlement(
          id: 'parking-1',
          name: 'Secure parking',
          status: 'active',
          category: 'parking',
          staffRedemption: true,
        ),
      ],
    ),
  );

  ScanResult _previewCheckIn(String action) => ScanResult(
    status: 'CHECKED_IN',
    severity: 'success',
    message: action == _admissionAction
        ? 'Preview admission recorded.'
        : 'Preview add-on redeemed.',
    attendee: const Attendee(
      id: 'preview-1',
      name: 'Amina Yusuf',
      ticketId: 'preview-ticket',
      role: 'VIP',
    ),
    checkedInAt: DateTime.now().toIso8601String(),
  );

  Future<String?> _showResult(ScanResult result) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.page,
        builder: (_) => _ResultSheet(result: result),
      );

  Future<void> _feedback(ScanResult result) async {
    if (widget.controller.hapticsEnabled) {
      if (result.isSuccess) {
        await HapticFeedback.heavyImpact();
      } else if (result.severity == 'warning') {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.selectionClick();
      }
    }
    if (widget.controller.soundEnabled) {
      await SystemSound.play(
        result.severity == 'error'
            ? SystemSoundType.alert
            : SystemSoundType.click,
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scanner.dispose();
    manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.controller.activeEvent;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SectionHeader(
            eyebrow: 'Gate operations',
            title: 'Scan tickets',
            subtitle: event == null
                ? 'Select an event before scanning.'
                : 'Validate first. Admit only after review.',
          ),
          const SizedBox(height: 15),
          if (event == null)
            const _Notice(
              icon: Icons.event_busy,
              title: 'No active event',
              text: 'Open Events and assign this scanner to an event.',
            )
          else ...[
            _EventBand(event: event),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: .82,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: scanner,
                      onDetect: (capture) {
                        final value = capture.barcodes.firstOrNull?.rawValue;
                        if (value != null) process(value);
                      },
                      errorBuilder: (_, error) => ColoredBox(
                        color: AppColors.graphite,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              error.errorDetails?.message ?? 'Camera unavailable. Check camera permission.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 235,
                        height: 235,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton.filled(
                        tooltip: 'Toggle torch',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                        onPressed: scanner.toggleTorch,
                        icon: const Icon(Icons.flash_on),
                      ),
                    ),
                    if (busy)
                      const ColoredBox(
                        color: Color(0x99000000),
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter code manually',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: manual,
                    onSubmitted: process,
                    decoration: const InputDecoration(
                      hintText: 'Ticket token or UUID',
                      prefixIcon: Icon(Icons.keyboard),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Validate ticket',
                  onPressed: busy ? null : () => process(manual.text),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

const _admissionAction = '__admission__';

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({required this.result});

  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final color = result.isSuccess
        ? AppColors.success
        : result.severity == 'error'
        ? AppColors.danger
        : result.severity == 'warning'
        ? AppColors.warning
        : AppColors.primary;
    final items = result.eventPass?.items ?? const <Entitlement>[];

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Icon(
              result.isSuccess
                  ? Icons.check_circle
                  : result.severity == 'error'
                  ? Icons.cancel
                  : Icons.verified_user,
              color: color,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              result.status.replaceAll('_', ' '),
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(result.message, style: const TextStyle(height: 1.4)),
            if (result.checkedInAt != null) ...[
              const SizedBox(height: 5),
              Text(
                'Recorded ${result.checkedInAt}',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
            if (result.attendee != null) ...[
              const SizedBox(height: 18),
              _GuestPanel(attendee: result.attendee!),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'INCLUDED ITEMS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              ...items.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.redeemedAt == null
                        ? Icons.redeem_outlined
                        : Icons.check_circle,
                    color: item.redeemedAt == null
                        ? AppColors.primary
                        : AppColors.success,
                  ),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    item.redeemedAt == null ? item.status : 'Redeemed',
                  ),
                  trailing: item.canRedeem && item.id != null
                      ? TextButton(
                          onPressed: () => Navigator.pop(context, item.id),
                          child: const Text('Redeem'),
                        )
                      : null,
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (result.canConfirm)
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, _admissionAction),
                icon: const Icon(Icons.login),
                label: const Text('Confirm admission'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Close and scan next'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestPanel extends StatelessWidget {
  const _GuestPanel({required this.attendee});

  final Attendee attendee;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GUEST IDENTITY',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          attendee.name,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        if (attendee.company != null) Text(attendee.company!),
        if (attendee.role != null) Text(attendee.role!),
        if (attendee.email != null)
          Text(attendee.email!, style: const TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}

class _EventBand extends StatelessWidget {
  const _EventBand({required this.event});

  final ScannerEvent event;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        const Icon(Icons.confirmation_number, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SCANNING FOR',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${event.title} (#${event.id})',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                [event.venue, event.city].whereType<String>().join(', '),
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    color: Colors.white,
    child: Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 34),
        const SizedBox(height: 9),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}
