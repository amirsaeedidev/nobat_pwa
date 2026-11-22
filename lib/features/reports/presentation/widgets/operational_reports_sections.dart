import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../providers/reports_provider.dart';
import '../../utils/report_table_export.dart';
import 'revenue_chart.dart';

/// بخش عملیاتی فاز چهار؛ از همان خروجی فیلترشده محاسبه‌گر گزارش استفاده می‌کند.
class OperationalReportsSections extends StatelessWidget {
  const OperationalReportsSections({super.key, required this.analytics, required this.provider});

  final ReportAnalytics analytics;
  final ReportsProvider provider;

  void _openDay(BuildContext context, ReportTrendPoint point) {
    final date = JalaliDate.fromDateTime(point.start);
    context.go('/reports?date=${date.iso}');
  }

  Future<void> _export(
    BuildContext context, {
    required String name,
    required List<String> headers,
    required List<List<Object?>> rows,
    required bool excel,
  }) async {
    try {
      if (excel) {
        await ReportTableExport.saveExcel(name: name, headers: headers, rows: rows);
      } else {
        await ReportTableExport.saveCsv(name: name, headers: headers, rows: rows);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فایل $name با موفقیت آماده شد.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خروجی گرفتن ناموفق بود: $error')));
      }
    }
  }

  Widget _exports(BuildContext context, String name, List<String> headers, List<List<Object?>> rows) =>
    Wrap(spacing: 6, runSpacing: 6, children: [
      TextButton(
        onPressed: () => _export(context, name: name, headers: headers, rows: rows, excel: false),
        child: const Text('خروجی CSV'),
      ),
      TextButton(
        onPressed: () => _export(context, name: name, headers: headers, rows: rows, excel: true),
        child: const Text('خروجی Excel'),
      ),
    ]);

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final services = provider.rankedServices;
    final customers = analytics.customerMetrics;
    final appointments = [...analytics.operationalAppointments]
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    final completed = analytics.operationalStatusCounts[AppointmentStatus.completed.label] ?? 0;
    final cancelled = analytics.operationalStatusCounts[AppointmentStatus.cancelled.label] ?? 0;
    final noShow = analytics.operationalStatusCounts[AppointmentStatus.noShow.label] ?? 0;
    final total = analytics.operationalAppointments.length;
    final rate = (int count) => total == 0 ? 0.0 : count * 100 / total;
    final averageGapValues = customers.where((item) => item.averageGapDays != null).map((item) => item.averageGapDays!).toList();
    final averageGap = averageGapValues.isEmpty ? null : averageGapValues.reduce((a, b) => a + b) / averageGapValues.length;

