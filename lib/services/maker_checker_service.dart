import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'audit_service.dart';

enum MakerCheckerStatus { pending, approved, rejected }

class MakerCheckerRequest {
  MakerCheckerRequest({
    required this.id,
    required this.actionType,
    required this.targetId,
    required this.amountInr,
    required this.reason,
    required this.makerUid,
    required this.makerEmail,
    required this.createdAtIso,
    this.status = MakerCheckerStatus.pending,
    this.checkerUid,
    this.checkerEmail,
    this.checkerNote,
    this.decidedAtIso,
  });

  final String id;
  final String actionType;
  final String targetId;
  final double amountInr;
  final String reason;
  final String makerUid;
  final String makerEmail;
  final String createdAtIso;
  MakerCheckerStatus status;
  String? checkerUid;
  String? checkerEmail;
  String? checkerNote;
  String? decidedAtIso;

  Map<String, dynamic> toMap() => {
        'id': id,
        'action_type': actionType,
        'target_id': targetId,
        'amount_inr': amountInr,
        'reason': reason,
        'maker_uid': makerUid,
        'maker_email': makerEmail,
        'created_at_iso': createdAtIso,
        'status': status.name,
        'checker_uid': checkerUid,
        'checker_email': checkerEmail,
        'checker_note': checkerNote,
        'decided_at_iso': decidedAtIso,
        'updated_at': FieldValue.serverTimestamp(),
      };
}

/// Manages Maker-Checker approval requests for sensitive financial adjustments
/// and prevents a Maker from approving their own request (four-eyes check).
class MakerCheckerService extends ChangeNotifier {
  MakerCheckerService({
    required this.useFirebase,
    AuditService? auditService,
  }) : _auditService = auditService;

  final bool useFirebase;
  final AuditService? _auditService;
  final List<MakerCheckerRequest> _requests = [];

  List<MakerCheckerRequest> get requests => List.unmodifiable(_requests);

  List<MakerCheckerRequest> get pendingRequests =>
      _requests.where((r) => r.status == MakerCheckerStatus.pending).toList();

  Future<MakerCheckerRequest> submitRequest({
    required AppUser maker,
    required String actionType,
    required String targetId,
    required double amountInr,
    required String reason,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final req = MakerCheckerRequest(
      id: 'MC-${DateTime.now().millisecondsSinceEpoch}',
      actionType: actionType,
      targetId: targetId,
      amountInr: amountInr,
      reason: reason.trim(),
      makerUid: maker.uid,
      makerEmail: maker.email,
      createdAtIso: nowIso,
    );

    _requests.insert(0, req);
    notifyListeners();

    if (useFirebase) {
      try {
        await FirebaseFirestore.instance
            .collection('maker_checker_requests')
            .doc(req.id)
            .set(req.toMap(), SetOptions(merge: true));
      } catch (_) {}
    }

    await _auditService?.record(
      actor: maker,
      action: 'MAKER_SUBMIT_$actionType',
      targetType: 'maker_checker_requests',
      targetId: req.id,
      details: 'target=$targetId, amount=$amountInr, reason=${req.reason}',
    );

    return req;
  }

  Future<String?> decideRequest({
    required AppUser checker,
    required String requestId,
    required bool approve,
    String? note,
  }) async {
    if (!checker.isAdminOrAbove) {
      return 'Only managers or administrators can act as Checker.';
    }

    final idx = _requests.indexWhere((r) => r.id == requestId);
    if (idx < 0) return 'Approval request not found.';

    final item = _requests[idx];
    if (item.status != MakerCheckerStatus.pending) {
      return 'Request has already been ${item.status.name}.';
    }

    // Four-eyes rule: Maker cannot approve/reject their own request unless Super Admin override
    if (item.makerUid == checker.uid && !checker.isSuperAdmin) {
      return 'Four-eyes policy: Maker cannot approve their own request.';
    }

    item.status = approve ? MakerCheckerStatus.approved : MakerCheckerStatus.rejected;
    item.checkerUid = checker.uid;
    item.checkerEmail = checker.email;
    item.checkerNote = note?.trim();
    item.decidedAtIso = DateTime.now().toUtc().toIso8601String();
    notifyListeners();

    if (useFirebase) {
      try {
        await FirebaseFirestore.instance
            .collection('maker_checker_requests')
            .doc(item.id)
            .set(item.toMap(), SetOptions(merge: true));
      } catch (_) {}
    }

    await _auditService?.record(
      actor: checker,
      action: approve ? 'CHECKER_APPROVE_${item.actionType}' : 'CHECKER_REJECT_${item.actionType}',
      targetType: 'maker_checker_requests',
      targetId: item.id,
      details: 'target=${item.targetId}, note=${item.checkerNote ?? ""}',
    );

    return null;
  }
}
