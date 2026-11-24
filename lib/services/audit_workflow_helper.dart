import 'package:flutter/material.dart';
import '../models/loan_model.dart';
import '../widgets/audit_review_dialog.dart';
import 'audit_ai_advisor.dart';
import 'audit_guardian_bridge.dart';
import 'audit_firestore_persistence.dart';
import 'audit_guardian_service.dart';
import 'excel_import_service.dart';

class AuditWorkflowHelper {
  final AuditGuardianBridge bridge;
  final AuditAiAdvisor advisor;

  final AuditFirestorePersistence? persistence;

  AuditWorkflowHelper({
    required this.bridge,
    required this.advisor,
    this.persistence,
  });

  static Map<String, dynamic> loanToAuditMap(LoanModel loan) {
    return {
      'loan_id': loan.loanId,
      'application_no': loan.applicationNo.trim().toUpperCase(),
      'dpd': loan.dpd,
      'principal_outstanding': loan.principalOutstanding,
      'interest_outstanding': loan.interestOutstanding,
      'fees_outstanding': loan.feesOutstanding,
      'loan_amount': loan.principalSanctioned,
      'status': loan.status.name,
      'assigned_agent_id': loan.assignedAgentId,
    };
  }

  static Map<String, dynamic> importRowToAuditMap(ExcelImportRow row) {
    final appNo = row.applicationNo.trim().toUpperCase();
    final id = row.loanNo.trim().isNotEmpty ? row.loanNo.trim() : appNo;
    return {
      'loan_id': id,
      'application_no': appNo,
      'dpd': row.dpd ?? 0,
      'principal_outstanding': row.principalOutstandingOverride ?? row.amount,
      'loan_amount': row.amount,
      'status': row.assetClassification ?? (row.isClosedOrRejected ? 'closed' : 'active'),
      'branch_name': row.branch,
    };
  }

  /// Stages parsed Excel rows against existing LoanModel records, shows the AI +
  /// diff review dialog, and commits accepted rows into a live map + snapshot.
  Future<BatchSnapshot?> reviewExcelImport({
    required BuildContext context,
    required ExcelParseResult parseResult,
    required List<LoanModel> existingLoans,
    required Map<String, Map<String, dynamic>> liveStoreById,
    required String actorId,
    required String fileLabel,
    VoidCallback? onRollbackLatest,
  }) async {
    final existingById = <String, Map<String, dynamic>>{};
    for (final loan in existingLoans) {
      final key = loan.applicationNo.trim().isNotEmpty
          ? loan.applicationNo.trim().toUpperCase()
          : loan.loanId.trim();
      if (key.isNotEmpty) {
        existingById[key] = loanToAuditMap(loan);
      }
    }

    final incomingRows = parseResult.rows
        .map((r) => {
              ...importRowToAuditMap(r),
              'application_no': r.applicationNo.trim().toUpperCase(),
            })
        .toList();

    final proposals = bridge.stageExcelBatch(
      existingLoansById: existingById,
      parsedRows: incomingRows,
      idKey: 'application_no',
      trackedFields: const [
        'dpd',
        'principal_outstanding',
        'interest_outstanding',
        'fees_outstanding',
        'loan_amount',
        'status',
        'assigned_agent_id',
      ],
    );

    return reviewAndCommit(
      context: context,
      dialogTitle: 'Audit Review — $fileLabel',
      proposals: proposals,
      liveStoreById: liveStoreById,
      actorId: actorId,
      source: ChangeSource.excelImport,
      batchLabel: fileLabel,
      onRollbackLatest: onRollbackLatest,
    );
  }

  /// Stages a single loan record edit (e.g. from LoanDetailScreen or edit sheet)
  /// and opens the review dialog when diffs or risk flags exist.
  Future<BatchSnapshot?> reviewDirectLoanEdit({
    required BuildContext context,
    required LoanModel beforeLoan,
    required Map<String, dynamic> updatedFields,
    required Map<String, Map<String, dynamic>> liveStoreById,
    required String actorId,
    VoidCallback? onRollbackLatest,
  }) async {
    final id = beforeLoan.applicationNo.trim().isNotEmpty
        ? beforeLoan.applicationNo.trim().toUpperCase()
        : beforeLoan.loanId.trim();
    final beforeMap = loanToAuditMap(beforeLoan)..['id_key'] = id;
    final afterMap = {
      ...beforeMap,
      ...updatedFields,
      'id_key': id,
    };

    final proposals = bridge.stageDirectEdit(
      recordId: id,
      existingRecord: beforeMap,
      updatedRecord: afterMap,
      idKey: 'id_key',
      trackedFields: const [
        'dpd',
        'principal_outstanding',
        'interest_outstanding',
        'fees_outstanding',
        'loan_amount',
        'status',
        'assigned_agent_id',
      ],
    );

    return reviewAndCommit(
      context: context,
      dialogTitle: 'Verify Edit — $id',
      proposals: proposals,
      liveStoreById: liveStoreById,
      actorId: actorId,
      source: ChangeSource.manualEdit,
      batchLabel: 'edit_$id',
      onRollbackLatest: onRollbackLatest,
    );
  }

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

    final snapshot = bridge.commitReviewedProposals(
      liveStoreById: liveStoreById,
      proposals: reviewed,
      actorId: actorId,
      source: source,
      label: batchLabel,
    );

    if (persistence != null) {
      final entriesForBatch = bridge.guardian.auditLogs
          .where((e) => e.batchId == snapshot.batchId)
          .toList();
      await persistence!.saveSnapshotAndLogs(
        snapshot: snapshot,
        entriesForBatch: entriesForBatch,
      );
    }

    return snapshot;
  }

  Future<int> rollbackLatestAndPersist({
    required Map<String, Map<String, dynamic>> liveStoreById,
    required String actorId,
  }) async {
    final latest = bridge.guardian.batches.reversed
        .where((b) => b.canRollback)
        .cast<BatchSnapshot?>()
        .firstWhere((b) => b != null, orElse: () => null);
    if (latest == null) return 0;

    final reverted = bridge.rollbackBatchId(
      batchId: latest.batchId,
      liveStoreById: liveStoreById,
      actorId: actorId,
    );

    if (reverted > 0 && persistence != null) {
      await persistence!.markBatchRolledBack(
        batchId: latest.batchId,
        rolledBackAt: DateTime.now(),
      );
    }
    return reverted;
  }
}
