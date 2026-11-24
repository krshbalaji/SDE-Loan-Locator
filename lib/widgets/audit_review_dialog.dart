import 'package:flutter/material.dart';
import '../services/audit_ai_advisor.dart';
import '../services/audit_guardian_service.dart';

class AuditReviewDialog extends StatefulWidget {
  final String title;
  final List<ChangeProposal> proposals;
  final AiBatchAssessment assessment;
  final VoidCallback? onRollbackLatest;

  const AuditReviewDialog({
    super.key,
    required this.title,
    required this.proposals,
    required this.assessment,
    this.onRollbackLatest,
  });

  @override
  State<AuditReviewDialog> createState() => _AuditReviewDialogState();
}

class _AuditReviewDialogState extends State<AuditReviewDialog> {
  bool _showUnchanged = false;

  List<ChangeProposal> get _visibleProposals {
    if (_showUnchanged) return widget.proposals;
    return widget.proposals
        .where((p) => p.status != ProposalStatus.unchanged)
        .toList();
  }

  void _acceptAllNonRisky() {
    setState(() {
      for (final p in widget.proposals) {
        if (p.status == ProposalStatus.changed || p.status == ProposalStatus.newRecord) {
          p.accepted = true;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final acceptedCount = widget.proposals.where((p) => p.accepted).length;
    final visible = _visibleProposals;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.verified_user_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
          if (widget.onRollbackLatest != null)
            TextButton.icon(
              onPressed: widget.onRollbackLatest,
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Rollback Last'),
            ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.assessment.headline,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      for (final finding in widget.assessment.keyFindings)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('• $finding'),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Advisory: ${widget.assessment.recommendedAction}',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Show Unchanged'),
                    selected: _showUnchanged,
                    onSelected: (v) => setState(() => _showUnchanged = v),
                  ),
                  TextButton(
                    onPressed: _acceptAllNonRisky,
                    child: const Text('Accept Normal & New'),
                  ),
                ],
              ),
              const Divider(),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No changed or flagged records to review.'),
                )
              else
                for (final p in visible)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: CheckboxListTile(
                      value: p.accepted,
                      onChanged: (val) => setState(() => p.accepted = val ?? false),
                      title: Text(
                        p.recordId.isEmpty
                            ? '[Missing ID]'
                            : 'ID: ${p.recordId}  (${p.status.name})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final r in p.riskReasons)
                            Text(
                              '⚠ $r',
                              style: const TextStyle(
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          for (final d in p.diffs)
                            Text('${d.field}: ${d.before ?? "(empty)"} → ${d.after ?? "(empty)"}'),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(widget.proposals),
          child: Text('Commit ($acceptedCount accepted)'),
        ),
      ],
    );
  }
}
