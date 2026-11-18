import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../engines/delinquency_engine.dart';
import '../models/loan_model.dart';
import '../utils/indian_formatters.dart';

/// Visualizes portfolio principal outstanding across all 5 DPD aging buckets.
class AgingBucketChart extends StatelessWidget {
  const AgingBucketChart({
    super.key,
    required this.breakdown,
  });

  final Map<AgingBucket, AgingBucketStat> breakdown;

  static Color colorForBucket(AgingBucket bucket) {
    switch (bucket) {
      case AgingBucket.current:
        return Colors.green.shade600;
      case AgingBucket.dpd1To30:
        return Colors.amber.shade700;
      case AgingBucket.dpd31To60:
        return Colors.orange.shade700;
      case AgingBucket.dpd61To90:
        return Colors.deepOrange.shade700;
      case AgingBucket.dpd90Plus:
        return Colors.red.shade700;
    }
  }

  static String shortLabel(AgingBucket bucket) {
    switch (bucket) {
      case AgingBucket.current:
        return 'Current';
      case AgingBucket.dpd1To30:
        return '1–30';
      case AgingBucket.dpd31To60:
        return '31–60';
      case AgingBucket.dpd61To90:
        return '61–90';
      case AgingBucket.dpd90Plus:
        return '90+';
    }
  }

  @override
  Widget build(BuildContext context) {
    final buckets = AgingBucket.values;
    final maxVal = buckets.fold<double>(
      10000.0,
      (prev, b) {
        final v = breakdown[b]?.principalOutstanding ?? 0.0;
        return v > prev ? v : prev;
      },
    );

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Portfolio Aging Breakdown (Principal Outstanding)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 210,
              child: BarChart(
                BarChartData(
                  maxY: maxVal * 1.18,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, _, rod, __) {
                        final bucket = buckets[group.x];
                        final stat = breakdown[bucket];
                        return BarTooltipItem(
                          '${bucket.label}\n'
                          '${IndianFormatters.formatInrCompact(rod.toY)} '
                          '(${stat?.loanCount ?? 0} loans)',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        getTitlesWidget: (val, _) => Text(
                          IndianFormatters.formatInrCompact(val),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx < 0 || idx >= buckets.length) {
                            return const SizedBox.shrink();
                          }
                          final b = buckets[idx];
                          final count = breakdown[b]?.loanCount ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${shortLabel(b)} ($count)',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < buckets.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: breakdown[buckets[i]]?.principalOutstanding ??
                                0.0,
                            color: colorForBucket(buckets[i]),
                            width: 26,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
