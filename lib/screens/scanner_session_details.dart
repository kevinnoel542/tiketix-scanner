import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../services/scanner_api.dart';
import '../services/scanner_staff_api.dart';

enum SessionPanel { attendance, attendees, history, staff }

class ScannerSessionDetails extends StatefulWidget {
  const ScannerSessionDetails({super.key, required this.api, required this.supervisor});
  final ScannerStaffApi api;
  final bool supervisor;

  @override
  State<ScannerSessionDetails> createState() => _ScannerSessionDetailsState();
}

class _ScannerSessionDetailsState extends State<ScannerSessionDetails> {
  SessionPanel panel = SessionPanel.attendance;
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  final search = TextEditingController();
  int page = 1;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final response = await switch (panel) {
        SessionPanel.attendance => widget.api.stats(),
        SessionPanel.attendees => widget.api.attendees(search: search.text.trim(), page: page),
        SessionPanel.history => widget.api.history(),
        SessionPanel.staff => widget.api.gateStaff(),
      };
      if (mounted) setState(() => data = response);
    } on ApiException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load this information. Please retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(Map staff, String action, {String? device}) async {
    String? gate;
    if (action == 'move-gate') {
      final field = TextEditingController(text: staff['gate'] as String);
      gate = await showDialog<String>(context: context, builder: (context) => AlertDialog(
        title: const Text('Move staff gate'), content: TextField(controller: field, maxLength: 100, decoration: const InputDecoration(labelText: 'Gate')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (field.text.trim().isNotEmpty) Navigator.pop(context, field.text.trim()); }, child: const Text('Move gate'))],
      ));
      field.dispose();
      if (gate == null || !mounted) return;
    }
    if (!mounted) return;
    final label = switch (action) {
      'invite' => 'Create invitation', 'move-gate' => 'Move gate', 'end-sessions' => 'End scanner sessions',
      'disable-offline' => 'Disable offline packages', _ => 'Revoke access',
    };
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('$label?'),
      content: Text(action == 'invite' ? 'The invitation for ${staff['name']} will expire in 30 minutes. Revoke the previous phone before activating a replacement.'
        : 'Apply this change for ${staff['name']}? Gate changes end existing sessions. A phone that is offline cannot receive revocation immediately.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(label))],
    ));
    if (confirmed != true || !mounted || busy) return;
    setState(() { busy = true; error = null; });
    try {
      final response = await widget.api.gateAction(staff['assignment_id'] as int, action, device: device, gate: gate);
      if (!mounted) return;
      if (response['invitation'] != null) {
        final secret = response['invitation'] as String;
        await showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('Scanner invitation'), content: SelectableText(secret), actions: [
            TextButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: secret)); }, icon: const Icon(Icons.copy), label: const Text('Copy')),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ));
      }
    } on ApiException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && error == null) await load();
  }

  @override
  void dispose() { search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final panels = [SessionPanel.attendance, SessionPanel.attendees, SessionPanel.history, if (widget.supervisor) SessionPanel.staff];
    return Scaffold(appBar: AppBar(title: const Text('Event activity'), actions: [
      IconButton(onPressed: busy ? null : load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
    ]), body: SafeArea(child: Column(children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        for (final option in panels) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
          label: Text(switch (option) { SessionPanel.attendance => 'Attendance', SessionPanel.attendees => 'Attendees', SessionPanel.history => 'Scan history', SessionPanel.staff => 'Gate staff' }),
          selected: panel == option, onSelected: busy ? null : (_) { setState(() { panel = option; data = null; page = 1; }); load(); },
        )),
      ])),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: const TextStyle(color: AppColors.danger))),
      if (panel == SessionPanel.attendees) Padding(padding: const EdgeInsets.all(16), child: TextField(
        controller: search, onSubmitted: (_) { page = 1; load(); }, decoration: InputDecoration(labelText: 'Attendee name',
          suffixIcon: IconButton(onPressed: busy ? null : () { page = 1; load(); }, icon: const Icon(Icons.search), tooltip: 'Search attendees')),
      )),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        if (data != null && panel == SessionPanel.attendance) ...[
          for (final item in [('Checked in', 'checked_in'), ('Not checked in', 'pending'), ('Valid tickets', 'total')])
            ListTile(title: Text(item.$1), trailing: Text('${data![item.$2]}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
        ],
        if (data != null && panel == SessionPanel.attendees) ...[
          if ((data!['items'] as List).isEmpty) const Text('No matching attendees.'),
          for (final attendee in data!['items'] as List) ListTile(title: Text(attendee['name']?.toString() ?? 'Guest'),
            subtitle: Text(attendee['ticket_type']?.toString() ?? ''),
            trailing: Icon(attendee['checked_in'] == true ? Icons.check_circle_outline : Icons.radio_button_unchecked,
              color: attendee['checked_in'] == true ? AppColors.success : AppColors.muted)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(tooltip: 'Previous page', onPressed: busy || page <= 1 ? null : () { page--; load(); }, icon: const Icon(Icons.chevron_left)),
            Text('Page ${data!['current_page']} of ${data!['last_page']}'),
            IconButton(tooltip: 'Next page', onPressed: busy || page >= (data!['last_page'] as int) ? null : () { page++; load(); }, icon: const Icon(Icons.chevron_right)),
          ]),
        ],
        if (data != null && panel == SessionPanel.history) ...[
          if ((data!['items'] as List).isEmpty) const Text('No scans in this session.'),
          for (final scan in data!['items'] as List) ListTile(
            leading: Icon(scan['result']['status'] == 'CHECKED_IN' ? Icons.check_circle_outline : Icons.info_outline),
            title: Text(scan['result']['message'] as String), subtitle: Text('${scan['action']} · ${scan['created_at']}')),
        ],
        if (data != null && panel == SessionPanel.staff) ...[
          if ((data!['review_required'] as int? ?? 0) > 0) Text('${data!['review_required']} offline scans require organizer review.', style: const TextStyle(color: AppColors.warning)),
          if ((data!['staff'] as List).isEmpty) const Text('No gate staff assigned.'),
          for (final staff in data!['staff'] as List) ...[
            ListTile(title: Text(staff['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${staff['gate']} · ${staff['revoked'] == true ? 'Revoked' : staff['role']}\n${staff['checkins']} online check-ins'),
              trailing: staff['role'] != 'gate_staff' || staff['revoked'] == true ? null : PopupMenuButton<String>(
                enabled: !busy, tooltip: 'Manage staff access', onSelected: (value) => action(staff as Map, value), itemBuilder: (_) => [
                  const PopupMenuItem(value: 'invite', child: Text('Create invitation')),
                  const PopupMenuItem(value: 'revoke-assignment', child: Text('Revoke assignment')),
                  const PopupMenuItem(value: 'move-gate', child: Text('Move gate')),
                  const PopupMenuItem(value: 'end-sessions', child: Text('End scanner sessions')),
                  const PopupMenuItem(value: 'disable-offline', child: Text('Disable offline packages')),
                ])),
            for (final device in staff['devices'] as List) ListTile(contentPadding: const EdgeInsets.only(left: 32, right: 16),
              leading: const Icon(Icons.smartphone_outlined), title: Text('${device['name']} · ${device['status']}'),
              subtitle: Text('${device['last_seen_at'] == null ? 'Not seen yet' : 'Last seen ${device['last_seen_at']}'}\nReported backlog: ${device['reported_pending_scans']} scans'),
              trailing: staff['role'] != 'gate_staff' || device['status'] == 'revoked' ? null : IconButton(
                tooltip: 'Revoke device', onPressed: busy ? null : () => action(staff as Map, 'revoke-device', device: device['id'] as String),
                icon: const Icon(Icons.block, color: AppColors.danger))),
            const Divider(),
          ],
        ],
      ])),
    ])));
  }
}
