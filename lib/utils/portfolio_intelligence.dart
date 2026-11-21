import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import 'indian_formatters.dart';

enum DiagnosticSeverity { good, watch, alert }

class DiagnosticCellMeta {
  const DiagnosticCellMeta({
    required this.title,
    required this.valueLabel,
    required this.severity,
    required this.whyPresented,
    required this.benchmark,
    required this.dataComparison,
    required this.improvementAction,
  });

  final String title;
  final String valueLabel;
  final DiagnosticSeverity severity;
  final String whyPresented;
  final String benchmark;
  final String dataComparison;
  final String improvementAction;
}

class DimensionRiskRow {
  const DimensionRiskRow({
    required this.bucketLabel,
    required this.loanCount,
    required this.sanctionedTotal,
    required this.posTotal,
    required this.npaCount,
    required this.npaPos,
    required this.npaPosPct,
    required this.diagnostic,
  });

  final String bucketLabel;
  final int loanCount;
  final double sanctionedTotal;
  final double posTotal;
  final int npaCount;
  final double npaPos;
  final double npaPosPct;
  final DiagnosticCellMeta diagnostic;
}

class NpaScenarioFinding {
  const NpaScenarioFinding({
    required this.scenarioTitle,
    required this.affectedLoans,
    required this.affectedPos,
    required this.diagnostic,
  });

  final String scenarioTitle;
  final int affectedLoans;
  final double affectedPos;
  final DiagnosticCellMeta diagnostic;
}

class PortfolioIntelligenceSummary {
  const PortfolioIntelligenceSummary({
    required this.totalLoans,
    required this.totalSanctioned,
    required this.totalDisbursed,
    required this.totalPos,
    required this.npaLoans,
    required this.npaPos,
    required this.npaPosPct,
    required this.weightedRoiPct,
    required this.estimatedCollectionEfficiencyPct,
    required this.missingScoreCount,
    required this.missingGeoCount,
    required this.salesKpiDiagnostic,
    required this.ceKpiDiagnostic,
    required this.npaKpiDiagnostic,
    required this.costKpiDiagnostic,
    required this.byScoreBand,
    required this.byTenureBand,
    required this.byLoanAvailedBand,
    required this.npaScenarios,
  });

  final int totalLoans;
  final double totalSanctioned;
  final double totalDisbursed;
  final double totalPos;
  final int npaLoans;
  final double npaPos;
  final double npaPosPct;
  final double weightedRoiPct;
  final double estimatedCollectionEfficiencyPct;
  final int missingScoreCount;
  final int missingGeoCount;
  final DiagnosticCellMeta salesKpiDiagnostic;
  final DiagnosticCellMeta ceKpiDiagnostic;
  final DiagnosticCellMeta npaKpiDiagnostic;
  final DiagnosticCellMeta costKpiDiagnostic;
  final List<DimensionRiskRow> byScoreBand;
  final List<DimensionRiskRow> byTenureBand;
  final List<DimensionRiskRow> byLoanAvailedBand;
  final List<NpaScenarioFinding> npaScenarios;
}

/// Computes Sales, Credit/NPA, Collection Efficiency, and hoverable cell
/// diagnostics from LoanModel and BorrowerModel records.
class PortfolioIntelligence {
  PortfolioIntelligence._();

  static bool _isNpa(LoanModel loan) =>
      loan.dpd >= 90 ||
      loan.agingBucket == AgingBucket.dpd90Plus;

