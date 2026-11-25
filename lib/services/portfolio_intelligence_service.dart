enum FunnelStage { logged, sanctioned, disbursed, closedOrRejected }

class FunnelConversionSummary {
  final int loggedCount;
  final int sanctionedCount;
  final int disbursedCount;
  final int closedOrRejectedCount;
  final double loggedAmount;
  final double sanctionedAmount;
  final double disbursedAmount;

  const FunnelConversionSummary({
    required this.loggedCount,
    required this.sanctionedCount,
    required this.disbursedCount,
    required this.closedOrRejectedCount,
    required this.loggedAmount,
    required this.sanctionedAmount,
    required this.disbursedAmount,
  });

  double get loginToSanctionCountPct =>
      loggedCount == 0 ? 0.0 : (sanctionedCount / loggedCount) * 100.0;

  double get sanctionToDisbursedCountPct =>
      sanctionedCount == 0 ? 0.0 : (disbursedCount / sanctionedCount) * 100.0;

  double get loginToDisbursedCountPct =>
      loggedCount == 0 ? 0.0 : (disbursedCount / loggedCount) * 100.0;

  double get loginToDisbursedAmountPct =>
      loggedAmount == 0 ? 0.0 : (disbursedAmount / loggedAmount) * 100.0;
}

class IdentifierDeviationFinding {
  final String dimension;
  final String identifier;
  final String severity; // 'high', 'medium', 'info'
  final String fact;
  final String suggestion;

  const IdentifierDeviationFinding({
    required this.dimension,
    required this.identifier,
    required this.severity,
    required this.fact,
    required this.suggestion,
  });
}

class PersonPerformanceRecord {
  final String personId;
  final int totalRecords;
  final int loggedCount;
  final int sanctionedCount;
  final int disbursedCount;
  final double posAmount;
  final double npaPosAmount;
  final double demandAmount;
  final double collectedAmount;
  final double avgDpd;

  const PersonPerformanceRecord({
    required this.personId,
    required this.totalRecords,
    required this.loggedCount,
    required this.sanctionedCount,
    required this.disbursedCount,
    required this.posAmount,
    required this.npaPosAmount,
    required this.demandAmount,
    required this.collectedAmount,
    required this.avgDpd,
  });

  double get loginToDisbursedPct =>
      loggedCount == 0 ? 0.0 : (disbursedCount / loggedCount) * 100.0;

  double get collectionEfficiencyPct =>
      demandAmount <= 0 ? 0.0 : (collectedAmount / demandAmount) * 100.0;

  double get npaPosPct =>
      posAmount <= 0 ? 0.0 : (npaPosAmount / posAmount) * 100.0;
}

class PortfolioIntelligenceReport {
  final FunnelConversionSummary funnel;
  final List<PersonPerformanceRecord> personScorecards;
  final List<IdentifierDeviationFinding> deviations;

  const PortfolioIntelligenceReport({
    required this.funnel,
    required this.personScorecards,
    required this.deviations,
  });
}

class PortfolioIntelligenceService {
  static FunnelStage classifyStage(Map<String, dynamic> row) {
    final rawStatus = (row['status'] ?? row['stage'] ?? row['currentStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final isClosedFlag = row['isClosedOrRejected'] == true;

    if (isClosedFlag ||
        rawStatus.contains('reject') ||
        rawStatus.contains('not sanction') ||
        rawStatus.contains('not aprove') ||
        rawStatus.contains('not approve') ||
        rawStatus.contains('closed') ||
        rawStatus.contains('foreclos')) {
      return FunnelStage.closedOrRejected;
    }

    if (rawStatus.contains('disburs') ||
        rawStatus.contains('active') ||
        rawStatus.contains('delinquent') ||
        rawStatus.contains('npa') ||
        (row['disbursementDate'] != null && row['disbursementDate'].toString().isNotEmpty)) {
      return FunnelStage.disbursed;
    }

    if (rawStatus.contains('sanction') || rawStatus.contains('approv')) {
      return FunnelStage.sanctioned;
    }

    return FunnelStage.logged;
  }

  static double _num(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v is num) return v.toDouble();
      if (v != null) {
        final cleaned = v.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
        final parsed = double.tryParse(cleaned);
        if (parsed != null) return parsed;
      }
    }
    return 0.0;
  }

