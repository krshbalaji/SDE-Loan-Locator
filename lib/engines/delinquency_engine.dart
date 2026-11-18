import 'dart:math';

import '../models/collection_log_model.dart';
import '../models/installment_model.dart';
import '../models/loan_model.dart';
import '../models/loan_product_model.dart';
import '../models/transaction_model.dart';
import '../utils/indian_formatters.dart';

class WaterfallAllocationResult {
  const WaterfallAllocationResult({
    required this.allocatedFees,
    required this.allocatedInterest,
    required this.allocatedPrincipalOverdue,
    required this.allocatedCurrentPrincipal,
    required this.unallocatedExcess,
    required this.updatedInstallments,
  });

  final double allocatedFees;
  final double allocatedInterest;
  final double allocatedPrincipalOverdue;
  final double allocatedCurrentPrincipal;
  final double unallocatedExcess;
  final List<InstallmentModel> updatedInstallments;

  double get allocatedPrincipalTotal => IndianFormatters.roundPaise(
        allocatedPrincipalOverdue + allocatedCurrentPrincipal,
      );
}

class DelinquencyEvaluationResult {
  const DelinquencyEvaluationResult({
    required this.updatedLoan,
    required this.updatedInstallments,
    required this.newlyBrokenPtpLogIds,
    required this.suggestedLateFeeBase,
    required this.suggestedLateFeeGst,
  });

  final LoanModel updatedLoan;
  final List<InstallmentModel> updatedInstallments;
  final List<String> newlyBrokenPtpLogIds;
  final double suggestedLateFeeBase;
  final double suggestedLateFeeGst;

  double get suggestedLateFeeTotal =>
      IndianFormatters.roundPaise(suggestedLateFeeBase + suggestedLateFeeGst);
}

class AgingBucketStat {
  const AgingBucketStat({
    required this.bucket,
    required this.loanCount,
    required this.principalOutstanding,
  });

  final AgingBucket bucket;
  final int loanCount;
  final double principalOutstanding;
}

class AgentPerformance {
  const AgentPerformance({
    required this.agentId,
    required this.agentName,
    required this.assignedLoans,
    required this.collectedAmount,
    required this.targetAmount,
    required this.efficiencyPct,
    required this.par30Count,
  });

  final String agentId;
  final String agentName;
  final int assignedLoans;
  final double collectedAmount;
  final double targetAmount;
  final double efficiencyPct;
  final int par30Count;
}

class PortfolioKpiSummary {
  const PortfolioKpiSummary({
    required this.totalDeployedCapital,
    required this.activeLoansCount,
    required this.totalPrincipalOutstanding,
    required this.totalInterestOutstanding,
    required this.totalFeesOutstanding,
    required this.collectedMtd,
    required this.collectedYtd,
    required this.principalCollectedYtd,
    required this.interestCollectedYtd,
    required this.par30Amount,
    required this.par30Percent,
    required this.earlyWarningCount,
    required this.agingBreakdown,
    required this.agentLeaderboard,
  });

  final double totalDeployedCapital;
  final int activeLoansCount;
  final double totalPrincipalOutstanding;
  final double totalInterestOutstanding;
  final double totalFeesOutstanding;
  final double collectedMtd;
  final double collectedYtd;
  final double principalCollectedYtd;
  final double interestCollectedYtd;
  final double par30Amount;
  final double par30Percent;
  final int earlyWarningCount;
  final Map<AgingBucket, AgingBucketStat> agingBreakdown;
  final List<AgentPerformance> agentLeaderboard;
}

