import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../engines/amortization_engine.dart';
import '../engines/delinquency_engine.dart';
import '../engines/geo_filter_engine.dart';
import '../models/borrower_model.dart';
import '../models/collection_log_model.dart';
import '../models/installment_model.dart';
import '../models/loan_model.dart';
import '../models/loan_product_model.dart';
import '../models/transaction_model.dart';
import '../utils/indian_formatters.dart';

/// Snapshot of all 6 relational collections in the lending & locator system.
class PortfolioSnapshot {
  const PortfolioSnapshot({
    required this.borrowers,
    required this.products,
    required this.loans,
    required this.installments,
    required this.transactions,
    required this.collectionLogs,
  });

  final List<BorrowerModel> borrowers;
  final List<LoanProductModel> products;
  final List<LoanModel> loans;
  final List<InstallmentModel> installments;
  final List<TransactionModel> transactions;
  final List<CollectionLogModel> collectionLogs;
}

/// Abstract repository for all 6 collections with atomic financial operations.
abstract class LoanDataRepository {
  Future<PortfolioSnapshot> loadAll();
  Future<void> saveBorrower(BorrowerModel borrower);
  Future<void> saveProduct(LoanProductModel product);

  /// Atomically creates `loans` + `installment_schedule` (v1) + `DISBURSEMENT` transaction.
  Future<void> originateLoan({
    required LoanModel loan,
    required List<InstallmentModel> initialSchedule,
    required TransactionModel disbursementTxn,
  });

  /// Atomically appends an immutable payment transaction, updates schedule & loan balances,
  /// and marks any open PTP for this loan as KEPT.
  Future<void> recordPaymentAtomic({
    required LoanModel updatedLoan,
    required List<InstallmentModel> updatedInstallments,
    required TransactionModel paymentTxn,
    required List<String> keptPtpLogIds,
  });

  /// Atomically appends a `REVERSAL` contra-entry linking `reversedTxnId` and restores balances.
  Future<void> recordReversalAtomic({
    required LoanModel restoredLoan,
    required List<InstallmentModel> restoredInstallments,
    required TransactionModel reversalTxn,
  });

  /// Atomically marks v1 rows `SUPERSEDED`, inserts v2 rows, and updates `loans`.
  Future<void> restructureLoanAtomic(RestructureResult result);

  /// Logs a field visit / tele-calling CRM entry.
  Future<void> addCollectionLog(CollectionLogModel log, {LoanModel? updatedLoan});

  /// Applies daily delinquency evaluation updates (DPD, bucket, early warning, broken PTPs).
  Future<void> applyDelinquencyUpdate({
    required LoanModel updatedLoan,
    required List<InstallmentModel> updatedInstallments,
    required List<String> brokenPtpLogIds,
    TransactionModel? lateFeeTxn,
  });
}

/// Production Cloud Firestore repository implementing the 6-collection schema.
class FirestoreLoanService implements LoanDataRepository {
  FirestoreLoanService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _borrowers =>
      _db.collection('borrowers');
  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('loan_products');
  CollectionReference<Map<String, dynamic>> get _loans =>
      _db.collection('loans');
  CollectionReference<Map<String, dynamic>> get _schedule =>
      _db.collection('installment_schedule');
  CollectionReference<Map<String, dynamic>> get _transactions =>
      _db.collection('transactions');
  CollectionReference<Map<String, dynamic>> get _logs =>
      _db.collection('collection_logs');

  @override
  Future<PortfolioSnapshot> loadAll() async {
    final results = await Future.wait([
      _borrowers.get(),
      _products.get(),
      _loans.get(),
      _schedule.get(),
      _transactions.orderBy('created_at', descending: true).get(),
      _logs.orderBy('created_at', descending: true).get(),
    ]);

    return PortfolioSnapshot(
      borrowers: results[0]
          .docs
          .map((d) => BorrowerModel.fromMap(d.data(), id: d.id))
          .toList(),
      products: results[1]
          .docs
          .map((d) => LoanProductModel.fromMap(d.data(), id: d.id))
          .toList(),
      loans: results[2]
          .docs
          .map((d) => LoanModel.fromMap(d.data(), id: d.id))
          .toList(),
      installments: results[3]
          .docs
          .map((d) => InstallmentModel.fromMap(d.data(), id: d.id))
          .toList(),
      transactions: results[4]
          .docs
          .map((d) => TransactionModel.fromMap(d.data(), id: d.id))
          .toList(),
      collectionLogs: results[5]
          .docs
          .map((d) => CollectionLogModel.fromMap(d.data(), id: d.id))
          .toList(),
    );
  }

  @override
  Future<void> saveBorrower(BorrowerModel borrower) async {
    final map = borrower.toMap()
      ..['created_at'] = Timestamp.fromDate(borrower.createdAt)
      ..['updated_at'] = Timestamp.fromDate(borrower.updatedAt);
    await _borrowers.doc(borrower.borrowerId).set(map, SetOptions(merge: true));
  }

  @override

