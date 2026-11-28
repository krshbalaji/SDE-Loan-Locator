import '../../utils/report_file_saver_stub.dart'
    if (dart.library.js_interop) '../../utils/report_file_saver_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/activity_telemetry_service.dart';
import '../../services/auth_service.dart';

Future<String> _saveReportToFile(String content, String fileName) async {
  final downloaded = await triggerTextFileDownload(content, fileName);
  await Clipboard.setData(ClipboardData(text: content));
  if (downloaded) {
    return 'Downloaded $fileName to Downloads (also copied to clipboard)';
  }
  return kIsWeb
      ? 'Prepared $fileName (report text copied to clipboard)'
      : 'Copied $fileName summary to clipboard';
}

class TesterActivityReportScreen extends StatefulWidget {
  const TesterActivityReportScreen({super.key});

  @override
  State<TesterActivityReportScreen> createState() =>
      _TesterActivityReportScreenState();
}

enum _DatePreset { all, today, last7Days, custom }

class _TesterActivityReportScreenState
    extends State<TesterActivityReportScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  _DatePreset _preset = _DatePreset.all;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ActivityTelemetryService>().syncFromFirestore();
    });
  }

  DateTime _dayOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _matchesSearch(TesterSessionRecord session) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return session.email.toLowerCase().contains(q) ||
        session.roleLabel.toLowerCase().contains(q) ||
        session.platform.toLowerCase().contains(q) ||
        session.screensVisited.any((sc) => sc.toLowerCase().contains(q)) ||
        session.itemsReviewed.any((it) => it.toLowerCase().contains(q));
  }

  bool _matchesRange(TesterSessionRecord session) {
    final refDay = _dayOnly(session.lastActiveAt);
    final today = _dayOnly(DateTime.now());
    switch (_preset) {
      case _DatePreset.all:
        return true;
      case _DatePreset.today:
        return refDay == today;
      case _DatePreset.last7Days:
        final start = today.subtract(const Duration(days: 6));
        return !refDay.isBefore(start) && !refDay.isAfter(today);
      case _DatePreset.custom:
        if (_fromDate != null && refDay.isBefore(_dayOnly(_fromDate!))) {
          return false;
        }
        if (_toDate != null && refDay.isAfter(_dayOnly(_toDate!))) {
          return false;
        }
        return true;
    }
  }

  String _rangeSlug() {
    String fmt(DateTime d) => d.toIso8601String().substring(0, 10);
    final now = DateTime.now();
    switch (_preset) {
      case _DatePreset.all:
        return 'all_${fmt(now)}';
      case _DatePreset.today:
        return 'today_${fmt(now)}';
      case _DatePreset.last7Days:
        return '${fmt(now.subtract(const Duration(days: 6)))}_to_${fmt(now)}';
      case _DatePreset.custom:
        final f = _fromDate != null ? fmt(_fromDate!) : 'start';
        final t = _toDate != null ? fmt(_toDate!) : 'end';
        return '${f}_to_$t';
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? _fromDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = _DatePreset.custom;
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _buildTextSummary(List<TesterSessionRecord> sessions) {
    final buf = StringBuffer()
      ..writeln('SDE LOAN LOCATOR — TESTER & USER ACTIVITY REPORT')
      ..writeln('Generated: ${_formatTimestamp(DateTime.now())}')
      ..writeln('Date Range Filter: ${_rangeSlug()}')
      ..writeln('Total Sessions: ${sessions.length}')
      ..writeln('');

    final grouped = <String, List<TesterSessionRecord>>{};
    for (final s in sessions) {
      grouped.putIfAbsent(s.email, () => <TesterSessionRecord>[]).add(s);
    }

    for (final entry in grouped.entries) {
      final userSessions = entry.value;
      final latest = userSessions.first;
      final totalSecs = userSessions.fold<int>(
        0,
        (sum, item) => sum + item.activeSeconds,
      );
      final screens = <String>{
        for (final item in userSessions) ...item.screensVisited,
      }.toList();
      final reviewed = <String>{
        for (final item in userSessions) ...item.itemsReviewed,
      }.toList();

      buf
        ..writeln('User: ${entry.key} (${latest.roleLabel})')
        ..writeln(
          '  Logins: ${userSessions.length} | Active Time: ${_formatDuration(totalSecs)}',
        )
        ..writeln(
          '  Last Active: ${_formatTimestamp(latest.lastActiveAt)} (${latest.platform})',
        )
        ..writeln(
          '  Screens Visited: ${screens.isEmpty ? "None" : screens.join(", ")}',
        );
      if (reviewed.isNotEmpty) {
        buf.writeln('  Reviewed Actions: ${reviewed.join(", ")}');
      }
      buf.writeln('');
    }

    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final telemetry = context.watch<ActivityTelemetryService>();
    final isSuperAdmin = auth.currentUser?.isExecutive == true;
    final allSessions = telemetry.sessions;
    final filteredSessions = allSessions
        .where((session) => _matchesRange(session) && _matchesSearch(session))
        .toList();
    final slug = _rangeSlug();

    final totalSeconds = filteredSessions.fold<int>(
      0,
      (sum, item) => sum + item.activeSeconds,
    );
    final uniqueUsers = <String>{
      for (final s in filteredSessions) s.email,
    }.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tester & User Activity Report'),
        actions: [
          IconButton(
            tooltip: 'Refresh Telemetry',
            onPressed: telemetry.isSyncing
                ? null
                : () => telemetry.syncFromFirestore(),
            icon: telemetry.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Download Report Summary (.txt)',
            onPressed: filteredSessions.isEmpty
                ? null
                : () async {
                    final report = _buildTextSummary(filteredSessions);
                    final fileName = 'tester_activity_report_$slug.txt';
                    final msg = await _saveReportToFile(report, fileName);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg)),
                    );
                  },
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: 'Download Audit CSV (.csv)',
            onPressed: filteredSessions.isEmpty
                ? null
                : () async {
                    final csv = telemetry.buildAuditCsv(filteredSessions);
                    final csvName = 'tester_audit_events_$slug.csv';
                    final ok = await triggerTextFileDownload(csv, csvName);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Downloaded $csvName to Downloads'
                              : 'Prepared $csvName audit log',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: !isSuperAdmin
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Restricted: Only Super Admin or Executive leadership can view tester and user activity reports.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _preset == _DatePreset.all,
                      onSelected: (_) =>
                          setState(() => _preset = _DatePreset.all),
                    ),
                    ChoiceChip(
                      label: const Text('Today'),
                      selected: _preset == _DatePreset.today,
                      onSelected: (_) =>
                          setState(() => _preset = _DatePreset.today),
                    ),
                    ChoiceChip(
                      label: const Text('Last 7 Days'),
                      selected: _preset == _DatePreset.last7Days,
                      onSelected: (_) =>
                          setState(() => _preset = _DatePreset.last7Days),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickDate(isFrom: true),
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        _fromDate == null
                            ? 'From'
                            : 'From: ${_fromDate!.toIso8601String().substring(0, 10)}',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickDate(isFrom: false),
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(
                        _toDate == null
                            ? 'To'
                            : 'To: ${_toDate!.toIso8601String().substring(0, 10)}',
                      ),
                    ),
                    if (_preset == _DatePreset.custom)
                      TextButton(
                        onPressed: () => setState(() {
                          _preset = _DatePreset.all;
                          _fromDate = null;
                          _toDate = null;
                        }),
                        child: const Text('Clear Dates'),
                      ),
                    Text(
                      'Showing ${filteredSessions.length} of ${allSessions.length} sessions',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (filteredSessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        'No tester or user sessions match the selected date range.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SummaryChip(
                        label: 'Active Users / Testers',
                        value: '$uniqueUsers',
                        icon: Icons.people_outline,
                      ),
                      _SummaryChip(
                        label: 'Total Login Sessions',
                        value: '${filteredSessions.length}',
                        icon: Icons.login,
                      ),
                      _SummaryChip(
                        label: 'Total Time Spent',
                        value: _formatDuration(totalSeconds),
                        icon: Icons.timer_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'User & Tester Summary',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._buildUserSummaries(filteredSessions),
                  const SizedBox(height: 16),
                  const Text(
                    'Session-by-Session Audit Trail',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...filteredSessions.map(
                    (session) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        leading: Icon(
                          session.logoutAt == null
                              ? Icons.radio_button_checked
                              : Icons.history,
                        ),
                        title: Text(
                          '${session.email} • ${_formatDuration(session.activeSeconds)}',
                        ),
                        subtitle: Text(
                          'Login: ${_formatTimestamp(session.loginAt)} | ${session.platform} | ${session.screensVisited.length} screens',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Screens: ${session.screensVisited.isEmpty ? "None" : session.screensVisited.join(" -> ")}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (session.itemsReviewed.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Reviewed Actions: ${session.itemsReviewed.join(", ")}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                                if (session.events.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  ...session.events.map(
                                    (ev) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• [${_formatTimestamp(ev.timestamp)}] ${ev.label}${ev.detail == null || ev.detail!.isEmpty ? "" : " — ${ev.detail}"}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  List<Widget> _buildUserSummaries(List<TesterSessionRecord> sessions) {
    final grouped = <String, List<TesterSessionRecord>>{};
    for (final s in sessions) {
      grouped.putIfAbsent(s.email, () => <TesterSessionRecord>[]).add(s);
    }
    return grouped.entries.map((entry) {
      final userSessions = entry.value;
      final latest = userSessions.first;
      final totalSeconds = userSessions.fold<int>(
        0,
        (sum, item) => sum + item.activeSeconds,
      );
      final screens = <String>{
        for (final item in userSessions) ...item.screensVisited,
      }.toList();
      final reviewed = <String>{
        for (final item in userSessions) ...item.itemsReviewed,
      }.toList();

            return _UserSummaryCard(
        email: entry.key,
        roleLabel: latest.roleLabel,
        platform: latest.platform,
        loginCount: userSessions.length,
        lastActiveText: _formatTimestamp(latest.lastActiveAt),
        totalSeconds: totalSeconds,
        screens: screens,
        reviewed: reviewed,
        sessions: userSessions,
        formatDuration: _formatDuration,
        formatTimestamp: _formatTimestamp,
      );
    }).toList();
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSummaryCard extends StatelessWidget {
  const _UserSummaryCard({
    required this.email,
    required this.roleLabel,
    required this.platform,
    required this.loginCount,
    required this.lastActiveText,
    required this.totalSeconds,
    required this.screens,
    required this.reviewed,
        required this.formatDuration,
    required this.sessions,
    required this.formatTimestamp,
  });

  final String email;
  final String roleLabel;
  final String platform;
  final int loginCount;
  final String lastActiveText;
  final int totalSeconds;
  final List<String> screens;
  final List<String> reviewed;
  final String Function(int) formatDuration;
  final List<TesterSessionRecord> sessions;
  final String Function(DateTime) formatTimestamp;

  @override
  Widget build(BuildContext context) {
        return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDrillDown(context),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$email ($roleLabel)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  'Time: ${formatDuration(totalSeconds)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Logins: $loginCount • Last Active: $lastActiveText • Platform: $platform',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Screens Reviewed (${screens.length}): ${screens.isEmpty ? "None" : screens.join(", ")}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (reviewed.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Actions & Records Reviewed (${reviewed.length}): ${reviewed.join(", ")}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Tap for session & dwell drill-down',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _openDrillDown(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '$email ($roleLabel)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Sessions: ${sessions.length} • Total Active: ${formatDuration(totalSeconds)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 20),
            for (var i = 0; i < sessions.length; i++) ...[
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session #${sessions.length - i} • ${formatDuration(sessions[i].activeSeconds)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Login: ${formatTimestamp(sessions[i].loginAt)} • Last: ${formatTimestamp(sessions[i].lastActiveAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      for (final ev in sessions[i].events.reversed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '[${ev.type}] ${ev.label}${ev.detail != null && ev.detail!.isNotEmpty ? ' - ${ev.detail}' : ''} (${formatTimestamp(ev.timestamp)})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}