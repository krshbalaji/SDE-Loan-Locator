import 'dart:math';

enum ChangeSource { excelImport, manualEdit, rollback }

enum ProposalStatus { newRecord, changed, unchanged, flagged }

class FieldDiff {
  final String field;
  final dynamic before;
  final dynamic after;

  const FieldDiff({
    required this.field,
    required this.before,
    required this.after,
  });

  Map<String, dynamic> toMap() => {
        'field': field,
        'before': before,
        'after': after,
      };
}

class ChangeProposal {
  final String recordId;
  final ProposalStatus status;
  final Map<String, dynamic>? existingRecord;
  final Map<String, dynamic> incomingRecord;
  final List<FieldDiff> diffs;
  final List<String> riskReasons;
  bool accepted;

  ChangeProposal({
    required this.recordId,
    required this.status,
    required this.existingRecord,
    required this.incomingRecord,
    required this.diffs,
    required this.riskReasons,
    required this.accepted,
  });

  bool get hasRisk => riskReasons.isNotEmpty;
}

class BatchSnapshot {
  final String batchId;
  final DateTime createdAt;
  final String actorId;
  final ChangeSource source;
  final String label;
  final Map<String, Map<String, dynamic>> previousFieldValuesById;
  final List<String> updatedRecordIds;
  DateTime? rolledBackAt;

  BatchSnapshot({
    required this.batchId,
    required this.createdAt,
    required this.actorId,
    required this.source,
    required this.label,
    required this.previousFieldValuesById,
    required this.updatedRecordIds,
    this.rolledBackAt,
  });

  bool get canRollback => rolledBackAt == null && previousFieldValuesById.isNotEmpty;
}

class AuditEntry {
  final String auditId;
  final String batchId;
  final String recordId;
  final String actorId;
  final ChangeSource source;
  final DateTime timestamp;
  final String summary;
  final Map<String, FieldDiff> changes;

  const AuditEntry({
    required this.auditId,
    required this.batchId,
    required this.recordId,
    required this.actorId,
    required this.source,
    required this.timestamp,
    required this.summary,
    required this.changes,
  });
}

class AuditGuardianService {
  final List<BatchSnapshot> _batches = [];
  final List<AuditEntry> _auditLogs = [];

  List<BatchSnapshot> get batches => List.unmodifiable(_batches);
  List<AuditEntry> get auditLogs => List.unmodifiable(_auditLogs);

