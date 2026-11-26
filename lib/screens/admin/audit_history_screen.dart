import 'package:provider/provider.dart';
import '../../services/activity_telemetry_service.dart';
import 'package:flutter/material.dart';
import '../../services/audit_firestore_persistence.dart';
import '../../services/audit_guardian_bridge.dart';
import '../../services/audit_guardian_service.dart';

class AuditHistoryScreen extends StatefulWidget {
  final AuditGuardianBridge bridge;
  final Map<String, Map<String, dynamic>> liveStoreById;
  final String actorId;
  final AuditFirestorePersistence? persistence;

  const AuditHistoryScreen({
    super.key,
    required this.bridge,
    required this.liveStoreById,
    required this.actorId,
    this.persistence,
  });

  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  String? _selectedBatchId;
  ChangeSource? _sourceFilter;

  Future<void> _rollbackBatch(BatchSnapshot batch) async {
    final telemetry = context.read<ActivityTelemetryService>();
    final reverted = widget.bridge.rollbackBatchId(
      batchId: batch.batchId,
      liveStoreById: widget.liveStoreById,
      actorId: widget.actorId,
    );
    if (reverted > 0 && widget.persistence != null) {
      await widget.persistence!.markBatchRolledBack(
        batchId: batch.batchId,
        rolledBackAt: DateTime.now(),
      );
    }
    if (reverted > 0) {
      telemetry.logFeatureReviewed(
        'Rolled Back Audit Batch',
        detail: 'Batch ${batch.batchId} (${batch.label}) • Source: ${batch.source.name} • Reverted: $reverted record(s)',
      );
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reverted > 0
              ? 'Rolled back $reverted record(s) from batch ${batch.label}.'
              : 'Batch ${batch.label} could not be rolled back.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final batches = widget.bridge.guardian.batches.reversed.where((b) {
      if (_sourceFilter != null && b.source != _sourceFilter) return false;
      return true;
    }).toList();

    final logs = widget.bridge.guardian.auditLogs.reversed.where((e) {
      if (_selectedBatchId != null && e.batchId != _selectedBatchId) return false;
      if (_sourceFilter != null && e.source != _sourceFilter) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Batches & Change Logs'),
        actions: [
          if (_selectedBatchId != null)
            TextButton(
              onPressed: () => setState(() => _selectedBatchId = null),
              child: const Text('Clear Batch Filter'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('All Sources'),
                  selected: _sourceFilter == null,
                  onSelected: (_) => setState(() => _sourceFilter = null),
                ),
                for (final src in ChangeSource.values)
                  ChoiceChip(
                    label: Text(src.name),
                    selected: _sourceFilter == src,
                    onSelected: (_) => setState(() => _sourceFilter = src),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Batch Snapshots (${batches.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 210,
              child: batches.isEmpty
                  ? const Center(child: Text('No committed batches yet.'))
                  : ListView.builder(
                      itemCount: batches.length,
                      itemBuilder: (ctx, i) {
                        final b = batches[i];
                        final isSelected = _selectedBatchId == b.batchId;
                        return Card(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: ListTile(
                            onTap: () => setState(() {
                              _selectedBatchId = isSelected ? null : b.batchId;
                            }),
                            title: Text('${b.label} • ${b.source.name}'),
                            subtitle: Text(
                              'Records: ${b.updatedRecordIds.length} | '
                              'At: ${b.createdAt.toIso8601String()} | '
                              'Status: ${b.rolledBackAt != null ? "Rolled Back" : "Active"}',
                            ),
                            trailing: b.canRollback
                                ? TextButton.icon(
                                    onPressed: () => _rollbackBatch(b),
                                    icon: const Icon(Icons.undo, size: 18),
                                    label: const Text('Rollback'),
                                  )
                                : const Icon(Icons.check_circle_outline),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 24),
            Text(
              'Immutable Audit Log (${logs.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: logs.isEmpty
                  ? const Center(child: Text('No audit log entries match filter.'))
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (ctx, i) {
                        final e = logs[i];
                        final diffLines = e.changes.entries
                            .map((kv) => '${kv.key}: ${kv.value.before ?? "(empty)"} -> ${kv.value.after ?? "(empty)"}')
                            .join(' | ');
                        final subtitleText = diffLines.isNotEmpty
                            ? '${e.timestamp.toIso8601String()} • By ${e.actorId}\n$diffLines'
                            : '${e.timestamp.toIso8601String()} • By ${e.actorId}';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            title: Text('${e.recordId} • ${e.summary}'),
                            subtitle: Text(subtitleText),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