  Future<void> saveProduct(LoanProductModel product) async {
    await _products
        .doc(product.productId)
        .set(product.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> originateLoan({
    required LoanModel loan,
    required List<InstallmentModel> initialSchedule,
    required TransactionModel disbursementTxn,
  }) async {
    final batch = _db.batch();
    batch.set(_loans.doc(loan.loanId), _loanToFirestore(loan));
    // Schedule rows are deterministically derived in-memory from loan terms + transactions
    batch.set(
      _transactions.doc(disbursementTxn.txnId),
      _txnToFirestore(disbursementTxn),
    );
    await batch.commit();
  }

  @override
  Future<void> recordPaymentAtomic({
    required LoanModel updatedLoan,
    required List<InstallmentModel> updatedInstallments,
    required TransactionModel paymentTxn,
    required List<String> keptPtpLogIds,
  }) async {
    final batch = _db.batch();
    batch.set(
      _transactions.doc(paymentTxn.txnId),
      _txnToFirestore(paymentTxn),
    );
    batch.set(_loans.doc(updatedLoan.loanId), _loanToFirestore(updatedLoan));
    for (final row in updatedInstallments) {
      batch.set(_schedule.doc(row.installmentId), _installmentToFirestore(row));
    }
    for (final logId in keptPtpLogIds) {
      batch.update(_logs.doc(logId), {'ptp_status': PtpStatus.kept.wireValue});
    }
    await batch.commit();
  }

  @override
  Future<void> recordReversalAtomic({
    required LoanModel restoredLoan,
    required List<InstallmentModel> restoredInstallments,
    required TransactionModel reversalTxn,
  }) async {
    final batch = _db.batch();
    batch.set(
      _transactions.doc(reversalTxn.txnId),
      _txnToFirestore(reversalTxn),
    );
    batch.set(_loans.doc(restoredLoan.loanId), _loanToFirestore(restoredLoan));
    for (final row in restoredInstallments) {
      batch.set(_schedule.doc(row.installmentId), _installmentToFirestore(row));
    }
    await batch.commit();
  }

  @override
  Future<void> restructureLoanAtomic(RestructureResult result) async {
    final batch = _db.batch();
    batch.set(
      _loans.doc(result.updatedLoan.loanId),
      _loanToFirestore(result.updatedLoan),
    );
    for (final oldRow in result.supersededInstallments) {
      batch.set(
        _schedule.doc(oldRow.installmentId),
        _installmentToFirestore(oldRow),
      );
    }
    for (final newRow in result.newVersionInstallments) {
      batch.set(
        _schedule.doc(newRow.installmentId),
        _installmentToFirestore(newRow),
      );
    }
    await batch.commit();
  }

  @override
  Future<void> addCollectionLog(
    CollectionLogModel log, {
    LoanModel? updatedLoan,
  }) async {
    final batch = _db.batch();
    batch.set(_logs.doc(log.logId), _logToFirestore(log));
    if (updatedLoan != null) {
      batch.set(_loans.doc(updatedLoan.loanId), _loanToFirestore(updatedLoan));
    }
    await batch.commit();
  }

  @override
  Future<void> applyDelinquencyUpdate({
    required LoanModel updatedLoan,
    required List<InstallmentModel> updatedInstallments,
    required List<String> brokenPtpLogIds,
    TransactionModel? lateFeeTxn,
  }) async {
    final batch = _db.batch();
    batch.set(_loans.doc(updatedLoan.loanId), _loanToFirestore(updatedLoan));
    for (final row in updatedInstallments) {
      batch.set(_schedule.doc(row.installmentId), _installmentToFirestore(row));
    }
    for (final id in brokenPtpLogIds) {
      batch.update(_logs.doc(id), {'ptp_status': PtpStatus.broken.wireValue});
    }
    if (lateFeeTxn != null) {
      batch.set(_transactions.doc(lateFeeTxn.txnId), _txnToFirestore(lateFeeTxn));
    }
    await batch.commit();
  }

  Map<String, dynamic> _loanToFirestore(LoanModel loan) => loan.toMap()
    ..['disbursement_date'] = Timestamp.fromDate(loan.disbursementDate)
    ..['first_due_date'] = Timestamp.fromDate(loan.firstDueDate)
    ..['maturity_date'] = Timestamp.fromDate(loan.maturityDate);

  Map<String, dynamic> _installmentToFirestore(InstallmentModel row) =>
      row.toMap()
        ..['due_date'] = Timestamp.fromDate(row.dueDate)
        ..['paid_date'] =
            row.paidDate != null ? Timestamp.fromDate(row.paidDate!) : null;

  Map<String, dynamic> _txnToFirestore(TransactionModel txn) => txn.toMap()
    ..['created_at'] = FieldValue.serverTimestamp();

  Map<String, dynamic> _logToFirestore(CollectionLogModel log) => log.toMap()
    ..['ptp_date'] =
        log.ptpDate != null ? Timestamp.fromDate(log.ptpDate!) : null
    ..['next_followup_at'] = Timestamp.fromDate(log.nextFollowupAt)
    ..['created_at'] = Timestamp.fromDate(log.createdAt);
}

/// Seeded in-memory repository for immediate offline / demo usage when Firebase
/// credentials are not yet configured.
class InMemoryDemoLoanService implements LoanDataRepository {
  void clearAllData() {
    _borrowers.clear();
    _products.clear();
    _loans.clear();
    _installments.clear();
    _transactions.clear();
    _logs.clear();
  }

  void seedSamplePortfolio() {
    if (_loans.isNotEmpty) return;
    final now = DateTime.now();
    const prod = LoanProductModel(
      productId: 'PROD_LAP_DEMO',
      productName: 'Loan Against Property (Demo)',
      interestMethod: InterestMethod.reducingBalance,
      annualInterestRate: 13.5,
      repaymentFrequency: RepaymentFrequency.monthly,
      maxTenureInstallments: 180,
      processingFeePct: 1.5,
      gstRatePct: 18.0,
    );
    _products[prod.productId] = prod;

    final b1 = BorrowerModel(
      borrowerId: 'BRW_DEMO_001',
      fullName: 'Bhagavati Demo (Hodal)',
      mobilePrimary: '9811100001',
      panNumber: 'ABCDE1234F',
      addressText: 'Main Market, Hodal, Haryana 121106',
      latitude: 27.8920,
      longitude: 77.3680,
      geohash: 'ttv4',
      geoVerified: true,
      branch: 'HODAL',
      pincode: '121106',
      assignedAgentId: 'uid_demo_tester',
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 11, 1),
    );
    final b2 = BorrowerModel(
      borrowerId: 'BRW_DEMO_002',
      fullName: 'Karthik Sundaram (Madurai)',
      mobilePrimary: '9842100002',
      panNumber: 'FGHIJ5678K',
      addressText: 'KK Nagar, Madurai, Tamil Nadu 625020',
      latitude: 9.9252,
      longitude: 78.1198,
      geohash: 'w6j3',
      geoVerified: true,
      branch: 'MADURAI',
      pincode: '625020',
      assignedAgentId: 'uid_demo_tester',
      createdAt: DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 11, 1),
    );
    _borrowers[b1.borrowerId] = b1;
    _borrowers[b2.borrowerId] = b2;

    final l1 = LoanModel(
      loanId: 'LN_DEMO_101',
      applicationNo: 'APP_DEMO_101',
      borrowerId: b1.borrowerId,
      productId: prod.productId,
      assignedAgentId: 'uid_demo_tester',
      principalSanctioned: 850000,
      processingFeeAmount: 12750,
      gstAmount: 2295,
      netDisbursedAmount: 834955,
      interestRateAnnual: 13.5,
      interestMethod: InterestMethod.reducingBalance,
      repaymentFrequency: RepaymentFrequency.monthly,
      tenureInstallments: 36,
      emiAmount: 28860,
      disbursementDate: now.subtract(const Duration(days: 180)),
      firstDueDate: now.subtract(const Duration(days: 150)),
      maturityDate: now.add(const Duration(days: 900)),
      scheduleVersion: 1,
      principalOutstanding: 710000,
      interestOutstanding: 42000,
      feesOutstanding: 0,
      dpd: 12,
      agingBucket: AgingBucket.dpd1To30,
      status: LoanStatus.active,
    );
    final l2 = LoanModel(
      loanId: 'LN_DEMO_102',
      applicationNo: 'APP_DEMO_102',
      borrowerId: b2.borrowerId,
      productId: prod.productId,
      assignedAgentId: 'uid_demo_tester',
      principalSanctioned: 1250000,
      processingFeeAmount: 18750,
      gstAmount: 3375,
      netDisbursedAmount: 1227875,
      interestRateAnnual: 12.75,
      interestMethod: InterestMethod.reducingBalance,
      repaymentFrequency: RepaymentFrequency.monthly,
      tenureInstallments: 48,
      emiAmount: 33250,
      disbursementDate: now.subtract(const Duration(days: 120)),
      firstDueDate: now.subtract(const Duration(days: 90)),
      maturityDate: now.add(const Duration(days: 1320)),
      scheduleVersion: 1,
      principalOutstanding: 1080000,
      interestOutstanding: 64000,
      feesOutstanding: 0,
      dpd: 0,
      agingBucket: AgingBucket.current,
      status: LoanStatus.active,
    );
    _loans[l1.loanId] = l1;
    _loans[l2.loanId] = l2;
  }
  InMemoryDemoLoanService() {
    seedSamplePortfolio();
    seedSamplePortfolio();
    _seedInitialData();
  }

