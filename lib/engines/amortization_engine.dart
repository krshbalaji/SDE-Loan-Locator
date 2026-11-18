import 'dart:math';

import '../models/installment_model.dart';
import '../models/loan_model.dart';
import '../models/loan_product_model.dart';
import '../utils/indian_formatters.dart';

class PrepaymentOptionResult {
  const PrepaymentOptionResult({
    required this.newEmi,
    required this.newTenureInstallments,
    required this.installmentsSaved,
    required this.monthlyCashflowRelief,
    required this.newTotalInterest,
    required this.interestSaved,
  });

  final double newEmi;
  final int newTenureInstallments;
  final int installmentsSaved;
  final double monthlyCashflowRelief;
  final double newTotalInterest;
  final double interestSaved;
}

class WhatIfSimulationResult {
  const WhatIfSimulationResult({
    required this.currentPrincipal,
    required this.currentEmi,
    required this.remainingInstallments,
    required this.baselineTotalInterest,
    required this.lumpSumPrepayment,
    required this.extraPerInstallment,
    required this.optionAReduceTenure,
    required this.optionBReduceEmi,
  });

  final double currentPrincipal;
  final double currentEmi;
  final int remainingInstallments;
  final double baselineTotalInterest;
  final double lumpSumPrepayment;
  final double extraPerInstallment;
  final PrepaymentOptionResult optionAReduceTenure;
  final PrepaymentOptionResult optionBReduceEmi;
}

class PayoffQuote {
  const PayoffQuote({
    required this.loanId,
    required this.asOfDate,
    required this.principalBalance,
    required this.accruedInterest,
    required this.unpaidFees,
    required this.totalPayoffAmount,
  });

  final String loanId;
  final DateTime asOfDate;
  final double principalBalance;
  final double accruedInterest;
  final double unpaidFees;
  final double totalPayoffAmount;
}

class RestructureResult {
  const RestructureResult({
    required this.updatedLoan,
    required this.supersededInstallments,
    required this.newVersionInstallments,
  });

  final LoanModel updatedLoan;
  final List<InstallmentModel> supersededInstallments;
  final List<InstallmentModel> newVersionInstallments;
}

/// Pure Dart Amortization, What-If Prepayment Simulator, Payoff & Restructuring Engine.
class AmortizationEngine {
  AmortizationEngine._();

  static double periodicRate(
    double annualInterestRate,
    RepaymentFrequency frequency,
  ) {
    return (annualInterestRate / 100.0) / frequency.periodsPerYear;
  }

  /// Advances [start] by [step] repayment periods with safe end-of-month clamping.
  static DateTime addPeriod(
    DateTime start,
    RepaymentFrequency frequency,
    int step,
  ) {
    switch (frequency) {
      case RepaymentFrequency.daily:
        return DateTime(start.year, start.month, start.day + step);
      case RepaymentFrequency.weekly:
        return DateTime(start.year, start.month, start.day + (7 * step));
      case RepaymentFrequency.monthly:
        final totalMonths = (start.year * 12 + (start.month - 1)) + step;
        final targetYear = totalMonths ~/ 12;
        final targetMonth = (totalMonths % 12) + 1;
        final lastDayOfMonth = DateTime(targetYear, targetMonth + 1, 0).day;
        final clampedDay = min(start.day, lastDayOfMonth);
        return DateTime(targetYear, targetMonth, clampedDay);
    }
  }

  /// Calculates periodic EMI for Reducing Balance or Flat Rate loans.
  static double calculateEmi({
    required double principal,
    required double annualInterestRate,
    required int tenureInstallments,
    required InterestMethod interestMethod,
    required RepaymentFrequency frequency,
  }) {
    if (principal <= 0 || tenureInstallments <= 0) return 0.0;

    if (interestMethod == InterestMethod.flatRate) {
      final years = tenureInstallments / frequency.periodsPerYear;
      final totalInterest = principal * (annualInterestRate / 100.0) * years;
      return IndianFormatters.roundPaise(
        (principal + totalInterest) / tenureInstallments,
      );
    }

    final r = periodicRate(annualInterestRate, frequency);
    if (r <= 0) {
      return IndianFormatters.roundPaise(principal / tenureInstallments);
    }
    final factor = pow(1 + r, tenureInstallments).toDouble();
    final emi = principal * (r * factor) / (factor - 1);
    return IndianFormatters.roundPaise(emi);
  }

