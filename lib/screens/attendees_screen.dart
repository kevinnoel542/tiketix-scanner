import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/scanner_models.dart';
import '../services/scanner_api.dart';
import '../state/app_controller.dart';
import '../widgets/brand.dart';

class AttendeesScreen extends StatefulWidget {
  const AttendeesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AttendeesScreen> createState() => _AttendeesScreenState();
}

class _AttendeesScreenState extends State<AttendeesScreen> {
  final search = TextEditingController();
  List<Attendee> items = [];
  bool loading = false;
  bool loadingMore = false;
  String? error;
  Timer? debounce;
  int page = 1;
  int lastPage = 1;
  int total = 0;
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
      items = [];
      page = 1;
      if (id != null) load();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load({int requestedPage = 1, bool append = false}) async {
    final event = widget.controller.activeEvent;
    if (event == null || loading || loadingMore) return;
    setState(() {
      append ? loadingMore = true : loading = true;
      error = null;
    });
    if (widget.controller.previewMode) {
      final demo = [
        const Attendee(
          id: '1',
          name: 'Kelvin Noel',
          ticketId: '019fa79c-10b2-734d-a903-526def753150',
          token: 'tkt_preview_kelvin',
          role: 'VIP',
          bookingCode: 'TX-KUKU-1042',
          checkedIn: true,
        ),
        const Attendee(
          id: '2',
          name: 'Amina Yusuf',
          ticketId: '019fa79c-10b2-734d-a903-526def753151',
          token: 'tkt_preview_amina',
          role: 'General admission',
          bookingCode: 'TX-KUKU-1088',
        ),
        const Attendee(
          id: '3',
          name: 'Neema Joseph',
          ticketId: '019fa79c-10b2-734d-a903-526def753152',
          token: 'tkt_preview_neema',
          role: 'VIP',
          bookingCode: 'TX-KUKU-1120',
        ),
      ];
      final query = search.text.trim().toLowerCase();
      setState(() {
        items = query.isEmpty
            ? demo
            : demo
                  .where(
                    (item) =>
                        item.name.toLowerCase().contains(query) ||
                        (item.bookingCode?.toLowerCase().contains(query) ??
                            false),
                  )
                  .toList();
        total = items.length;
        page = 1;
        lastPage = 1;
        loading = false;
        loadingMore = false;
      });
      return;
    }
    try {
      final query = search.text.trim();
      if (query.isNotEmpty) {
        final results = await widget.controller.api.lookup(query, event);
        if (mounted) {
          setState(() {
            items = results;
            page = 1;
            lastPage = 1;
            total = results.length;
          });
        }
      } else {
        final result = await widget.controller.api.attendees(
          event,
          page: requestedPage,
        );
        if (mounted) {
          setState(() {
            items = append ? [...items, ...result.items] : result.items;
            page = result.page;
            lastPage = result.lastPage;
            total = result.total;
          });
        }
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  void onSearch(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), load);
  }

  Future<void> validateAttendee(Attendee attendee) async {
    final event = widget.controller.activeEvent;
    if (event == null || attendee.scanCode.isEmpty) return;
    setState(() => loading = true);
    try {
      final result = widget.controller.previewMode
          ? ScanResult(
              status: attendee.checkedIn
                  ? 'ALREADY_CHECKED_IN'
                  : 'PENDING_CONFIRMATION',
              severity: attendee.checkedIn ? 'warning' : 'info',
              message: attendee.checkedIn
                  ? 'This ticket is already checked in.'
                  : 'Ticket valid. Confirm check-in.',
              attendee: attendee,
            )
          : await widget.controller.api.validate(attendee.scanCode, event);
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            result.canConfirm ? Icons.verified_user : Icons.info_outline,
            color: result.canConfirm ? AppColors.primary : AppColors.warning,
          ),
          title: Text(result.status.replaceAll('_', ' ')),
          content: Text('${attendee.name}\n\n${result.message}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
            if (result.canConfirm)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm admission'),
              ),
          ],
        ),
      );
      if (confirm == true) {
        final checked = widget.controller.previewMode
            ? ScanResult(
                status: 'CHECKED_IN',
                severity: 'success',
                message: 'Preview admission recorded.',
                attendee: attendee,
              )
            : await widget.controller.api.checkIn(attendee.scanCode, event);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(checked.message)));
          await load();
        }
      }
    } on ApiException catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(exception.message)));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.controller.activeEvent;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: SectionHeader(
              eyebrow: 'Live roster',
              title: 'Attendees',
              subtitle: event == null
                  ? 'Select an event to view its roster.'
                  : '${event.title} (#${event.id}) - $total records',
            ),
          ),
          if (event == null)
            const Expanded(
              child: Center(child: Text('No active event selected.')),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                controller: search,
                onChanged: onSearch,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Name, phone, booking or ticket',
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            search.clear();
                            load();
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (loading)
              const LinearProgressIndicator()
            else if (error != null)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  error!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: items.length + (page < lastPage ? 1 : 0),
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      if (index == items.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: OutlinedButton.icon(
                            onPressed: loadingMore
                                ? null
                                : () => load(
                                    requestedPage: page + 1,
                                    append: true,
                                  ),
                            icon: loadingMore
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more),
                            label: const Text('Load more'),
                          ),
                        );
                      }
                      final item = items[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 7),
                        onTap: () => validateAttendee(item),
                        leading: CircleAvatar(
                          backgroundColor: item.checkedIn
                              ? AppColors.softGreen
                              : const Color(0xFFE9ECEA),
                          child: Text(
                            item.name.isEmpty
                                ? '?'
                                : item.name[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          item.bookingCode ?? item.role ?? item.ticketId,
                        ),
                        trailing: Icon(
                          item.checkedIn
                              ? Icons.check_circle
                              : Icons.chevron_right,
                          color: item.checkedIn
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
