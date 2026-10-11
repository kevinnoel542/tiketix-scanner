import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/scanner_staff_screen.dart';
import 'screens/shell_screen.dart';
import 'state/app_controller.dart';
import 'widgets/brand.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    title: 'TiketiX Scanner', debugShowCheckedModeBanner: false,
    theme: buildAppTheme(), home: const ScannerStaffScreen(),
  ));
}

class TicketXApp extends StatelessWidget {
  const TicketXApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TiketiX Scanner',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: AnimatedBuilder(
      animation: controller,
      builder: (_, _) => switch (controller.stage) {
        AppStage.loading => const _LoadingScreen(),
        AppStage.signedOut => LoginScreen(controller: controller),
        AppStage.deviceSetup => DeviceSetupScreen(controller: controller),
        AppStage.blocked => _AccessScreen(
          controller: controller,
          icon: Icons.phonelink_erase_rounded,
          title: 'Device blocked',
          message: 'This scanner has been blocked. Contact the event organizer before continuing.',
        ),
        AppStage.noAccess => _AccessScreen(
          controller: controller,
          icon: Icons.no_accounts_outlined,
          title: 'Scanner access unavailable',
          message:
              controller.message ??
              'This account has no assigned scanner event access.',
        ),
        AppStage.error => _AccessScreen(
          controller: controller,
          icon: Icons.cloud_off_outlined,
          title: 'Service unavailable',
          message:
              controller.message ??
              'TiketiX could not verify this scanner right now.',
          canRetry: true,
        ),
        AppStage.ready => ShellScreen(controller: controller),
      },
    ),
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _AccessScreen extends StatelessWidget {
  const _AccessScreen({
    required this.controller,
    required this.icon,
    required this.title,
    required this.message,
    this.canRetry = false,
  });

  final AppController controller;
  final IconData icon;
  final String title;
  final String message;
  final bool canRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TicketXBrand(),
                const SizedBox(height: 48),
                Icon(icon, size: 54, color: AppColors.primary),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(message, style: const TextStyle(height: 1.45)),
                const SizedBox(height: 24),
                if (canRetry)
                  FilledButton.icon(
                    onPressed: () =>
                        controller.refreshSession(showConnectionError: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry connection'),
                  ),
                OutlinedButton.icon(
                  onPressed: controller.logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
