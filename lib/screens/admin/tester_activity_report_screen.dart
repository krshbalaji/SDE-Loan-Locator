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

class _TesterActivityReportScreenState
    extends State<TesterActivityReportScreen> {
  String _datePreset = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;

  DateTime _dayOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _matchesDateFilter(TesterSessionRecord session) {
    final day = _dayOnly(session.lastActiveAt);
    final today = _dayOnly(DateTime.now());
    if (_datePreset == 'today') {
      return day == today;
    }
    if (_datePreset == '7d') {
      final start = today.subtract(const Duration(days: 6));
      return !day.isBefore(start) && !day.isAfter(today);
    }
    if (_datePreset == 'custom') {
      if (_fromDate != null && day.isBefore(_dayOnly(_fromDate!))) {
        return false;
      }
      if (_toDate != null && day.isAfter(_dayOnly(_toDate!))) {
        return false;
      }
    }
    return true;
  }

  String _filterSlug() {
    String dStr(DateTime d) => d.toIso8601String().substring(0, 10);
    final now = DateTime.now();
    if (_datePreset == 'today') return 'today_${dStr(now)}';
    if (_datePreset == '7d') {
      return '${dStr(now.subtract(const Duration(days: 6)))}_to_${dStr(now)}';
    }
    if (_datePreset == 'custom') {
      final f = _fromDate != null ? dStr(_fromDate!) : 'any';
      final t = _toDate != null ? dStr(_toDate!) : 'any';
      return '$f_to_$t';
    }
    return 'all_${dStr(now)}';
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
      _datePreset = 'custom';
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ActivityTelemetryService>().syncFromFirestore();
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
      ..writeln('Total Sessions: ${sessions.length}')
      ..writeln('');

    final grouped = <String, List<TesterSessionRecord>>{};
    for (final s in sessions) {
      grouped.putIfAbsent(s.uid, () => <TesterSessionRecord>[]).add(s);
    }

    for (final entry in grouped.entries) {
      final list = entry.value;
      final first = list.first;
      final totalSec =
          list.fold<int>(0, (sum, s) => sum + s.activeSeconds);
      final screens = list.expand((s) => s.screensVisited).toSet().toList();
      final reviewed = list.expand((s) => s.itemsReviewed).toSet().toList();
      buf
        ..writeln('User: ${first.displayName} (${first.roleLabel})')
        ..writeln('  Logins: ${list.length} | Active Time: ${_formatDuration(totalSec)}')
        ..writeln('  Last Active: ${_formatTimestamp(first.lastActiveAt)} (${first.platform})')
        ..writeln('  Screens Visited: ${screens.isEmpty ? "None" : screens.join(", ")}')
        ..writeln('  Reviewed Actions: ${reviewed.isEmpty ? "None" : reviewed.join(", ")}')
        ..writeln('');
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isSuperAdmin = (auth.currentUser?.isSuperAdmin ?? false) || (auth.currentUser?.isExecutive ?? false);
    final telemetry = context.watch<ActivityTelemetryService>();
    final sessions = telemetry.sessions;

    final groupedByUser = <String, List<TesterSessionRecord>>{};
    for (final s in sessions) {
      groupedByUser.putIfAbsent(s.uid, () => <TesterSessionRecord>[]).add(s);
    }

    final totalActiveSeconds =
        sessions.fold<int>(0, (sum, s) => sum + s.activeSeconds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tester & User Activity Report'),
        actions: [
          if (telemetry.useFirebase)
            IconButton(
              tooltip: 'Sync from Firestore',
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
            tooltip: 'Copy Report Summary',
            onPressed: sessions.isEmpty
                ? null
                : () async {
                    final report = _buildTextSummary(filteredSessions);
                    final fileName = 'tester_activity_report_$slug.txt'; final msg = await _saveReportToFile(report, fileName);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(msg),
                      ),
                    );
                  },
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: 'Download Audit CSV',
            onPressed: sessions.isEmpty
                ? null
                : () async {
                    final csv = context.read<ActivityTelemetryService>().buildAuditCsv(filteredSessions);
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
          : sessions.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No tester or user sessions recorded yet. Log in and navigate screens to capture usage telemetry.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : () {
              final filteredSessions = sessions.where(_matchesDateFilter).toList();
              final slug = _filterSlug();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _datePreset == 'all',
                        onSelected: (_) => setState(() => _datePreset = 'all'),
                      ),
                      ChoiceChip(
                        label: const Text('Today'),
                        selected: _datePreset == 'today',
                        onSelected: (_) => setState(() => _datePreset = 'today'),
                      ),
                      ChoiceChip(
                        label: const Text('Last 7 Days'),
                        selected: _datePreset == '7d',
                        onSelected: (_) => setState(() => _datePreset = '7d'),
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
                      Text(
                        'Showing ${filteredSessions.length} of ${sessions.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryChip(
                      label: 'Active Users / Testers',
                      value: '${groupedByUser.length}',
                      icon: Icons.people_outline,
                    ),
                    _SummaryChip(
                      label: 'Total Login Sessions',
                      value: '${sessions.length}',
                      icon: Icons.login,
                    ),
                    _SummaryChip(
                      label: 'Total Time Spent',
                      value: _formatDuration(totalActiveSeconds),
                      icon: Icons.timer_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'User & Tester Summary',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final entry in groupedByUser.entries)
                  _UserSummaryCard(
                    userSessions: entry.value,
                    formatDuration: _formatDuration,
                    formatTimestamp: _formatTimestamp,
                  ),
                const SizedBox(height: 16),
                Text(
                  'Session-by-Session Audit Trail',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final session in sessions)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      leading: Icon(
                        session.logoutAt == null
                            ? Icons.radio_button_checked
                            : Icons.history,
                        color: session.logoutAt == null
                            ? Colors.green
                            : Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        '${session.displayName} • ${_formatDuration(session.activeSeconds)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Login: ${_formatTimestamp(session.loginAt)} | ${session.platform} | '
                        '${session.screensVisited.length} screens',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Screens Visited: ${session.screensVisited.join(" -> ")}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (session.itemsReviewed.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Reviewed Items: ${session.itemsReviewed.join(" | ")}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                        const Divider(height: 16),
                        for (final ev in session.events.reversed.take(15))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Text(
                                  _formatTimestamp(ev.timestamp).split(' ').last,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ev.detail != null && ev.detail!.isNotEmpty
                                        ? '${ev.label} (${ev.detail})'
                                        : ev.label,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
              ),
            );
          }(),

    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
              ),
            );
          }(),
      ),
    );
  }
}
class _UserSummaryCard extends StatelessWidget {
  final List<TesterSessionRecord> userSessions;
  final String Function(int) formatDuration;
  final String Function(DateTime) formatTimestamp;

  const _UserSummaryCard({
    required this.userSessions,
    required this.formatDuration,
    required this.formatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final latest = userSessions.first;
    final totalSeconds =
        userSessions.fold<int>(0, (sum, s) => sum + s.activeSeconds);
    final screens =
        userSessions.expand((s) => s.screensVisited).toSet().toList();
    final reviewed =
        userSessions.expand((s) => s.itemsReviewed).toSet().toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${latest.displayName} (${latest.roleLabel})',
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
              'Logins: ${userSessions.length} • Last Active: ${formatTimestamp(latest.lastActiveAt)} • Platform: ${latest.platform}',
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
          ],
        ),
      ),
    );
  }
}