  final Map<String, BorrowerModel> _borrowers = {};
  final Map<String, LoanProductModel> _products = {};
  final Map<String, LoanModel> _loans = {};
  final Map<String, InstallmentModel> _installments = {};
  final List<TransactionModel> _transactions = [];
  final Map<String, CollectionLogModel> _logs = {};

  void _seedInitialData() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Loan Products
    final products = [
      const LoanProductModel(
        productId: 'PROD-QBL',
        productName: 'Quick Business Loan',
        interestMethod: InterestMethod.reducingBalance,
        annualInterestRate: 24.0,
        repaymentFrequency: RepaymentFrequency.monthly,
        maxTenureInstallments: 24,
        processingFeePct: 2.0,
        gstRatePct: 18.0,
        gracePeriodDays: 3,
        lateFeeType: LateFeeType.percentOverdue,
        lateFeeValue: 2.0,
        atRiskDpdThreshold: 30,
      ),
      const LoanProductModel(
        productId: 'PROD-LAP',
        productName: 'Asset-Backed LAP',
        interestMethod: InterestMethod.reducingBalance,
        annualInterestRate: 16.5,
        repaymentFrequency: RepaymentFrequency.monthly,
        maxTenureInstallments: 60,
        processingFeePct: 1.5,
        gstRatePct: 18.0,
        gracePeriodDays: 5,
        lateFeeType: LateFeeType.flatInr,
        lateFeeValue: 500.0,
        atRiskDpdThreshold: 30,
      ),
      const LoanProductModel(
        productId: 'PROD-MICRO',
        productName: 'Weekly Micro Trader Loan',
        interestMethod: InterestMethod.flatRate,
        annualInterestRate: 22.0,
        repaymentFrequency: RepaymentFrequency.weekly,
        maxTenureInstallments: 52,
        processingFeePct: 1.0,
        gstRatePct: 18.0,
        gracePeriodDays: 2,
        lateFeeType: LateFeeType.flatInr,
        lateFeeValue: 150.0,
        atRiskDpdThreshold: 30,
      ),
    ];
    for (final p in products) {
      _products[p.productId] = p;
    }

    // 2. Borrowers (Madurai landmarks & realistic Indian KYC)
    final rawBorrowers = [
      (
        'SDE-CUST-1001',
        'Muruganandam Textiles',
        '+919842111001',
        'Sri Murugan Silks',
        'ABCDE1234F',
        'XXXX-XXXX-4821',
        '33ABCDE1234F1Z5',
        '14 West Masi Street, Madurai',
        9.9195,
        78.1193,
        'uid_agent_karthik',
        true,
      ),
      (
        'SDE-CUST-1002',
        'Lakshmi Narayanan',
        '+919842111002',
        'Lakshmi Hardware & Pipes',
        'BGTPL4421K',
        'XXXX-XXXX-9012',
        '33BGTPL4421K1Z8',
        '82 Anna Nagar Main Rd, Madurai',
        9.9225,
        78.1456,
        'uid_agent_karthik',
        true,
      ),
      (
        'SDE-CUST-1003',
        'Senthil Kumar R',
        '+919842111003',
        'Senthil Auto Spares',
        'CWRPS7819M',
        'XXXX-XXXX-3319',
        null,
        '29 KK Nagar 80 Feet Rd, Madurai',
        9.9390,
        78.1489,
        'uid_agent_karthik',
        false,
      ),
      (
        'SDE-CUST-1004',
        'Kavitha Devi Traders',
        '+919842111004',
        'Kavitha Agro Mart',
        'DKLPT6502H',
        'XXXX-XXXX-7745',
        '33DKLPT6502H1Z1',
        '51 Simmakkal Main Rd, Madurai',
        9.9288,
        78.1225,
        'uid_agent_priya',
        true,
      ),
      (
        'SDE-CUST-1005',
        'Ramesh Babu K',
        '+919842111005',
        'Madurai Fresh Foods',
        'ERBKP2290Q',
        'XXXX-XXXX-6610',
        null,
        '108 Thirupparankundram Rd, Madurai',
        9.8824,
        78.0715,
        'uid_agent_priya',
        true,
      ),
      (
        'SDE-CUST-1006',
        'Arunachalam Jewellers',
        '+919842111006',
        'Arunachalam Gold House',
        'FAJPM9104R',
        'XXXX-XXXX-1182',
        '33FAJPM9104R1Z2',
        '4 South Avani Moola St, Madurai',
        9.9154,
        78.1190,
        'uid_agent_priya',
        true,
      ),
    ];

    for (final b in rawBorrowers) {
      _borrowers[b.$1] = BorrowerModel(
        borrowerId: b.$1,
        fullName: b.$2,
        mobilePrimary: b.$3,
        businessName: b.$4,
        panNumber: b.$5,
        aadhaarMasked: b.$6,
        gstin: b.$7,
        bankAccountNo: '309101000${b.$1.substring(b.$1.length - 4)}',
        bankIfsc: 'SBIN0000869',
        addressText: b.$8,
        latitude: b.$9,
        longitude: b.$10,
        geohash: GeoFilterEngine.encodeGeohash(b.$9, b.$10),
        geoVerified: b.$12,
        assignedAgentId: b.$11,
        createdAt: today.subtract(const Duration(days: 180)),
        updatedAt: today.subtract(const Duration(days: 2)),
      );
    }

