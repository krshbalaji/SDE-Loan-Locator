import '../utils/indian_formatters.dart';

enum TransactionType {
  disbursement('DISBURSEMENT', 'Disbursement'),
  repayment('REPAYMENT', 'Repayment'),
  prepayment('PREPAYMENT', 'Prepayment'),
  lateFeeAssessed('LATE_FEE_ASSESSED', 'Late Fee Assessed'),
  waiver('WAIVER', 'Waiver'),
  reversal('REVERSAL', 'Reversal'),
  writeOff('WRITE_OFF', 'Write-Off'),
  recovery('RECOVERY', 'Recovery');

  const TransactionType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static TransactionType fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return TransactionType.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => TransactionType.repayment,
    );
  }
}

enum PaymentMode {
  upi('UPI', 'UPI'),
  neftRtgs('NEFT_RTGS', 'NEFT / RTGS'),
  enach('ENACH', 'e-NACH'),
  cash('CASH', 'Cash'),
  cheque('CHEQUE', 'Cheque'),
  systemAuto('SYSTEM_AUTO', 'System Auto');

  const PaymentMode(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static PaymentMode fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return PaymentMode.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => PaymentMode.upi,
    );
  }
}

/// Table 5: `transactions` — Immutable append-only financial ledger.
/// Reversals insert a contra-entry referencing `reversedTxnId`.
class TransactionModel {
  const TransactionModel({
    required this.txnId,
    required this.loanId,
    required this.borrowerId,
    required this.txnType,
    required this.paymentMode,
    required this.referenceNo,
    required this.totalAmount,
    this.allocatedFees = 0.0,
    this.allocatedInterest = 0.0,
    this.allocatedPrincipal = 0.0,
    this.reversedTxnId,
    required this.collectedByUid,
    this.geoLat,
    this.geoLng,
    this.receiptPdfUrl,
    this.notes,
    required this.createdAt,
  });

  final String txnId;
  final String loanId;
  final String borrowerId;
  final TransactionType txnType;
  final PaymentMode paymentMode;
  final String referenceNo;
  final double totalAmount;
  final double allocatedFees;
  final double allocatedInterest;
  final double allocatedPrincipal;
  final String? reversedTxnId;
  final String collectedByUid;
  final double? geoLat;
  final double? geoLng;
  final String? receiptPdfUrl;
  final String? notes;
  final DateTime createdAt;

  bool get isCreditToLoan =>
      txnType == TransactionType.repayment ||
      txnType == TransactionType.prepayment ||
      txnType == TransactionType.recovery;

  factory TransactionModel.fromMap(Map<String, dynamic> map, {String? id}) {
    return TransactionModel(
      txnId: id ?? (map['txn_id'] as String? ?? ''),
      loanId: map['loan_id'] as String? ?? '',
      borrowerId: map['borrower_id'] as String? ?? '',
      txnType: TransactionType.fromString(map['txn_type'] as String?),
      paymentMode: PaymentMode.fromString(map['payment_mode'] as String?),
      referenceNo: map['reference_no'] as String? ?? '',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      allocatedFees: (map['allocated_fees'] as num?)?.toDouble() ?? 0.0,
      allocatedInterest: (map['allocated_interest'] as num?)?.toDouble() ?? 0.0,
      allocatedPrincipal: (map['allocated_principal'] as num?)?.toDouble() ?? 0.0,
      reversedTxnId: map['reversed_txn_id'] as String?,
      collectedByUid: map['collected_by_uid'] as String? ?? '',
      geoLat: (map['geo_lat'] as num?)?.toDouble(),
      geoLng: (map['geo_lng'] as num?)?.toDouble(),
      receiptPdfUrl: map['receipt_pdf_url'] as String?,
      notes: map['notes'] as String?,
      createdAt: IndianFormatters.parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'txn_id': txnId,
        'loan_id': loanId,
        'borrower_id': borrowerId,
        'txn_type': txnType.wireValue,
        'payment_mode': paymentMode.wireValue,
        'reference_no': referenceNo,
        'total_amount': totalAmount,
        'allocated_fees': allocatedFees,
        'allocated_interest': allocatedInterest,
        'allocated_principal': allocatedPrincipal,
        'reversed_txn_id': reversedTxnId,
        'collected_by_uid': collectedByUid,
        'geo_lat': geoLat,
        'geo_lng': geoLng,
        'receipt_pdf_url': receiptPdfUrl,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
      };
}