  static PortfolioIntelligenceSummary analyze({
    required List<LoanModel> loans,
    required Map<String, BorrowerModel> borrowerMap,
  }) {
    var totalSanctioned = 0.0;
    var totalDisbursed = 0.0;
    var totalPos = 0.0;
    var weightedRateNumerator = 0.0;
    var totalEmiDemand = 0.0;
    var estimatedCollected = 0.0;
    var npaLoans = 0;
    var npaPos = 0.0;
    var missingScore = 0;
    var missingGeo = 0;

    for (final b in borrowerMap.values) {
      if (b.creditScore == null || b.creditScore! <= 0) missingScore++;
      if (!b.hasValidCoordinates) missingGeo++;
    }

    for (final l in loans) {
      totalSanctioned += l.principalSanctioned;
      totalDisbursed += l.netDisbursedAmount > 0 ? l.netDisbursedAmount : l.principalSanctioned;
      totalPos += l.principalOutstanding;
      weightedRateNumerator += l.interestRateAnnual * (l.principalOutstanding > 0 ? l.principalOutstanding : 1.0);
      totalEmiDemand += l.emiAmount;

      if (l.dpd == 0) {
        estimatedCollected += l.emiAmount;
      } else if (l.dpd <= 30) {
        estimatedCollected += l.emiAmount * 0.75;
      } else if (l.dpd <= 90) {
        estimatedCollected += l.emiAmount * 0.35;
      }

      if (_isNpa(l)) {
        npaLoans++;
        npaPos += l.principalOutstanding;
      }
    }

    final posDenom = totalPos > 0 ? totalPos : 1.0;
    final npaPosPct = (npaPos / posDenom) * 100.0;
    final weightedRoiPct = weightedRateNumerator / posDenom;
    final cePct = totalEmiDemand > 0
        ? ((estimatedCollected / totalEmiDemand) * 100.0).clamp(0.0, 100.0)
        : 100.0;

    final salesDiag = DiagnosticCellMeta(
      title: 'Sales Disbursal & Ticket Book',
      valueLabel: IndianFormatters.formatInr(totalDisbursed),
      severity: DiagnosticSeverity.good,
      whyPresented:
          'Pairs net disbursed volume with sanctioned book size so origination velocity is viewed alongside real cash deployed.',
      benchmark: 'Disbursal / Sanction >= 90%; balanced HF & LAP mix',
      dataComparison:
          'Disbursed ${IndianFormatters.formatInr(totalDisbursed)} vs Sanctioned ${IndianFormatters.formatInr(totalSanctioned)} across ${loans.length} loans.',
      improvementAction:
          'Track pending sanction-to-disbursal lag and segment ticket/tenure mix by branch and relationship manager.',
    );

    final ceDiag = DiagnosticCellMeta(
      title: 'Collection Efficiency (CE)',
      valueLabel: '${cePct.toStringAsFixed(1)}%',
      severity: cePct >= 95.0
          ? DiagnosticSeverity.good
          : (cePct >= 88.0 ? DiagnosticSeverity.watch : DiagnosticSeverity.alert),
      whyPresented:
          'Measures EMI recovery traction across current and overdue accounts to spot collection drag early.',
      benchmark: 'Target >= 95.0% current/period collection efficiency',
      dataComparison:
          'Estimated CE ${cePct.toStringAsFixed(1)}% vs 95.0% target; ${loans.where((l) => l.dpd > 0).length} loans currently in DPD > 0.',
      improvementAction:
          'Prioritize 1–30 and 61–90 DPD beat stops using BeatRoutePlanner and send Tamil/English reminders before due dates.',
    );

    final npaDiag = DiagnosticCellMeta(
      title: 'Gross NPA (90+ DPD POS %)',
      valueLabel: '${npaPosPct.toStringAsFixed(2)}%',
      severity: npaPosPct <= 2.5
          ? DiagnosticSeverity.good
          : (npaPosPct <= 5.0 ? DiagnosticSeverity.watch : DiagnosticSeverity.alert),
      whyPresented:
          'Tracks 90+ DPD exposure on Principal Outstanding so large HF/LAP tickets reflect true balance-sheet risk.',
      benchmark: 'Benchmark <= 2.50% POS in NPA (90+ DPD)',
      dataComparison:
          'NPA POS ${IndianFormatters.formatInr(npaPos)} (${npaPosPct.toStringAsFixed(2)}%) across $npaLoans NPA loans out of ${loans.length} total.',
      improvementAction:
          'Ring-fence 61–90 DPD accounts before 90-day roll-forward and enforce Maker-Checker review on restructures/reversals.',
    );

    final costDiag = DiagnosticCellMeta(
      title: 'Portfolio Weighted ROI',
      valueLabel: '${weightedRoiPct.toStringAsFixed(2)}%',
      severity: weightedRoiPct >= 11.0 ? DiagnosticSeverity.good : DiagnosticSeverity.watch,
      whyPresented:
          'Monitors POS-weighted interest rate alongside fee/LTV/FOIR profile to protect net spread after credit cost.',
      benchmark: 'Healthy NBFC yield spread vs borrowing cost & credit slippage',
      dataComparison:
          'POS-weighted ROI ${weightedRoiPct.toStringAsFixed(2)}% across ${IndianFormatters.formatInr(totalPos)} POS ($missingScore borrowers missing credit score).',
      improvementAction:
          'Complete credit score, FOIR, and LTV fields on imported records and review high-rate/high-DPD cohorts.',
    );

    final byScoreBand = _groupBuckets(
      loans: loans,
      borrowerMap: borrowerMap,
      titlePrefix: 'Credit Score Band',
      benchmarkText: 'NPA POS <= 2.50% (stricter for <650 / NTC)',
      bucketResolver: (loan, b) {
        final s = b?.creditScore;
        if (s == null || s <= 0) return 'Unscored / NTC';
        if (s < 650) return '< 650';
        if (s < 700) return '650 - 699';
        if (s < 750) return '700 - 749';
        return '750+';
      },
      rationale:
          'Shows which credit score band contributes the highest NPA count and POS so underwriting cutoffs can be calibrated.',
      action:
          'Tighten FOIR/LTV or require co-applicant/collateral buffer on lower-score and unscored segments.',
    );

    final byTenureBand = _groupBuckets(
      loans: loans,
      borrowerMap: borrowerMap,
      titlePrefix: 'Tenure Band',
      benchmarkText: 'NPA POS <= 2.50% across tenures',
      bucketResolver: (loan, _) {
        final t = loan.tenureInstallments;
        if (t <= 36) return 'Up to 36M';
        if (t <= 84) return '37 - 84M';
        if (t <= 144) return '85 - 144M';
        return '145M+';
      },
      rationale:
          'Compares short vs. long repayment tenures—long tenures lower monthly EMI but extend exposure to income/rate shifts.',
      action:
          'Review EMI burden and early-vintage DPD on long-tenure loans when borrower cash flow tightens.',
    );

    final byLoanAvailedBand = _groupBuckets(
      loans: loans,
      borrowerMap: borrowerMap,
      titlePrefix: 'Loan Availed Band',
      benchmarkText: 'NPA POS <= 2.50%; watch large-ticket concentration',
      bucketResolver: (loan, _) {
        final amt = loan.principalSanctioned;
        if (amt < 500000) return '< ₹5L';
        if (amt < 1500000) return '₹5L - ₹15L';
        if (amt < 3500000) return '₹15L - ₹35L';
        return '₹35L+';
      },
      rationale:
          'Evaluates ticket-size tiers so high-rupee loans don’t hide inside low account counts.',
      action:
          'Apply manager-level beat follow-up and collateral/LTV checks on higher-ticket delinquent accounts.',
    );

    final npaScenarios = _buildNpaScenarios(
      loans: loans,
      borrowerMap: borrowerMap,
      missingGeoCount: missingGeo,
      missingScoreCount: missingScore,
    );

    return PortfolioIntelligenceSummary(
      totalLoans: loans.length,
      totalSanctioned: totalSanctioned,
      totalDisbursed: totalDisbursed,
      totalPos: totalPos,
      npaLoans: npaLoans,
      npaPos: npaPos,
      npaPosPct: npaPosPct,
      weightedRoiPct: weightedRoiPct,
      estimatedCollectionEfficiencyPct: cePct,
      missingScoreCount: missingScore,
      missingGeoCount: missingGeo,
      salesKpiDiagnostic: salesDiag,
      ceKpiDiagnostic: ceDiag,
      npaKpiDiagnostic: npaDiag,
      costKpiDiagnostic: costDiag,
      byScoreBand: byScoreBand,
      byTenureBand: byTenureBand,
      byLoanAvailedBand: byLoanAvailedBand,
      npaScenarios: npaScenarios,
    );
  }