    // Helper to seed a loan + schedule + payments + logs
    void seedLoan({
      required String loanId,
      required String appNo,
      required String borrowerId,
      required String productId,
      required String agentId,
      required double principal,
      required int tenure,
      required DateTime disbursedOn,
      required int paidInstallments,
      double partialExtra = 0.0,
      List<CollectionLogModel> extraLogs = const [],
    }) {
      final product = _products[productId]!;
      final feeSplit = IndianFormatters.computeFeeWithGst(
        baseFee: principal * (product.processingFeePct / 100.0),
        gstRatePct: product.gstRatePct,
      );
      final netDisbursed =
          IndianFormatters.roundPaise(principal - feeSplit.totalFee);
      final emi = AmortizationEngine.calculateEmi(
        principal: principal,
        annualInterestRate: product.annualInterestRate,
        tenureInstallments: tenure,
        interestMethod: product.interestMethod,
        frequency: product.repaymentFrequency,
      );
      final firstDue = AmortizationEngine.addPeriod(
        disbursedOn,
        product.repaymentFrequency,
        1,
      );
      final schedule = AmortizationEngine.generateSchedule(
        loanId: loanId,
        principal: principal,
        annualInterestRate: product.annualInterestRate,
        tenureInstallments: tenure,
        interestMethod: product.interestMethod,
        frequency: product.repaymentFrequency,
        firstDueDate: firstDue,
      );

      _transactions.add(
        TransactionModel(
          txnId: 'TXN-$loanId-DISB',
          loanId: loanId,
          borrowerId: borrowerId,
          txnType: TransactionType.disbursement,
          paymentMode: PaymentMode.neftRtgs,
          referenceNo: 'UTR${loanId.replaceAll('-', '')}',
          totalAmount: netDisbursed,
          allocatedFees: feeSplit.totalFee,
          allocatedPrincipal: principal,
          collectedByUid: 'uid_master_balaji',
          notes: 'Initial disbursement (net of processing fee + 18% GST)',
          createdAt: disbursedOn,
        ),
      );

      var workingSchedule = schedule;
      for (var i = 0; i < paidInstallments && i < workingSchedule.length; i++) {
        final targetRow = workingSchedule[i];
        final payDate = targetRow.dueDate;
        final alloc = DelinquencyEngine.allocatePaymentWaterfall(
          paymentAmount: targetRow.totalDue,
          installments: workingSchedule,
          activeScheduleVersion: 1,
          paymentDate: payDate,
        );
        workingSchedule = alloc.updatedInstallments;
        _transactions.add(
          TransactionModel(
            txnId: 'TXN-$loanId-EMI-${i + 1}',
            loanId: loanId,
            borrowerId: borrowerId,
            txnType: TransactionType.repayment,
            paymentMode: i.isEven ? PaymentMode.upi : PaymentMode.enach,
            referenceNo: 'UPI${100000 + i * 137}${loanId.substring(loanId.length - 2)}',
            totalAmount: targetRow.totalDue,
            allocatedFees: alloc.allocatedFees,
            allocatedInterest: alloc.allocatedInterest,
            allocatedPrincipal: alloc.allocatedPrincipalTotal,
            collectedByUid: agentId,
            geoLat: _borrowers[borrowerId]!.latitude,
            geoLng: _borrowers[borrowerId]!.longitude,
            createdAt: payDate,
          ),
        );
      }

      if (partialExtra > 0) {
        final payDate = today.subtract(const Duration(days: 5));
        final alloc = DelinquencyEngine.allocatePaymentWaterfall(
          paymentAmount: partialExtra,
          installments: workingSchedule,
          activeScheduleVersion: 1,
          paymentDate: payDate,
        );
        workingSchedule = alloc.updatedInstallments;
        _transactions.add(
          TransactionModel(
            txnId: 'TXN-$loanId-PART',
            loanId: loanId,
            borrowerId: borrowerId,
            txnType: TransactionType.repayment,
            paymentMode: PaymentMode.cash,
            referenceNo: 'RCPT-${loanId.substring(loanId.length - 4)}-P',
            totalAmount: partialExtra,
            allocatedFees: alloc.allocatedFees,
            allocatedInterest: alloc.allocatedInterest,
            allocatedPrincipal: alloc.allocatedPrincipalTotal,
            collectedByUid: agentId,
            geoLat: _borrowers[borrowerId]!.latitude,
            geoLng: _borrowers[borrowerId]!.longitude,
            notes: 'Field partial cash receipt',
            createdAt: payDate,
          ),
        );
      }

      final baseLoan = LoanModel(
        loanId: loanId,
        applicationNo: appNo,
        borrowerId: borrowerId,
        productId: productId,
        assignedAgentId: agentId,
        principalSanctioned: principal,
        processingFeeAmount: feeSplit.baseFee,
        gstAmount: feeSplit.gstAmount,
        netDisbursedAmount: netDisbursed,
        interestRateAnnual: product.annualInterestRate,
        interestMethod: product.interestMethod,
        repaymentFrequency: product.repaymentFrequency,
        tenureInstallments: tenure,
        emiAmount: emi,
        disbursementDate: disbursedOn,
        firstDueDate: firstDue,
        maturityDate: workingSchedule.last.dueDate,
        principalOutstanding: principal,
      );

      for (final log in extraLogs) {
        _logs[log.logId] = log;
      }

      final eval = DelinquencyEngine.evaluateLoan(
        loan: baseLoan,
        installments: workingSchedule,
        product: product,
        collectionLogs: extraLogs,
        asOfDate: today,
      );

      _loans[loanId] = eval.updatedLoan;
      for (final row in eval.updatedInstallments) {
        _installments[row.installmentId] = row;
      }
    }

    // Loan 1: Current (Green) â€” 3 of 12 EMIs paid on time
    seedLoan(
      loanId: 'SDE-LN-2001',
      appNo: 'APP-2026-001',
      borrowerId: 'SDE-CUST-1001',
      productId: 'PROD-QBL',
      agentId: 'uid_agent_karthik',
      principal: 300000,
      tenure: 12,
      disbursedOn: DateTime(today.year, today.month - 3, max(1, min(28, today.day + 5))),
      paidInstallments: 3,
    );

    // Loan 2: 1â€“30 DPD + PTP Due Today (Amber)
    seedLoan(
      loanId: 'SDE-LN-2002',
      appNo: 'APP-2026-002',
      borrowerId: 'SDE-CUST-1002',
      productId: 'PROD-QBL',
      agentId: 'uid_agent_karthik',
      principal: 250000,
      tenure: 18,
      disbursedOn: today.subtract(const Duration(days: 105)),
      paidInstallments: 2,
      extraLogs: [
        CollectionLogModel(
          logId: 'LOG-2002-1',
          loanId: 'SDE-LN-2002',
          borrowerId: 'SDE-CUST-1002',
          agentId: 'uid_agent_karthik',
          actionType: CollectionActionType.call,
          disposition: CollectionDisposition.ptpConfirmed,
          ptpDate: today,
          ptpAmount: 16700,
          ptpStatus: PtpStatus.open,
          notes: 'Customer promised UPI transfer by 5 PM today.',
          nextFollowupAt: today.add(const Duration(hours: 17)),
          createdAt: today.subtract(const Duration(days: 2)),
        ),
      ],
    );

