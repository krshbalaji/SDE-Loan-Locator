import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/borrower_model.dart';
import '../models/loan_model.dart';
import '../models/loan_product_model.dart';
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

  static const List<Color> _palette = [
    Color(0xFF2563EB),
    Color(0xFF0D9488),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF4F46E5),
    Color(0xFF059669),
  ];

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
          if (widget.productNameResolver != null) {
            return widget.productNameResolver!(key);
          }
          for (final p in widget.products) {
            if (p.productId == key) return p.productName;
          }
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
    final overallNpaPct =
        totalPos <= 0 ? 0.0 : (totalNpaPos / totalPos) * 100.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(140),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.donut_large_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Visual Portfolio Breakdown',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Tap any slice or bar to cross-filter portfolio & intelligence',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.selectedSliceKey != null)
                  FilledButton.tonalIcon(
                    onPressed: () => widget.onSelectSlice(_dimension, null),
                    icon: const Icon(Icons.filter_alt_off, size: 16),
                    label: const Text('Clear Slice'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _SummaryPill(
                  label: 'Slice POS',
                  value: IndianFormatters.formatInrCompact(totalPos),
                ),
                _SummaryPill(
                  label: '90+ DPD NPA',
                  value:
                      '${IndianFormatters.formatInrCompact(totalNpaPos)} (${overallNpaPct.toStringAsFixed(1)}%)',
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
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 680;
                  final donutWidget = _PortfolioDonutCard(
                    metrics: metrics,
                    totalPos: totalPos,
                    selectedKey: widget.selectedSliceKey,
                    palette: _palette,
                    onSelect: (key) => widget.onSelectSlice(
                      _dimension,
                      widget.selectedSliceKey == key ? null : key,
                    ),
                  );

                  final barsList = Column(
                    children: List.generate(metrics.length, (index) {
                      final item = metrics[index];
                      final color = _palette[index % _palette.length];
                      final isSelected = widget.selectedSliceKey == item.key;
                      final ratio = maxPos <= 0
                          ? 0.0
                          : (item.posAmount / maxPos).clamp(0.0, 1.0);
                      final npaRatioInBar = item.posAmount <= 0
                          ? 0.0
                          : (item.npaPosAmount / item.posAmount)
                              .clamp(0.0, 1.0);
                      final sharePct = totalPos <= 0
                          ? 0.0
                          : (item.posAmount / totalPos) * 100.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => widget.onSelectSlice(
                            _dimension,
                            isSelected ? null : item.key,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isSelected
                                  ? color.withAlpha(28)
                                  : theme.colorScheme.surfaceContainerLowest,
                              border: Border.all(
                                color: isSelected
                                    ? color
                                    : theme.colorScheme.outlineVariant
                                        .withAlpha(160),
                                width: isSelected ? 1.6 : 1.0,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${sharePct.toStringAsFixed(1)}% • ${IndianFormatters.formatInrCompact(item.posAmount)} (${item.loanCount})',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                LayoutBuilder(
                                  builder: (context, barConstraints) {
                                    final barWidth =
                                        barConstraints.maxWidth * ratio;
                                    final npaWidth = barWidth * npaRatioInBar;
                                    return Stack(
                                      children: [
                                        Container(
                                          height: 10,
                                          width: barConstraints.maxWidth,
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                        ),
                                        AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 250),
                                          height: 10,
                                          width: barWidth,
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                        ),
                                        if (npaWidth > 0)
                                          AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 250),
                                            height: 10,
                                            width: npaWidth,
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme.error,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                if (item.npaPosAmount > 0) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    '90+ DPD NPA: ${IndianFormatters.formatInrCompact(item.npaPosAmount)} (${item.npaSharePct.toStringAsFixed(1)}% of bucket POS)',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 240, child: donutWidget),
                        const SizedBox(width: 16),
                        Expanded(child: barsList),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      donutWidget,
                      const SizedBox(height: 14),
                      barsList,
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PortfolioDonutCard extends StatelessWidget {
  const _PortfolioDonutCard({
    required this.metrics,
    required this.totalPos,
    required this.selectedKey,
    required this.palette,
    required this.onSelect,
  });

  final List<SliceMetric> metrics;
  final double totalPos;
  final String? selectedKey;
  final List<Color> palette;
  final void Function(String key) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeMetric = selectedKey == null
        ? null
        : metrics.cast<SliceMetric?>().firstWhere(
              (m) => m?.key == selectedKey,
              orElse: () => null,
            );

    final centerTitle = activeMetric != null
        ? '${((activeMetric.posAmount / (totalPos <= 0 ? 1 : totalPos)) * 100).toStringAsFixed(1)}%'
        : '${metrics.length}';
    final centerSub = activeMetric?.title ?? 'Buckets';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(160),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 156,
            width: 156,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(156, 156),
                  painter: _DonutRingPainter(
                    metrics: metrics,
                    totalPos: totalPos,
                    selectedKey: selectedKey,
                    palette: palette,
                    trackColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        centerSub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: List.generate(math.min(metrics.length, 5), (i) {
              final m = metrics[i];
              final c = palette[i % palette.length];
              final isSel = selectedKey == m.key;
              return ChoiceChip(
                label: Text(
                  m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
                avatar: CircleAvatar(backgroundColor: c, radius: 5),
                selected: isSel,
                onSelected: (_) => onSelect(m.key),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DonutRingPainter extends CustomPainter {
  const _DonutRingPainter({
    required this.metrics,
    required this.totalPos,
    required this.selectedKey,
    required this.palette,
    required this.trackColor,
  });

  final List<SliceMetric> metrics;
  final double totalPos;
  final String? selectedKey;
  final List<Color> palette;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 18.0;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    if (totalPos <= 0 || metrics.isEmpty) return;

    var startAngle = -math.pi / 2;
    for (var i = 0; i < metrics.length; i++) {
      final m = metrics[i];
      final sweep = (m.posAmount / totalPos) * math.pi * 2;
      if (sweep <= 0) continue;

      final isSelected = selectedKey == m.key;
      final paint = Paint()
        ..color = palette[i % palette.length]
            .withAlpha(selectedKey == null || isSelected ? 255 : 95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? strokeWidth + 4 : strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutRingPainter oldDelegate) {
    return oldDelegate.metrics != metrics ||
        oldDelegate.totalPos != totalPos ||
        oldDelegate.selectedKey != selectedKey;
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
              color: isAlert
                  ? scheme.onErrorContainer
                  : scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

