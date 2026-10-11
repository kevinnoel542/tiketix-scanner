import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/scanner_api.dart';
import '../state/app_controller.dart';
import '../widgets/brand.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const TicketXBrand(),
                const SizedBox(height: 54),
                const Text(
                  'Gate access',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 38,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Work email',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 7),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.alternate_email),
                          hintText: 'name@company.com',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Password',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 7),
                      TextField(
                        controller: password,
                        obscureText: obscure,
                        onSubmitted: (_) =>
                            widget.controller.enterPreviewMode(),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline),
                          hintText: 'Enter password',
                          suffixIcon: IconButton(
                            tooltip: obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: widget.controller.enterPreviewMode,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Sign in to scanner'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.phonelink_lock,
                      color: AppColors.primary,
                      size: 19,
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'This device will be registered before it can scan tickets.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  final name = TextEditingController(text: 'Gate scanner');
  bool busy = false;
  String? message;

  Future<void> register() async {
    if (name.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.controller.registerDevice(name.text.trim());
      if (mounted && widget.controller.stage == AppStage.deviceSetup) {
        setState(() => message = 'Approval requested.');
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => message = exception.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> check() async {
    setState(() => busy = true);
    try {
      await widget.controller.refreshSession(showConnectionError: true);
      if (mounted && widget.controller.stage == AppStage.deviceSetup) {
        setState(() => message = 'Approval is still pending.');
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => message = exception.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const TicketXBrand(),
                const SizedBox(height: 48),
                const Icon(
                  Icons.smartphone,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Register scanner',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: name,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(hintText: 'Gate A phone'),
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(message!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: busy ? null : register,
                  child: const Text('Register'),
                ),
                TextButton(
                  onPressed: busy ? null : check,
                  child: const Text('Check status'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
