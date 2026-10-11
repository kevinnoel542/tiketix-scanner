import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/scanner_models.dart';
import '../services/scanner_api.dart';
import '../state/app_controller.dart';
import '../widgets/brand.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  EventStats? stats;
  SyncStatus? sync;
  bool loading = false;
  String? error;
  int? loadedEventId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
    _controllerChanged();
  }

  void _controllerChanged() {
    final id = widget.controller.activeEvent?.id;
    if (id != loadedEventId) {
      loadedEventId = id;
      stats = null;
      sync = null;
      if (id != null) load();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  Future<void> load() async {
    final event = widget.controller.activeEvent;
    if (event == null || loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    if (widget.controller.previewMode) {
      setState(() {
        stats = const EventStats(
          total: 1000,
          checkedIn: 240,
          pending: 760,
          duplicates: 9,
          invalidAttempts: 4,
        );
        sync = const SyncStatus();
        loading = false;
      });
      return;
    }
    try {
      final results = await Future.wait<Object>([
        widget.controller.api.stats(event),
        widget.controller.api.syncStatus(event),
      ]);
      if (mounted) {
        setState(() {
          stats = results[0] as EventStats;
          sync = results[1] as SyncStatus;
        });
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.controller.activeEvent;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            SectionHeader(
              eyebrow: 'Live operations',
              title: 'Progress',
              subtitle: event == null
                  ? 'Select an event to view live progress.'
                  : '${event.title} (#${event.id})',
              trailing: IconButton(
                tooltip: 'Refresh progress',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 24),
            if (loading && stats == null)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              _MessagePanel(message: error!, onRetry: load)
            else if (event == null)
              const _MessagePanel(message: 'No event selected.')
            else if (stats != null) ...[
              _ProgressBand(stats: stats!),
              const SizedBox(height: 16),
              _MetricRow(
                label: 'Checked in',
                value: '${stats!.checkedIn}',
                icon: Icons.how_to_reg_rounded,
              ),
              _MetricRow(
                label: 'Remaining',
                value: '${stats!.pending}',
                icon: Icons.schedule_rounded,
              ),
              _MetricRow(
                label: 'Duplicate attempts',
                value: '${stats!.duplicates}',
                icon: Icons.content_copy_rounded,
              ),
              _MetricRow(
                label: 'Invalid attempts',
                value: '${stats!.invalidAttempts}',
                icon: Icons.gpp_bad_outlined,
              ),
              const SizedBox(height: 22),
              const Text(
                'Synchronization',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              _MetricRow(
                label: 'Server pending',
                value: '${sync?.pendingCount ?? 0}',
                icon: Icons.cloud_upload_outlined,
              ),
              _MetricRow(
                label: 'Failed operations',
                value: '${sync?.failedCount ?? 0}',
                icon: Icons.cloud_off_outlined,
              ),
              const Text(
                'Offline admission is disabled; no local queue is created.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressBand extends StatelessWidget {
  const _ProgressBand({required this.stats});

  final EventStats stats;

  @override
  Widget build(BuildContext context) {
    final progress = stats.total == 0 ? 0.0 : stats.checkedIn / stats.total;
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${(progress * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${stats.checkedIn} of ${stats.total} attendees admitted',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 10,
            backgroundColor: Colors.white24,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ],
    ),
  );
}
