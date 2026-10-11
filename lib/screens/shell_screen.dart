import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../state/app_controller.dart';
import 'attendees_screen.dart';
import 'events_screen.dart';
import 'progress_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final screens = [
      ScanScreen(controller: widget.controller, isActive: index == 0),
      EventsScreen(
        controller: widget.controller,
        onSelected: () => setState(() => index = 0),
      ),
      AttendeesScreen(controller: widget.controller),
      ProgressScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller, onSignedOut: () {}),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: screens),
      bottomNavigationBar: NavigationBar(
        height: 76,
        backgroundColor: AppColors.graphite,
        indicatorColor: AppColors.primary,
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xFF9AA59F),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner, color: Colors.white70),
            selectedIcon: Icon(Icons.qr_code_scanner, color: Colors.white),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.event, color: Colors.white70),
            selectedIcon: Icon(Icons.event, color: Colors.white),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups, color: Colors.white70),
            selectedIcon: Icon(Icons.groups, color: Colors.white),
            label: 'Attendees',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart, color: Colors.white70),
            selectedIcon: Icon(Icons.bar_chart, color: Colors.white),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings, color: Colors.white70),
            selectedIcon: Icon(Icons.settings, color: Colors.white),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
