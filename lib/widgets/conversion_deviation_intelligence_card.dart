import 'package:flutter/material.dart';
import '../services/portfolio_intelligence_service.dart';

class ConversionDeviationIntelligenceCard extends StatelessWidget {
  final List<LoanRecordMap> records;
  final PortfolioIntelligenceService? service;
  final int maxDeviationsShown;
  final int maxPeopleShown;

  const ConversionDeviationIntelligenceCard({
    super.key,
    required this.records,
    this.service,
    this.maxDeviationsShown = 5,
    this.maxPeopleShown = 4,
  });

  Color _severityColor(BuildContext context, String severity) {
    final scheme = Theme.of(context).colorScheme;
    switch (severity.toLowerCase()) {
      case 'high':
        return scheme.error;
      case 'medium':
        return Colors.orange.shade800;
      default:
        return scheme.primary;
    }
  }

  String _fmtAmount(double value) {
    if (value.abs() >= 10000000) {
      return '₹${(value / 10000000).toStringAsFixed(2)} Cr';
    }
    if (value.abs() >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(2)} L';
    }
    return '₹${value.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final report = (service ?? PortfolioIntelligenceService()).analyze(records);
    final funnel = report.funnel;
    final visiblePeople = report.personScorecards.take(maxPeopleShown).toList();
    final visibleDeviations = report.deviations.take(maxDeviationsShown).toList();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Conversion & Identifier Deviation Intelligence',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  'Login->Disb: ${funnel.loginToDisbursedCountPct.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _MetricPill(
                  label: 'Logged',
                  value: '${funnel.loggedCount}',
                  sub: _fmtAmount(funnel.loggedAmount),
                ),
                _MetricPill(
                  label: 'Sanctioned',
                  value: '${funnel.sanctionedCount} (${funnel.loginToSanctionCountPct.toStringAsFixed(1)}%)',
                  sub: _fmtAmount(funnel.sanctionedAmount),
                ),
                _MetricPill(
                  label: 'Disbursed',
                  value: '${funnel.disbursedCount} (${funnel.sanctionToDisbursedCountPct.toStringAsFixed(1)}%)',
                  sub: _fmtAmount(funnel.disbursedAmount),
                ),
                _MetricPill(
                  label: 'Closed / Rejected',
                  value: '${funnel.closedOrRejectedCount}',
                  sub: 'Excluded from active conv.',
                ),
              ],
            ),
            if (visiblePeople.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Person Scorecard (Sales Funnel • Demand/Collection • Quality)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final p in visiblePeople)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p.personId} • ${p.totalRecords} records • Conv ${p.loginToDisbursedPct.toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Funnel: L ${p.loggedCount} -> S ${p.sanctionedCount} -> D ${p.disbursedCount} | '
                          'Demand ${_fmtAmount(p.demandAmount)} / Coll ${_fmtAmount(p.collectedAmount)} (${p.collectionEfficiencyPct.toStringAsFixed(1)}%)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          'Quality: POS ${_fmtAmount(p.posAmount)} | NPA ${p.npaPosPct.toStringAsFixed(1)}% | Avg DPD ${p.avgDpd.toStringAsFixed(0)}d',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (visibleDeviations.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Identifier Deviations (${report.deviations.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final d in visibleDeviations)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: _severityColor(context, d.severity),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[${d.dimension}] ${d.identifier}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              d.fact,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'Action: ${d.suggestion}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final String sub;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(sub, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
