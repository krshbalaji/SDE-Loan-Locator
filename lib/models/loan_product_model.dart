enum InterestMethod {
  reducingBalance('REDUCING_BALANCE', 'Reducing Balance'),
  flatRate('FLAT_RATE', 'Flat Rate');

  const InterestMethod(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static InterestMethod fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return InterestMethod.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => InterestMethod.reducingBalance,
    );
  }
}

enum RepaymentFrequency {
  daily('DAILY', 'Daily', 365),
  weekly('WEEKLY', 'Weekly', 52),
  monthly('MONTHLY', 'Monthly', 12);

  const RepaymentFrequency(this.wireValue, this.label, this.periodsPerYear);
  final String wireValue;
  final String label;
  final int periodsPerYear;

  static RepaymentFrequency fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return RepaymentFrequency.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => RepaymentFrequency.monthly,
    );
  }
}

enum LateFeeType {
  flatInr('FLAT_INR', 'Flat INR'),
  percentOverdue('PERCENT_OVERDUE', '% of Overdue');

  const LateFeeType(this.wireValue, this.label);
  final String wireValue;
  final String label;

  static LateFeeType fromString(String? value) {
    final normalized = (value ?? '').trim().toUpperCase();
    return LateFeeType.values.firstWhere(
      (e) => e.wireValue == normalized,
      orElse: () => LateFeeType.flatInr,
    );
  }
}

/// Table 2: `loan_products` — Reusable product templates controlling math & fee rules.
class LoanProductModel {
  const LoanProductModel({
    required this.productId,
    required this.productName,
    required this.interestMethod,
    required this.annualInterestRate,
    required this.repaymentFrequency,
    required this.maxTenureInstallments,
    this.minTenureInstallments = 1,
    this.minAnnualInterestRate,
    this.maxAnnualInterestRate,
    this.processingFeePct = 2.0,
    this.gstRatePct = 18.0,
    this.gracePeriodDays = 3,
    this.lateFeeType = LateFeeType.percentOverdue,
    this.lateFeeValue = 2.0,
    this.atRiskDpdThreshold = 30,
    this.isActive = true,
  });

  final String productId;
  final String productName;
  final InterestMethod interestMethod;
  final double annualInterestRate;
  final RepaymentFrequency repaymentFrequency;
  final int maxTenureInstallments;
  final int minTenureInstallments;
  final double? minAnnualInterestRate;
  final double? maxAnnualInterestRate;
  final double processingFeePct;
  final double gstRatePct;
  final int gracePeriodDays;
  final LateFeeType lateFeeType;
  final double lateFeeValue;
  final int atRiskDpdThreshold;
  final bool isActive;

  double get effectiveMinAnnualInterestRate {
    final v = minAnnualInterestRate ?? (annualInterestRate - 2.0);
    if (v < 1.0) return 1.0;
    if (v > 60.0) return 60.0;
    return v;
  }

  double get effectiveMaxAnnualInterestRate {
    final v = maxAnnualInterestRate ?? (annualInterestRate + 3.0);
    if (v < 1.0) return 1.0;
    if (v > 65.0) return 65.0;
    return v;
  }

  LoanProductModel copyWith({
    String? productId,
    String? productName,
    InterestMethod? interestMethod,
    double? annualInterestRate,
    RepaymentFrequency? repaymentFrequency,
    int? maxTenureInstallments,
    int? minTenureInstallments,
    double? minAnnualInterestRate,
    double? maxAnnualInterestRate,
    double? processingFeePct,
    double? gstRatePct,
    int? gracePeriodDays,
    LateFeeType? lateFeeType,
    double? lateFeeValue,
    int? atRiskDpdThreshold,
    bool? isActive,
  }) {
    return LoanProductModel(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      interestMethod: interestMethod ?? this.interestMethod,
      annualInterestRate: annualInterestRate ?? this.annualInterestRate,
      repaymentFrequency: repaymentFrequency ?? this.repaymentFrequency,
      maxTenureInstallments:
          maxTenureInstallments ?? this.maxTenureInstallments,
      minTenureInstallments:
          minTenureInstallments ?? this.minTenureInstallments,
      minAnnualInterestRate:
          minAnnualInterestRate ?? this.minAnnualInterestRate,
      maxAnnualInterestRate:
          maxAnnualInterestRate ?? this.maxAnnualInterestRate,
      processingFeePct: processingFeePct ?? this.processingFeePct,
      gstRatePct: gstRatePct ?? this.gstRatePct,
      gracePeriodDays: gracePeriodDays ?? this.gracePeriodDays,
      lateFeeType: lateFeeType ?? this.lateFeeType,
      lateFeeValue: lateFeeValue ?? this.lateFeeValue,
      atRiskDpdThreshold: atRiskDpdThreshold ?? this.atRiskDpdThreshold,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'interestMethod': interestMethod.name,
      'annualInterestRate': annualInterestRate,
      'repaymentFrequency': repaymentFrequency.name,
      'maxTenureInstallments': maxTenureInstallments,
      'minTenureInstallments': minTenureInstallments,
      'minAnnualInterestRate': minAnnualInterestRate,
      'maxAnnualInterestRate': maxAnnualInterestRate,
      'processingFeePct': processingFeePct,
      'gstRatePct': gstRatePct,
      'gracePeriodDays': gracePeriodDays,
      'lateFeeType': lateFeeType.name,
      'lateFeeValue': lateFeeValue,
      'atRiskDpdThreshold': atRiskDpdThreshold,
      'isActive': isActive,
    };
  }