/// Pure Dart DPD, Aging Bucket, Waterfall Payment Allocation, Early Warning & PAR Engine.
class DelinquencyEngine {
  DelinquencyEngine._();

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// Strict waterfall allocation:
  /// 1. Fees / Penalties -> 2. Accrued Interest -> 3. Principal Overdue -> 4. Current Principal.
  static WaterfallAllocationResult allocatePaymentWaterfall({
    required double paymentAmount,
    required List<InstallmentModel> installments,
    required int activeScheduleVersion,
    required DateTime paymentDate,
  }) {
    var remaining = IndianFormatters.roundPaise(max(0.0, paymentAmount));
    final today = _dateOnly(paymentDate);

    // Work on a mutable copy of active-version installments ordered by installmentNo.
    final activeRows = installments
        .where(
          (i) =>
              i.scheduleVersion == activeScheduleVersion &&
              i.status != InstallmentStatus.superseded,
        )
        .toList()
      ..sort((a, b) => a.installmentNo.compareTo(b.installmentNo));

    final working = List<InstallmentModel>.from(activeRows);
    var feesAllocated = 0.0;
    var interestAllocated = 0.0;
    var principalOverdueAllocated = 0.0;
    var currentPrincipalAllocated = 0.0;

    // Pass 1: Fees / Penalties across all unpaid installments (oldest first)
    for (var i = 0; i < working.length && remaining > 0.009; i++) {
      final row = working[i];
      if (row.feeRemaining > 0.009) {
        final take = IndianFormatters.roundPaise(min(remaining, row.feeRemaining));
        working[i] = row.copyWith(
          feePaid: IndianFormatters.roundPaise(row.feePaid + take),
        );
        feesAllocated = IndianFormatters.roundPaise(feesAllocated + take);
        remaining = IndianFormatters.roundPaise(remaining - take);
      }
    }

    // Pass 2: Accrued / Due Interest (overdue & dueToday only; future interest
    // must not jump ahead of overdue principal)
    for (var i = 0; i < working.length && remaining > 0.009; i++) {
      final row = working[i];
      final isDueOrPast = !_dateOnly(row.dueDate).isAfter(today);
      if (!isDueOrPast) continue;

      if (row.interestRemaining > 0.009) {
        final take = IndianFormatters.roundPaise(
          min(remaining, row.interestRemaining),
        );
        working[i] = row.copyWith(
          interestPaid: IndianFormatters.roundPaise(row.interestPaid + take),
        );
        interestAllocated =
            IndianFormatters.roundPaise(interestAllocated + take);
        remaining = IndianFormatters.roundPaise(remaining - take);
      }
    }

    // Pass 3: Principal Overdue (dueDate < paymentDate)
    for (var i = 0; i < working.length && remaining > 0.009; i++) {
      final row = working[i];
      final isOverdue = _dateOnly(row.dueDate).isBefore(today);
      if (!isOverdue) continue;

      if (row.principalRemaining > 0.009) {
        final take = IndianFormatters.roundPaise(
          min(remaining, row.principalRemaining),
        );
        working[i] = row.copyWith(
          principalPaid: IndianFormatters.roundPaise(row.principalPaid + take),
        );
        principalOverdueAllocated =
            IndianFormatters.roundPaise(principalOverdueAllocated + take);
        remaining = IndianFormatters.roundPaise(remaining - take);
      }
    }

    // Pass 4: Current Principal (dueDate == paymentDate)
    for (var i = 0; i < working.length && remaining > 0.009; i++) {
      final row = working[i];
      final isDueToday = _dateOnly(row.dueDate).isAtSameMomentAs(today);
      if (!isDueToday) continue;

      if (row.principalRemaining > 0.009) {
        final take = IndianFormatters.roundPaise(
          min(remaining, row.principalRemaining),
        );
        working[i] = row.copyWith(
          principalPaid: IndianFormatters.roundPaise(row.principalPaid + take),
        );
        currentPrincipalAllocated =
            IndianFormatters.roundPaise(currentPrincipalAllocated + take);
        remaining = IndianFormatters.roundPaise(remaining - take);
      }
    }

    // Pass 5: Advance / Upcoming Installments (dueDate > paymentDate),
    // settled chronologically (interest then principal per installment)
    for (var i = 0; i < working.length && remaining > 0.009; i++) {
      var row = working[i];
      if (!_dateOnly(row.dueDate).isAfter(today)) continue;

      if (row.interestRemaining > 0.009) {
        final takeInt = IndianFormatters.roundPaise(
          min(remaining, row.interestRemaining),
        );
        row = row.copyWith(
          interestPaid: IndianFormatters.roundPaise(row.interestPaid + takeInt),
        );
        interestAllocated =
            IndianFormatters.roundPaise(interestAllocated + takeInt);
        remaining = IndianFormatters.roundPaise(remaining - takeInt);
      }

      if (remaining > 0.009 && row.principalRemaining > 0.009) {
        final takePrin = IndianFormatters.roundPaise(
          min(remaining, row.principalRemaining),
        );
        row = row.copyWith(
          principalPaid:
              IndianFormatters.roundPaise(row.principalPaid + takePrin),
        );
        currentPrincipalAllocated =
            IndianFormatters.roundPaise(currentPrincipalAllocated + takePrin);
        remaining = IndianFormatters.roundPaise(remaining - takePrin);
      }

      working[i] = row;
    }

    // Refresh installment statuses
    final finalized = working.map((row) {
      final totalPaid =
          row.feePaid + row.interestPaid + row.principalPaid;
      final dueDay = _dateOnly(row.dueDate);
      if (row.isFullyPaid) {
        return row.copyWith(
          status: InstallmentStatus.paid,
          paidDate: row.paidDate ?? paymentDate,
        );
      }
      if (totalPaid > 0.01) {
        return row.copyWith(status: InstallmentStatus.partial);
      }
      if (dueDay.isBefore(today)) {
        return row.copyWith(status: InstallmentStatus.overdue);
      }
      if (dueDay.isAtSameMomentAs(today)) {
        return row.copyWith(status: InstallmentStatus.dueToday);
      }
      return row.copyWith(status: InstallmentStatus.upcoming);
    }).toList();

    return WaterfallAllocationResult(
      allocatedFees: feesAllocated,
      allocatedInterest: interestAllocated,
      allocatedPrincipalOverdue: principalOverdueAllocated,
      allocatedCurrentPrincipal: currentPrincipalAllocated,
      unallocatedExcess: remaining,
      updatedInstallments: finalized,
    );
  }