  static List<DimensionRiskRow> _groupBuckets({
    required List<LoanModel> loans,
    required Map<String, BorrowerModel> borrowerMap,
    required String titlePrefix,
    required String benchmarkText,
    required String Function(LoanModel loan, BorrowerModel? borrower) bucketResolver,
    required String rationale,
    required String action,
  }) {
    final grouped = <String, List<LoanModel>>{};
    for (final loan in loans) {
      final b = borrowerMap[loan.borrowerId];
      final key = bucketResolver(loan, b);
      grouped.putIfAbsent(key, () => []).add(loan);
    }

    final rows = <DimensionRiskRow>[];
    for (final entry in grouped.entries) {
      final items = entry.value;
      var sanc = 0.0;
      var pos = 0.0;
      var npaCnt = 0;
      var npaBalance = 0.0;

      for (final l in items) {
        sanc += l.principalSanctioned;
        pos += l.principalOutstanding;
        if (_isNpa(l)) {
          npaCnt++;
          npaBalance += l.principalOutstanding;
        }
      }

      final pct = pos > 0 ? (npaBalance / pos) * 100.0 : 0.0;
      final sev = pct <= 2.5
          ? DiagnosticSeverity.good
          : (pct <= 5.0 ? DiagnosticSeverity.watch : DiagnosticSeverity.alert);

      rows.add(
        DimensionRiskRow(
          bucketLabel: entry.key,
          loanCount: items.length,
          sanctionedTotal: sanc,
          posTotal: pos,
          npaCount: npaCnt,
          npaPos: npaBalance,
          npaPosPct: pct,
          diagnostic: DiagnosticCellMeta(
            title: '$titlePrefix: ${entry.key}',
            valueLabel: '${pct.toStringAsFixed(2)}% NPA POS',
            severity: sev,
            whyPresented: rationale,
            benchmark: benchmarkText,
            dataComparison:
                '${items.length} loans, POS ${IndianFormatters.formatInr(pos)}, NPA ${IndianFormatters.formatInr(npaBalance)} ($npaCnt accts).',
            improvementAction: action,
          ),
        ),
      );
    }

    rows.sort((a, b) => b.npaPos.compareTo(a.npaPos));
    return rows;
  }

