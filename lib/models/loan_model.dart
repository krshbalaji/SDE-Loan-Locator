import '../utils/indian_formatters.dart';
import 'loan_product_model.dart';

enum AgingBucket {
  current('CURRENT', 'Current (0 DPD)'),
  dpd1To30('DPD_1_30', '1-30 DPD'),
  dpd31To60('DPD_31_60', '31-60 DPD'),
  dpd61To90('DPD_61_90', '61-90 DPD'),
  dpd90Plus('DPD_90_PLUS', '90+ DPD (NPA)');

  const AgingBucket(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static AgingBucket fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return AgingBucket.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => AgingBucket.current,
    );
  }

  static AgingBucket fromDpd(int dpd) {
    if (dpd <= 0) return AgingBucket.current;
    if (dpd <= 30) return AgingBucket.dpd1To30;
    if (dpd <= 60) return AgingBucket.dpd31To60;
    if (dpd <= 90) return AgingBucket.dpd61To90;
    return AgingBucket.dpd90Plus;
  }
}

enum LoanStatus {
  pendingApproval('PENDING_APPROVAL', 'Pending Approval'),
  active('ACTIVE', 'Active'),
  delinquent('DELINQUENT', 'Delinquent'),
  restructured('RESTRUCTURED', 'Restructured'),
  closed('CLOSED', 'Closed'),
  writtenOff('WRITTEN_OFF', 'Written Off');

  const LoanStatus(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static LoanStatus fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return LoanStatus.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => LoanStatus.active,
    );
  }
}

/// Table 3: `loans` — Master loan account record.
class LoanModel {
  const LoanModel({
    required this.loanId,
    required this.applicationNo,
    required this.borrowerId,
    required this.productId,
    required this.assignedAgentId,
    required this.principalSanctioned,
    required this.processingFeeAmount,
    required this.gstAmount,
    required this.netDisbursedAmount,
    required this.interestRateAnnual,
    required this.interestMethod,
    this.repaymentFrequency = RepaymentFrequency.monthly,
    required this.tenureInstallments,
    required this.emiAmount,
    required this.disbursementDate,
    required this.firstDueDate,
    required this.maturityDate,
    this.scheduleVersion = 1,
    required this.principalOutstanding,
    this.interestOutstanding = 0.0,
    this.feesOutstanding = 0.0,
    this.dpd = 0,
    this.agingBucket = AgingBucket.current,
    this.status = LoanStatus.active,
    this.earlyWarningFlag = false,
    this.monthsOnBooks,
    this.ltvPct,
    this.foirPct,
    this.assetClassification,
    this.lastPaidDate,
  });

  final String loanId;
  final String applicationNo;
  final String borrowerId;
  final String productId;
  final String assignedAgentId;
  final double principalSanctioned;
  final double processingFeeAmount;
  final double gstAmount;
  final double netDisbursedAmount;
  final double interestRateAnnual;
  final InterestMethod interestMethod;
  final RepaymentFrequency repaymentFrequency;
  final int tenureInstallments;
  final double emiAmount;
  final DateTime disbursementDate;
  final DateTime firstDueDate;
  final DateTime maturityDate;
  final int scheduleVersion;
  final double principalOutstanding;
  final double interestOutstanding;
  final double feesOutstanding;
  final int dpd;
  final AgingBucket agingBucket;
  final LoanStatus status;
  final bool earlyWarningFlag;
  final int? monthsOnBooks;
  final double? ltvPct;
  final double? foirPct;
  final String? assetClassification;
  final DateTime? lastPaidDate;

  double get totalOutstanding => IndianFormatters.roundPaise(
        principalOutstanding + interestOutstanding + feesOutstanding,
      );

  bool get isPortfolioActive =>
      status == LoanStatus.active ||
      status == LoanStatus.delinquent ||
      status == LoanStatus.restructured;

  LoanModel copyWith({
    String? loanId,
    String? applicationNo,
    String? borrowerId,
    String? productId,
    String? assignedAgentId,
    double? principalSanctioned,
    double? processingFeeAmount,
    double? gstAmount,
    double? netDisbursedAmount,
    double? interestRateAnnual,
    InterestMethod? interestMethod,
    RepaymentFrequency? repaymentFrequency,
    int? tenureInstallments,
    double? emiAmount,
    DateTime? disbursementDate,
    DateTime? firstDueDate,
    DateTime? maturityDate,
    int? scheduleVersion,
    double? principalOutstanding,
    double? interestOutstanding,
    double? feesOutstanding,
    int? dpd,
    AgingBucket? agingBucket,
    LoanStatus? status,
    bool? earlyWarningFlag,
    int? monthsOnBooks,
    double? ltvPct,
    double? foirPct,
    String? assetClassification,
    DateTime? lastPaidDate,
  }) {
    return LoanModel(
      loanId: loanId ?? this.loanId,
      applicationNo: applicationNo ?? this.applicationNo,
      borrowerId: borrowerId ?? this.borrowerId,
      productId: productId ?? this.productId,
      assignedAgentId: assignedAgentId ?? this.assignedAgentId,
      principalSanctioned: principalSanctioned ?? this.principalSanctioned,
      processingFeeAmount: processingFeeAmount ?? this.processingFeeAmount,
      gstAmount: gstAmount ?? this.gstAmount,
      netDisbursedAmount: netDisbursedAmount ?? this.netDisbursedAmount,
      interestRateAnnual: interestRateAnnual ?? this.interestRateAnnual,
      interestMethod: interestMethod ?? this.interestMethod,
      repaymentFrequency: repaymentFrequency ?? this.repaymentFrequency,
      tenureInstallments: tenureInstallments ?? this.tenureInstallments,
      emiAmount: emiAmount ?? this.emiAmount,
      disbursementDate: disbursementDate ?? this.disbursementDate,
      firstDueDate: firstDueDate ?? this.firstDueDate,
      maturityDate: maturityDate ?? this.maturityDate,
      scheduleVersion: scheduleVersion ?? this.scheduleVersion,
      principalOutstanding: principalOutstanding ?? this.principalOutstanding,
      interestOutstanding: interestOutstanding ?? this.interestOutstanding,
      feesOutstanding: feesOutstanding ?? this.feesOutstanding,
      dpd: dpd ?? this.dpd,
      agingBucket: agingBucket ?? this.agingBucket,
      status: status ?? this.status,
      earlyWarningFlag: earlyWarningFlag ?? this.earlyWarningFlag,
      monthsOnBooks: monthsOnBooks ?? this.monthsOnBooks,
      ltvPct: ltvPct ?? this.ltvPct,
      foirPct: foirPct ?? this.foirPct,
      assetClassification: assetClassification ?? this.assetClassification,
      lastPaidDate: lastPaidDate ?? this.lastPaidDate,
    );
  }

