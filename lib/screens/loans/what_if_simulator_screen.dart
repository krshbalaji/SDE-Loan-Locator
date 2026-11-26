import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/activity_telemetry_service.dart';

import '../../engines/amortization_engine.dart';
import '../../models/borrower_model.dart';
import '../../models/loan_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_loan_service.dart';
import '../../services/pdf_export_service.dart';
import '../../utils/indian_formatters.dart';

/// Interactive "What-If" Prepayment Simulator & Non-Destructive Restructuring (`v1 -> v2`).
class WhatIfSimulatorScreen extends StatefulWidget {
  const WhatIfSimulatorScreen({
    super.key,
    required this.loan,
    required this.borrower,
  });

  final LoanModel loan;
  final BorrowerModel borrower;

  @override
  State<WhatIfSimulatorScreen> createState() => _WhatIfSimulatorScreenState();
}

class _WhatIfSimulatorScreenState extends State<WhatIfSimulatorScreen> {
  double _lumpSum = 25000.0;
  double _extraPerInstallment = 0.0;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _lumpSum = min(25000.0, widget.loan.principalOutstanding * 0.25);
  }

  int _remainingInstallments(LoanPortfolioProvider portfolio) {
    final rows = portfolio.scheduleForLoan(
      widget.loan.loanId,
      version: widget.loan.scheduleVersion,
    );
    final openCount = rows.where((r) => !r.isFullyPaid).length;
    return max(1, openCount);
  }

  Future<void> _exportPayoffPdf(LoanPortfolioProvider portfolio) async {
    final quote = AmortizationEngine.calculatePayoffQuote(
      loan: widget.loan,
      activeSchedule: portfolio.scheduleForLoan(
        widget.loan.loanId,
        version: widget.loan.scheduleVersion,
      ),
      asOfDate: DateTime.now(),
    );
    final bytes = await PdfExportService.buildPayoffQuotePdf(
      borrower: widget.borrower,
      loan: widget.loan,
      quote: quote,
    );
    await PdfExportService.shareOrPrintPdf(
      bytes,
      'Payoff_Quote_${widget.loan.loanId}.pdf',
    );
  }

  Future<void> _applyRestructure({
    required LoanPortfolioProvider portfolio,
    required double newPrincipal,
    required int newTenure,
    required String label,
  }) async {
    if (newPrincipal <= 0 || newTenure <= 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm Restructuring (v${widget.loan.scheduleVersion} → v${widget.loan.scheduleVersion + 1})'),
        content: Text(
          'Apply "$label"?\n\n'
          '• Unpaid v${widget.loan.scheduleVersion} rows will be marked SUPERSEDED (never deleted).\n'
          '• New v${widget.loan.scheduleVersion + 1} schedule will be generated for '
          '${IndianFormatters.formatInr(newPrincipal)} over $newTenure installments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
                          context.read<ActivityTelemetryService>().logFeatureReviewed(
                            'Approved Loan Restructure',
                            detail: '$label • ${widget.loan.loanId} • Principal: ${IndianFormatters.formatInr(newPrincipal)} • Tenure: ${newTenure}m',
                          );
                          Navigator.pop(ctx, true);
                        },
            child: const Text('Approve & Restructure'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _applying = true);
    try {
      await portfolio.applyRestructure(
        loanId: widget.loan.loanId,
        newPrincipal: newPrincipal,
        newAnnualRate: widget.loan.interestRateAnnual,
        newTenure: newTenure,
        newFirstDueDate: AmortizationEngine.addPeriod(
          DateTime.now(),
          widget.loan.repaymentFrequency,
          1,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Schedule restructured to v${widget.loan.scheduleVersion + 1}!',
          ),
        ),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = context.watch<LoanPortfolioProvider>();
    final auth = context.watch<AuthService>();
    final liveLoan = portfolio.loanById(widget.loan.loanId) ?? widget.loan;
    final remainingCount = _remainingInstallments(portfolio);
    final maxLump = max(1000.0, liveLoan.principalOutstanding);
    final clampedLump = _lumpSum.clamp(0.0, maxLump);

    final sim = AmortizationEngine.simulateWhatIf(
      principalOutstanding: liveLoan.principalOutstanding,
      annualInterestRate: liveLoan.interestRateAnnual,
      remainingInstallments: remainingCount,
      currentEmi: liveLoan.emiAmount,
      interestMethod: liveLoan.interestMethod,
      frequency: liveLoan.repaymentFrequency,
      lumpSumPrepayment: clampedLump,
      extraPerInstallment: _extraPerInstallment,
    );

    final newPrincipal = IndianFormatters.roundPaise(
      max(0.0, liveLoan.principalOutstanding - clampedLump),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('What-If Simulator • ${liveLoan.loanId}'),
        actions: [
          TextButton.icon(
            onPressed: () => _exportPayoffPdf(portfolio),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Payoff Quote'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Loan Baseline (${widget.borrower.fullName})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      _stat(
                        'Principal Outstanding',
                        IndianFormatters.formatInr(liveLoan.principalOutstanding),
                      ),
                      _stat(
                        'Current EMI',
                        IndianFormatters.formatInr(liveLoan.emiAmount),
                      ),
                      _stat('Remaining Installments', '$remainingCount'),
                      _stat(
                        'Baseline Interest Left',
                        IndianFormatters.formatInr(sim.baselineTotalInterest),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Lump-Sum Prepayment (ΔP)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        IndianFormatters.formatInr(clampedLump, showDecimals: false),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: clampedLump,
                    min: 0,
                    max: maxLump,
                    divisions: 40,
                    onChanged: (v) => setState(() => _lumpSum = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recurring Extra EMI (ΔE)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        IndianFormatters.formatInr(
                          _extraPerInstallment,
                          showDecimals: false,
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _extraPerInstallment,
                    min: 0,
                    max: max(1000.0, liveLoan.emiAmount),
                    divisions: 20,
                    onChanged: (v) => setState(() => _extraPerInstallment = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth > 640;
              final cardA = _OptionCard(
                title: 'Option A: Reduce Tenure',
                subtitle: 'Keep EMI constant (+ ΔE), pay off faster',
                accent: Colors.indigo,
                metrics: [
                  ('Effective EMI', IndianFormatters.formatInr(sim.optionAReduceTenure.newEmi)),
                  ('New Remaining Tenure', '${sim.optionAReduceTenure.newTenureInstallments} installments'),
                  ('Installments Saved', '${sim.optionAReduceTenure.installmentsSaved}'),
                  ('Total Interest Saved', IndianFormatters.formatInr(sim.optionAReduceTenure.interestSaved)),
                ],
                canApply: auth.currentUser?.isMaster == true &&
                    !_applying &&
                    newPrincipal > 0 &&
                    sim.optionAReduceTenure.newTenureInstallments > 0,
                onApply: () => _applyRestructure(
                  portfolio: portfolio,
                  newPrincipal: newPrincipal,
                  newTenure: sim.optionAReduceTenure.newTenureInstallments,
                  label: 'Option A — Reduce Tenure',
                ),
              );

              final cardB = _OptionCard(
                title: 'Option B: Reduce EMI',
                subtitle: 'Keep tenure constant ($remainingCount), lower monthly outflow',
                accent: Colors.teal,
                metrics: [
                  ('New Lower EMI', IndianFormatters.formatInr(sim.optionBReduceEmi.newEmi)),
                  ('Cashflow Relief / Period', IndianFormatters.formatInr(sim.optionBReduceEmi.monthlyCashflowRelief)),
                  ('Remaining Tenure', '${sim.optionBReduceEmi.newTenureInstallments} installments'),
                  ('Total Interest Saved', IndianFormatters.formatInr(sim.optionBReduceEmi.interestSaved)),
                ],
                canApply: auth.currentUser?.isMaster == true &&
                    !_applying &&
                    newPrincipal > 0,
                onApply: () => _applyRestructure(
                  portfolio: portfolio,
                  newPrincipal: newPrincipal,
                  newTenure: remainingCount,
                  label: 'Option B — Reduce EMI',
                ),
              );

              if (sideBySide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cardA),
                    const SizedBox(width: 12),
                    Expanded(child: cardB),
                  ],
                );
              }
              return Column(
                children: [
                  cardA,
                  const SizedBox(height: 12),
                  cardB,
                ],
              );
            },
          ),
          if (auth.currentUser?.isMaster != true)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Note: Only MASTER officers can approve non-destructive schedule restructuring (v1 → v2).',
                style: TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.metrics,
    required this.canApply,
    required this.onApply,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final List<(String, String)> metrics;
  final bool canApply;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const Divider(height: 20),
            for (final m in metrics)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(m.$1, style: const TextStyle(fontSize: 13)),
                    Text(
                      m.$2,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: canApply ? onApply : null,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Apply Non-Destructive Restructure'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