  /// Evaluates daily DPD, aging bucket, grace-period late fee (+18% GST),
  /// broken PTPs, and Early Warning Flag for a single loan.
  static DelinquencyEvaluationResult evaluateLoan({
    required LoanModel loan,
    required List<InstallmentModel> installments,
    required LoanProductModel product,
    required List<CollectionLogModel> collectionLogs,
    required DateTime asOfDate,
  }) {
    final today = _dateOnly(asOfDate);
    final activeRows = installments
        .where(
          (i) =>
              i.scheduleVersion == loan.scheduleVersion &&
              i.status != InstallmentStatus.superseded,
        )
        .toList()
      ..sort((a, b) => a.installmentNo.compareTo(b.installmentNo));

    var maxDpd = 0;
    var overdueTotal = 0.0;
    final refreshedRows = <InstallmentModel>[];

    for (final row in activeRows) {
      final dueDay = _dateOnly(row.dueDate);
      if (row.isFullyPaid) {
        refreshedRows.add(row.copyWith(status: InstallmentStatus.paid));
        continue;
      }

      final daysPast = today.difference(dueDay).inDays;
      final hasPartial =
          (row.principalPaid + row.interestPaid + row.feePaid) > 0.01;

      InstallmentStatus nextStatus;
      if (daysPast > 0) {
        maxDpd = max(maxDpd, daysPast);
        overdueTotal = IndianFormatters.roundPaise(
          overdueTotal + row.principalRemaining + row.interestRemaining,
        );
        nextStatus =
            hasPartial ? InstallmentStatus.partial : InstallmentStatus.overdue;
      } else if (daysPast == 0) {
        nextStatus =
            hasPartial ? InstallmentStatus.partial : InstallmentStatus.dueToday;
      } else {
        nextStatus =
            hasPartial ? InstallmentStatus.partial : InstallmentStatus.upcoming;
      }
      refreshedRows.add(row.copyWith(status: nextStatus));
    }

    // Identify newly broken PTPs (open PTP whose ptpDate < today)
    final brokenPtpIds = <String>[];
    var hasBrokenPtp = false;
    for (final log in collectionLogs) {
      if (log.ptpStatus == PtpStatus.broken) {
        hasBrokenPtp = true;
      } else if (log.ptpStatus == PtpStatus.open &&
          log.ptpDate != null &&
          _dateOnly(log.ptpDate!).isBefore(today)) {
        brokenPtpIds.add(log.logId);
        hasBrokenPtp = true;
      }
    }

    // Early Warning Triggers:
    // 1) Missed 1st EMI, 2) 2 consecutive partial pays, 3) Broken PTP
    final missedFirstEmi = refreshedRows.any(
      (r) =>
          r.installmentNo == 1 &&
          !r.isFullyPaid &&
          _dateOnly(r.dueDate).isBefore(today),
    );
    var consecutivePartials = 0;
    var hasTwoConsecutivePartials = false;
    for (final r in refreshedRows) {
      if (r.status == InstallmentStatus.partial) {
        consecutivePartials++;
        if (consecutivePartials >= 2) {
          hasTwoConsecutivePartials = true;
          break;
        }
      } else {
        consecutivePartials = 0;
      }
    }
    final earlyWarning =
        missedFirstEmi || hasTwoConsecutivePartials || hasBrokenPtp;

    // Late fee suggestion when DPD exceeds product grace period
    var lateFeeBase = 0.0;
    var lateFeeGst = 0.0;
    if (maxDpd > product.gracePeriodDays && overdueTotal > 0) {
      final rawFee = product.lateFeeType == LateFeeType.flatInr
          ? product.lateFeeValue
          : overdueTotal * (product.lateFeeValue / 100.0);
      final feeSplit = IndianFormatters.computeFeeWithGst(
        baseFee: rawFee,
        gstRatePct: product.gstRatePct,
      );
      lateFeeBase = feeSplit.baseFee;
      lateFeeGst = feeSplit.gstAmount;
    }

    final principalOut = IndianFormatters.roundPaise(
      refreshedRows.fold<double>(0.0, (s, r) => s + r.principalRemaining),
    );
    final interestOut = IndianFormatters.roundPaise(
      refreshedRows.fold<double>(0.0, (s, r) => s + r.interestRemaining),
    );
    final feesOut = IndianFormatters.roundPaise(
      refreshedRows.fold<double>(0.0, (s, r) => s + r.feeRemaining),
    );

    LoanStatus nextLoanStatus = loan.status;
    if (loan.status != LoanStatus.writtenOff &&
        loan.status != LoanStatus.pendingApproval) {
      if (principalOut <= 0.01 && interestOut <= 0.01 && feesOut <= 0.01) {
        nextLoanStatus = LoanStatus.closed;
      } else if (maxDpd > 0) {
        nextLoanStatus = LoanStatus.delinquent;
      } else if (loan.status == LoanStatus.delinquent) {
        nextLoanStatus = loan.scheduleVersion > 1
            ? LoanStatus.restructured
            : LoanStatus.active;
      }
    }

    final updatedLoan = loan.copyWith(
      principalOutstanding: principalOut,
      interestOutstanding: interestOut,
      feesOutstanding: feesOut,
      dpd: nextLoanStatus == LoanStatus.closed ? 0 : maxDpd,
      agingBucket: nextLoanStatus == LoanStatus.closed
          ? AgingBucket.current
          : AgingBucket.fromDpd(maxDpd),
      status: nextLoanStatus,
      earlyWarningFlag: earlyWarning,
    );

    return DelinquencyEvaluationResult(
      updatedLoan: updatedLoan,
      updatedInstallments: refreshedRows,
      newlyBrokenPtpLogIds: brokenPtpIds,
      suggestedLateFeeBase: lateFeeBase,
      suggestedLateFeeGst: lateFeeGst,
    );
  }

