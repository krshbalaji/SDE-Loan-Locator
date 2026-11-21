import 'package:flutter/material.dart';

import '../utils/portfolio_intelligence.dart';

/// Displays a metric or table cell with hover-on-desktop and tap-on-touch
/// diagnostic breakdown (Why Presented, Benchmark, Data Comparison, Improvement).
class DiagnosticCellCard extends StatelessWidget {
  const DiagnosticCellCard({
    super.key,
    required this.meta,
    this.compact = false,
  });

  final DiagnosticCellMeta meta;
  final bool compact;

  Color _accentColor(BuildContext context) {
    switch (meta.severity) {
      case DiagnosticSeverity.good:
        return Colors.green.shade700;
      case DiagnosticSeverity.watch:
        return Colors.amber.shade800;
      case DiagnosticSeverity.alert:
        return Colors.red.shade700;
    }
  }

  void _openDetailsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              meta.title,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              meta.valueLabel,
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    color: _accentColor(ctx),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Divider(height: 20),
            _lineItem(ctx, 'Why Presented This Way', meta.whyPresented),
            _lineItem(ctx, 'Benchmark Standard', meta.benchmark),
            _lineItem(ctx, 'Real Data Comparison', meta.dataComparison),
            _lineItem(ctx, 'Suggestion to Improve', meta.improvementAction),
          ],
        ),
      ),
    );
  }

  Widget _lineItem(BuildContext context, String heading, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(context);
    final tooltipText = [
      '${meta.title}: ${meta.valueLabel}',
      'Why: ${meta.whyPresented}',
      'Benchmark: ${meta.benchmark}',
      'Actual vs Benchmark: ${meta.dataComparison}',
      'Improve: ${meta.improvementAction}',
    ].join('\n');

    return Tooltip(
      message: tooltipText,
      waitDuration: const Duration(milliseconds: 200),
      showDuration: const Duration(seconds: 8),
      child: InkWell(
        onTap: () => _openDetailsSheet(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.all(compact ? 10 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meta.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Icon(Icons.info_outline, size: 14, color: accent),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                meta.valueLabel,
                style: (compact
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.titleLarge)
                    ?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 6),
                Text(
                  meta.dataComparison,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