  /// Generates a complete versioned amortization schedule (`installmentNo` 1..N).
  static List<InstallmentModel> generateSchedule({
    required String loanId,
    required double principal,
    required double annualInterestRate,
    required int tenureInstallments,
    required InterestMethod interestMethod,
    required RepaymentFrequency frequency,
    required DateTime firstDueDate,
    int scheduleVersion = 1,
    double? overrideEmi,
  }) {
    if (principal <= 0 || tenureInstallments <= 0) return const [];

    final emi = overrideEmi ??
        calculateEmi(
          principal: principal,
          annualInterestRate: annualInterestRate,
          tenureInstallments: tenureInstallments,
          interestMethod: interestMethod,
          frequency: frequency,
        );

    final r = periodicRate(annualInterestRate, frequency);
    final rows = <InstallmentModel>[];
    var opening = IndianFormatters.roundPaise(principal);

    final flatYears = tenureInstallments / frequency.periodsPerYear;
    final flatTotalInterest = IndianFormatters.roundPaise(
      principal * (annualInterestRate / 100.0) * flatYears,
    );
    final flatInterestPerPeriod =
        IndianFormatters.roundPaise(flatTotalInterest / tenureInstallments);
    var flatInterestAllocated = 0.0;

    for (var i = 1; i <= tenureInstallments; i++) {
      final isLast = i == tenureInstallments;
      final dueDate = addPeriod(firstDueDate, frequency, i - 1);

      double interestDue;
      double principalDue;

      if (interestMethod == InterestMethod.flatRate) {
        interestDue = isLast
            ? IndianFormatters.roundPaise(
                max(0, flatTotalInterest - flatInterestAllocated),
              )
            : flatInterestPerPeriod;
        flatInterestAllocated =
            IndianFormatters.roundPaise(flatInterestAllocated + interestDue);
        principalDue = isLast
            ? opening
            : IndianFormatters.roundPaise(min(opening, max(0, emi - interestDue)));
      } else {
        interestDue = IndianFormatters.roundPaise(opening * r);
        if (isLast) {
          principalDue = opening;
        } else {
          principalDue =
              IndianFormatters.roundPaise(min(opening, max(0, emi - interestDue)));
        }
      }

      final totalDue = IndianFormatters.roundPaise(principalDue + interestDue);
      rows.add(
        InstallmentModel(
          installmentId: '${loanId}_v${scheduleVersion}_$i',
          loanId: loanId,
          scheduleVersion: scheduleVersion,
          installmentNo: i,
          dueDate: dueDate,
          openingPrincipal: opening,
          principalDue: principalDue,
          interestDue: interestDue,
          totalDue: totalDue,
          status: InstallmentStatus.upcoming,
        ),
      );

      opening = IndianFormatters.roundPaise(max(0, opening - principalDue));
    }

    return rows;
  }

  /// Simulates lump-sum prepayment (`ΔP`) and/or recurring extra EMI (`ΔE`)
  /// comparing Option A (Reduce Tenure) vs Option B (Reduce EMI).
  static WhatIfSimulationResult simulateWhatIf({
    required double principalOutstanding,
    required double annualInterestRate,
    required int remainingInstallments,
    required double currentEmi,
    required InterestMethod interestMethod,
    required RepaymentFrequency frequency,
    double lumpSumPrepayment = 0.0,
    double extraPerInstallment = 0.0,
  }) {
    final safePrincipal = max(0.0, principalOutstanding);
    final safeRemaining = max(1, remainingInstallments);
    final safeLumpSum = lumpSumPrepayment.clamp(0.0, safePrincipal);
    final safeExtra = max(0.0, extraPerInstallment);

    final baselineInterest = _computeRemainingInterest(
      principal: safePrincipal,
      annualInterestRate: annualInterestRate,
      tenureInstallments: safeRemaining,
      emi: currentEmi,
      interestMethod: interestMethod,
      frequency: frequency,
    );

    final reducedPrincipal =
        IndianFormatters.roundPaise(max(0.0, safePrincipal - safeLumpSum));

    // Option A: Keep EMI (+ extra ΔE), reduce tenure N'
    final optionA = _simulateOptionAReduceTenure(
      reducedPrincipal: reducedPrincipal,
      annualInterestRate: annualInterestRate,
      remainingInstallments: safeRemaining,
      targetEmi: IndianFormatters.roundPaise(currentEmi + safeExtra),
      interestMethod: interestMethod,
      frequency: frequency,
      baselineInterest: baselineInterest,
    );

    // Option B: Keep tenure N_rem constant, reduce EMI'
    final newEmi = reducedPrincipal <= 0
        ? 0.0
        : calculateEmi(
            principal: reducedPrincipal,
            annualInterestRate: annualInterestRate,
            tenureInstallments: safeRemaining,
            interestMethod: interestMethod,
            frequency: frequency,
          );
    final optionBInterest = reducedPrincipal <= 0
        ? 0.0
        : _computeRemainingInterest(
            principal: reducedPrincipal,
            annualInterestRate: annualInterestRate,
            tenureInstallments: safeRemaining,
            emi: newEmi,
            interestMethod: interestMethod,
            frequency: frequency,
          );
    final optionB = PrepaymentOptionResult(
      newEmi: newEmi,
      newTenureInstallments: reducedPrincipal <= 0 ? 0 : safeRemaining,
      installmentsSaved: reducedPrincipal <= 0 ? safeRemaining : 0,
      monthlyCashflowRelief: IndianFormatters.roundPaise(
        max(0.0, currentEmi - newEmi),
      ),
      newTotalInterest: optionBInterest,
      interestSaved: IndianFormatters.roundPaise(
        max(0.0, baselineInterest - optionBInterest),
      ),
    );

    return WhatIfSimulationResult(
      currentPrincipal: safePrincipal,
      currentEmi: currentEmi,
      remainingInstallments: safeRemaining,
      baselineTotalInterest: baselineInterest,
      lumpSumPrepayment: safeLumpSum,
      extraPerInstallment: safeExtra,
      optionAReduceTenure: optionA,
      optionBReduceEmi: optionB,
    );
  }