  /// Priority queue order: `early_warning_flag` -> `Broken PTP` -> `DPD desc` -> `totalOutstanding desc`.
  static List<LoanModel> sortCollectionsQueue({
    required List<LoanModel> loans,
    required List<CollectionLogModel> allLogs,
  }) {
    final brokenLoanIds = allLogs
        .where((l) => l.ptpStatus == PtpStatus.broken)
        .map((l) => l.loanId)
        .toSet();

    final list = loans.where((l) => l.isPortfolioActive).toList();
    list.sort((a, b) {
      final ewA = a.earlyWarningFlag ? 1 : 0;
      final ewB = b.earlyWarningFlag ? 1 : 0;
      if (ewA != ewB) return ewB.compareTo(ewA);

      final bpA = brokenLoanIds.contains(a.loanId) ? 1 : 0;
      final bpB = brokenLoanIds.contains(b.loanId) ? 1 : 0;
      if (bpA != bpB) return bpB.compareTo(bpA);

      if (a.dpd != b.dpd) return b.dpd.compareTo(a.dpd);
      return b.totalOutstanding.compareTo(a.totalOutstanding);
    });
    return list;
  }

  /// Computes Master/Admin Dashboard KPIs including PAR > 30 % and Agent Leaderboard.
  static PortfolioKpiSummary computePortfolioKpis({
    required List<LoanModel> loans,
    required List<TransactionModel> transactions,
    required Map<String, String> agentNames,
    required DateTime asOfDate,
    int parThresholdDpd = 30,
  }) {
    final activeLoans = loans.where((l) => l.isPortfolioActive).toList();
    final totalDeployed = IndianFormatters.roundPaise(
      loans.fold<double>(0.0, (s, l) => s + l.principalSanctioned),
    );
    final totalPrincipalOut = IndianFormatters.roundPaise(
      activeLoans.fold<double>(0.0, (s, l) => s + l.principalOutstanding),
    );
    final totalInterestOut = IndianFormatters.roundPaise(
      activeLoans.fold<double>(0.0, (s, l) => s + l.interestOutstanding),
    );
    final totalFeesOut = IndianFormatters.roundPaise(
      activeLoans.fold<double>(0.0, (s, l) => s + l.feesOutstanding),
    );

    final par30Amount = IndianFormatters.roundPaise(
      activeLoans
          .where((l) => l.dpd > parThresholdDpd)
          .fold<double>(0.0, (s, l) => s + l.principalOutstanding),
    );
    final par30Percent = totalPrincipalOut > 0
        ? IndianFormatters.roundPaise((par30Amount / totalPrincipalOut) * 100)
        : 0.0;

    final earlyWarningCount =
        activeLoans.where((l) => l.earlyWarningFlag).length;

    // Aging Breakdown
    final agingMap = <AgingBucket, AgingBucketStat>{};
    for (final bucket in AgingBucket.values) {
      final inBucket = activeLoans.where((l) => l.agingBucket == bucket).toList();
      agingMap[bucket] = AgingBucketStat(
        bucket: bucket,
        loanCount: inBucket.length,
        principalOutstanding: IndianFormatters.roundPaise(
          inBucket.fold<double>(0.0, (s, l) => s + l.principalOutstanding),
        ),
      );
    }

    // Net collections MTD & YTD (credits minus reversals)
    final startOfMonth = DateTime(asOfDate.year, asOfDate.month, 1);
    final startOfYear = DateTime(asOfDate.year, 1, 1);
    var collectedMtd = 0.0;
    var collectedYtd = 0.0;
    var principalYtd = 0.0;
    var interestYtd = 0.0;

    final agentCollected = <String, double>{};

    for (final txn in transactions) {
      double sign = 0.0;
      if (txn.isCreditToLoan) {
        sign = 1.0;
      } else if (txn.txnType == TransactionType.reversal) {
        sign = -1.0;
      }
      if (sign == 0.0) continue;

      if (!txn.createdAt.isBefore(startOfYear)) {
        collectedYtd += sign * txn.totalAmount;
        principalYtd += sign * txn.allocatedPrincipal;
        interestYtd += sign * txn.allocatedInterest;
      }
      if (!txn.createdAt.isBefore(startOfMonth)) {
        collectedMtd += sign * txn.totalAmount;
        agentCollected[txn.collectedByUid] =
            (agentCollected[txn.collectedByUid] ?? 0.0) +
                (sign * txn.totalAmount);
      }
    }

    // Agent Collection Efficiency Leaderboard
    final agentIds = <String>{
      ...agentNames.keys,
      ...activeLoans.map((l) => l.assignedAgentId).where((id) => id.isNotEmpty),
    };
    final leaderboard = <AgentPerformance>[];
    for (final agentId in agentIds) {
      final agentLoans =
          activeLoans.where((l) => l.assignedAgentId == agentId).toList();
      if (agentLoans.isEmpty && !agentCollected.containsKey(agentId)) continue;
      final target = IndianFormatters.roundPaise(
        agentLoans.fold<double>(0.0, (s, l) => s + l.emiAmount),
      );
      final collected = IndianFormatters.roundPaise(
        max(0.0, agentCollected[agentId] ?? 0.0),
      );
      final eff = target > 0
          ? IndianFormatters.roundPaise(min(150.0, (collected / target) * 100))
          : 0.0;
      leaderboard.add(
        AgentPerformance(
          agentId: agentId,
          agentName: agentNames[agentId] ?? agentId,
          assignedLoans: agentLoans.length,
          collectedAmount: collected,
          targetAmount: target,
          efficiencyPct: eff,
          par30Count: agentLoans.where((l) => l.dpd > parThresholdDpd).length,
        ),
      );
    }
    leaderboard.sort((a, b) => b.efficiencyPct.compareTo(a.efficiencyPct));

    return PortfolioKpiSummary(
      totalDeployedCapital: totalDeployed,
      activeLoansCount: activeLoans.length,
      totalPrincipalOutstanding: totalPrincipalOut,
      totalInterestOutstanding: totalInterestOut,
      totalFeesOutstanding: totalFeesOut,
      collectedMtd: IndianFormatters.roundPaise(max(0.0, collectedMtd)),
      collectedYtd: IndianFormatters.roundPaise(max(0.0, collectedYtd)),
      principalCollectedYtd: IndianFormatters.roundPaise(max(0.0, principalYtd)),
      interestCollectedYtd: IndianFormatters.roundPaise(max(0.0, interestYtd)),
      par30Amount: par30Amount,
      par30Percent: par30Percent,
      earlyWarningCount: earlyWarningCount,
      agingBreakdown: agingMap,
      agentLeaderboard: leaderboard,
    );
  }
}