  static String _str(Map<String, dynamic> row, List<String> keys, String fallback) {
    for (final k in keys) {
      final v = row[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return fallback;
  }

  PortfolioIntelligenceReport analyze(List> rows) {
    int loggedCount = 0;
    int sanctionedCount = 0;
    int disbursedCount = 0;
    int closedOrRejectedCount = 0;

    double loggedAmount = 0.0;
    double sanctionedAmount = 0.0;
    double disbursedAmount = 0.0;

    final byBranch = <String, List>>{};
    final byPerson = <String, List>>{};
    final nameToIds = <String, Set<String>>{};
    final deviations = <IdentifierDeviationFinding>[];

    for (final row in rows) {
      final stage = classifyStage(row);
      final amt = _num(row, ['amount', 'principalSanctioned', 'sanctionAmount', 'pos']);
      final disbAmt = _num(row, ['disbursedAmount', 'totalDisbursedAmount', 'netDisbursedAmount', 'pos']);
      final sancAmt = _num(row, ['sanctionAmount', 'principalSanctioned', 'amount']);

      loggedCount++;
      loggedAmount += amt;

      if (stage == FunnelStage.sanctioned || stage == FunnelStage.disbursed) {
        sanctionedCount++;
        sanctionedAmount += sancAmt > 0 ? sancAmt : amt;
      }
      if (stage == FunnelStage.disbursed) {
        disbursedCount++;
        disbursedAmount += disbAmt > 0 ? disbAmt : amt;
      }
      if (stage == FunnelStage.closedOrRejected) {
        closedOrRejectedCount++;
      }

      final branch = _str(row, ['branch', 'branchName', 'territory'], 'Unassigned');
      byBranch.putIfAbsent(branch, () => []).add(row);

      final person = _str(row, ['agentId', 'assignedTo', 'sdeName', 'person', 'uid'], 'Unassigned');
      byPerson.putIfAbsent(person, () => []).add(row);

      final borrowerName = _str(row, ['borrowerName', 'customerName', 'name'], '').toLowerCase();
      final loanId = _str(row, ['loanId', 'id', 'applicationNo'], '');
      if (borrowerName.isNotEmpty && loanId.isNotEmpty) {
        nameToIds.putIfAbsent(borrowerName, () => <String>{}).add(loanId);
      }

      final tokens = borrowerName.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      if (tokens.length >= 2 && tokens.toSet().length == 1) {
        deviations.add(IdentifierDeviationFinding(
          dimension: 'Borrower Name',
          identifier: loanId.isEmpty ? borrowerName : '$borrowerName ($loanId)',
          severity: 'medium',
          fact: 'Repeated token detected in borrower name ("$borrowerName").',
          suggestion: 'Verify KYC/master data for duplicate or typoed name strings before reporting.',
        ));
      }
    }

    final funnel = FunnelConversionSummary(
      loggedCount: loggedCount,
      sanctionedCount: sanctionedCount,
      disbursedCount: disbursedCount,
      closedOrRejectedCount: closedOrRejectedCount,
      loggedAmount: loggedAmount,
      sanctionedAmount: sanctionedAmount,
      disbursedAmount: disbursedAmount,
    );

    if (loggedCount > 0 && funnel.loginToDisbursedCountPct < 25.0) {
      deviations.add(IdentifierDeviationFinding(
        dimension: 'Funnel Conversion',
        identifier: 'Login -> Disbursement',
        severity: 'high',
        fact: 'Overall login-to-disbursement conversion is ${funnel.loginToDisbursedCountPct.toStringAsFixed(1)}% '
            '($disbursedCount disbursed out of $loggedCount logged; sanction-to-disbursed is ${funnel.sanctionToDisbursedCountPct.toStringAsFixed(1)}%).',
        suggestion: 'Audit drop-off stages between logged, sanctioned, and disbursed records to isolate underwriting vs. payout bottlenecks.',
      ));
    }

    // Branch-level deviations
    final totalRowsCount = rows.isEmpty ? 1 : rows.length;
    byBranch.forEach((branch, list) {
      double pos = 0;
      double npaPos = 0;
      double dpdSum = 0;
      int zeroPosCount = 0;
      for (final r in list) {
        final p = _num(r, ['pos', 'principalOutstanding', 'amount']);
        final dpd = _num(r, ['dpd', 'daysPastDue']);
        pos += p;
        dpdSum += dpd;
        if (dpd >= 90 || (r['isNpa'] == true)) {
          npaPos += p;
        }
        if (p <= 0) zeroPosCount++;
      }
      final npaPct = pos <= 0 ? 0.0 : (npaPos / pos) * 100.0;
      final avgDpd = list.isEmpty ? 0.0 : dpdSum / list.length;

      if (branch.toLowerCase() == 'unassigned' && list.isNotEmpty) {
        deviations.add(IdentifierDeviationFinding(
          dimension: 'Branch',
          identifier: branch,
          severity: 'high',
          fact: '${list.length} record(s) with POS ₹${pos.toStringAsFixed(2)} lack a valid branch assignment.',
          suggestion: 'Map unassigned loans to their originating branch/territory so regional exposure and DPD are accurate.',
        ));
      } else if (npaPct >= 30.0) {
        deviations.add(IdentifierDeviationFinding(
          dimension: 'Branch',
          identifier: branch,
          severity: 'high',
          fact: 'NPA POS is ${npaPct.toStringAsFixed(1)}% (₹${npaPos.toStringAsFixed(2)} of ₹${pos.toStringAsFixed(2)}) across ${list.length} loans; avg DPD is ${avgDpd.toStringAsFixed(0)}d.',
          suggestion: 'Prioritize field collections and restructuring review on 90+ DPD accounts in $branch.',
        ));
      } else if (list.length >= 25 && zeroPosCount / list.length >= 0.8) {
        deviations.add(IdentifierDeviationFinding(
          dimension: 'Branch',
          identifier: branch,
          severity: 'medium',
          fact: '$zeroPosCount of ${list.length} records in $branch have ₹0.00 POS (avg DPD ${avgDpd.toStringAsFixed(0)}d).',
          suggestion: 'Separate closed/zero-balance or pre-disbursement rows from active POS/DPD averages.',
        ));
      }
    });

    // Person-level scorecards & deviations
    final personScorecards = <PersonPerformanceRecord>[];
    byPerson.forEach((person, list) {
      int pLogged = 0;
      int pSanctioned = 0;
      int pDisbursed = 0;
      double pPos = 0;
      double pNpaPos = 0;
      double pDemand = 0;
      double pCollected = 0;
      double pDpdSum = 0;

      for (final r in list) {
        final st = classifyStage(r);
        pLogged++;
        if (st == FunnelStage.sanctioned || st == FunnelStage.disbursed) pSanctioned++;
        if (st == FunnelStage.disbursed) pDisbursed++;

        final pos = _num(r, ['pos', 'principalOutstanding', 'amount']);
        final dpd = _num(r, ['dpd', 'daysPastDue']);
        pPos += pos;
        pDpdSum += dpd;
        if (dpd >= 90 || r['isNpa'] == true) pNpaPos += pos;
        pDemand += _num(r, ['demand', 'totalDemand', 'emiAmount']);
        pCollected += _num(r, ['collected', 'totalCollected', 'amountPaid']);
      }

      final record = PersonPerformanceRecord(
        personId: person,
        totalRecords: list.length,
        loggedCount: pLogged,
        sanctionedCount: pSanctioned,
        disbursedCount: pDisbursed,
        posAmount: pPos,
        npaPosAmount: pNpaPos,
        demandAmount: pDemand,
        collectedAmount: pCollected,
        avgDpd: list.isEmpty ? 0.0 : pDpdSum / list.length,
      );
      personScorecards.add(record);

      if (list.length / totalRowsCount >= 0.75 && byPerson.length == 1) {
        deviations.add(IdentifierDeviationFinding(
          dimension: 'Person',
          identifier: person,
          severity: 'medium',
          fact: '100% of ${list.length} records map to a single owner ("$person"), with ${record.npaPosPct.toStringAsFixed(1)}% NPA POS and ${record.avgDpd.toStringAsFixed(1)}d avg DPD.',
          suggestion: 'Populate individual SDE/agent/relationship-manager identifiers per loan so origination conversion, demand collection, and delinquency can be evaluated per person.',
        ));
      } else if (record.demandAmount > 0 && record.collectionEfficiencyPct < 60.0) {
        deviations.add(IdentifierDeviationFinding(
          dimension: 'Person',
          identifier: person,
          severity: 'high',
          fact: 'Collection efficiency for $person is ${record.collectionEfficiencyPct.toStringAsFixed(1)}% '
              '(₹${record.collectedAmount.toStringAsFixed(0)} collected vs ₹${record.demandAmount.toStringAsFixed(0)} demand).',
          suggestion: 'Review pending demands, PTP commitments, and field visit logs for $person.',
        ));
      }
    });

    personScorecards.sort((a, b) => b.posAmount.compareTo(a.posAmount));

    // Multi-ID same borrower check
    nameToIds.forEach((bName, ids) {
      if (ids.length >= 4) {
        deviations.add(IdentifierDeviationFinding(
          dimension: 'Borrower IDs',
          identifier: bName,
          severity: 'info',
          fact: '${ids.length} distinct loan/application IDs share borrower name "$bName".',
          suggestion: 'Confirm whether these represent legitimate repeat loans/tranches or multi-row import entries.',
        ));
      }
    });

    return PortfolioIntelligenceReport(
      funnel: funnel,
      personScorecards: personScorecards,
      deviations: deviations,
    );
  }
}