    final serviceHeaders = ['خدمت', 'تعداد ارائه', 'درآمد', 'میانگین قیمت واقعی', 'هزینه مستقیم', 'سود', 'حاشیه سود٪', 'پرسنل'];
    final serviceRows = [for (final item in services) [
      item.name, item.count, item.revenue.round(), item.averagePrice.round(),
      item.directCost?.round() ?? 'ثبت نشده', item.profit?.round() ?? 'نامشخص',
      item.marginPercent?.toStringAsFixed(1) ?? 'نامشخص',
      item.employeeCounts.entries.map((entry) => '${entry.key} (${entry.value})').join('، '),
    ]];
    final customerHeaders = ['مشتری', 'مراجعه در بازه', 'کل مراجعات', 'مراجعه مجدد', 'مجموع خرید', 'میانگین هر مراجعه', 'اولین مراجعه', 'آخرین مراجعه', 'فاصله میان مراجعات', 'وضعیت'];
    final customerRows = [for (final item in customers) [
      item.name, item.visits, item.lifetimeVisits, item.repeatVisits, item.totalSpent.round(), item.averageSpend.round(),
      item.firstVisitAt == null ? '' : JalaliDate.fromDateTime(item.firstVisitAt!).short,
      item.lastVisitAt == null ? '' : JalaliDate.fromDateTime(item.lastVisitAt!).short,
      item.averageGapDays?.toStringAsFixed(1) ?? '—',
      item.isInactive ? 'غیرفعال' : item.isAtRisk ? 'در معرض غیرفعال‌شدن' : item.isLoyal ? 'وفادار' : item.isNew ? 'جدید' : 'قدیمی',
    ]];
    final appointmentHeaders = ['کد نوبت', 'مشتری', 'خدمت', 'پرسنل', 'تاریخ', 'ساعت', 'وضعیت', 'مبلغ'];
    final appointmentRows = [for (final item in appointments) [
      item.reference, item.customerName, item.serviceName, item.employeeName,
      item.jalali.short, '${item.startAt.hour.toString().padLeft(2, '0')}:${item.startAt.minute.toString().padLeft(2, '0')}',
      item.status.label, item.price.round(),
    ]];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'گزارش خدمات', subtitle: 'مبنای تعداد، درآمد و میانگین قیمت، نوبت‌های تکمیل‌شده در فیلتر فعلی است.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 190, child: DropdownButtonFormField<ReportServiceSort>(
            value: provider.serviceSort,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'رتبه‌بندی خدمات'),
            items: const [
              DropdownMenuItem(value: ReportServiceSort.revenue, child: Text('درآمد بیشتر')),
              DropdownMenuItem(value: ReportServiceSort.bookings, child: Text('تعداد ارائه بیشتر')),
              DropdownMenuItem(value: ReportServiceSort.profit, child: Text('سود بیشتر')),
            ],
            onChanged: (value) { if (value != null) provider.setServiceSort(value); },
          )),
          _exports(context, 'گزارش-خدمات', serviceHeaders, serviceRows),
        ]),
        const SizedBox(height: 8),
        Text('پوشش ثبت هزینه مستقیم: ${FaNum.convert(analytics.directCostCoveragePercent.toStringAsFixed(1))}٪ از دفعات ارائه. هزینه و سود برای ردیف‌هایی که هزینه مستقیم همه نوبت‌هایشان ثبت نشده، «نامشخص» باقی می‌ماند.',
          style: TextStyle(fontSize: 10, color: pal.textMuted)),
        const SizedBox(height: 8),
        if (services.isEmpty)
          const EmptyState(title: 'در این بازه خدمت تکمیل‌شده‌ای وجود ندارد', compact: true)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text('خدمت')),
                DataColumn(label: Text('تعداد')),
                DataColumn(label: Text('درآمد')),
                DataColumn(label: Text('میانگین قیمت')),
                DataColumn(label: Text('هزینه مستقیم')),
                DataColumn(label: Text('سود')),
                DataColumn(label: Text('حاشیه سود')),
                DataColumn(label: Text('پرسنل')),
              ],
              rows: [for (final item in services) DataRow(cells: [
                DataCell(Text(item.name)),
                DataCell(Text(FaNum.ofInt(item.count))),
                DataCell(Text(Fmt.compactMoney(item.revenue))),
                DataCell(Text(Fmt.compactMoney(item.averagePrice))),
                DataCell(Text(item.directCost == null ? 'ثبت نشده' : Fmt.compactMoney(item.directCost!))),
                DataCell(Text(item.profit == null ? '—' : Fmt.compactMoney(item.profit!))),
                DataCell(Text(item.marginPercent == null ? '—' : '${FaNum.convert(item.marginPercent!.toStringAsFixed(1))}٪')),
                DataCell(Text(item.employeeCounts.keys.join('، '), maxLines: 2)),
              ])],
            ),
          ),
        for (final item in services)
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('روند فروش: ${item.name}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            subtitle: Text('${FaNum.ofInt(item.count)} ارائه در بازه', style: TextStyle(fontSize: 9, color: pal.textMuted)),
            children: [
              if (item.trend.isEmpty)
                const EmptyState(title: 'روندی برای این خدمت ثبت نشده است', compact: true)
              else
                SizedBox(height: 130, child: RevenueBarChart(
                  data: [for (final point in item.trend) RevenuePoint(label: point.label, value: point.revenue)],
                  height: 130,
                  onPointTap: (index) => _openDay(context, item.trend[index]),
                )),
            ],
          )),
      ])),
      const SizedBox(height: 12),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'گزارش و رفتار مشتریان', subtitle: 'وفاداری از تعداد مراجعات تکمیل‌شده در کل تاریخچه و غیرفعالی از آخرین مراجعه محاسبه می‌شود.'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _SegmentMetric(label: 'مشتری جدید', value: analytics.newCustomers, color: pal.info),
          _SegmentMetric(label: 'مشتری قدیمی', value: analytics.oldCustomers, color: pal.primaryBright),
          _SegmentMetric(label: 'وفادار (۴ مراجعه+)', value: analytics.loyalCustomers, color: pal.success),
          _SegmentMetric(label: 'غیرفعال (۹۰ روز+)', value: analytics.inactiveCustomers, color: pal.textMuted),
          _SegmentMetric(label: 'در معرض ریزش (۶۰ تا ۸۹ روز)', value: analytics.atRiskCustomers, color: pal.warning),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _SegmentMetric(label: 'نرخ بازگشت در بازه', value: analytics.repeatCustomerRate, percent: true, color: pal.success),
          _SegmentMetric(label: 'میانگین فاصله مراجعات', value: averageGap ?? 0, suffix: 'روز', decimal: true, color: pal.info),
        ]),
        const SizedBox(height: 8),
        if (analytics.newCustomerTrend.isNotEmpty) ...[
          const SectionHeader(title: 'روند جذب مشتری جدید'),
          SizedBox(height: 140, child: RevenueBarChart(
            data: [for (final item in analytics.newCustomerTrend)
              RevenuePoint(label: item.label, value: item.appointments)],
            height: 140,
            onPointTap: (index) => _openDay(context, analytics.newCustomerTrend[index]),
          )),
        ],
        const SizedBox(height: 8),
        _exports(context, 'گزارش-مشتریان', customerHeaders, customerRows),
        if (customers.isEmpty)
          const EmptyState(title: 'مشتری‌ای برای نمایش وجود ندارد', compact: true)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text('مشتری')),
                DataColumn(label: Text('مراجعه بازه')),
                DataColumn(label: Text('کل مراجعات')),
                DataColumn(label: Text('مراجعه مجدد')),
                DataColumn(label: Text('مجموع خرید')),
                DataColumn(label: Text('میانگین مراجعه')),
                DataColumn(label: Text('آخرین مراجعه')),
                DataColumn(label: Text('فاصله میان مراجعات')),
                DataColumn(label: Text('وضعیت')),
              ],
              rows: [for (final item in customers) DataRow(cells: [
                DataCell(Text(item.name)),
                DataCell(Text(FaNum.ofInt(item.visits))),
                DataCell(Text(FaNum.ofInt(item.lifetimeVisits))),
                DataCell(Text(FaNum.ofInt(item.repeatVisits))),
                DataCell(Text(Fmt.compactMoney(item.totalSpent))),
                DataCell(Text(Fmt.compactMoney(item.averageSpend))),
                DataCell(Text(item.lastVisitAt == null ? '—' : JalaliDate.fromDateTime(item.lastVisitAt!).short)),
                DataCell(Text(item.averageGapDays == null ? '—' : '${FaNum.convert(item.averageGapDays!.toStringAsFixed(1))} روز')),
                DataCell(Text(item.isInactive ? 'غیرفعال' : item.isAtRisk ? 'در معرض ریزش' : item.isLoyal ? 'وفادار' : item.isNew ? 'جدید' : 'قدیمی')),
              ])],
            ),
          ),
      ])),
      const SizedBox(height: 12),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'تحلیل نوبت‌ها', subtitle: 'نرخ‌ها از مجموع نوبت‌های منطبق با فیلترها محاسبه می‌شوند.'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _SegmentMetric(label: 'ثبت‌شده', value: total, color: pal.primaryBright),
          _SegmentMetric(label: 'تکمیل‌شده', value: completed, color: pal.success),
          _SegmentMetric(label: 'لغوشده', value: cancelled, color: pal.danger),
          _SegmentMetric(label: 'عدم حضور', value: noShow, color: pal.textMuted),
          _SegmentMetric(label: 'نوبت دوره قبل', value: analytics.previousPeriodAppointments, color: pal.info),
          _SegmentMetric(label: 'ردشده', value: analytics.rejectedAppointments, color: pal.warning),
          _SegmentMetric(label: 'نرخ تکمیل', value: rate(completed), percent: true, color: pal.success),
          _SegmentMetric(label: 'نرخ لغو', value: rate(cancelled), percent: true, color: pal.danger),
          _SegmentMetric(label: 'نرخ عدم مراجعه', value: rate(noShow), percent: true, color: pal.textMuted),
          _SegmentMetric(label: 'میانگین مدت نوبت تکمیل‌شده', value: analytics.averageAppointmentMinutes, suffix: 'دقیقه', decimal: true, color: pal.info),
        ]),
        const SizedBox(height: 6),
        Text('در مدل فعلی نوبت، وضعیت مستقلی برای «ردشده» تعریف نشده است؛ این عدد به‌صورت ساختگی از لغوها جدا نشده است.',
          style: TextStyle(fontSize: 10, color: pal.textMuted)),
        const SizedBox(height: 8),
        _exports(context, 'گزارش-نوبت‌ها', appointmentHeaders, appointmentRows),
        if (appointments.isEmpty)
          const EmptyState(title: 'نوبتی مطابق فیلترها وجود ندارد', compact: true)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text('کد')),
                DataColumn(label: Text('مشتری')),
                DataColumn(label: Text('خدمت')),
                DataColumn(label: Text('پرسنل')),
                DataColumn(label: Text('تاریخ')),
                DataColumn(label: Text('ساعت')),
                DataColumn(label: Text('وضعیت')),
                DataColumn(label: Text('مبلغ')),
              ],
              rows: [for (final item in appointments) DataRow(cells: [
                DataCell(Text(item.reference)),
                DataCell(Text(item.customerName)),
                DataCell(Text(item.serviceName)),
                DataCell(Text(item.employeeName)),
                DataCell(Text(item.jalali.short)),
                DataCell(Text('${item.startAt.hour.toString().padLeft(2, '0')}:${item.startAt.minute.toString().padLeft(2, '0')}')),
                DataCell(Text(item.status.label, style: TextStyle(color: item.status.color))),
                DataCell(Text(Fmt.compactMoney(item.price))),
              ])],
            ),
          ),
      ])),
      const SizedBox(height: 12),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'روزها و ساعت‌های پرتردد', subtitle: 'تقاضا از نوبت‌های فعال و تکمیل‌شده و ظرفیت از شیفت‌های ثبت‌شده استخراج می‌شود.'),
        const SizedBox(height: 8),
        if (analytics.capacityMinutes <= 0)
          Text('برای این بازه ظرفیت برنامه‌ریزی‌شده قابل محاسبه نیست؛ بازه‌های حداکثر یک‌ساله یا برنامه کاری ثبت‌شده را انتخاب کنید.',
            style: TextStyle(fontSize: 10, color: pal.textMuted))
        else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _SegmentMetric(label: 'ظرفیت برنامه', value: analytics.capacityMinutes / 60, suffix: 'ساعت', decimal: true, color: pal.info),
            _SegmentMetric(label: 'زمان رزروشده', value: analytics.bookedCapacityMinutes / 60, suffix: 'ساعت', decimal: true, color: pal.primaryBright),
            _SegmentMetric(label: 'ظرفیت خالی', value: analytics.emptyCapacityMinutes / 60, suffix: 'ساعت', decimal: true, color: pal.warning),
            _SegmentMetric(label: 'استفاده از ظرفیت', value: analytics.capacityUtilizationPercent, percent: true, color: pal.success),
          ]),
          const SizedBox(height: 12),
          const SectionHeader(title: 'تقاضا بر اساس روز هفته'),
          for (final item in analytics.weekdayDemand)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              SizedBox(width: 72, child: Text(item.label, style: TextStyle(fontSize: 10, color: pal.textSecondary))),
              Expanded(child: LinearProgressIndicator(
                value: analytics.weekdayDemand.isEmpty ? 0 : item.appointments / analytics.weekdayDemand.first.appointments.clamp(1, 1 << 30),
                minHeight: 7, backgroundColor: pal.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(pal.primaryBright),
              )),
              const SizedBox(width: 8),
              Text(FaNum.ofInt(item.appointments), style: TextStyle(fontSize: 10, color: pal.textPrimary)),
            ])),
        ],
        const SizedBox(height: 12),
        const SectionHeader(title: 'تقاضا بر اساس ساعت'),
        if (analytics.hourlyDemand.isEmpty)
          const EmptyState(title: 'داده ساعتی موجود نیست', compact: true)
        else
          for (final item in analytics.hourlyDemand)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              SizedBox(width: 48, child: Text('${item.hour.toString().padLeft(2, '0')}:00', style: TextStyle(fontSize: 10, color: pal.textSecondary))),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LinearProgressIndicator(
                  value: item.scheduledMinutes <= 0 ? 0 : (item.bookedMinutes / item.scheduledMinutes).clamp(0, 1).toDouble(),
                  minHeight: 7, backgroundColor: pal.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(item.appointments == 0 ? pal.warning : pal.success),
                ),
                Text(item.appointments == 0 ? 'ساعت کم‌تقاضا / بدون نوبت' : '${FaNum.ofInt(item.appointments)} نوبت • ${FaNum.ofInt(item.bookedMinutes)} دقیقه رزرو از ${FaNum.ofInt(item.scheduledMinutes)} دقیقه برنامه',
                  style: TextStyle(fontSize: 9, color: pal.textMuted)),
              ])),
            ])),
      ])),
    ]);
  }
}

class _SegmentMetric extends StatelessWidget {
  const _SegmentMetric({
    required this.label, required this.value, required this.color,
    this.percent = false, this.suffix = '', this.decimal = false,
  });
  final String label, suffix;
  final num value;
  final Color color;
  final bool percent, decimal;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 125, maxWidth: 210),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(percent ? '${FaNum.convert(value.toStringAsFixed(1))}٪' : decimal ? '${FaNum.convert(value.toStringAsFixed(1))} $suffix' : '${FaNum.ofInt(value.round())} $suffix',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: TextStyle(fontSize: 9.5, color: context.pal.textMuted)),
    ]),
  );
}
