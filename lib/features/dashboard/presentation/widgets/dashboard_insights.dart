import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/models/enums.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';

/// نمودارها و شاخص‌های داشبورد از مدل گزارش مشترک تغذیه می‌شوند.
class DashboardInsights extends StatelessWidget {
  const DashboardInsights({super.key, required this.analytics, required this.filter, required this.onFilterChanged});
  final ReportAnalytics analytics;
  final ReportAnalyticsFilter filter;
  final ValueChanged<ReportAnalyticsFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final methods = analytics.paymentsByMethod.keys.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title: 'تحلیل مالی و عملکردی', subtitle: analytics.range.label),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth < 380 ? 1 : 2;
        return GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols, mainAxisSpacing: 8, crossAxisSpacing: 8,
          childAspectRatio: cols == 1 ? 3.6 : 2.1,
          children: [
            _MetricTile('درآمد خالص', Fmt.compactMoneyShort(analytics.netRevenue), pal.success),
            _MetricTile('پورسانت پرسنل', Fmt.compactMoneyShort(analytics.commissionCost), pal.warning),
            _MetricTile('سهم مجموعه', Fmt.compactMoneyShort(analytics.companyShare), pal.primary),
            _MetricTile('هزینه‌ها', Fmt.compactMoneyShort(analytics.cost), pal.danger),
          ]);
      }),
      const SizedBox(height: 12),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('فیلترهای ترکیبی', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth < 360 ? c.maxWidth : (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(width: w, child: _select<String>('پرسنل', filter.employeeId,
              analytics.employees.map((e) => DropdownMenuItem(value: e.employeeId, child: Text(e.name, overflow: TextOverflow.ellipsis))).toList(),
              (v) => onFilterChanged(filter.copyWith(employeeId: v, clearEmployee: v == null)))),
            SizedBox(width: w, child: _select<String>('خدمت', filter.serviceId,
              analytics.services.where((e) => e.serviceId.isNotEmpty).map((e) => DropdownMenuItem(value: e.serviceId, child: Text(e.name, overflow: TextOverflow.ellipsis))).toList(),
              (v) => onFilterChanged(filter.copyWith(serviceId: v, clearService: v == null)))),
            SizedBox(width: w, child: _select<AppointmentStatus>('وضعیت', filter.status,
              AppointmentStatus.values.map((e) => DropdownMenuItem(value: e, child: Text(e.label))).toList(),
              (v) => onFilterChanged(filter.copyWith(status: v, clearStatus: v == null)))),
            SizedBox(width: w, child: _select<String>('روش پرداخت', filter.paymentMethod,
              methods.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              (v) => onFilterChanged(filter.copyWith(paymentMethod: v, clearPaymentMethod: v == null)))),
          ]);
        }),
        Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(
          onPressed: () => onFilterChanged(const ReportAnalyticsFilter()), child: const Text('پاک‌کردن فیلترها'))),
      ])),
      const SizedBox(height: 12),
      _Chart(title: 'عملکرد پرسنل', subtitle: 'درآمد و پورسانت', child: SizedBox(height: 210,
        child: analytics.employees.isEmpty ? const EmptyState(title: 'داده‌ای وجود ندارد', compact: true) : BarChart(BarChartData(
          maxY: _max(analytics.employees.map((e) => e.revenue).toList()),
          barGroups: [for (var i=0;i<analytics.employees.length;i++) BarChartGroupData(x:i, barRods:[
            BarChartRodData(toY: analytics.employees[i].revenue.toDouble(), color: pal.primary, width: 12),
            BarChartRodData(toY: analytics.employees[i].commission.toDouble(), color: pal.warning, width: 7),
          ])],
          barTouchData: BarTouchData(enabled: true, touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
              '${analytics.employees[g.x].name}\n${Fmt.money(rod.toY)}', const TextStyle(color: Colors.white, fontSize: 11)))),
          titlesData: const FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
          gridData: const FlGridData(show: true), borderData: FlBorderData(show: false),
        )))),
      const SizedBox(height: 12),
      _Chart(title: 'محبوبیت خدمات', subtitle: 'تعداد نوبت‌های تکمیل‌شده', child: SizedBox(height: 210,
        child: analytics.services.isEmpty ? const EmptyState(title: 'داده‌ای وجود ندارد', compact: true) : PieChart(PieChartData(
          centerSpaceRadius: 38, sectionsSpace: 3,
          sections: [for (var i=0;i<analytics.services.length;i++) PieChartSectionData(
            value: analytics.services[i].count.toDouble(), title: FaNum.ofInt(analytics.services[i].count),
            radius: 72, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))],
        )))),
      const SizedBox(height: 12),
      _Chart(title: 'مقایسه درآمد و هزینه', subtitle: 'روند بازه انتخاب‌شده', child: SizedBox(height: 205,
        child: BarChart(BarChartData(
          barGroups: [for (var i=0;i<analytics.trend.length;i++) BarChartGroupData(x:i, barRods:[
            BarChartRodData(toY: analytics.trend[i].revenue.toDouble(), color: pal.success, width: 10),
            BarChartRodData(toY: analytics.trend[i].cost.toDouble(), color: pal.danger, width: 10),
          ])],
          barTouchData: BarTouchData(enabled: true, touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem('${ri == 0 ? 'درآمد' : 'هزینه'}: ${Fmt.money(rod.toY)}', const TextStyle(color: Colors.white, fontSize: 10)))),
          titlesData: const FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
          gridData: const FlGridData(show: true), borderData: FlBorderData(show: false),
        )))),
      const SizedBox(height: 12),
      _Chart(title: 'روند جذب مشتری', subtitle: 'مشتریان جدید در هر بازه', child: SizedBox(height: 190,
        child: LineChart(LineChartData(
          lineTouchData: LineTouchData(enabled: true, touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem('مشتری جدید: ${FaNum.ofInt(s.y.round())}', const TextStyle(color: Colors.white, fontSize: 10))).toList())),
          lineBarsData: [LineChartBarData(isCurved: true, color: pal.primary, barWidth: 3,
            dotData: const FlDotData(show: true),
            spots: [for (var i=0;i<analytics.newCustomerTrend.length;i++) FlSpot(i.toDouble(), analytics.newCustomerTrend[i].appointments.toDouble())])],
          titlesData: const FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false))),
          gridData: const FlGridData(show: true), borderData: FlBorderData(show: false),
        )))),
      const SizedBox(height: 8),
      Text(analytics.costNote, style: TextStyle(fontSize: 10, color: pal.textMuted)),
    ]);
  }

  static double _max(List<num> values) {
    final m = values.fold<num>(0, (a,b) => a > b ? a : b).toDouble();
    return m <= 0 ? 1 : m * 1.2;
  }

  Widget _select<T>(String label, T? value, List<DropdownMenuItem<T>> items, ValueChanged<T?> changed) =>
    DropdownButtonFormField<T>(value: value, isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      items: [DropdownMenuItem<T>(value: null, child: Text('همه $label')),...items], onChanged: changed);
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.title, this.value, this.color);
  final String title, value; final Color color;
  @override Widget build(BuildContext context) => AppCard(child: Row(children: [
    Container(width: 4, height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
    const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 11, color: context.pal.textSecondary)),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.pal.textPrimary)),
    ])),
  ]));
}

class _Chart extends StatelessWidget {
  const _Chart({required this.title, required this.subtitle, required this.child});
  final String title, subtitle; final Widget child;
  @override Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: context.pal.textPrimary)),
    const SizedBox(height: 3), Text(subtitle, style: TextStyle(fontSize: 10, color: context.pal.textMuted)),
    const SizedBox(height: 10), child,
  ]));
}
