import 'package:flutter/material.dart';

import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import '../utils/indian_formatters.dart';
import '../utils/portfolio_intelligence.dart';
import 'diagnostic_cell_card.dart';

/// Displays Sales, Credit/NPA, and Collection Efficiency diagnostics with
/// hover/tap cell explanations across score, tenure, loan-availed, and NPA scenarios.
class PortfolioIntelligencePanel extends StatefulWidget {
  const PortfolioIntelligencePanel({
    super.key,
    required this.loans,
    required this.borrowers,
    this.title = 'Sales, Credit & NPA Intelligence',
  });

  final List<LoanModel> loans;
  final List<BorrowerModel> borrowers;
  final String title;

  @override
  State<PortfolioIntelligencePanel> createState() => _PortfolioIntelligencePanelState();
}

class _PortfolioIntelligencePanelState extends State<PortfolioIntelligencePanel> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final borrowerMap = <String, BorrowerModel>{
      for (final b in widget.borrowers) b.borrowerId: b,
    };
    final summary = PortfolioIntelligence.analyze(
      loans: widget.loans,
      borrowerMap: borrowerMap,
    );

    final tabs = ['Score Band', 'Tenure Band', 'Loan Availed', 'NPA Scenarios'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Text(
                  'Hover or tap any card for benchmark & action',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 220,
                  child: DiagnosticCellCard(meta: summary.salesKpiDiagnostic, compact: true),
                ),
                SizedBox(
                  width: 220,
                  child: DiagnosticCellCard(meta: summary.ceKpiDiagnostic, compact: true),
                ),
                SizedBox(
                  width: 220,
                  child: DiagnosticCellCard(meta: summary.npaKpiDiagnostic, compact: true),
                ),
                SizedBox(
                  width: 220,
                  child: DiagnosticCellCard(meta: summary.costKpiDiagnostic, compact: true),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  ChoiceChip(
                    label: Text(tabs[i]),
                    selected: _tabIndex == i,
                    onSelected: (_) => setState(() => _tabIndex = i),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTabBody(context, summary),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBody(BuildContext context, PortfolioIntelligenceSummary summary) {
    if (_tabIndex == 3) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final sc in summary.npaScenarios)
            SizedBox(
              width: 250,
              child: DiagnosticCellCard(meta: sc.diagnostic, compact: false),
            ),
        ],
      );
    }

    final rows = _tabIndex == 0
        ? summary.byScoreBand
        : (_tabIndex == 1 ? summary.byTenureBand : summary.byLoanAvailedBand);

    if (rows.isEmpty) {
      return const Text('No loan records available for this view.');
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final row in rows)
          SizedBox(
            width: 250,
            child: Tooltip(
              message: [
                '${row.diagnostic.title}: ${row.diagnostic.valueLabel}',
                'Why: ${row.diagnostic.whyPresented}',
                'Benchmark: ${row.diagnostic.benchmark}',
                'Actual vs Benchmark: ${row.diagnostic.dataComparison}',
                'Improve: ${row.diagnostic.improvementAction}',
              ].join('\n'),
              waitDuration: const Duration(milliseconds: 200),
              showDuration: const Duration(seconds: 8),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.bucketLabel,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          const Icon(Icons.info_outline, size: 14),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Loans: ${row.loanCount} | NPA: ${row.npaCount} (${row.npaPosPct.toStringAsFixed(2)}% POS)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'POS: ${IndianFormatters.formatInr(row.posTotal)} | NPA POS: ${IndianFormatters.formatInr(row.npaPos)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
