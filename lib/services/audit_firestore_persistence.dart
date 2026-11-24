import 'package:cloud_firestore/cloud_firestore.dart';
import 'audit_guardian_service.dart';

class AuditFirestorePersistence {
  final FirebaseFirestore _firestore;
  final String batchesCollection;
  final String logsCollection;

  AuditFirestorePersistence({
    FirebaseFirestore? firestore,
    this.batchesCollection = 'audit_batches',
    this.logsCollection = 'audit_logs',
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> saveSnapshotAndLogs({
    required BatchSnapshot snapshot,
    required List<AuditEntry> entriesForBatch,
  }) async {
    final batch = _firestore.batch();

    final batchDoc = _firestore.collection(batchesCollection).doc(snapshot.batchId);
    batch.set(batchDoc, {
      'batch_id': snapshot.batchId,
      'created_at': snapshot.createdAt.toIso8601String(),
      'actor_id': snapshot.actorId,
      'source': snapshot.source.name,
      'label': snapshot.label,
      'updated_record_ids': snapshot.updatedRecordIds,
      'previous_field_values_by_id': snapshot.previousFieldValuesById,
      'rolled_back_at': snapshot.rolledBackAt?.toIso8601String(),
    }, SetOptions(merge: true));

    for (final entry in entriesForBatch) {
      final logDoc = _firestore.collection(logsCollection).doc(entry.auditId);
      batch.set(logDoc, {
        'audit_id': entry.auditId,
        'batch_id': entry.batchId,
        'record_id': entry.recordId,
        'actor_id': entry.actorId,
        'source': entry.source.name,
        'timestamp': entry.timestamp.toIso8601String(),
        'summary': entry.summary,
        'changes': entry.changes.map(
          (k, d) => MapEntry(k, d.toMap()),
        ),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> markBatchRolledBack({
    required String batchId,
    required DateTime rolledBackAt,
  }) async {
    await _firestore.collection(batchesCollection).doc(batchId).set({
      'rolled_back_at': rolledBackAt.toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> fetchRecentBatches({int limit = 25}) async {
    final snap = await _firestore
        .collection(batchesCollection)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }
}