  static String generateBatchId(String prefix) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final salt = Random().nextInt(9000) + 1000;
    return '${prefix}_${now}_$salt';
  }

  dynamic normalizeValue(dynamic value, {bool isNumeric = false}) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
      if (isNumeric) {
        final cleaned = trimmed.replaceAll(',', '').replaceAll('₹', '').trim();
        final parsed = num.tryParse(cleaned);
        if (parsed != null) {
          return parsed is double ? double.parse(parsed.toStringAsFixed(2)) : parsed;
        }
      }
      return trimmed;
    }
    if (isNumeric && value is num) {
      if (value is double) {
        return double.parse(value.toStringAsFixed(2));
      }
      return value;
    }
    return value;
  }

  List<ChangeProposal> buildProposals({
    required Map<String, Map<String, dynamic>> existingById,
    required List<Map<String, dynamic>> incomingRows,
    required String idKey,
    required List<String> trackedFields,
    Set<String> numericFields = const {
      'dpd',
      'overdue_amount',
      'demand_amount',
      'collected_amount',
      'outstanding_principal',
      'loan_amount',
    },
    double largeAmountDropRatio = 0.5,
    int largeDpdJump = 30,
  }) {
    final proposals = <ChangeProposal>[];

    for (final rawIncoming in incomingRows) {
      final rawId = rawIncoming[idKey]?.toString().trim() ?? '';
      if (rawId.isEmpty) {
        proposals.add(
          ChangeProposal(
            recordId: '',
            status: ProposalStatus.flagged,
            existingRecord: null,
            incomingRecord: rawIncoming,
            diffs: const [],
            riskReasons: const ['Missing Loan / Application ID'],
            accepted: false,
          ),
        );
        continue;
      }

      final existing = existingById[rawId];
      if (existing == null) {
        proposals.add(
          ChangeProposal(
            recordId: rawId,
            status: ProposalStatus.newRecord,
            existingRecord: null,
            incomingRecord: rawIncoming,
            diffs: const [],
            riskReasons: const [],
            accepted: true,
          ),
        );
        continue;
      }

      final diffs = <FieldDiff>[];
      final riskReasons = <String>[];

      for (final field in trackedFields) {
        final isNum = numericFields.contains(field);
        final beforeVal = normalizeValue(existing[field], isNumeric: isNum);
        final incomingRaw = rawIncoming[field];
        final afterNorm = normalizeValue(incomingRaw, isNumeric: isNum);

        if (afterNorm == null && beforeVal != null) {
          continue;
        }

        if (beforeVal != afterNorm) {
          diffs.add(FieldDiff(field: field, before: beforeVal, after: afterNorm));

          if (isNum &&
              beforeVal is num &&
              afterNorm is num &&
              beforeVal > 0 &&
              (beforeVal - afterNorm) / beforeVal >= largeAmountDropRatio) {
            riskReasons.add(
              '$field dropped by ${(((beforeVal - afterNorm) / beforeVal) * 100).toStringAsFixed(0)}% ($beforeVal -> $afterNorm)',
            );
          }

          if (field == 'dpd' && beforeVal is num && afterNorm is num) {
            final delta = (afterNorm - beforeVal).abs();
            if (delta >= largeDpdJump) {
              riskReasons.add('DPD shifted by $delta days ($beforeVal -> $afterNorm)');
            }
          }
        }
      }

      if (diffs.isEmpty) {
        proposals.add(
          ChangeProposal(
            recordId: rawId,
            status: ProposalStatus.unchanged,
            existingRecord: existing,
            incomingRecord: rawIncoming,
            diffs: const [],
            riskReasons: const [],
            accepted: false,
          ),
        );
      } else if (riskReasons.isNotEmpty) {
        proposals.add(
          ChangeProposal(
            recordId: rawId,
            status: ProposalStatus.flagged,
            existingRecord: existing,
            incomingRecord: rawIncoming,
            diffs: diffs,
            riskReasons: riskReasons,
            accepted: false,
          ),
        );
      } else {
        proposals.add(
          ChangeProposal(
            recordId: rawId,
            status: ProposalStatus.changed,
            existingRecord: existing,
            incomingRecord: rawIncoming,
            diffs: diffs,
            riskReasons: const [],
            accepted: true,
          ),
        );
      }
    }

    return proposals;
  }

  BatchSnapshot commitProposals({
    required Map<String, Map<String, dynamic>> liveStoreById,
    required List<ChangeProposal> proposals,
    required String actorId,
    required ChangeSource source,
    required String label,
  }) {
    final batchId = generateBatchId(source.name);
    final now = DateTime.now().toUtc();
    final previousFieldValuesById = <String, Map<String, dynamic>>{};
    final updatedRecordIds = <String>[];

    for (final p in proposals) {
      if (!p.accepted || p.recordId.isEmpty) continue;

      if (p.status == ProposalStatus.newRecord) {
        final created = Map<String, dynamic>.from(p.incomingRecord)
          ..['last_batch_id'] = batchId
          ..['updated_at'] = now.toIso8601String()
          ..['updated_by'] = actorId
          ..['update_source'] = source.name;
        liveStoreById[p.recordId] = created;
        previousFieldValuesById[p.recordId] = <String, dynamic>{};
        updatedRecordIds.add(p.recordId);

        _auditLogs.add(
          AuditEntry(
            auditId: 'aud_${now.microsecondsSinceEpoch}_${p.recordId}',
            batchId: batchId,
            recordId: p.recordId,
            actorId: actorId,
            source: source,
            timestamp: now,
            summary: 'Created new record via ${source.name}',
            changes: const {},
          ),
        );
      } else if (p.diffs.isNotEmpty) {
        final current = Map<String, dynamic>.from(
          liveStoreById[p.recordId] ?? p.existingRecord ?? const {},
        );
        final priorSlice = <String, dynamic>{};
        final diffMap = <String, FieldDiff>{};

        for (final d in p.diffs) {
          priorSlice[d.field] = current[d.field];
          current[d.field] = d.after;
          diffMap[d.field] = d;
        }

        current['last_batch_id'] = batchId;
        current['updated_at'] = now.toIso8601String();
        current['updated_by'] = actorId;
        current['update_source'] = source.name;

        liveStoreById[p.recordId] = current;
        previousFieldValuesById[p.recordId] = priorSlice;
        updatedRecordIds.add(p.recordId);

        _auditLogs.add(
          AuditEntry(
            auditId: 'aud_${now.microsecondsSinceEpoch}_${p.recordId}',
            batchId: batchId,
            recordId: p.recordId,
            actorId: actorId,
            source: source,
            timestamp: now,
            summary: 'Updated ${p.diffs.length} field(s) via ${source.name}',
            changes: diffMap,
          ),
        );
      }
    }

    final snapshot = BatchSnapshot(
      batchId: batchId,
      createdAt: now,
      actorId: actorId,
      source: source,
      label: label,
      previousFieldValuesById: previousFieldValuesById,
      updatedRecordIds: updatedRecordIds,
    );
    _batches.add(snapshot);
    return snapshot;
  }

  int rollbackBatch({
    required String batchId,
    required Map<String, Map<String, dynamic>> liveStoreById,
    required String actorId,
  }) {
    final idx = _batches.indexWhere((b) => b.batchId == batchId);
    if (idx == -1) return 0;

    final snap = _batches[idx];
    if (!snap.canRollback) return 0;

    final now = DateTime.now().toUtc();
    var restoredCount = 0;

    snap.previousFieldValuesById.forEach((recordId, priorFields) {
      if (priorFields.isEmpty) {
        if (liveStoreById.remove(recordId) != null) {
          restoredCount++;
          _auditLogs.add(
            AuditEntry(
              auditId: 'rb_${now.microsecondsSinceEpoch}_$recordId',
              batchId: batchId,
              recordId: recordId,
              actorId: actorId,
              source: ChangeSource.rollback,
              timestamp: now,
              summary: 'Rolled back new record created in batch $batchId',
              changes: const {},
            ),
          );
        }
        return;
      }

      final current = liveStoreById[recordId];
      if (current == null) return;

      final diffMap = <String, FieldDiff>{};
      priorFields.forEach((field, priorVal) {
        diffMap[field] = FieldDiff(field: field, before: current[field], after: priorVal);
        current[field] = priorVal;
      });
      current['rolled_back_from_batch'] = batchId;
      current['updated_at'] = now.toIso8601String();
      current['updated_by'] = actorId;
      current['update_source'] = ChangeSource.rollback.name;
      liveStoreById[recordId] = current;
      restoredCount++;

      _auditLogs.add(
        AuditEntry(
          auditId: 'rb_${now.microsecondsSinceEpoch}_$recordId',
          batchId: batchId,
          recordId: recordId,
          actorId: actorId,
          source: ChangeSource.rollback,
          timestamp: now,
          summary: 'Restored ${priorFields.length} field(s) from batch $batchId',
          changes: diffMap,
        ),
      );
    });

    snap.rolledBackAt = now;
    return restoredCount;
  }
}
