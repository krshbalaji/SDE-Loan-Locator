import 'audit_guardian_service.dart';

class AuditGuardianBridge {
  final AuditGuardianService guardian;

  static const List<String> defaultTrackedLoanFields = [
    'dpd',
    'overdue_amount',
    'demand_amount',
    'collected_amount',
    'outstanding_principal',
    'loan_amount',
    'status',
    'assigned_agent_id',
    'branch_name',
  ];

  AuditGuardianBridge(this.guardian);

  /// Stage an Excel/CSV batch before mutating live records.
  List<ChangeProposal> stageExcelBatch({
    required Map<String, Map<String, dynamic>> existingLoansById,
    required List<Map<String, dynamic>> parsedRows,
    String idKey = 'loan_id',
    List<String> trackedFields = defaultTrackedLoanFields,
  }) {
    return guardian.buildProposals(
      existingById: existingLoansById,
      incomingRows: parsedRows,
      idKey: idKey,
      trackedFields: trackedFields,
    );
  }

  /// Stage a single direct record edit (e.g., from a detail/edit form).
  List<ChangeProposal> stageDirectEdit({
    required String recordId,
    required Map<String, dynamic>? existingRecord,
    required Map<String, dynamic> updatedRecord,
    String idKey = 'loan_id',
    List<String> trackedFields = defaultTrackedLoanFields,
  }) {
    final existingMap = existingRecord != null
        ? {recordId: existingRecord}
        : <String, Map<String, dynamic>>{};
    final rowWithId = Map<String, dynamic>.from(updatedRecord)..[idKey] = recordId;

    return guardian.buildProposals(
      existingById: existingMap,
      incomingRows: [rowWithId],
      idKey: idKey,
      trackedFields: trackedFields,
    );
  }

  /// Commit reviewed proposals for either Excel import or direct edit.
  BatchSnapshot commitReviewedProposals({
    required Map<String, Map<String, dynamic>> liveStoreById,
    required List<ChangeProposal> proposals,
    required String actorId,
    required ChangeSource source,
    required String label,
  }) {
    return guardian.commitProposals(
      liveStoreById: liveStoreById,
      proposals: proposals,
      actorId: actorId,
      source: source,
      label: label,
    );
  }

  /// Roll back a specific batch by ID.
  int rollbackBatchId({
    required String batchId,
    required Map<String, Map<String, dynamic>> liveStoreById,
    required String actorId,
  }) {
    return guardian.rollbackBatch(
      batchId: batchId,
      liveStoreById: liveStoreById,
      actorId: actorId,
    );
  }

  /// Roll back the most recent rollback-eligible batch.
  int rollbackLatestBatch({
    required Map<String, Map<String, dynamic>> liveStoreById,
    required String actorId,
  }) {
    final latest = guardian.batches.reversed.cast<BatchSnapshot?>().firstWhere(
          (b) => b != null && b.canRollback,
          orElse: () => null,
        );
    if (latest == null) return 0;
    return rollbackBatchId(
      batchId: latest.batchId,
      liveStoreById: liveStoreById,
      actorId: actorId,
    );
  }
}
