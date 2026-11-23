import 'package:flutter_test/flutter_test.dart';
import 'package:loan_locator_app/engines/amortization_engine.dart';
import 'package:loan_locator_app/models/loan_product_model.dart';
import 'package:loan_locator_app/utils/indian_formatters.dart';

void main() {
  group('IndianFormatters & AmortizationEngine', () {
    test('roundPaise guards non-finite values and rounds to 2 decimals', () {
      expect(IndianFormatters.roundPaise(123.456), 123.46);
      expect(IndianFormatters.roundPaise(double.nan), 0.0);
      expect(IndianFormatters.roundPaise(double.infinity), 0.0);
      expect(IndianFormatters.roundPaise(double.negativeInfinity), 0.0);
    });

    test('calculateEmi and generateSchedule produce N installments', () {
      final emi = AmortizationEngine.calculateEmi(
        principal: 500000,
        annualInterestRate: 10.5,
        tenureInstallments: 24,
        interestMethod: InterestMethod.reducingBalance,
        frequency: RepaymentFrequency.monthly,
      );
      expect(emi, greaterThan(20000));

      final schedule = AmortizationEngine.generateSchedule(
        loanId: 'LN-TEST-001',
        scheduleVersion: 1,
        principal: 500000,
        annualInterestRate: 10.5,
        tenureInstallments: 24,
        interestMethod: InterestMethod.reducingBalance,
        frequency: RepaymentFrequency.monthly,
        firstDueDate: DateTime(2026, 5, 1),
      );
      expect(schedule.length, 24);
      expect(schedule.first.installmentNo, 1);
      expect(schedule.last.installmentNo, 24);
      expect(schedule.last.totalRemaining, greaterThan(0));
    });
  });
}