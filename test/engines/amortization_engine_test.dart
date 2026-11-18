import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/engines/amortization_engine.dart';
import 'package:loan_locator_app/models/installment_model.dart';
import 'package:loan_locator_app/models/loan_model.dart';
import 'package:loan_locator_app/models/loan_product_model.dart';

void main() {
  group('AmortizationEngine', () {
    test('calculates standard reducing balance monthly EMI accurately', () {
      // ₹1,00,000 at 12% p.a. for 12 months -> ₹8,884.88
      final emi = AmortizationEngine.calculateEmi(
        principal: 100000,
        annualInterestRate: 12.0,
        tenureInstallments: 12,
        interestMethod: InterestMethod.reducingBalance,
        frequency: RepaymentFrequency.monthly,
      );
      expect(emi, closeTo(8884.88, 0.05));
    });

    test('calculates flat rate weekly EMI accurately', () {
      // ₹52,000 at 20% flat for 52 weeks (1 year): interest = ₹10,400 -> total ₹62,400 / 52 = ₹1,200
      final emi = AmortizationEngine.calculateEmi(
        principal: 52000,
        annualInterestRate: 20.0,
        tenureInstallments: 52,
        interestMethod: InterestMethod.flatRate,
        frequency: RepaymentFrequency.weekly,
      );
      expect(emi, 1200.0);
    });

    test('generated schedule reconciles total principal exactly', () {
      final rows = AmortizationEngine.generateSchedule(
        loanId: 'SDE-LN-9001',
        principal: 250000,
        annualInterestRate: 18.0,
        tenureInstallments: 18,
        interestMethod: InterestMethod.reducingBalance,
        frequency: RepaymentFrequency.monthly,
        firstDueDate: DateTime(2026, 1, 31),
      );
      expect(rows.length, 18);
      final totalPrincipal =
          rows.fold<double>(0.0, (s, r) => s + r.principalDue);
      expect(totalPrincipal, closeTo(250000.0, 0.01));
      // Verifies Jan 31 -> Feb 28 end-of-month clamping
      expect(rows[1].dueDate, DateTime(2026, 2, 28));
    });

    test('What-If Simulator compares Option A (Reduce Tenure) vs Option B (Reduce EMI)', () {
      final emi = AmortizationEngine.calculateEmi(
        principal: 300000,
        annualInterestRate: 24.0,
        tenureInstallments: 24,
        interestMethod: InterestMethod.reducingBalance,
        frequency: RepaymentFrequency.monthly,
      );

      final sim = AmortizationEngine.simulateWhatIf(
        principalOutstanding: 300000,
        annualInterestRate: 24.0,
        remainingInstallments: 24,
        currentEmi: emi,
        interestMethod: InterestMethod.reducingBalance,
        frequency: RepaymentFrequency.monthly,
        lumpSumPrepayment: 60000,
        extraPerInstallment: 1000,
      );

      // Option A reduces tenure & saves more interest than Option B
      expect(sim.optionAReduceTenure.newTenureInstallments, lessThan(24));
      expect(sim.optionAReduceTenure.installmentsSaved, greaterThan(0));
      expect(sim.optionAReduceTenure.interestSaved, greaterThan(0));

      // Option B keeps tenure at 24 and reduces monthly EMI
      expect(sim.optionBReduceEmi.newTenureInstallments, 24);
      expect(sim.optionBReduceEmi.newEmi, lessThan(emi));
      expect(sim.optionBReduceEmi.monthlyCashflowRelief, greaterThan(0));
      expect(
        sim.optionAReduceTenure.interestSaved,
        greaterThan(sim.optionBReduceEmi.interestSaved),
      );
    });

    test('non-destructive restructuring marks v1 rows SUPERSEDED and emits v2 rows', () {
      final v1 = AmortizationEngine.generateSchedule(
        loanId: 'SDE-LN-9002',
        principal: 100000,
        annualInterestRate: 18.0,
        tenureInstallments: 10,
        interestMethod: InterestMethod.reducingBalance,
        frequency: RepaymentFrequency.monthly,
        firstDueDate: DateTime(2026, 1, 10),
      );
      // Mark first 2 rows paid
      final modifiedV1 = [
        v1[0].copyWith(
          principalPaid: v1[0].principalDue,
          interestPaid: v1[0].interestDue,
          status: InstallmentStatus.paid,
        ),
        v1[1].copyWith(
          principalPaid: v1[1].principalDue,
          interestPaid: v1[1].interestDue,
          status: InstallmentStatus.paid,
        ),
        ...v1.sublist(2),
      ];

      final loan = LoanModel(
        loanId: 'SDE-LN-9002',
        applicationNo: 'APP-9002',
        borrowerId: 'SDE-CUST-1',
        productId: 'PROD-QBL',
        assignedAgentId: 'uid_agent_1',
        principalSanctioned: 100000,
        processingFeeAmount: 2000,
        gstAmount: 360,
        netDisbursedAmount: 97640,
        interestRateAnnual: 18.0,
        interestMethod: InterestMethod.reducingBalance,
        tenureInstallments: 10,
        emiAmount: 10843.42,
        disbursementDate: DateTime(2025, 12, 10),
        firstDueDate: DateTime(2026, 1, 10),
        maturityDate: v1.last.dueDate,
        principalOutstanding: 81000,
      );

      final result = AmortizationEngine.restructureLoan(
        loan: loan,
        existingSchedule: modifiedV1,
        newPrincipal: 81000,
        newAnnualInterestRate: 16.0,
        newTenureInstallments: 12,
        newFirstDueDate: DateTime(2026, 4, 10),
      );

      expect(result.updatedLoan.scheduleVersion, 2);
      expect(result.updatedLoan.status, LoanStatus.restructured);
      expect(result.supersededInstallments.length, 8);
      expect(
        result.supersededInstallments
            .every((r) => r.status == InstallmentStatus.superseded),
        isTrue,
      );
      expect(result.newVersionInstallments.length, 12);
      expect(
        result.newVersionInstallments.every((r) => r.scheduleVersion == 2),
        isTrue,
      );
    });
  });
}