  factory LoanProductModel.fromMap(Map<String, dynamic> map, {String? id}) {
    final methodName = map['interestMethod']?.toString() ?? 'reducingBalance';
    final method = InterestMethod.values.firstWhere(
      (e) => e.name == methodName,
      orElse: () => InterestMethod.reducingBalance,
    );
    final freqName = map['repaymentFrequency']?.toString() ?? 'monthly';
    final freq = RepaymentFrequency.values.firstWhere(
      (e) => e.name == freqName,
      orElse: () => RepaymentFrequency.monthly,
    );
    final lateName = map['lateFeeType']?.toString() ?? 'percentOverdue';
    final lateType = LateFeeType.values.firstWhere(
      (e) => e.name == lateName,
      orElse: () => LateFeeType.percentOverdue,
    );
    return LoanProductModel(
      productId: (id ?? map['productId'] ?? '').toString(),
      productName: (map['productName'] ?? 'Loan Product').toString(),
      interestMethod: method,
      annualInterestRate: (map['annualInterestRate'] as num?)?.toDouble() ?? 18.0,
      repaymentFrequency: freq,
      maxTenureInstallments: (map['maxTenureInstallments'] as num?)?.toInt() ?? 24,
      minTenureInstallments: (map['minTenureInstallments'] as num?)?.toInt() ?? 1,
      minAnnualInterestRate: (map['minAnnualInterestRate'] as num?)?.toDouble(),
      maxAnnualInterestRate: (map['maxAnnualInterestRate'] as num?)?.toDouble(),
      processingFeePct: (map['processingFeePct'] as num?)?.toDouble() ?? 2.0,
      gstRatePct: (map['gstRatePct'] as num?)?.toDouble() ?? 18.0,
      gracePeriodDays: (map['gracePeriodDays'] as num?)?.toInt() ?? 3,
      lateFeeType: lateType,
      lateFeeValue: (map['lateFeeValue'] as num?)?.toDouble() ?? 2.0,
      atRiskDpdThreshold: (map['atRiskDpdThreshold'] as num?)?.toInt() ?? 30,
      isActive: (map['isActive'] as bool?) ?? true,
    );
  }
}

/// Ready-to-use default NBFC product templates for Housing Finance, LAP,
/// and collections workflows. Use `.copyWith(...)` to customize per deal/branch.
class DefaultLoanProducts {
  static const List<LoanProductModel> catalog = [
    LoanProductModel(
      productId: 'PROD_HF_HL',
      productName: 'Housing Finance - Home Loan',
      interestMethod: InterestMethod.reducingBalance,
      annualInterestRate: 9.5,
      repaymentFrequency: RepaymentFrequency.monthly,
      maxTenureInstallments: 240,
      processingFeePct: 1.0,
      gstRatePct: 18.0,
      gracePeriodDays: 5,
      lateFeeType: LateFeeType.percentOverdue,
      lateFeeValue: 2.0,
      atRiskDpdThreshold: 30,
      isActive: true,
    ),
    LoanProductModel(
      productId: 'PROD_LAP_STD',
      productName: 'Loan Against Property - Standard LAP',
      interestMethod: InterestMethod.reducingBalance,
      annualInterestRate: 12.0,
      repaymentFrequency: RepaymentFrequency.monthly,
      maxTenureInstallments: 120,
      processingFeePct: 1.5,
      gstRatePct: 18.0,
      gracePeriodDays: 3,
      lateFeeType: LateFeeType.percentOverdue,
      lateFeeValue: 2.0,
      atRiskDpdThreshold: 30,
      isActive: true,
    ),
    LoanProductModel(
      productId: 'PROD_LAP_MICRO',
      productName: 'Micro-LAP - Small Business Term',
      interestMethod: InterestMethod.reducingBalance,
      annualInterestRate: 15.5,
      repaymentFrequency: RepaymentFrequency.monthly,
      maxTenureInstallments: 60,
      processingFeePct: 2.0,
      gstRatePct: 18.0,
      gracePeriodDays: 3,
      lateFeeType: LateFeeType.percentOverdue,
      lateFeeValue: 2.5,
      atRiskDpdThreshold: 15,
      isActive: true,
    ),
    LoanProductModel(
      productId: 'PROD_COLL_DAILY',
      productName: 'Short-Cycle Collections Facility',
      interestMethod: InterestMethod.flatRate,
      annualInterestRate: 18.0,
      repaymentFrequency: RepaymentFrequency.daily,
      maxTenureInstallments: 180,
      processingFeePct: 2.0,
      gstRatePct: 18.0,
      gracePeriodDays: 1,
      lateFeeType: LateFeeType.flatInr,
      lateFeeValue: 250.0,
      atRiskDpdThreshold: 7,
      isActive: true,
    ),
  ];

  static LoanProductModel get primaryDefault => catalog[1];
}
