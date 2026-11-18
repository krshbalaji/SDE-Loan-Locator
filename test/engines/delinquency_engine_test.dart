import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/engines/delinquency_engine.dart';
import 'package:loan_locator_app/models/collection_log_model.dart';
import 'package:loan_locator_app/models/installment_model.dart';
import 'package:loan_locator_app/models/loan_model.dart';
import 'package:loan_locator_app/models/loan_product_model.dart';
import 'package:loan_locator_app/models/transaction_model.dart';
import 'package:loan_locator_app/utils/indian_formatters.dart';

void main() {
  group('DelinquencyEngine & IndianFormatters', () {
    test('enforces strict waterfall: Fees -> Interest -> Overdue Principal -> Current Principal', () {
      final rows = [
        InstallmentModel(
          installmentId: 'L1_v1_1',
          loanId: 'L1',
          scheduleVersion: 1,
          installmentNo: 1,
          dueDate: DateTime(2026, 1, 10),
          openingPrincipal: 20000,
          principalDue: 10000,
          interestDue: 1000,
          feeDue: 500,
          totalDue: 11500,
          status: InstallmentStatus.overdue,
        ),
        InstallmentModel(
          installmentId: 'L1_v1_2',
          loanId: 'L1',
          scheduleVersion: 1,
          installmentNo: 2,
          dueDate: DateTime(2026, 2, 10),
          openingPrincipal: 10000,
          principalDue: 10000,
          interestDue: 500,
          feeDue: 0,
          totalDue: 10500,
          status: InstallmentStatus.upcoming,
        ),
      ];

      // Pay ₹4,000 on Jan 25 -> ₹500 to fees, ₹1,000 to overdue interest, ₹2,500 to overdue principal
      final res = DelinquencyEngine.allocatePaymentWaterfall(
        paymentAmount: 4000,
        installments: rows,
        activeScheduleVersion: 1,
        paymentDate: DateTime(2026, 1, 25),
      );

      expect(res.allocatedFees, 500.0);
      expect(res.allocatedInterest, 1000.0);
      expect(res.allocatedPrincipalOverdue, 2500.0);
      expect(res.allocatedCurrentPrincipal, 0.0);
      expect(res.updatedInstallments.first.status, InstallmentStatus.partial);
    });

    test('computes DPD, aging bucket, grace-period late fee (+18% GST), broken PTP, and EWS', () {
      const product = LoanProductModel(
        productId: 'P1',
        productName: 'Quick Business Loan',
        interestMethod: InterestMethod.reducingBalance,
        annualInterestRate: 24.0,
        repaymentFrequency: RepaymentFrequency.monthly,
        maxTenureInstallments: 12,
        gracePeriodDays: 3,
        lateFeeType: LateFeeType.percentOverdue,
        lateFeeValue: 2.0,
        gstRatePct: 18.0,
      );

      final loan = LoanModel(
        loanId: 'SDE-LN-1',
        applicationNo: 'APP-1',
        borrowerId: 'SDE-CUST-1',
        productId: 'P1',
        assignedAgentId: 'agent_1',
        principalSanctioned: 100000,
        processingFeeAmount: 2000,
        gstAmount: 360,
        netDisbursedAmount: 97640,
        interestRateAnnual: 24,
        interestMethod: InterestMethod.reducingBalance,
        tenureInstallments: 12,
        emiAmount: 9456,
        disbursementDate: DateTime(2026, 1, 1),
        firstDueDate: DateTime(2026, 2, 1),
        maturityDate: DateTime(2027, 1, 1),
        principalOutstanding: 100000,
      );

      final schedule = [
        InstallmentModel(
          installmentId: 'SDE-LN-1_v1_1',
          loanId: 'SDE-LN-1',
          scheduleVersion: 1,
          installmentNo: 1,
          dueDate: DateTime(2026, 2, 1),
          openingPrincipal: 100000,
          principalDue: 8000,
          interestDue: 2000,
          totalDue: 10000,
        ),
      ];

      final logs = [
        CollectionLogModel(
          logId: 'LOG-1',
          loanId: 'SDE-LN-1',
          borrowerId: 'SDE-CUST-1',
          agentId: 'agent_1',
          actionType: CollectionActionType.call,
          disposition: CollectionDisposition.ptpConfirmed,
          ptpDate: DateTime(2026, 3, 1),
          ptpAmount: 10000,
          ptpStatus: PtpStatus.open,
          notes: 'Promised payment',
          nextFollowupAt: DateTime(2026, 3, 2),
          createdAt: DateTime(2026, 2, 20),
        ),
      ];

      // Evaluate on March 18 -> 45 DPD (Feb 1 to Mar 18 in 2026 = 45 days)
      final eval = DelinquencyEngine.evaluateLoan(
        loan: loan,
        installments: schedule,
        product: product,
        collectionLogs: logs,
        asOfDate: DateTime(2026, 3, 18),
      );

      expect(eval.updatedLoan.dpd, 45);
      expect(eval.updatedLoan.agingBucket, AgingBucket.dpd31To60);
      expect(eval.updatedLoan.status, LoanStatus.delinquent);
      expect(eval.updatedLoan.earlyWarningFlag, isTrue);
      expect(eval.newlyBrokenPtpLogIds, contains('LOG-1'));
      // 2% of ₹10,000 = ₹200 base + 18% GST = ₹36 -> ₹236 total
      expect(eval.suggestedLateFeeBase, 200.0);
      expect(eval.suggestedLateFeeGst, 36.0);
      expect(eval.suggestedLateFeeTotal, 236.0);
    });

    test('computes PAR > 30% and nets reversals from YTD collections', () {
      final now = DateTime(2026, 6, 15);
      final loans = [
        LoanModel(
          loanId: 'L1',
          applicationNo: 'A1',
          borrowerId: 'B1',
          productId: 'P1',
          assignedAgentId: 'ag1',
          principalSanctioned: 100000,
          processingFeeAmount: 0,
          gstAmount: 0,
          netDisbursedAmount: 100000,
          interestRateAnnual: 18,
          interestMethod: InterestMethod.reducingBalance,
          tenureInstallments: 12,
          emiAmount: 9000,
          disbursementDate: DateTime(2026, 1, 1),
          firstDueDate: DateTime(2026, 2, 1),
          maturityDate: DateTime(2027, 1, 1),
          principalOutstanding: 75000,
          dpd: 0,
          agingBucket: AgingBucket.current,
          status: LoanStatus.active,
        ),
        LoanModel(
          loanId: 'L2',
          applicationNo: 'A2',
          borrowerId: 'B2',
          productId: 'P1',
          assignedAgentId: 'ag1',
          principalSanctioned: 50000,
          processingFeeAmount: 0,
          gstAmount: 0,
          netDisbursedAmount: 50000,
          interestRateAnnual: 18,
          interestMethod: InterestMethod.reducingBalance,
          tenureInstallments: 12,
          emiAmount: 4500,
          disbursementDate: DateTime(2026, 1, 1),
          firstDueDate: DateTime(2026, 2, 1),
          maturityDate: DateTime(2027, 1, 1),
          principalOutstanding: 25000,
          dpd: 42,
          agingBucket: AgingBucket.dpd31To60,
          status: LoanStatus.delinquent,
          earlyWarningFlag: true,
        ),
      ];

      final txns = [
        TransactionModel(
          txnId: 'T1',
          loanId: 'L1',
          borrowerId: 'B1',
          txnType: TransactionType.repayment,
          paymentMode: PaymentMode.upi,
          referenceNo: 'UPI1',
          totalAmount: 10000,
          allocatedPrincipal: 8000,
          allocatedInterest: 2000,
          collectedByUid: 'ag1',
          createdAt: DateTime(2026, 6, 10),
        ),
        TransactionModel(
          txnId: 'T2',
          loanId: 'L1',
          borrowerId: 'B1',
          txnType: TransactionType.reversal,
          paymentMode: PaymentMode.upi,
          referenceNo: 'REV-UPI1',
          totalAmount: 4000,
          allocatedPrincipal: 3000,
          allocatedInterest: 1000,
          reversedTxnId: 'T1',
          collectedByUid: 'ag1',
          createdAt: DateTime(2026, 6, 11),
        ),
      ];

      final kpi = DelinquencyEngine.computePortfolioKpis(
        loans: loans,
        transactions: txns,
        agentNames: const {'ag1': 'Karthik'},
        asOfDate: now,
      );

      // PAR30 = 25,000 / 100,000 = 25.0%
      expect(kpi.par30Percent, 25.0);
      expect(kpi.collectedMtd, 6000.0);
      expect(kpi.principalCollectedYtd, 5000.0);
      expect(kpi.interestCollectedYtd, 1000.0);
    });

    test('formats INR with Indian lakh/crore grouping and validates PAN/GSTIN/Aadhaar', () {
      expect(IndianFormatters.formatInr(1234567.5), '₹12,34,567.50');
      expect(IndianFormatters.formatInr(50000, showDecimals: false), '₹50,000');
      expect(IndianFormatters.isValidPan('ABCDE1234F'), isTrue);
      expect(IndianFormatters.isValidPan('INVALID123'), isFalse);
      expect(IndianFormatters.maskAadhaar('123456789012'), 'XXXX-XXXX-9012');
      expect(IndianFormatters.normalizeIndianMobile('9842111001'), '+919842111001');
    });
  });
}
