import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actorUid,
    required this.actorEmail,
    required this.actorRole,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.details,
    required this.timestampIso,
  });

  final String id;
  final String actorUid;
  final String actorEmail;
  final String actorRole;
  final String action;
  final String targetType;
  final String targetId;
  final String details;
  final String timestampIso;

  Map<String, dynamic> toMap() => {
        'actor_uid': actorUid,
        'actor_email': actorEmail,
        'actor_role': actorRole,
        'action': action,
        'target_type': targetType,
        'target_id': targetId,
        'details': details,
        'timestamp_iso': timestampIso,
        'created_at': FieldValue.serverTimestamp(),
      };
}

/// Records immutable audit entries to Firestore `audit_logs` (or local buffer in sandbox).
class AuditService extends ChangeNotifier {
  AuditService({required this.useFirebase});

  final bool useFirebase;
  final List<AuditEntry> _recentLogs = [];

  List<AuditEntry> get recentLogs => List.unmodifiable(_recentLogs);

  Future<void> record({
    required AppUser? actor,
    required String action,
    required String targetType,
    required String targetId,
    required String details,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final entry = AuditEntry(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      actorUid: actor?.uid ?? 'anonymous',
      actorEmail: actor?.email ?? 'unknown',
      actorRole: actor?.role.wireValue ?? 'NONE',
      action: action,
      targetType: targetType,
      targetId: targetId,
      details: details,
      timestampIso: nowIso,
    );
    _recentLogs.insert(0, entry);
    if (_recentLogs.length > 100) {
      _recentLogs.removeRange(100, _recentLogs.length);
    }
    notifyListeners();

    if (!useFirebase) return;
    try {
      await FirebaseFirestore.instance.collection('audit_logs').add(entry.toMap());
    } catch (_) {
      // Avoid breaking primary workflow if audit write fails offline.
    }
  }
}
