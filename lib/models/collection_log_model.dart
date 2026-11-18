import '../utils/indian_formatters.dart';

enum CollectionActionType {
  call('CALL', 'Phone Call'),
  fieldVisit('FIELD_VISIT', 'Field Visit'),
  whatsappReminder('WHATSAPP_REMINDER', 'WhatsApp Reminder'),
  legalNotice('LEGAL_NOTICE', 'Legal Notice');

  const CollectionActionType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static CollectionActionType fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return CollectionActionType.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => CollectionActionType.call,
    );
  }
}

enum CollectionDisposition {
  ptpConfirmed('PTP_CONFIRMED', 'PTP Confirmed'),
  partialCollected('PARTIAL_COLLECTED', 'Partial Collected'),
  refusedToPay('REFUSED_TO_PAY', 'Refused to Pay'),
  customerUnavailable('CUSTOMER_UNAVAILABLE', 'Customer Unavailable'),
  wrongAddress('WRONG_ADDRESS', 'Wrong Address'),
  dispute('DISPUTE', 'Dispute');

  const CollectionDisposition(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static CollectionDisposition fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return CollectionDisposition.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => CollectionDisposition.customerUnavailable,
    );
  }
}

enum PtpStatus {
  open('OPEN', 'Open PTP'),
  kept('KEPT', 'Kept'),
  broken('BROKEN', 'Broken PTP'),
  notApplicable('NOT_APPLICABLE', 'N/A');

  const PtpStatus(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static PtpStatus fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return PtpStatus.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => PtpStatus.notApplicable,
    );
  }
}

/// Table 6: `collection_logs` — Field visit & tele-calling CRM with geo-stamped PTP tracking.
class CollectionLogModel {
  const CollectionLogModel({
    required this.logId,
    required this.loanId,
    required this.borrowerId,
    required this.agentId,
    required this.actionType,
    required this.disposition,
    this.ptpDate,
    this.ptpAmount,
    this.ptpStatus = PtpStatus.notApplicable,
    this.visitLat,
    this.visitLng,
    required this.notes,
    required this.nextFollowupAt,
    required this.createdAt,
  });

  final String logId;
  final String loanId;
  final String borrowerId;
  final String agentId;
  final CollectionActionType actionType;
  final CollectionDisposition disposition;
  final DateTime? ptpDate;
  final double? ptpAmount;
  final PtpStatus ptpStatus;
  final double? visitLat;
  final double? visitLng;
  final String notes;
  final DateTime nextFollowupAt;
  final DateTime createdAt;

  CollectionLogModel copyWith({
    String? logId,
    String? loanId,
    String? borrowerId,
    String? agentId,
    CollectionActionType? actionType,
    CollectionDisposition? disposition,
    DateTime? ptpDate,
    double? ptpAmount,
    PtpStatus? ptpStatus,
    double? visitLat,
    double? visitLng,
    String? notes,
    DateTime? nextFollowupAt,
    DateTime? createdAt,
  }) {
    return CollectionLogModel(
      logId: logId ?? this.logId,
      loanId: loanId ?? this.loanId,
      borrowerId: borrowerId ?? this.borrowerId,
      agentId: agentId ?? this.agentId,
      actionType: actionType ?? this.actionType,
      disposition: disposition ?? this.disposition,
      ptpDate: ptpDate ?? this.ptpDate,
      ptpAmount: ptpAmount ?? this.ptpAmount,
      ptpStatus: ptpStatus ?? this.ptpStatus,
      visitLat: visitLat ?? this.visitLat,
      visitLng: visitLng ?? this.visitLng,
      notes: notes ?? this.notes,
      nextFollowupAt: nextFollowupAt ?? this.nextFollowupAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory CollectionLogModel.fromMap(Map<String, dynamic> map, {String? id}) {
    return CollectionLogModel(
      logId: id ?? (map['log_id'] as String? ?? ''),
      loanId: map['loan_id'] as String? ?? '',
      borrowerId: map['borrower_id'] as String? ?? '',
      agentId: map['agent_id'] as String? ?? '',
      actionType: CollectionActionType.fromString(map['action_type'] as String?),
      disposition:
          CollectionDisposition.fromString(map['disposition'] as String?),
      ptpDate: IndianFormatters.parseNullableDate(map['ptp_date']),
      ptpAmount: (map['ptp_amount'] as num?)?.toDouble(),
      ptpStatus: PtpStatus.fromString(map['ptp_status'] as String?),
      visitLat: (map['visit_lat'] as num?)?.toDouble(),
      visitLng: (map['visit_lng'] as num?)?.toDouble(),
      notes: map['notes'] as String? ?? '',
      nextFollowupAt: IndianFormatters.parseDate(map['next_followup_at']),
      createdAt: IndianFormatters.parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'log_id': logId,
        'loan_id': loanId,
        'borrower_id': borrowerId,
        'agent_id': agentId,
        'action_type': actionType.wireValue,
        'disposition': disposition.wireValue,
        'ptp_date': ptpDate?.toIso8601String(),
        'ptp_amount': ptpAmount,
        'ptp_status': ptpStatus.wireValue,
        'visit_lat': visitLat,
        'visit_lng': visitLng,
        'notes': notes,
        'next_followup_at': nextFollowupAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}