    // Loan 3: 31â€“60 DPD + Broken PTP + Early Warning (Red)
    seedLoan(
      loanId: 'SDE-LN-2003',
      appNo: 'APP-2026-003',
      borrowerId: 'SDE-CUST-1003',
      productId: 'PROD-QBL',
      agentId: 'uid_agent_karthik',
      principal: 180000,
      tenure: 12,
      disbursedOn: today.subtract(const Duration(days: 135)),
      paidInstallments: 2,
      partialExtra: 5000,
      extraLogs: [
        CollectionLogModel(
          logId: 'LOG-2003-1',
          loanId: 'SDE-LN-2003',
          borrowerId: 'SDE-CUST-1003',
          agentId: 'uid_agent_karthik',
          actionType: CollectionActionType.fieldVisit,
          disposition: CollectionDisposition.ptpConfirmed,
          ptpDate: today.subtract(const Duration(days: 4)),
          ptpAmount: 17000,
          ptpStatus: PtpStatus.broken,
          visitLat: 9.9390,
          visitLng: 78.1489,
          notes: 'Visited shop; promised clearance 4 days ago, now overdue.',
          nextFollowupAt: today,
          createdAt: today.subtract(const Duration(days: 7)),
        ),
      ],
    );

    // Loan 4: Asset-Backed LAP â€” Current (Green)
    seedLoan(
      loanId: 'SDE-LN-2004',
      appNo: 'APP-2026-004',
      borrowerId: 'SDE-CUST-1004',
      productId: 'PROD-LAP',
      agentId: 'uid_agent_priya',
      principal: 850000,
      tenure: 36,
      disbursedOn: today.subtract(const Duration(days: 118)),
      paidInstallments: 4,
    );

    // Loan 5: Weekly Micro Loan â€” Missed 1st EMI Early Warning (Red / 35+ DPD)
    seedLoan(
      loanId: 'SDE-LN-2005',
      appNo: 'APP-2026-005',
      borrowerId: 'SDE-CUST-1005',
      productId: 'PROD-MICRO',
      agentId: 'uid_agent_priya',
      principal: 75000,
      tenure: 24,
      disbursedOn: today.subtract(const Duration(days: 50)),
      paidInstallments: 0,
      extraLogs: [
        CollectionLogModel(
          logId: 'LOG-2005-1',
          loanId: 'SDE-LN-2005',
          borrowerId: 'SDE-CUST-1005',
          agentId: 'uid_agent_priya',
          actionType: CollectionActionType.fieldVisit,
          disposition: CollectionDisposition.customerUnavailable,
          ptpStatus: PtpStatus.notApplicable,
          visitLat: 9.8825,
          visitLng: 78.0716,
          notes: 'Shop shutter closed at 11 AM; neighbor said owner returns evening.',
          nextFollowupAt: today.add(const Duration(days: 1)),
          createdAt: today.subtract(const Duration(days: 1)),
        ),
      ],
    );

    // Loan 6: 90+ DPD NPA (Red)
    seedLoan(
      loanId: 'SDE-LN-2006',
      appNo: 'APP-2025-098',
      borrowerId: 'SDE-CUST-1006',
      productId: 'PROD-LAP',
      agentId: 'uid_agent_priya',
      principal: 600000,
      tenure: 24,
      disbursedOn: today.subtract(const Duration(days: 220)),
      paidInstallments: 3,
      extraLogs: [
        CollectionLogModel(
          logId: 'LOG-2006-1',
          loanId: 'SDE-LN-2006',
          borrowerId: 'SDE-CUST-1006',
          agentId: 'uid_agent_priya',
          actionType: CollectionActionType.legalNotice,
          disposition: CollectionDisposition.refusedToPay,
          ptpStatus: PtpStatus.broken,
          notes: 'Demand notice served; escalated to Master for settlement/restructure.',
          nextFollowupAt: today,
          createdAt: today.subtract(const Duration(days: 10)),
        ),
      ],
    );
  }

  @override
  Future<PortfolioSnapshot> loadAll() async {
    final sortedTxns = List<TransactionModel>.from(_transactions)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final sortedLogs = _logs.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return PortfolioSnapshot(
      borrowers: _borrowers.values.toList(),
      products: _products.values.toList(),
      loans: _loans.values.toList(),
      installments: _installments.values.toList(),
      transactions: sortedTxns,
      collectionLogs: sortedLogs,
    );
  }

  @override
  Future<void> saveBorrower(BorrowerModel borrower) async {
    _borrowers[borrower.borrowerId] = borrower;
  }

  @override

  Future<void> saveProduct(LoanProductModel product) async {
    _products[product.productId] = product;
  }

  @override
  Future<void> originateLoan({
    required LoanModel loan,
    required List<InstallmentModel> initialSchedule,
    required TransactionModel disbursementTxn,
  }) async {
    _loans[loan.loanId] = loan;
    for (final row in initialSchedule) {
      _installments[row.installmentId] = row;
    }
    _transactions.insert(0, disbursementTxn);
  }

  @override
  Future<void> recordPaymentAtomic({
    required LoanModel updatedLoan,
    required List<InstallmentModel> updatedInstallments,
    required TransactionModel paymentTxn,
    required List<String> keptPtpLogIds,
  }) async {
    _transactions.insert(0, paymentTxn);
    _loans[updatedLoan.loanId] = updatedLoan;
    for (final row in updatedInstallments) {
      _installments[row.installmentId] = row;
    }
    for (final id in keptPtpLogIds) {
      final existing = _logs[id];
      if (existing != null) {
        _logs[id] = existing.copyWith(ptpStatus: PtpStatus.kept);
      }
    }
  }

  @override
  Future<void> recordReversalAtomic({
    required LoanModel restoredLoan,
    required List<InstallmentModel> restoredInstallments,
    required TransactionModel reversalTxn,
  }) async {
    _transactions.insert(0, reversalTxn);
    _loans[restoredLoan.loanId] = restoredLoan;
    for (final row in restoredInstallments) {
      _installments[row.installmentId] = row;
    }
  }

  @override
  Future<void> restructureLoanAtomic(RestructureResult result) async {
    _loans[result.updatedLoan.loanId] = result.updatedLoan;
    for (final row in result.supersededInstallments) {
      _installments[row.installmentId] = row;
    }
    for (final row in result.newVersionInstallments) {
      _installments[row.installmentId] = row;
    }
  }

  @override
  Future<void> addCollectionLog(
    CollectionLogModel log, {
    LoanModel? updatedLoan,
  }) async {
    _logs[log.logId] = log;
    if (updatedLoan != null) {
      _loans[updatedLoan.loanId] = updatedLoan;
    }
  }

  @override
  Future<void> applyDelinquencyUpdate({
    required LoanModel updatedLoan,
    required List<InstallmentModel> updatedInstallments,
    required List<String> brokenPtpLogIds,
    TransactionModel? lateFeeTxn,
  }) async {
    _loans[updatedLoan.loanId] = updatedLoan;
    for (final row in updatedInstallments) {
      _installments[row.installmentId] = row;
    }
    for (final id in brokenPtpLogIds) {
      final existing = _logs[id];
      if (existing != null) {
        _logs[id] = existing.copyWith(ptpStatus: PtpStatus.broken);
      }
    }
    if (lateFeeTxn != null) {
      _transactions.insert(0, lateFeeTxn);
    }
  }
}

