import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/audit_service.dart';
import '../../services/maker_checker_service.dart';
import '../../utils/indian_formatters.dart';

/// Displays pending Maker-Checker requests (with four-eyes checker controls)
/// and recent immutable audit entries for admins/managers.
class GovernanceApprovalsPanel extends StatefulWidget {
  const GovernanceApprovalsPanel({
    super.key,
    required this.currentUser,
  });

  final AppUser currentUser;

  @override
  State<GovernanceApprovalsPanel> createState() => _GovernanceApprovalsPanelState();
}

class _GovernanceApprovalsPanelState extends State<GovernanceApprovalsPanel> {
  String? _statusMessage;

  Future<void> _handleDecision(
    MakerCheckerService mc,
    String requestId,
    bool approve,
  ) async {
    final err = await mc.decideRequest(
      checker: widget.currentUser,
      requestId: requestId,
      approve: approve,
      note: approve ? 'Approved in Master Command Center' : 'Rejected in Master Command Center',
    );
    if (!mounted) return;
    setState(() {
      _statusMessage = err ??
          (approve
              ? 'Request $requestId approved and logged to audit trail.'
              : 'Request $requestId rejected and logged to audit trail.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final mc = context.watch<MakerCheckerService>();
    final audit = context.watch<AuditService>();
    final allReqs = mc.requests;
    final logs = audit.recentLogs;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Maker-Checker Approvals & Audit Trail',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Pending items: ${mc.pendingRequests.length} | Total logged requests: ${allReqs.length} | Audit entries: ${logs.length}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 10),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_statusMessage!),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Approval Queue',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (allReqs.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No Maker-Checker requests submitted yet.'),
            ),
          )
        else
          for (final r in allReqs)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${r.actionType} • ${r.targetId} (${r.id})',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Chip(label: Text(r.status.name.toUpperCase())),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Amount: ${IndianFormatters.formatInr(r.amountInr)} | Maker: ${r.makerEmail}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text('Reason: ${r.reason}', style: Theme.of(context).textTheme.bodyMedium),
                    if (r.checkerEmail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Checker: ${r.checkerEmail} (${r.checkerNote ?? ""})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (r.status == MakerCheckerStatus.pending && widget.currentUser.isAdminOrAbove) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () => _handleDecision(mc, r.id, true),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Approve'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => _handleDecision(mc, r.id, false),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Reject'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        const SizedBox(height: 16),
        Text(
          'Recent Audit Logs',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (logs.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No audit entries recorded in this session yet.'),
            ),
          )
        else
          for (final entry in logs.take(15))
            ListTile(
              dense: true,
              leading: const Icon(Icons.verified_user_outlined),
              title: Text('${entry.action} • ${entry.targetType}/${entry.targetId}'),
              subtitle: Text('${entry.actorEmail} • ${entry.details}'),
              trailing: Text(
                entry.timestampIso.length >= 16 ? entry.timestampIso.substring(0, 16) : entry.timestampIso,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
      ],
    );
  }
}

