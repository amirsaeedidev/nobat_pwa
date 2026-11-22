import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/app_chart.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/dashboard_stats.dart';

/// Compatibility adapter; rendering is delegated to the shared chart layer.
class RevenueBarChart extends StatelessWidget {
  const RevenueBarChart({super.key, required this.data, this.height = 190, this.onPointTap});
  final List<RevenuePoint> data;
  final double height;
  final ValueChanged<int>? onPointTap;

  @override
  Widget build(BuildContext context) => AppChart(
    type: AppChartType.bar,
    height: height,
    points: [for (final item in data) AppChartPoint(label: item.label, value: item.value)],
    valueFormatter: (value) => Fmt.compactMoney(value.toDouble()),
    showLegend: false,
    onPointTap: (label, series, value) {
      final index = data.indexWhere((item) => item.label == label);
      if (index >= 0) onPointTap?.call(index);
    },
  );
}

/// Line chart with optional second repository-backed series for comparisons.
class RevenueLineChart extends StatelessWidget {
  const RevenueLineChart({super.key, required this.data, this.height = 180, this.showSecondary = false, this.onPointTap});
  final List<RevenuePoint> data;
  final double height;
  final bool showSecondary;
  final ValueChanged<int>? onPointTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.pal;
    return AppChart(
      type: AppChartType.line,
      height: height,
      points: [for (final item in data) AppChartPoint(label: item.label, value: item.value)],
      series: [
        AppChartSeries(name: 'درآمد', color: palette.primary,
          values: [for (final item in data) item.value]),
        if (showSecondary)
          AppChartSeries(name: 'هزینه', color: palette.warning,
            values: [for (final item in data) item.secondary]),
      ],
      valueFormatter: (value) => Fmt.compactMoney(value.toDouble()),
      onPointTap: (label, series, value) {
        final index = data.indexWhere((item) => item.label == label);
        if (index >= 0) onPointTap?.call(index);
      },
    );
  }
}

/// Status donut uses the same semantic status colors in every app theme.
class StatusDonut extends StatelessWidget {
  const StatusDonut({super.key, required this.counts, this.size = 150, this.centerLabel = 'نوبت', this.onSegmentTap});
  final Map<String, int> counts;
  final double size;
  final String centerLabel;
  final ValueChanged<String>? onSegmentTap;

  Color _statusColor(String label, AppPalette palette) {
    if (label.contains('انتظار')) return const Color(0xFFE69A32);
    if (label.contains('مراجعه') || label.contains('غیبت')) return const Color(0xFF8B929B);
    if (label.contains('لغو') || label.contains('رد')) return const Color(0xFFD95757);
    if (label.contains('تأیید') || label.contains('تایید')) return const Color(0xFF3987D7);
    if (label.contains('تکمیل') || label.contains('انجام')) return const Color(0xFF32966B);
    return palette.primaryBright;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.pal;
    return AppChart(
      type: AppChartType.donut,
      height: size,
      points: [
        for (final entry in counts.entries)
          AppChartPoint(label: entry.key, value: entry.value, color: _statusColor(entry.key, palette)),
      ],
      showLegend: true,
      onPointTap: (label, series, value) => onSegmentTap?.call(label),
    );
  }
}

/// Shared entrance animation retained for existing report layouts.
class ReportChartEntrance extends StatelessWidget {
  const ReportChartEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 520),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(offset: Offset(0, (1 - value) * 18), child: child),
    ),
  );
}
