import 'package:flutter/material.dart';

import '../models/borrower_model.dart';
import '../models/loan_product_model.dart';
import '../models/loan_model.dart';
import '../utils/indian_formatters.dart';

enum AnalyticsDimension {
  branch('Branch'),
  employee('Employee'),
  product('Product'),
  tenureMob('Tenure (MOB)'),
  creditScore('Credit Score'),
  loanBand('Loan Band'),
  npaBand('NPA / DPD Band');

  const AnalyticsDimension(this.label);
  final String label;
}

class SliceMetric {
  const SliceMetric({
    required this.key,
    required this.title,
    required this.loanCount,
    required this.posAmount,
    required this.npaPosAmount,
  });

  final String key;
  final String title;
  final int loanCount;
  final double posAmount;
  final double npaPosAmount;

  double get npaSharePct =>
      posAmount <= 0 ? 0 : (npaPosAmount / posAmount) * 100;
}

class PortfolioVisualAnalyticsPanel extends StatefulWidget {
  const PortfolioVisualAnalyticsPanel({
    super.key,
    required this.loans,
    required this.borrowersById,
    required this.selectedSliceKey,
    required this.onSelectSlice,
    this.branchNameResolver,
    this.employeeNameResolver,
    this.productNameResolver,
    this.products = const [],
  });

  final List<LoanModel> loans;
  final Map<String, BorrowerModel> borrowersById;
  final String? selectedSliceKey;
  final void Function(AnalyticsDimension dimension, String? sliceKey)
      onSelectSlice;

  final String Function(String key)? branchNameResolver;
  final String Function(String key)? employeeNameResolver;
  final String Function(String key)? productNameResolver;
  final List<LoanProductModel> products;

  @override
  State<PortfolioVisualAnalyticsPanel> createState() =>
      _PortfolioVisualAnalyticsPanelState();
}

