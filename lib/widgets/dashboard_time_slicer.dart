import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/activity_telemetry_service.dart';

enum DashboardTimeSlice { today, last7Days, mtd, fy, custom }

class DashboardTimeSlicerController {
  DashboardTimeSlice slice;
  DateTimeRange? customRange;

  DashboardTimeSlicerController({
    this.slice = DashboardTimeSlice.mtd,
    this.customRange,
  });

  DateTimeRange resolveRange(DateTime now) {
    final todayStart = DateTime(now.year, now.month, now.day);
    switch (slice) {
      case DashboardTimeSlice.today:
        return DateTimeRange(start: todayStart, end: now);
      case DashboardTimeSlice.last7Days:
        return DateTimeRange(
          start: todayStart.subtract(const Duration(days: 6)),
          end: now,
        );
      case DashboardTimeSlice.mtd:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case DashboardTimeSlice.fy:
        final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
        return DateTimeRange(start: DateTime(fyStartYear, 4, 1), end: now);
      case DashboardTimeSlice.custom:
        if (customRange != null) {
          return DateTimeRange(
            start: DateTime(
              customRange!.start.year,
              customRange!.start.month,
              customRange!.start.day,
            ),
            end: DateTime(
              customRange!.end.year,
              customRange!.end.month,
              customRange!.end.day,
              23,
              59,
              59,
            ),
          );
        }
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    }
  }

  static String labelFor(DashboardTimeSlice s) {
    switch (s) {
      case DashboardTimeSlice.today:
        return 'Today';
      case DashboardTimeSlice.last7Days:
        return '7D';
      case DashboardTimeSlice.mtd:
        return 'MTD';
      case DashboardTimeSlice.fy:
        return 'FY';
      case DashboardTimeSlice.custom:
        return 'Custom';
    }
  }
}

class DashboardTimeSlicerBar extends StatelessWidget {
  final DashboardTimeSlicerController controller;
  final DateTime? referenceNow;
  final VoidCallback onChanged;
  final String telemetryScreenName;

  const DashboardTimeSlicerBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.referenceNow,
    this.telemetryScreenName = 'Executive BI',
  });

  String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickRange(BuildContext context, DateTime now) async {
    final initial = controller.customRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
    );
    if (picked == null || !context.mounted) return;
    controller.slice = DashboardTimeSlice.custom;
    controller.customRange = picked;
    onChanged();
    context.read<ActivityTelemetryService>().logFilterApplied(
          telemetryScreenName,
          'Custom range ${picked.start.toIso8601String().substring(0, 10)} to ${picked.end.toIso8601String().substring(0, 10)}',
        );
  }

  @override
  Widget build(BuildContext context) {
    final now = referenceNow ?? DateTime.now();
    final range = controller.resolveRange(now);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.date_range, size: 18),
          const SizedBox(width: 8),
          for (final s in DashboardTimeSlice.values) ...[
            ChoiceChip(
              label: Text(DashboardTimeSlicerController.labelFor(s)),
              selected: controller.slice == s,
              onSelected: (_) async {
                if (s == DashboardTimeSlice.custom) {
                  await _pickRange(context, now);
                  return;
                }
                controller.slice = s;
                onChanged();
                context.read<ActivityTelemetryService>().logFilterApplied(
                      telemetryScreenName,
                      'Time slice: ${DashboardTimeSlicerController.labelFor(s)}',
                    );
              },
            ),
            const SizedBox(width: 6),
          ],
          Chip(
            label: Text('${_fmtShort(range.start)} – ${_fmtShort(range.end)}'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}