  static List<NpaScenarioFinding> _buildNpaScenarios({
    required List<LoanModel> loans,
    required Map<String, BorrowerModel> borrowerMap,
    required int missingGeoCount,
    required int missingScoreCount,
  }) {
    final npaList = loans.where(_isNpa).toList();

    final highFoir = npaList.where((l) => (l.foirPct ?? 0) >= 50.0).toList();
    final highLtv = npaList.where((l) => (l.ltvPct ?? 0) >= 75.0).toList();
    final earlyMob = npaList.where((l) => (l.monthsOnBooks ?? 999) <= 12).toList();
    final unverifiedGeo = npaList.where((l) {
      final b = borrowerMap[l.borrowerId];
      return b == null || !b.hasValidCoordinates;
    }).toList();

    double sumPos(List<LoanModel> list) =>
        list.fold(0.0, (acc, l) => acc + l.principalOutstanding);

    return [
      NpaScenarioFinding(
        scenarioTitle: 'High Obligation / FOIR Stress (>= 50%)',
        affectedLoans: highFoir.length,
        affectedPos: sumPos(highFoir),
        diagnostic: DiagnosticCellMeta(
          title: 'Scenario: FOIR / Cash-Flow Strain',
          valueLabel: '${highFoir.length} NPA loans',
          severity: highFoir.isEmpty ? DiagnosticSeverity.good : DiagnosticSeverity.alert,
          whyPresented:
              'Identifies NPA borrowers whose EMI burden relative to income leaves thin buffer against cash-flow dips.',
          benchmark: 'FOIR <= 50% at origination; minimal 90+ DPD slippage',
          dataComparison:
              '${highFoir.length} of ${npaList.length} NPA accounts show FOIR >= 50% (${IndianFormatters.formatInr(sumPos(highFoir))} POS).',
          improvementAction:
              'Cap FOIR during underwriting and review restructuring/rescheduling options where cash flow is recoverable.',
        ),
      ),
      NpaScenarioFinding(
        scenarioTitle: 'High LTV / Collateral Buffer Risk (>= 75%)',
        affectedLoans: highLtv.length,
        affectedPos: sumPos(highLtv),
        diagnostic: DiagnosticCellMeta(
          title: 'Scenario: LTV & Collateral Cover',
          valueLabel: '${highLtv.length} NPA loans',
          severity: highLtv.isEmpty ? DiagnosticSeverity.good : DiagnosticSeverity.watch,
          whyPresented:
              'Flags NPA accounts with high loan-to-value where recovery depends heavily on collateral valuation and enforcement.',
          benchmark: 'Conservative LTV cap per HF/LAP policy',
          dataComparison:
              '${highLtv.length} NPA accounts have LTV >= 75% (${IndianFormatters.formatInr(sumPos(highLtv))} POS).',
          improvementAction:
              'Verify property valuation, legal title status, and escalation readiness on high-LTV delinquent cases.',
        ),
      ),
      NpaScenarioFinding(
        scenarioTitle: 'Early-Vintage Slippage (<= 12 MOB)',
        affectedLoans: earlyMob.length,
        affectedPos: sumPos(earlyMob),
        diagnostic: DiagnosticCellMeta(
          title: 'Scenario: Early MOB Underwriting / Onboarding',
          valueLabel: '${earlyMob.length} NPA loans',
          severity: earlyMob.isEmpty ? DiagnosticSeverity.good : DiagnosticSeverity.alert,
          whyPresented:
              'Separates quick defaults within 12 months on book from longer-term lifecycle stress.',
          benchmark: 'Low early-MOB NPA; fast intervention in 1–30 DPD',
          dataComparison:
              '${earlyMob.length} NPA loans slipped within <= 12 MOB (${IndianFormatters.formatInr(sumPos(earlyMob))} POS).',
          improvementAction:
              'Audit origination checks, early EMI reminders, and first-cycle field visits on new cohorts.',
        ),
      ),
      NpaScenarioFinding(
        scenarioTitle: 'Unverified Field Geo-Coordinates / Score Gaps',
        affectedLoans: unverifiedGeo.length,
        affectedPos: sumPos(unverifiedGeo),
        diagnostic: DiagnosticCellMeta(
          title: 'Scenario: Field Traceability & Data Hygiene',
          valueLabel: '${unverifiedGeo.length} NPA loans',
          severity: unverifiedGeo.isEmpty ? DiagnosticSeverity.good : DiagnosticSeverity.watch,
          whyPresented:
              'Surfaces field-traceability gaps alongside portfolio-wide missing score ($missingScoreCount) and missing geo ($missingGeoCount) counts.',
          benchmark: '100% verified coordinates & score coverage on active/NPA book',
          dataComparison:
              '${unverifiedGeo.length} NPA loans lack verified coordinates; $missingGeoCount total borrowers unmapped.',
          improvementAction:
              'Capture GPS coordinates on field visits and complete missing score/KYC fields during batch imports.',
        ),
      ),
    ];
  }
}

