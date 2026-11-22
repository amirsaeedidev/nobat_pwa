import 'package:flutter/material.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_chart.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/models/enums.dart';
import '../../../../core/widgets/app_card.dart';
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
          childAspectRatio: cols == 1 ? 2.8 : 1.75,
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
      _Chart(title: 'عملکرد پرسنل', subtitle: 'درآمد و پورسانت', child: AppChart(
        type: AppChartType.bar, height: 210,
        points: [for (final e in analytics.employees) AppChartPoint(label: e.name, value: e.revenue)],
        series: [
          AppChartSeries(name: 'درآمد', color: pal.primary,
            values: [for (final e in analytics.employees) e.revenue]),
          AppChartSeries(name: 'پورسانت', color: pal.warning,
            values: [for (final e in analytics.employees) e.commission]),
        ],
        valueFormatter: (v) => Fmt.compactMoney(v.toDouble()),
      )),
      const SizedBox(height: 12),
      _Chart(title: 'محبوبیت خدمات', subtitle: 'تعداد نوبت‌های تکمیل‌شده', child: AppChart(
        type: AppChartType.pie, height: 210,
        points: [for (final e in analytics.services)
          AppChartPoint(label: e.name, value: e.count, color: [
            pal.primaryBright, pal.info, pal.success, pal.warning, pal.purple,
          ][analytics.services.indexOf(e) % 5])],
        valueFormatter: (v) => FaNum.ofInt(v.round()),
      )),
      const SizedBox(height: 12),
      _Chart(title: 'ترکیب درآمد و هزینه', subtitle: 'سهم هر بخش از مجموع مبالغ ثبت‌شده', child: AppChart(
        type: AppChartType.donut, height: 190,
        points: [
          AppChartPoint(label: 'درآمد', value: analytics.revenue, color: pal.success),
          AppChartPoint(label: 'هزینه', value: analytics.cost, color: pal.danger),
        ],
        valueFormatter: (v) => Fmt.compactMoney(v.toDouble()),
      )),
      const SizedBox(height: 12),
      _Chart(title: 'ترکیب خدمات به تفکیک پرسنل', subtitle: 'تعداد ارائه هر خدمت توسط هر پرسنل', child: AppChart(
        type: AppChartType.stackedBar, height: 210,
        points: [for (final service in analytics.services)
          AppChartPoint(label: service.name, value: service.count, segments: service.employeeCounts)],
        valueFormatter: (v) => FaNum.ofInt(v.round()),
      )),
      const SizedBox(height: 12),
      _Chart(title: 'مقایسه درآمد و هزینه', subtitle: 'روند بازه انتخاب‌شده', child: AppChart(
        type: AppChartType.bar, height: 205,
        points: [for (final e in analytics.trend) AppChartPoint(label: e.label, value: e.revenue)],
        series: [
          AppChartSeries(name: 'درآمد', color: pal.success,
            values: [for (final e in analytics.trend) e.revenue]),
          AppChartSeries(name: 'هزینه', color: pal.danger,
            values: [for (final e in analytics.trend) e.cost]),
        ],
        valueFormatter: (v) => Fmt.compactMoney(v.toDouble()),
      )),
      const SizedBox(height: 12),
      _Chart(title: 'روند جذب مشتری', subtitle: 'مشتریان جدید در هر بازه', child: AppChart(
        type: AppChartType.area, height: 190,
        points: [for (final e in analytics.newCustomerTrend)
          AppChartPoint(label: e.label, value: e.appointments)],
        series: [AppChartSeries(name: 'مشتری جدید', color: pal.primary,
          values: [for (final e in analytics.newCustomerTrend) e.appointments])],
        valueFormatter: (v) => FaNum.ofInt(v.round()),
      )),
      const SizedBox(height: 8),
      Text(analytics.costNote, style: TextStyle(fontSize: 10, color: pal.textMuted)),
    ]);
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