  static PrepaymentOptionResult _simulateOptionAReduceTenure({
    required double reducedPrincipal,
    required double annualInterestRate,
    required int remainingInstallments,
    required double targetEmi,
    required InterestMethod interestMethod,
    required RepaymentFrequency frequency,
    required double baselineInterest,
  }) {
    if (reducedPrincipal <= 0.01) {
      return PrepaymentOptionResult(
        newEmi: 0.0,
        newTenureInstallments: 0,
        installmentsSaved: remainingInstallments,
        monthlyCashflowRelief: 0.0,
        newTotalInterest: 0.0,
        interestSaved: baselineInterest,
      );
    }

    final r = periodicRate(annualInterestRate, frequency);
    var balance = reducedPrincipal;
    var totalInterest = 0.0;
    var months = 0;
    final maxCap = remainingInstallments * 2 + 12;

    if (interestMethod == InterestMethod.flatRate) {
      // Flat rate proportional tenure compression based on reduced principal
      final yearsPerInst = 1.0 / frequency.periodsPerYear;
      final ratePerInst = (annualInterestRate / 100.0) * yearsPerInst;
      final flatInterestPerPeriod =
          IndianFormatters.roundPaise(reducedPrincipal * ratePerInst);
      final principalPerStep = max(1.0, targetEmi - flatInterestPerPeriod);
      while (balance > 0.01 && months < maxCap) {
        months++;
        final interest = flatInterestPerPeriod;
        final principalPay = min(balance, principalPerStep);
        totalInterest += interest;
        balance = IndianFormatters.roundPaise(balance - principalPay);
      }
    } else {
      while (balance > 0.01 && months < maxCap) {
        months++;
        final interest = IndianFormatters.roundPaise(balance * r);
        final effectivePayment = max(targetEmi, interest + 1.0);
        final principalPay = min(balance, effectivePayment - interest);
        totalInterest += interest;
        balance = IndianFormatters.roundPaise(balance - principalPay);
      }
    }

    final roundedInterest = IndianFormatters.roundPaise(totalInterest);
    return PrepaymentOptionResult(
      newEmi: targetEmi,
      newTenureInstallments: months,
      installmentsSaved: max(0, remainingInstallments - months),
      monthlyCashflowRelief: 0.0,
      newTotalInterest: roundedInterest,
      interestSaved: IndianFormatters.roundPaise(
        max(0.0, baselineInterest - roundedInterest),
      ),
    );
  }

  static double _computeRemainingInterest({
    required double principal,
    required double annualInterestRate,
    required int tenureInstallments,
    required double emi,
    required InterestMethod interestMethod,
    required RepaymentFrequency frequency,
  }) {
    if (principal <= 0.01 || tenureInstallments <= 0) return 0.0;
    if (interestMethod == InterestMethod.flatRate) {
      final years = tenureInstallments / frequency.periodsPerYear;
      return IndianFormatters.roundPaise(
        principal * (annualInterestRate / 100.0) * years,
      );
    }

    final r = periodicRate(annualInterestRate, frequency);
    var balance = principal;
    var totalInterest = 0.0;
    for (var i = 1; i <= tenureInstallments && balance > 0.01; i++) {
      final interest = IndianFormatters.roundPaise(balance * r);
      final principalPay = i == tenureInstallments
          ? balance
          : min(balance, max(0.0, emi - interest));
      totalInterest += interest;
      balance = IndianFormatters.roundPaise(balance - principalPay);
    }
    return IndianFormatters.roundPaise(totalInterest);
  }

