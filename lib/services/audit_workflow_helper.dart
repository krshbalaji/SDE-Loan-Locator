import 'package:flutter/material.dart';
import '../widgets/audit_review_dialog.dart';
import 'audit_ai_advisor.dart';
import 'audit_guardian_bridge.dart';
import 'audit_guardian_service.dart';

class AuditWorkflowHelper {
  final AuditGuardianBridge bridge;
  final AuditAiAdvisor advisor;

  AuditWorkflowHelper({
    required this.bridge,
    required this.advisor,
  });

  /// Runs staging -> AI advisory assessment -> UI diff review -> snapshot commit
  /// for either an Excel import batch or a single direct record edit.
  Future<BatchSnapshot?> reviewAndCommit({
    required BuildContext context,
    required String dialogTitle,
    required List<ChangeProposal> proposals,
    required Map<String, Map<String, dynamic>> liveStoreById,
    required String actorId,
    required ChangeSource source,
    required String batchLabel,
    VoidCallback? onRollbackLatest,
  }) async {
    final assessment = advisor.assessProposals(proposals);

    final reviewed = await showDialog<List<ChangeProposal>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AuditReviewDialog(
        title: dialogTitle,
        proposals: proposals,
        assessment: assessment,
        onRollbackLatest: onRollbackLatest,
      ),
    );

    if (reviewed == null) return null;

    final anyAccepted = reviewed.any((p) => p.accepted);
    if (!anyAccepted) return null;

    return bridge.commitReviewedProposals(
      liveStoreById: liveStoreById,
      proposals: reviewed,
      actorId: actorId,
      source: source,
      label: batchLabel,
    );
  }
}