class _PortfolioVisualAnalyticsPanelState
    extends State<PortfolioVisualAnalyticsPanel> {
  AnalyticsDimension _dimension = AnalyticsDimension.branch;

  List<SliceMetric> _computeMetrics() {
    final grouped = <String, _MutableBucket>{};

    String bucketForLoan(LoanModel loan) {
      final borrower = widget.borrowersById[loan.borrowerId];
      switch (_dimension) {
        case AnalyticsDimension.branch:
          final rawBranch = (borrower?.branch ?? '').trim();
          return rawBranch.isEmpty ? 'Unassigned Branch' : rawBranch;

        case AnalyticsDimension.employee:
          final agentId = loan.assignedAgentId.trim();
          return agentId.isEmpty ? 'Unassigned Officer' : agentId;

        case AnalyticsDimension.product:
          final prod = loan.productId.trim();
          return prod.isEmpty ? 'General Loan' : prod;

        case AnalyticsDimension.tenureMob:
          final mob = loan.monthsOnBooks ?? 0;
          if (mob <= 6) return '0-6M';
          if (mob <= 12) return '7-12M';
          if (mob <= 24) return '13-24M';
          return '25M+';

        case AnalyticsDimension.creditScore:
          final score = borrower?.creditScore;
          if (score == null || score <= 0) return 'NTC / Unrated';
          if (score < 650) return '< 650';
          if (score < 700) return '650-699';
          if (score < 750) return '700-749';
          return '750+';

        case AnalyticsDimension.loanBand:
          final amt = loan.principalOutstanding > 0
              ? loan.principalOutstanding
              : loan.principalSanctioned;
          if (amt < 500000) return '< Rs 5L';
          if (amt < 1500000) return 'Rs 5L-15L';
          if (amt < 5000000) return 'Rs 15L-50L';
          return 'Rs 50L+';

        case AnalyticsDimension.npaBand:
          if (loan.dpd <= 0) return 'Current (0 DPD)';
          if (loan.dpd <= 30) return '1-30 DPD';
          if (loan.dpd <= 60) return '31-60 DPD';
          if (loan.dpd <= 90) return '61-90 DPD';
          return '90+ DPD (NPA)';
      }
    }

    String displayTitle(String key) {
      switch (_dimension) {
        case AnalyticsDimension.branch:
          return widget.branchNameResolver?.call(key) ?? key;
        case AnalyticsDimension.employee:
          return widget.employeeNameResolver?.call(key) ?? key;
        case AnalyticsDimension.product:
          if (widget.productNameResolver != null) return widget.productNameResolver!(key);
          for (final p in widget.products) { if (p.productId == key) return p.productName; }
          return key;
        default:
          return key;
      }
    }

    for (final loan in widget.loans) {
      final key = bucketForLoan(loan);
      final bucket = grouped.putIfAbsent(key, () => _MutableBucket());
      final pos = loan.principalOutstanding;
      bucket.loanCount += 1;
      bucket.posAmount += pos;
      if (loan.dpd > 90 || loan.agingBucket == AgingBucket.dpd90Plus) {
        bucket.npaPosAmount += pos;
      }
    }

    final list = grouped.entries
        .map(
          (e) => SliceMetric(
            key: e.key,
            title: displayTitle(e.key),
            loanCount: e.value.loanCount,
            posAmount: e.value.posAmount,
            npaPosAmount: e.value.npaPosAmount,
          ),
        )
        .toList();

    list.sort((a, b) => b.posAmount.compareTo(a.posAmount));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _computeMetrics();
    final totalPos = metrics.fold<double>(0, (acc, m) => acc + m.posAmount);
    final totalNpaPos =
        metrics.fold<double>(0, (acc, m) => acc + m.npaPosAmount);
    final maxPos = metrics.isEmpty
        ? 1.0
        : metrics.map((m) => m.posAmount).reduce((a, b) => a > b ? a : b);

    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Visual Portfolio Breakdown',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (widget.selectedSliceKey != null)
                  TextButton.icon(
                    onPressed: () => widget.onSelectSlice(_dimension, null),
                    icon: const Icon(Icons.filter_alt_off, size: 16),
                    label: const Text('Clear Slice'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _SummaryPill(
                  label: 'Slice POS',
                  value: IndianFormatters.formatInrCompact(totalPos),
                ),
                _SummaryPill(
                  label: '90+ DPD NPA POS',
                  value: IndianFormatters.formatInrCompact(totalNpaPos),
                  isAlert: totalNpaPos > 0,
                ),
                _SummaryPill(
                  label: 'Accounts',
                  value: '${widget.loans.length}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<AnalyticsDimension>(
                segments: AnalyticsDimension.values
                    .map(
                      (d) => ButtonSegment<AnalyticsDimension>(
                        value: d,
                        label: Text(d.label),
                      ),
                    )
                    .toList(),
                selected: {_dimension},
                onSelectionChanged: (set) {
                  setState(() => _dimension = set.first);
                },
              ),
            ),
            const SizedBox(height: 16),
            if (metrics.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No loans match the current filter criteria.'),
              )
            else
              ...metrics.map((item) {
                final isSelected = widget.selectedSliceKey == item.key;
                final ratio = maxPos <= 0
                    ? 0.0
                    : (item.posAmount / maxPos).clamp(0.0, 1.0);
                final npaRatioInBar = item.posAmount <= 0
                    ? 0.0
                    : (item.npaPosAmount / item.posAmount).clamp(0.0, 1.0);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => widget.onSelectSlice(
                      _dimension,
                      isSelected ? null : item.key,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isSelected
                            ? theme.colorScheme.primaryContainer.withAlpha(115)
                            : theme.colorScheme.surfaceContainerLowest,
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant.withAlpha(153),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${IndianFormatters.formatInrCompact(item.posAmount)} • ${item.loanCount} loans',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final barWidth = constraints.maxWidth * ratio;
                              final npaWidth = barWidth * npaRatioInBar;
                              return Stack(
                                children: [
                                  Container(
                                    height: 10,
                                    width: constraints.maxWidth,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    height: 10,
                                    width: barWidth,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  if (npaWidth > 0)
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 250),
                                      height: 10,
                                      width: npaWidth,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.error,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          if (item.npaPosAmount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '90+ DPD NPA: ${IndianFormatters.formatInrCompact(item.npaPosAmount)} (${item.npaSharePct.toStringAsFixed(1)}% of bucket POS)',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _MutableBucket {
  int loanCount = 0;
  double posAmount = 0;
  double npaPosAmount = 0;
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.value,
    this.isAlert = false,
  });

  final String label;
  final String value;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAlert
            ? scheme.errorContainer.withAlpha(128)
            : scheme.secondaryContainer.withAlpha(115),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: isAlert ? scheme.onErrorContainer : scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