  /// Generates a foreclosure / payoff quote as of [asOfDate].
  static PayoffQuote calculatePayoffQuote({
    required LoanModel loan,
    required List<InstallmentModel> activeSchedule,
    required DateTime asOfDate,
  }) {
    final activeRows = activeSchedule
        .where((i) => i.scheduleVersion == loan.scheduleVersion)
        .toList();

    final unpaidFees = IndianFormatters.roundPaise(
      activeRows.fold<double>(0.0, (sum, row) => sum + row.feeRemaining) +
          max(0.0, loan.feesOutstanding -
              activeRows.fold<double>(0.0, (s, r) => s + r.feeRemaining)),
    );

    final accruedInterest = IndianFormatters.roundPaise(
      activeRows
          .where((row) => !row.dueDate.isAfter(asOfDate))
          .fold<double>(0.0, (sum, row) => sum + row.interestRemaining),
    );

    final principalBal = IndianFormatters.roundPaise(loan.principalOutstanding);
    final total = IndianFormatters.roundPaise(
      principalBal + accruedInterest + unpaidFees,
    );

    return PayoffQuote(
      loanId: loan.loanId,
      asOfDate: asOfDate,
      principalBalance: principalBal,
      accruedInterest: accruedInterest,
      unpaidFees: unpaidFees,
      totalPayoffAmount: total,
    );
  }

  /// Non-destructive restructuring (`v1 -> v2`):
  /// Marks unpaid current-version installments `SUPERSEDED` and generates a new version.
  static RestructureResult restructureLoan({
    required LoanModel loan,
    required List<InstallmentModel> existingSchedule,
    required double newPrincipal,
    required double newAnnualInterestRate,
    required int newTenureInstallments,
    required DateTime newFirstDueDate,
    InterestMethod? newInterestMethod,
    RepaymentFrequency? newFrequency,
  }) {
    final nextVersion = loan.scheduleVersion + 1;
    final method = newInterestMethod ?? loan.interestMethod;
    final freq = newFrequency ?? loan.repaymentFrequency;

    final superseded = existingSchedule
        .where(
          (row) =>
              row.scheduleVersion == loan.scheduleVersion &&
              row.status != InstallmentStatus.paid &&
              row.status != InstallmentStatus.superseded,
        )
        .map((row) => row.copyWith(status: InstallmentStatus.superseded))
        .toList();

    final newEmi = calculateEmi(
      principal: newPrincipal,
      annualInterestRate: newAnnualInterestRate,
      tenureInstallments: newTenureInstallments,
      interestMethod: method,
      frequency: freq,
    );

    final newRows = generateSchedule(
      loanId: loan.loanId,
      principal: newPrincipal,
      annualInterestRate: newAnnualInterestRate,
      tenureInstallments: newTenureInstallments,
      interestMethod: method,
      frequency: freq,
      firstDueDate: newFirstDueDate,
      scheduleVersion: nextVersion,
      overrideEmi: newEmi,
    );

    final newMaturity = newRows.isNotEmpty ? newRows.last.dueDate : newFirstDueDate;
    final newInterestOutstanding = IndianFormatters.roundPaise(
      newRows.fold<double>(0.0, (sum, r) => sum + r.interestDue),
    );

    final updatedLoan = loan.copyWith(
      interestRateAnnual: newAnnualInterestRate,
      interestMethod: method,
      repaymentFrequency: freq,
      tenureInstallments: newTenureInstallments,
      emiAmount: newEmi,
      firstDueDate: newFirstDueDate,
      maturityDate: newMaturity,
      scheduleVersion: nextVersion,
      principalOutstanding: IndianFormatters.roundPaise(newPrincipal),
      interestOutstanding: newInterestOutstanding,
      dpd: 0,
      agingBucket: AgingBucket.current,
      status: LoanStatus.restructured,
    );

    return RestructureResult(
      updatedLoan: updatedLoan,
      supersededInstallments: superseded,
      newVersionInstallments: newRows,
    );
  }
}
