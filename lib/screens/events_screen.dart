import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/scanner_models.dart';
import '../services/scanner_api.dart';
import '../state/app_controller.dart';
import '../widgets/brand.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.controller,
    required this.onSelected,
  });
  final AppController controller;
  final VoidCallback onSelected;
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<ScannerEvent> items = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    if (widget.controller.previewMode) {
      setState(() {
        items = [widget.controller.activeEvent!];
        loading = false;
      });
      return;
    }
    try {
      final data = await widget.controller.api.events();
      if (mounted) setState(() => items = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: SectionHeader(
            eyebrow: 'Gate assignment',
            title: 'Events',
            subtitle: 'Choose an assigned event for this scanner.',
            trailing: IconButton(
              onPressed: load,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        if (loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (error != null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = items[index];
                  final active = item.id == widget.controller.activeEvent?.id;
                  final date = item.startAt == null
                      ? '--'
                      : DateFormat('dd\nMMM').format(item.startAt!);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    leading: Container(
                      width: 54,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.graphite
                            : const Color(0xFFE6EBE8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        date.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: active ? Colors.white : AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      [item.venue, item.city].whereType<String>().join(', '),
                    ),
                    trailing: active
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => showDetails(item),
                  );
                },
              ),
            ),
          ),
      ],
    ),
  );
  Future<void> showDetails(ScannerEvent event) async {
    ScannerEvent details = event;
    if (!widget.controller.previewMode) {
      try {
        details = await widget.controller.api.event(event.id);
      } on ApiException catch (exception) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(exception.message)));
        }
        return;
      }
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                details.title,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [details.venue, details.city].whereType<String>().join(', '),
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _Metric('Issued', details.total),
                  _Metric('Inside', details.checkedIn),
                  _Metric('Waiting', details.pending),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Use this event'),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == true) {
      await widget.controller.selectEvent(details);
      if (mounted) setState(() {});
      widget.onSelected();
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    ),
  );
}
