import 'audit_guardian_service.dart';

class AiBatchAssessment {
  final String headline;
  final List<String> keyFindings;
  final List<String> flaggedRecordIds;
  final String recommendedAction;

  const AiBatchAssessment({
    required this.headline,
    required this.keyFindings,
    required this.flaggedRecordIds,
    required this.recommendedAction,
  });
}

/// Strictly advisory intelligence layer over deterministic AuditGuardianService
/// proposals and snapshots. Never mutates live records or executes commits/rollbacks
/// on its own—human confirmation and deterministic rules remain authoritative.
class AuditAiAdvisor {
  /// Builds a concise, structured review summary and anomaly list from staged
  /// proposals (works for both Excel imports and direct record edits).
  AiBatchAssessment assessProposals(List<ChangeProposal> proposals) {
    var newCount = 0;
    var changedCount = 0;
    var unchangedCount = 0;
    final flagged = <ChangeProposal>[];
    final findings = <String>[];
    var dpdJumpCount = 0;
    var amountDropCount = 0;
    var missingIdCount = 0;

    for (final p in proposals) {
      switch (p.status) {
        case ProposalStatus.newRecord:
          newCount++;
          break;
        case ProposalStatus.changed:
          changedCount++;
          break;
        case ProposalStatus.unchanged:
          unchangedCount++;
          break;
        case ProposalStatus.flagged:
          flagged.add(p);
          if (p.recordId.isEmpty) missingIdCount++;
          for (final reason in p.riskReasons) {
            if (reason.contains('DPD')) dpdJumpCount++;
            if (reason.contains('dropped')) amountDropCount++;
          }
          break;
      }
    }

    if (proposals.isEmpty) {
      return const AiBatchAssessment(
        headline: 'No records staged for review.',
        keyFindings: ['Upload a valid sheet or edit a record to generate diffs.'],
        flaggedRecordIds: [],
        recommendedAction: 'Stage changes first.',
      );
    }

    final headline =
        'Staged ${proposals.length} row(s): $newCount new, $changedCount normal updates, '
        '${flagged.length} flagged for review, $unchangedCount unchanged.';

    if (missingIdCount > 0) {
      findings.add(
        '$missingIdCount row(s) lack a Loan / Application ID—verify mapping before committing.',
      );
    }
    if (amountDropCount > 0) {
      findings.add(
        '$amountDropCount record(s) show a sharp financial/overdue drop—confirm whether a '
        'legitimate collection occurred or an Excel column shifted/errored.',
      );
    }
    if (dpdJumpCount > 0) {
      findings.add(
        '$dpdJumpCount record(s) show a large DPD shift—verify existing record vs. incoming sheet.',
      );
    }
    if (findings.isEmpty) {
      findings.add(
        'No sharp amount drops, large DPD jumps, or missing IDs detected in staged diffs.',
      );
    }

    final flaggedIds = flagged
        .map((p) => p.recordId)
        .where((id) => id.isNotEmpty)
        .toList();

    final action = flagged.isNotEmpty
        ? 'Review ${flagged.length} flagged item(s) individually first; keep existing values '
          'where incoming data looks wrong, or roll back the batch if a mistake is committed.'
        : (changedCount + newCount) > 0
            ? 'Safe to review and commit accepted changes; a rollback snapshot will be saved automatically.'
            : 'No live updates needed—all matched records already match incoming values.';

    return AiBatchAssessment(
      headline: headline,
      keyFindings: findings,
      flaggedRecordIds: flaggedIds,
      recommendedAction: action,
    );
  }

  /// Advises on whether rolling back a batch makes sense based on its snapshot state.
  String adviseOnRollback(BatchSnapshot snapshot) {
    if (snapshot.rolledBackAt != null) {
      return 'Batch ${snapshot.batchId} was already rolled back at ${snapshot.rolledBackAt!.toIso8601String()}.';
    }
    if (!snapshot.canRollback) {
      return 'Batch ${snapshot.batchId} has no stored prior field values to restore.';
    }
    return 'Rolling back batch ${snapshot.batchId} (${snapshot.label}) will restore '
        '${snapshot.updatedRecordIds.length} affected record(s) to their pre-commit state '
        'and log a rollback audit entry.';
  }
}
