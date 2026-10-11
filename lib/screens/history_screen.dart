import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/scanner_models.dart';
import '../services/scanner_api.dart';
import '../state/app_controller.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ScanHistoryItem> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final event = widget.controller.activeEvent;
    if (event == null) {
      setState(() => loading = false);
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    if (widget.controller.previewMode) {
      setState(() {
        items = [
          ScanHistoryItem(
            id: '1',
            action: 'check_in',
            status: 'CHECKED_IN',
            severity: 'success',
            message: 'Kelvin Noel admitted at the main gate.',
            timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
            syncStatus: 'online',
          ),
          ScanHistoryItem(
            id: '2',
            action: 'validate',
            status: 'ALREADY_CHECKED_IN',
            severity: 'warning',
            message: 'Duplicate scan detected.',
            timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
            syncStatus: 'online',
          ),
        ];
        loading = false;
      });
      return;
    }
    try {
      final result = await widget.controller.api.history(event);
      if (mounted) setState(() => items = result);
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan history')),
    body: widget.controller.activeEvent == null
        ? const Center(child: Text('Select an event first.'))
        : loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : RefreshIndicator(
            onRefresh: load,
            child: ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = items[index];
                final success = item.severity == 'success';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: Icon(
                    success ? Icons.check_circle : Icons.info_outline,
                    color: success ? AppColors.success : AppColors.warning,
                  ),
                  title: Text(
                    item.status.replaceAll('_', ' '),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(item.message),
                  trailing: Text(
                    item.timestamp == null
                        ? '--'
                        : DateFormat('HH:mm\ndd MMM')
                              .format(item.timestamp!.toLocal()),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
  );
}
