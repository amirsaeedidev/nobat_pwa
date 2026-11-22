import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../utils/fa_num.dart';

enum AppChartType {
  line('خطی'), area('ناحیه‌ای'), bar('میله‌ای'),
  stackedBar('میله‌ای انباشته'), horizontalBar('میله‌ای افقی'),
  pie('دایره‌ای'), donut('حلقه‌ای');
  const AppChartType(this.label);
  final String label;
}

class AppChartPoint {
  const AppChartPoint({
    required this.label, required this.value, this.secondary = 0,
    this.segments = const {}, this.color,
  });
  final String label;
  final num value;
  final num secondary;
  final Map<String, num> segments;
  final Color? color;
}

class AppChartSeries {
  const AppChartSeries({required this.name, required this.values, this.color});
  final String name;
  final List<num> values;
  final Color? color;
}

/// Shared fl_chart renderer. Values must come from the caller's repository/provider.
class AppChart extends StatelessWidget {
  const AppChart({
    super.key, required this.points, this.type = AppChartType.line,
    this.series = const [], this.height = 220, this.title,
    this.valueSuffix = '', this.valueFormatter, this.onPointTap,
    this.loading = false, this.error, this.showLegend = true, this.onTypeChanged, this.centerLabel = 'مجموع',
  });
  final List<AppChartPoint> points;
  final AppChartType type;
  final List<AppChartSeries> series;
  final double height;
  final String? title;
  final String valueSuffix;
  final String Function(num)? valueFormatter;
  final void Function(String label, String series, num value)? onPointTap;
  final bool loading;
  final String? error;
  final bool showLegend;
  final ValueChanged<AppChartType>? onTypeChanged;
  final String centerLabel;
  final List<AppChartType> switchableTypes = const [AppChartType.line, AppChartType.area, AppChartType.bar];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final resolved = _series(p);
    final circular = type == AppChartType.pie || type == AppChartType.donut;
    final valid = circular
        ? points.any((e) => e.value > 0)
        : points.isNotEmpty && resolved.any((e) => e.values.isNotEmpty);
    return LayoutBuilder(builder: (context, box) {
      final compact = box.maxWidth < 360;
      final h = math.max(120.0, height);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null || onTypeChanged != null)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
            if (title != null) Expanded(child: Text(title!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w700))),
            if (onTypeChanged != null) PopupMenuButton<AppChartType>(
              tooltip: 'تغییر نوع نمودار', padding: EdgeInsets.zero,
              icon: Icon(Icons.swap_horiz_rounded, color: p.textSecondary, size: 20),
              onSelected: onTypeChanged,
              itemBuilder: (context) => [for (final t in switchableTypes) PopupMenuItem(value: t, child: Text(t.label))],
            ),
          ])),
        if (loading)
          SizedBox(height: h, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: p.primary)))
        else if (error != null)
          SizedBox(height: h, child: Center(child: Text(error!, textAlign: TextAlign.center,
            style: TextStyle(color: p.danger, fontSize: 12))))
        else if (!valid)
          SizedBox(height: h, child: Center(child: Text('برای این بازه داده‌ای ثبت نشده است',
            textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, fontSize: 12))))
        else
          SizedBox(height: h, child: _render(context, resolved, compact)),
        if (showLegend && valid && !loading && error == null)
          _legend(context, resolved, compact),
      ]);
    });
  }

  List<AppChartSeries> _series(AppPalette p) {
    final colors = _colors(p);
    if (series.isNotEmpty) return series;
    if (type == AppChartType.stackedBar) {
      final keys = <String>{};
      for (final point in points) { keys.addAll(point.segments.keys); }
      return [
        for (var i = 0; i < keys.length; i++)
          AppChartSeries(name: keys.elementAt(i), color: colors[i % colors.length],
            values: [for (final point in points) point.segments[keys.elementAt(i)] ?? 0]),
      ];
    }
    return [
      AppChartSeries(name: title ?? 'مقدار', color: p.primary,
        values: [for (final point in points) point.value]),
      if (points.any((point) => point.secondary != 0))
        AppChartSeries(name: 'مقدار دوم', color: p.warning,
          values: [for (final point in points) point.secondary]),
    ];
  }

  Widget _render(BuildContext context, List<AppChartSeries> data, bool compact) {
    switch (type) {
      case AppChartType.pie:
      case AppChartType.donut: return _pie(context, compact);
      case AppChartType.line:
      case AppChartType.area: return _line(context, data);
      case AppChartType.bar:
      case AppChartType.stackedBar:
      case AppChartType.horizontalBar: return _bar(context, data, compact);
    }
  }

  Widget _line(BuildContext context, List<AppChartSeries> data) {
    final p = context.pal;
    final colors = _colors(p);
    final maxValue = data.expand((s) => s.values).fold<double>(0, (a, b) => math.max(a, b.toDouble()));
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.18;
    final count = points.length;
    return LineChart(LineChartData(
      minX: 0, maxX: math.max(1, count - 1).toDouble(), minY: 0, maxY: maxY,
      gridData: FlGridData(drawVerticalLine: false, horizontalInterval: maxY / 4,
        getDrawingHorizontalLine: (_) => FlLine(color: p.textPrimary.withValues(alpha: .07))),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: horizontal, reservedSize: horizontal ? 76 : 0,
          getTitlesWidget: (v, _) {
            final i = v.round();
            if (!horizontal || i < 0 || i >= count) return const SizedBox.shrink();
            return Text(points[i].label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.textMuted, fontSize: 9));
          })),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 25,
          interval: count > 6 ? (count / 5).ceilToDouble() : 1,
          getTitlesWidget: (v, _) {
            final i = v.round();
            if (i < 0 || i >= count) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(top: 5),
              child: Text(points[i].label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textMuted, fontSize: 9)));
          },
        )),
      ),
      lineTouchData: LineTouchData(enabled: true,
        touchTooltipData: LineTouchTooltipData(getTooltipColor: (_) => p.surfaceHigh,
          tooltipRoundedRadius: 9,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                points[s.x.round().clamp(0, count - 1)].label + '\n' +
                  data[s.barIndex].name + ': ' + _format(s.y),
                TextStyle(color: p.textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
        touchCallback: (event, response) {
          if (event is FlTapUpEvent && response?.lineBarSpots?.isNotEmpty == true) {
            final s = response!.lineBarSpots!.first;
            final i = s.x.round().clamp(0, count - 1);
            onPointTap?.call(points[i].label, data[s.barIndex].name, s.y);
          }
        }),
      lineBarsData: [
        for (var s = 0; s < data.length; s++)
          LineChartBarData(
            spots: [for (var i = 0; i < math.min(count, data[s].values.length); i++)
              FlSpot(i.toDouble(), data[s].values[i].toDouble())],
            isCurved: true, curveSmoothness: .25, barWidth: 2.5,
            color: data[s].color ?? colors[s % colors.length],
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: type == AppChartType.area && s == 0,
              color: (data[s].color ?? colors[s % colors.length]).withValues(alpha: .20)),
          ),
      ],
    ), duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic);
  }

  Widget _bar(BuildContext context, List<AppChartSeries> data, bool compact) {
    final p = context.pal;
    final colors = _colors(p);
    final stacked = type == AppChartType.stackedBar;
    final horizontal = type == AppChartType.horizontalBar;
    final count = points.length;
    final totals = <double>[
      for (var i = 0; i < count; i++)
        stacked
          ? data.fold<double>(0, (sum, s) => sum + (i < s.values.length ? s.values[i].toDouble() : 0))
          : data.fold<double>(0, (max, s) => math.max(max, i < s.values.length ? s.values[i].toDouble() : 0)),
    ];
    final peak = totals.fold<double>(0, math.max);
    final maxY = peak <= 0 ? 1.0 : peak * 1.18;
    final groups = <BarChartGroupData>[
      for (var i = 0; i < count; i++)
        BarChartGroupData(x: i, barsSpace: 3, barRods: stacked
          ? [BarChartRodData(toY: totals[i], width: compact ? 15 : 21,
              borderRadius: BorderRadius.circular(4), rodStackItems: _stackItems(data, i, colors))]
          : [for (var s = 0; s < data.length; s++)
              if (i < data[s].values.length)
                BarChartRodData(toY: data[s].values[i].toDouble(),
                  width: data.length > 1 ? (compact ? 8 : 12) : (compact ? 17 : 23),
                  color: data[s].color ?? colors[s % colors.length],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)))],
        ),
    ];
    return BarChart(BarChartData(
      maxY: maxY, minY: 0, alignment: BarChartAlignment.spaceAround,
      groupsSpace: 8, rotationQuarterTurns: horizontal ? 1 : 0,
      gridData: FlGridData(drawVerticalLine: false, horizontalInterval: maxY / 4,
        getDrawingHorizontalLine: (_) => FlLine(color: p.textPrimary.withValues(alpha: .07))),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: !horizontal, reservedSize: 26,
          interval: count > 7 ? (count / 6).ceilToDouble() : 1,
          getTitlesWidget: (v, _) {
            final i = v.round();
            if (i < 0 || i >= count) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(top: 5),
              child: Text(points[i].label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textMuted, fontSize: 9)));
          },
        )),
      ),
      barTouchData: BarTouchData(enabled: true,
        touchTooltipData: BarTouchTooltipData(getTooltipColor: (_) => p.surfaceHigh,
          tooltipRoundedRadius: 9,
          getTooltipItem: (g, _, rod, ri) {
            final name = stacked ? 'مجموع' : (ri < data.length ? data[ri].name : 'مجموع');
            return BarTooltipItem(points[g.x].label + '\n' + name + ': ' + _format(rod.toY),
              TextStyle(color: p.textPrimary, fontSize: 10, fontWeight: FontWeight.w600));
          }),
        touchCallback: (event, response) {
          if (event is FlTapUpEvent && response?.spot != null) {
            final s = response!.spot!;
            final i = s.touchedBarGroupIndex;
            final ri = s.touchedRodDataIndex;
            if (i >= 0 && i < count) {
              final value = !stacked && ri < data.length && i < data[ri].values.length ? data[ri].values[i] : totals[i];
              onPointTap?.call(points[i].label, !stacked && ri < data.length ? data[ri].name : 'مجموع', value);
            }
          }
        }),
      barGroups: groups,
    ), duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic);
  }

  List<BarChartRodStackItem> _stackItems(List<AppChartSeries> data, int index, List<Color> colors) {
    var start = 0.0;
    final items = <BarChartRodStackItem>[];
    for (var i = 0; i < data.length; i++) {
      if (index >= data[i].values.length || data[i].values[index] <= 0) continue;
      final end = start + data[i].values[index].toDouble();
      items.add(BarChartRodStackItem(start, end, data[i].color ?? colors[i % colors.length]));
      start = end;
    }
    return items;
  }

  Widget _pie(BuildContext context, bool compact) {
    final p = context.pal;
    final colors = _colors(p);
    final entries = points.where((e) => e.value > 0).toList();
    final total = entries.fold<double>(0, (sum, e) => sum + e.value.toDouble());
    final diameter = math.min(height, compact ? 190.0 : 240.0);
    return Center(child: SizedBox(width: diameter, height: diameter,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(PieChartData(startDegreeOffset: -90,
          centerSpaceRadius: type == AppChartType.donut ? diameter * .28 : 0,
          sectionsSpace: 2,
          pieTouchData: PieTouchData(touchCallback: (event, response) {
            final i = response?.touchedSection?.touchedSectionIndex;
            if (event is FlTapUpEvent && i != null && i >= 0 && i < entries.length) {
              onPointTap?.call(entries[i].label, entries[i].label, entries[i].value);
            }
          }),
          sections: [for (var i = 0; i < entries.length; i++)
            PieChartSectionData(value: entries[i].value.toDouble(),
              color: entries[i].color ?? colors[i % colors.length],
              radius: diameter * .40, showTitle: false)],
        ), duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic),
        if (type == AppChartType.donut)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_format(total), style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
            Text(centerLabel, style: TextStyle(color: p.textMuted, fontSize: 10)),
          ]),
      ])));
  }

  Widget _legend(BuildContext context, List<AppChartSeries> data, bool compact) {
    final p = context.pal;
    final colors = _colors(p);
    final List<(String, Color)> items = type == AppChartType.pie || type == AppChartType.donut
      ? [for (var i = 0; i < points.length; i++) (points[i].label, points[i].color ?? colors[i % colors.length])]
      : [for (var i = 0; i < data.length; i++) (data[i].name, data[i].color ?? colors[i % colors.length])];
    if (items.length <= 1) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(
      alignment: WrapAlignment.center, spacing: compact ? 8 : 12, runSpacing: 6,
      children: [for (final item in items) Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: item.$2, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(item.$1, style: TextStyle(color: p.textSecondary, fontSize: 9)),
      ])],
    ));
  }

  List<Color> _colors(AppPalette p) => [
    p.primaryBright, p.info, p.success, p.warning, p.danger, p.purple, p.accentGlow,
  ];

  String _format(num value) =>
    (valueFormatter?.call(value) ?? FaNum.ofInt(value.round())) + valueSuffix;
}