  factory LoanModel.fromMap(Map<String, dynamic> map, {String? id}) {
    return LoanModel(
      loanId: id ?? (map['loan_id'] as String? ?? ''),
      applicationNo: map['application_no'] as String? ?? '',
      borrowerId: map['borrower_id'] as String? ?? '',
      productId: map['product_id'] as String? ?? '',
      assignedAgentId: map['assigned_agent_id'] as String? ?? '',
      principalSanctioned: (map['principal_sanctioned'] as num?)?.toDouble() ?? 0.0,
      processingFeeAmount: (map['processing_fee_amount'] as num?)?.toDouble() ?? 0.0,
      gstAmount: (map['gst_amount'] as num?)?.toDouble() ?? 0.0,
      netDisbursedAmount: (map['net_disbursed_amount'] as num?)?.toDouble() ?? 0.0,
      interestRateAnnual: (map['interest_rate_annual'] as num?)?.toDouble() ?? 18.0,
      interestMethod: InterestMethod.fromString(map['interest_method'] as String?),
      repaymentFrequency:
          RepaymentFrequency.fromString(map['repayment_frequency'] as String?),
      tenureInstallments: (map['tenure_installments'] as num?)?.toInt() ?? 12,
      emiAmount: (map['emi_amount'] as num?)?.toDouble() ?? 0.0,
      disbursementDate: IndianFormatters.parseDate(map['disbursement_date']),
      firstDueDate: IndianFormatters.parseDate(map['first_due_date']),
      maturityDate: IndianFormatters.parseDate(map['maturity_date']),
      scheduleVersion: (map['schedule_version'] as num?)?.toInt() ?? 1,
      principalOutstanding:
          (map['principal_outstanding'] as num?)?.toDouble() ?? 0.0,
      interestOutstanding:
          (map['interest_outstanding'] as num?)?.toDouble() ?? 0.0,
      feesOutstanding: (map['fees_outstanding'] as num?)?.toDouble() ?? 0.0,
      dpd: (map['dpd'] as num?)?.toInt() ?? 0,
      agingBucket: AgingBucket.fromString(map['aging_bucket'] as String?),
      status: LoanStatus.fromString(map['status'] as String?),
      earlyWarningFlag: map['early_warning_flag'] as bool? ?? false,
      monthsOnBooks: (map['months_on_books'] as num?)?.toInt(),
      ltvPct: (map['ltv_pct'] as num?)?.toDouble(),
      foirPct: (map['foir_pct'] as num?)?.toDouble(),
      assetClassification: map['asset_classification'] as String?,
      lastPaidDate: map['last_paid_date'] != null
          ? IndianFormatters.parseDate(map['last_paid_date'])
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'loan_id': loanId,
        'application_no': applicationNo,
        'borrower_id': borrowerId,
        'product_id': productId,
        'assigned_agent_id': assignedAgentId,
        'principal_sanctioned': principalSanctioned,
        'processing_fee_amount': processingFeeAmount,
        'gst_amount': gstAmount,
        'net_disbursed_amount': netDisbursedAmount,
        'interest_rate_annual': interestRateAnnual,
        'interest_method': interestMethod.wireValue,
        'repayment_frequency': repaymentFrequency.wireValue,
        'tenure_installments': tenureInstallments,
        'emi_amount': emiAmount,
        'disbursement_date': disbursementDate.toIso8601String(),
        'first_due_date': firstDueDate.toIso8601String(),
        'maturity_date': maturityDate.toIso8601String(),
        'schedule_version': scheduleVersion,
        'principal_outstanding': principalOutstanding,
        'interest_outstanding': interestOutstanding,
        'fees_outstanding': feesOutstanding,
        'dpd': dpd,
        'aging_bucket': agingBucket.wireValue,
        'status': status.wireValue,
        'early_warning_flag': earlyWarningFlag,
        'months_on_books': monthsOnBooks,
        'ltv_pct': ltvPct,
        'foir_pct': foirPct,
        'asset_classification': assetClassification,
        'last_paid_date': lastPaidDate?.toIso8601String(),
      };
}
