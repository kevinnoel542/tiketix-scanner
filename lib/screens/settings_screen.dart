import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/scanner_api.dart';
import '../state/app_controller.dart';
import '../widgets/brand.dart';
import 'history_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onSignedOut,
  });

  final AppController controller;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    final event = controller.activeEvent;
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const Padding(
            padding: EdgeInsets.all(18),
            child: SectionHeader(
              eyebrow: 'Device control',
              title: 'Settings',
              subtitle: 'Account, assignment, feedback and diagnostics.',
            ),
          ),
          Container(
            color: AppColors.graphite,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 25,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.userName ?? 'Scanner staff',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        controller.email ?? 'Not signed in',
                        style: const TextStyle(color: Color(0xFFAFC0B9)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.verified_user, color: Color(0xFF63E0B0)),
              ],
            ),
          ),
          _Section(
            title: 'Gate assignment',
            children: [
              _Info(
                icon: Icons.event,
                label: 'Active event',
                value: event == null
                    ? 'No event selected'
                    : '${event.title} (#${event.id})',
              ),
              FutureBuilder<String?>(
                future: controller.storage.getDeviceName(),
                builder: (_, snapshot) => _Info(
                  icon: Icons.smartphone,
                  label: 'Approved device',
                  value: snapshot.data ?? 'This phone',
                ),
              ),
            ],
          ),
          _Section(
            title: 'Scan feedback',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.volume_up_outlined),
                title: const Text('Result sounds'),
                value: controller.soundEnabled,
                onChanged: controller.setSoundEnabled,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.vibration),
                title: const Text('Haptic feedback'),
                value: controller.hapticsEnabled,
                onChanged: controller.setHapticsEnabled,
              ),
            ],
          ),
          _Section(
            title: 'Operations',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history),
                title: const Text('Scan history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HistoryScreen(controller: controller),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('Connection diagnostics'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDiagnostics(context),
              ),
              const _Info(
                icon: Icons.wifi_off,
                label: 'Offline admission',
                value: 'Disabled until secure manifests are available',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: OutlinedButton.icon(
              onPressed: () => confirmSignOut(context),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out and reset device'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> showDiagnostics(BuildContext context) async {
    if (controller.previewMode) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Connection diagnostics'),
          content: const Text(
            'Mode: Local preview\nAPI: Not connected\nDevice: Preview approved\nApp version: 1.0.0',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    String status;
    try {
      final health = await controller.api.health();
      status = health['status']?.toString() ?? 'Unknown response';
    } on ApiException catch (exception) {
      status = exception.message;
    }
    if (!context.mounted) return;
    Navigator.pop(context);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Connection diagnostics'),
        content: Text(
          'API: $status\n'
          'Device: ${controller.deviceStatus}\n'
          'Event: ${controller.activeEvent?.id ?? 'not selected'}\n'
          'App version: 1.0.0',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> confirmSignOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out this scanner?'),
        content: const Text('This phone may need device approval again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await controller.logout();
      onSignedOut();
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 22, 18, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 7),
        ...children,
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    ),
  );
}