/// Application state provider wrapping the active [LoanDataRepository].
class LoanPortfolioProvider extends ChangeNotifier {
  LoanPortfolioProvider({
    required LoanDataRepository repository,
    required this.isDemoMode,
  }) : _repository = repository;

  final LoanDataRepository _repository;
  final bool isDemoMode;
  LoanDataRepository get repository => _repository;

  bool _isLoading = false;
  String? _error;

  List<BorrowerModel> borrowers = const [];
  List<LoanProductModel> products = const [];
  List<LoanModel> loans = const [];
  List<InstallmentModel> installments = const [];
  List<TransactionModel> transactions = const [];
  List<CollectionLogModel> collectionLogs = const [];

  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final snap = await _repository.loadAll();
      borrowers = snap.borrowers;
      products = snap.products;
      loans = snap.loans;
      installments = snap.installments;
      transactions = snap.transactions;
      collectionLogs = snap.collectionLogs;
    } catch (e) {
      _error = 'Failed to load portfolio: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  BorrowerModel? borrowerById(String id) {
    for (final b in borrowers) {
      if (b.borrowerId == id) return b;
    }
    return null;
  }

  LoanProductModel? productById(String id) {
    for (final p in products) {
      if (p.productId == id) return p;
    }
    return null;
  }

  LoanModel? loanById(String id) {
    for (final l in loans) {
      if (l.loanId == id) return l;
    }
    return null;
  }

  List<InstallmentModel> scheduleForLoan(String loanId, {int? version}) {
    final list = installments
        .where(
          (i) =>
              i.loanId == loanId &&
              (version == null || i.scheduleVersion == version),
        )
        .toList()
      ..sort((a, b) {
        final vCmp = b.scheduleVersion.compareTo(a.scheduleVersion);
        if (vCmp != 0) return vCmp;
        return a.installmentNo.compareTo(b.installmentNo);
      });
    return list;
  }

  List<TransactionModel> transactionsForLoan(String loanId) {
    return transactions.where((t) => t.loanId == loanId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<CollectionLogModel> logsForLoan(String loanId) {
    return collectionLogs.where((l) => l.loanId == loanId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  String generateNextBorrowerId() {
    var maxNum = 1000;
    for (final b in borrowers) {
      final n = int.tryParse(b.borrowerId.split('-').last);
      if (n != null && n > maxNum) maxNum = n;
    }
    return 'SDE-CUST-${maxNum + 1}';
  }

  String generateNextLoanId() {
    var maxNum = 2000;
    for (final l in loans) {
      final n = int.tryParse(l.loanId.split('-').last);
      if (n != null && n > maxNum) maxNum = n;
    }
    return 'SDE-LN-${maxNum + 1}';
  }

  Future<void> saveBorrower(BorrowerModel borrower, {bool skipRefresh = false}) async {
    await _repository.saveBorrower(borrower);
    if (!skipRefresh) await refresh();
  }


  Future<void> saveProduct(LoanProductModel product) async {
    await _repository.saveProduct(product);
    await refresh();
  }

  /// Creates a new loan, its v1 amortization schedule, and initial immutable disbursement ledger entry.
  Future<void> applyBatchImportState({
    required LoanModel updatedLoan,
    required List<InstallmentModel> updatedInstallments,
    bool skipRefresh = false,
  }) async {
    await _repository.applyDelinquencyUpdate(
      updatedLoan: updatedLoan,
      updatedInstallments: updatedInstallments,
      brokenPtpLogIds: const [],
    );
    if (!skipRefresh) await refresh();
  }

  Future<void> updateLoanRecord(LoanModel loan) async {
    await _repository.applyDelinquencyUpdate(updatedLoan: loan, updatedInstallments: const [], brokenPtpLogIds: const []);
    await refresh();
  }

  Future<LoanModel> originateNewLoan({
    required BorrowerModel borrower,
    required LoanProductModel product,
    required double principalSanctioned,
    required int tenureInstallments,
    required String collectedByUid,
    String? customLoanId,
    String? customApplicationNo,
    DateTime? disbursementDate,
    bool skipRefresh = false,
    int initialPaidInstallments = 0,
    int initialDpd = 0,
    double? principalOutstandingOverride,
  }) async {
    final disbursedOn = disbursementDate ?? DateTime.now();
    final loanId = (customLoanId != null && customLoanId.trim().isNotEmpty)
        ? customLoanId.trim()
        : generateNextLoanId();
    final appNo = (customApplicationNo != null &&
            customApplicationNo.trim().isNotEmpty)
        ? customApplicationNo.trim()
        : 'APP-${disbursedOn.year}-${loanId.split('-').last}';

    final feeSplit = IndianFormatters.computeFeeWithGst(
      baseFee: principalSanctioned * (product.processingFeePct / 100.0),
      gstRatePct: product.gstRatePct,
    );
    final netDisbursed =
        IndianFormatters.roundPaise(principalSanctioned - feeSplit.totalFee);
    final emi = AmortizationEngine.calculateEmi(
      principal: principalSanctioned,
      annualInterestRate: product.annualInterestRate,
      tenureInstallments: tenureInstallments,
      interestMethod: product.interestMethod,
      frequency: product.repaymentFrequency,
    );
    final firstDue = AmortizationEngine.addPeriod(
      disbursedOn,
      product.repaymentFrequency,
      1,
    );
    final schedule = AmortizationEngine.generateSchedule(
      loanId: loanId,
      principal: principalSanctioned,
      annualInterestRate: product.annualInterestRate,
      tenureInstallments: tenureInstallments,
      interestMethod: product.interestMethod,
      frequency: product.repaymentFrequency,
      firstDueDate: firstDue,
    );

    var paidPrincipal = 0.0;
    var paidInterest = 0.0;
    final settledSchedule = <InstallmentModel>[];
    for (var i = 0; i < schedule.length; i++) {
      final inst = schedule[i];
      if (i < initialPaidInstallments) {
        paidPrincipal += inst.principalDue;
        paidInterest += inst.interestDue;
        settledSchedule.add(
          inst.copyWith(
            principalPaid: inst.principalDue,
            interestPaid: inst.interestDue,
            status: InstallmentStatus.paid,
          ),
        );
      } else {
        settledSchedule.add(inst);
      }
    }

    final totalInterest = IndianFormatters.roundPaise(
      schedule.fold<double>(0.0, (s, r) => s + r.interestDue),
    );
    final remPrincipal = (principalOutstandingOverride != null &&
            principalOutstandingOverride > 0)
        ? principalOutstandingOverride
        : IndianFormatters.roundPaise(
            (principalSanctioned - paidPrincipal)
                .clamp(0.0, principalSanctioned),
          );
    final remInterest = IndianFormatters.roundPaise(
      (totalInterest - paidInterest).clamp(0.0, totalInterest),
    );

    final loan = LoanModel(
      loanId: loanId,
      applicationNo: appNo,
      borrowerId: borrower.borrowerId,
      productId: product.productId,
      assignedAgentId: borrower.assignedAgentId,
      principalSanctioned: principalSanctioned,
      processingFeeAmount: feeSplit.baseFee,
      gstAmount: feeSplit.gstAmount,
      netDisbursedAmount: netDisbursed,
      interestRateAnnual: product.annualInterestRate,
      interestMethod: product.interestMethod,
      repaymentFrequency: product.repaymentFrequency,
      tenureInstallments: tenureInstallments,
      emiAmount: emi,
      disbursementDate: disbursedOn,
      firstDueDate: firstDue,
      maturityDate: schedule.last.dueDate,
      scheduleVersion: 1,
      principalOutstanding: remPrincipal,
      interestOutstanding: remInterest,
      feesOutstanding: 0.0,
      dpd: initialDpd > 0 ? initialDpd : 0,
      agingBucket: initialDpd > 0
          ? AgingBucket.fromDpd(initialDpd)
          : AgingBucket.current,
      status: LoanStatus.active,
    );

    final disbTxn = TransactionModel(
      txnId: 'TXN-${DateTime.now().millisecondsSinceEpoch}-DISB',
      loanId: loanId,
      borrowerId: borrower.borrowerId,
      txnType: TransactionType.disbursement,
      paymentMode: PaymentMode.neftRtgs,
      referenceNo: 'UTR-${loanId.replaceAll('-', '')}',
      totalAmount: netDisbursed,
      allocatedFees: feeSplit.totalFee,
      allocatedPrincipal: principalSanctioned,
      collectedByUid: collectedByUid,
      notes: 'Loan disbursement (net of processing fee + ${product.gstRatePct}% GST)',
      createdAt: disbursedOn,
    );

    await _repository.originateLoan(
      loan: loan,
      initialSchedule: settledSchedule,
      disbursementTxn: disbTxn,
    );
    if (!skipRefresh) await refresh();
    return loan;
  }

  /// Records a repayment or prepayment using strict waterfall allocation and append-only ledger.
  Future<TransactionModel> recordPayment({
    required String loanId,
    required double amount,
    required PaymentMode paymentMode,
    required String referenceNo,
    required String collectedByUid,
    TransactionType txnType = TransactionType.repayment,
    double? geoLat,
    double? geoLng,
    String? notes,
  }) async {
    final loan = loanById(loanId);
    if (loan == null) throw StateError('Loan $loanId not found.');
    final product = productById(loan.productId) ?? products.first;
    final now = DateTime.now();

    final currentRows = scheduleForLoan(loanId, version: loan.scheduleVersion);
    final allocation = DelinquencyEngine.allocatePaymentWaterfall(
      paymentAmount: amount,
      installments: currentRows,
      activeScheduleVersion: loan.scheduleVersion,
      paymentDate: now,
    );

    final openPtpIds = logsForLoan(loanId)
        .where((l) => l.ptpStatus == PtpStatus.open)
        .map((l) => l.logId)
        .toList();

    final updatedLogs = logsForLoan(loanId)
        .map(
          (l) => openPtpIds.contains(l.logId)
              ? l.copyWith(ptpStatus: PtpStatus.kept)
              : l,
        )
        .toList();

    final eval = DelinquencyEngine.evaluateLoan(
      loan: loan,
      installments: allocation.updatedInstallments,
      product: product,
      collectionLogs: updatedLogs,
      asOfDate: now,
    );

    final txn = TransactionModel(
      txnId: 'TXN-${now.millisecondsSinceEpoch}',
      loanId: loanId,
      borrowerId: loan.borrowerId,
      txnType: txnType,
      paymentMode: paymentMode,
      referenceNo: referenceNo.trim().isEmpty
          ? 'RCPT-${now.millisecondsSinceEpoch % 100000}'
          : referenceNo.trim(),
      totalAmount: IndianFormatters.roundPaise(amount),
      allocatedFees: allocation.allocatedFees,
      allocatedInterest: allocation.allocatedInterest,
      allocatedPrincipal: allocation.allocatedPrincipalTotal,
      collectedByUid: collectedByUid,
      geoLat: geoLat,
      geoLng: geoLng,
      notes: notes,
      createdAt: now,
    );

    await _repository.recordPaymentAtomic(
      updatedLoan: eval.updatedLoan,
      updatedInstallments: eval.updatedInstallments,
      paymentTxn: txn,
      keptPtpLogIds: openPtpIds,
    );
    await refresh();
    return txn;
  }

  /// Master-only immutable reversal: inserts a `REVERSAL` contra-entry and restores balances.
  Future<TransactionModel> reverseTransaction({
    required TransactionModel originalTxn,
    required String authorizedByUid,
    required String reason,
  }) async {
    final loan = loanById(originalTxn.loanId);
    if (loan == null) throw StateError('Loan ${originalTxn.loanId} not found.');
    final product = productById(loan.productId) ?? products.first;
    final now = DateTime.now();

    // Reverse allocations back onto active installments (most recently paid first)
    final activeRows =
        scheduleForLoan(loan.loanId, version: loan.scheduleVersion)
          ..sort((a, b) => b.installmentNo.compareTo(a.installmentNo));

    var remPrincipal = originalTxn.allocatedPrincipal;
    var remInterest = originalTxn.allocatedInterest;
    var remFees = originalTxn.allocatedFees;

    final restored = <InstallmentModel>[];
    for (final row in activeRows) {
      var pPaid = row.principalPaid;
      var iPaid = row.interestPaid;
      var fPaid = row.feePaid;

      if (remPrincipal > 0.009 && pPaid > 0.009) {
        final take = min(remPrincipal, pPaid);
        pPaid = IndianFormatters.roundPaise(pPaid - take);
        remPrincipal = IndianFormatters.roundPaise(remPrincipal - take);
      }
      if (remInterest > 0.009 && iPaid > 0.009) {
        final take = min(remInterest, iPaid);
        iPaid = IndianFormatters.roundPaise(iPaid - take);
        remInterest = IndianFormatters.roundPaise(remInterest - take);
      }
      if (remFees > 0.009 && fPaid > 0.009) {
        final take = min(remFees, fPaid);
        fPaid = IndianFormatters.roundPaise(fPaid - take);
        remFees = IndianFormatters.roundPaise(remFees - take);
      }

      restored.add(
        row.copyWith(
          principalPaid: pPaid,
          interestPaid: iPaid,
          feePaid: fPaid,
          clearPaidDate: (pPaid + iPaid + fPaid) < row.totalDue - 0.01,
        ),
      );
    }

    final eval = DelinquencyEngine.evaluateLoan(
      loan: loan,
      installments: restored,
      product: product,
      collectionLogs: logsForLoan(loan.loanId),
      asOfDate: now,
    );

    final reversalTxn = TransactionModel(
      txnId: 'TXN-${now.millisecondsSinceEpoch}-REV',
      loanId: originalTxn.loanId,
      borrowerId: originalTxn.borrowerId,
      txnType: TransactionType.reversal,
      paymentMode: originalTxn.paymentMode,
      referenceNo: 'REV-${originalTxn.referenceNo}',
      totalAmount: originalTxn.totalAmount,
      allocatedFees: originalTxn.allocatedFees,
      allocatedInterest: originalTxn.allocatedInterest,
      allocatedPrincipal: originalTxn.allocatedPrincipal,
      reversedTxnId: originalTxn.txnId,
      collectedByUid: authorizedByUid,
      notes: 'Reversal of ${originalTxn.txnId}: $reason',
      createdAt: now,
    );

    await _repository.recordReversalAtomic(
      restoredLoan: eval.updatedLoan,
      restoredInstallments: eval.updatedInstallments,
      reversalTxn: reversalTxn,
    );
    await refresh();
    return reversalTxn;
  }

  /// Non-destructive restructuring (`v1 -> v2`).
  Future<RestructureResult> applyRestructure({
    required String loanId,
    required double newPrincipal,
    required double newAnnualRate,
    required int newTenure,
    required DateTime newFirstDueDate,
    InterestMethod? newMethod,
    RepaymentFrequency? newFrequency,
  }) async {
    final loan = loanById(loanId);
    if (loan == null) throw StateError('Loan $loanId not found.');
    final existing = scheduleForLoan(loanId);

    final result = AmortizationEngine.restructureLoan(
      loan: loan,
      existingSchedule: existing,
      newPrincipal: newPrincipal,
      newAnnualInterestRate: newAnnualRate,
      newTenureInstallments: newTenure,
      newFirstDueDate: newFirstDueDate,
      newInterestMethod: newMethod,
      newFrequency: newFrequency,
    );

    await _repository.restructureLoanAtomic(result);
    await refresh();
    return result;
  }

  /// Logs a collection visit / call / PTP entry and refreshes Early Warning status.
  Future<void> logCollectionActivity(CollectionLogModel log) async {
    final loan = loanById(log.loanId);
    LoanModel? updatedLoan;
    if (loan != null) {
      final product = productById(loan.productId) ?? products.first;
      final eval = DelinquencyEngine.evaluateLoan(
        loan: loan,
        installments: scheduleForLoan(loan.loanId, version: loan.scheduleVersion),
        product: product,
        collectionLogs: [log, ...logsForLoan(loan.loanId)],
        asOfDate: DateTime.now(),
      );
      updatedLoan = eval.updatedLoan;
    }
    await _repository.addCollectionLog(log, updatedLoan: updatedLoan);
    await refresh();
  }

  /// Marks borrower's on-site GPS coordinates as verified.
  Future<void> verifyBorrowerGeoPin({
    required String borrowerId,
    required double latitude,
    required double longitude,
  }) async {
    final existing = borrowerById(borrowerId);
    if (existing == null) return;
    final updated = existing.copyWith(
      latitude: latitude,
      longitude: longitude,
      geohash: GeoFilterEngine.encodeGeohash(latitude, longitude),
      geoVerified: true,
      updatedAt: DateTime.now(),
    );
    await _repository.saveBorrower(updated);
    await refresh();
  }

  /// Bulk-assigns matching borrowers and their loans to a target collection agent.
  Future<int> assignAccountsToAgent({
    required List<String> loanIds,
    required String targetAgentUid,
  }) async {
    if (loanIds.isEmpty) return 0;
    final loanIdSet = loanIds.toSet();
    final now = DateTime.now();
    var count = 0;

    for (final loan in loans.where((l) => loanIdSet.contains(l.loanId))) {
      final borrower = borrowerById(loan.borrowerId);
      if (borrower != null && borrower.assignedAgentId != targetAgentUid) {
        await _repository.saveBorrower(
          borrower.copyWith(assignedAgentId: targetAgentUid, updatedAt: now),
        );
      }
      await _repository.applyDelinquencyUpdate(
        updatedLoan: loan.copyWith(assignedAgentId: targetAgentUid),
        updatedInstallments: const [],
        brokenPtpLogIds: const [],
      );
      count++;
    }
    await refresh();
    return count;
  }

  /// Runs the daily DPD, aging bucket, broken-PTP, and late-fee sweep on demand.
  Future<int> runDailyDelinquencySweep({DateTime? asOfDate}) async {
    final today = asOfDate ?? DateTime.now();
    var updatedCount = 0;
    for (final loan in loans.where((l) => l.isPortfolioActive)) {
      final product = productById(loan.productId) ?? products.first;
      final eval = DelinquencyEngine.evaluateLoan(
        loan: loan,
        installments: scheduleForLoan(loan.loanId, version: loan.scheduleVersion),
        product: product,
        collectionLogs: logsForLoan(loan.loanId),
        asOfDate: today,
      );
      await _repository.applyDelinquencyUpdate(
        updatedLoan: eval.updatedLoan,
        updatedInstallments: eval.updatedInstallments,
        brokenPtpLogIds: eval.newlyBrokenPtpLogIds,
      );
      updatedCount++;
    }
    await refresh();
    return updatedCount;
  }
}




















