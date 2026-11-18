import '../utils/indian_formatters.dart';

enum InstallmentStatus {
  upcoming('UPCOMING', 'Upcoming'),
  dueToday('DUE_TODAY', 'Due Today'),
  partial('PARTIAL', 'Partial'),
  paid('PAID', 'Paid'),
  overdue('OVERDUE', 'Overdue'),
  superseded('SUPERSEDED', 'Superseded');

  const InstallmentStatus(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static InstallmentStatus fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return InstallmentStatus.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => InstallmentStatus.upcoming,
    );
  }
}

/// Table 4: `installment_schedule` — Versioned amortization schedule rows.
class InstallmentModel {
  const InstallmentModel({
    required this.installmentId,
    required this.loanId,
    required this.scheduleVersion,
    required this.installmentNo,
    required this.dueDate,
    required this.openingPrincipal,
    required this.principalDue,
    required this.interestDue,
    this.feeDue = 0.0,
    required this.totalDue,
    this.principalPaid = 0.0,
    this.interestPaid = 0.0,
    this.feePaid = 0.0,
    this.paidDate,
    this.status = InstallmentStatus.upcoming,
  });

  final String installmentId;
  final String loanId;
  final int scheduleVersion;
  final int installmentNo;
  final DateTime dueDate;
  final double openingPrincipal;
  final double principalDue;
  final double interestDue;
  final double feeDue;
  final double totalDue;
  final double principalPaid;
  final double interestPaid;
  final double feePaid;
  final DateTime? paidDate;
  final InstallmentStatus status;

  double get feeRemaining =>
      IndianFormatters.roundPaise((feeDue - feePaid).clamp(0, double.infinity));

  double get interestRemaining => IndianFormatters.roundPaise(
        (interestDue - interestPaid).clamp(0, double.infinity),
      );

  double get principalRemaining => IndianFormatters.roundPaise(
        (principalDue - principalPaid).clamp(0, double.infinity),
      );

  double get totalRemaining => IndianFormatters.roundPaise(
        feeRemaining + interestRemaining + principalRemaining,
      );

  bool get isFullyPaid => totalRemaining <= 0.01;

  InstallmentModel copyWith({
    String? installmentId,
    String? loanId,
    int? scheduleVersion,
    int? installmentNo,
    DateTime? dueDate,
    double? openingPrincipal,
    double? principalDue,
    double? interestDue,
    double? feeDue,
    double? totalDue,
    double? principalPaid,
    double? interestPaid,
    double? feePaid,
    DateTime? paidDate,
    bool clearPaidDate = false,
    InstallmentStatus? status,
  }) {
    return InstallmentModel(
      installmentId: installmentId ?? this.installmentId,
      loanId: loanId ?? this.loanId,
      scheduleVersion: scheduleVersion ?? this.scheduleVersion,
      installmentNo: installmentNo ?? this.installmentNo,
      dueDate: dueDate ?? this.dueDate,
      openingPrincipal: openingPrincipal ?? this.openingPrincipal,
      principalDue: principalDue ?? this.principalDue,
      interestDue: interestDue ?? this.interestDue,
      feeDue: feeDue ?? this.feeDue,
      totalDue: totalDue ?? this.totalDue,
      principalPaid: principalPaid ?? this.principalPaid,
      interestPaid: interestPaid ?? this.interestPaid,
      feePaid: feePaid ?? this.feePaid,
      paidDate: clearPaidDate ? null : (paidDate ?? this.paidDate),
      status: status ?? this.status,
    );
  }

  factory InstallmentModel.fromMap(Map<String, dynamic> map, {String? id}) {
    return InstallmentModel(
      installmentId: id ?? (map['installment_id'] as String? ?? ''),
      loanId: map['loan_id'] as String? ?? '',
      scheduleVersion: (map['schedule_version'] as num?)?.toInt() ?? 1,
      installmentNo: (map['installment_no'] as num?)?.toInt() ?? 1,
      dueDate: IndianFormatters.parseDate(map['due_date']),
      openingPrincipal: (map['opening_principal'] as num?)?.toDouble() ?? 0.0,
      principalDue: (map['principal_due'] as num?)?.toDouble() ?? 0.0,
      interestDue: (map['interest_due'] as num?)?.toDouble() ?? 0.0,
      feeDue: (map['fee_due'] as num?)?.toDouble() ?? 0.0,
      totalDue: (map['total_due'] as num?)?.toDouble() ?? 0.0,
      principalPaid: (map['principal_paid'] as num?)?.toDouble() ?? 0.0,
      interestPaid: (map['interest_paid'] as num?)?.toDouble() ?? 0.0,
      feePaid: (map['fee_paid'] as num?)?.toDouble() ?? 0.0,
      paidDate: IndianFormatters.parseNullableDate(map['paid_date']),
      status: InstallmentStatus.fromString(map['status'] as String?),
    );
  }

  Map<String, dynamic> toMap() => {
        'installment_id': installmentId,
        'loan_id': loanId,
        'schedule_version': scheduleVersion,
        'installment_no': installmentNo,
        'due_date': dueDate.toIso8601String(),
        'opening_principal': openingPrincipal,
        'principal_due': principalDue,
        'interest_due': interestDue,
        'fee_due': feeDue,
        'total_due': totalDue,
        'principal_paid': principalPaid,
        'interest_paid': interestPaid,
        'fee_paid': feePaid,
        'paid_date': paidDate?.toIso8601String(),
        'status': status.wireValue,
      };
}
