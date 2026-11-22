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
import '../../../../data/models/appointment.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../providers/reports_provider.dart';
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
              rows: [for (final item in services) DataRow(
                onSelectChanged: (_) => showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
                  title: Text(item.name),
                  content: Text('تعداد ارائه: ${item.count}\nدرآمد: ${Fmt.compactMoney(item.revenue)}\nمیانگین قیمت: ${Fmt.compactMoney(item.averagePrice)}\nهزینه مستقیم: ${item.directCost == null ? 'ثبت نشده' : Fmt.compactMoney(item.directCost!)}\nسود: ${item.profit == null ? 'نامشخص' : Fmt.compactMoney(item.profit!)}'),
                  actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
                )),
                cells: [
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
              rows: [for (final item in customers) DataRow(
                onSelectChanged: (_) => showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
                  title: Text(item.name),
                  content: Text('مراجعات این بازه: ${item.visits}\nکل مراجعات: ${item.lifetimeVisits}\nمراجعه مجدد: ${item.repeatVisits}\nمجموع خرید: ${Fmt.compactMoney(item.totalSpent)}\nاولین مراجعه: ${item.firstVisitAt == null ? '—' : JalaliDate.fromDateTime(item.firstVisitAt!).long}\nآخرین مراجعه: ${item.lastVisitAt == null ? '—' : JalaliDate.fromDateTime(item.lastVisitAt!).long}'),
                  actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
                )),
                cells: [
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
        
        if (appointments.isEmpty)
          const EmptyState(title: 'نوبتی مطابق فیلترها وجود ندارد', compact: true)
        else
          _AppointmentReportTable(items: appointments),
      ])),
      const SizedBox(height: 12),

    ]);
  }
}

class _AppointmentReportTable extends StatefulWidget {
  const _AppointmentReportTable({required this.items});
  final List<Appointment> items;

  @override
  State<_AppointmentReportTable> createState() => _AppointmentReportTableState();
}

class _AppointmentReportTableState extends State<_AppointmentReportTable> {
  int _page = 0;
  int _pageSize = 10;
  int _sortColumn = 4;
  bool _ascending = false;

  void _sort(int column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _ascending = ascending;
      _page = 0;
    });
  }

  List<Appointment> get _sorted {
    final result = [...widget.items];
    int compare(Appointment a, Appointment b) => switch (_sortColumn) {
      0 => a.reference.compareTo(b.reference),
      1 => a.customerName.compareTo(b.customerName),
      2 => a.serviceName.compareTo(b.serviceName),
      3 => a.employeeName.compareTo(b.employeeName),
      4 || 5 => a.startAt.compareTo(b.startAt),
      6 => a.status.index.compareTo(b.status.index),
      _ => a.price.compareTo(b.price),
    };
    result.sort((a, b) => _ascending ? compare(a, b) : compare(b, a));
    return result;
  }

  void _showDetails(Appointment item) {
    showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('جزئیات نوبت ${item.reference}'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('مشتری: ${item.customerName}'),
          Text('خدمت: ${item.serviceName}'),
          Text('پرسنل: ${item.employeeName}'),
          Text('تاریخ: ${item.jalali.long}'),
          Text('ساعت: ${item.startAt.hour.toString().padLeft(2, '0')}:${item.startAt.minute.toString().padLeft(2, '0')}'),
          Text('مدت: ${item.durationMinutes} دقیقه'),
          Text('وضعیت: ${item.status.label}'),
          Text('مبلغ: ${Fmt.compactMoney(item.price)}'),
          if (item.cancelReason != null && item.cancelReason!.isNotEmpty) Text('علت لغو: ${item.cancelReason}'),
        ],
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    final pageCount = (rows.length / _pageSize).ceil().clamp(1, 1 << 20).toInt();
    if (_page >= pageCount) _page = pageCount - 1;
    final start = _page * _pageSize;
    final visible = rows.skip(start).take(_pageSize);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _sortColumn,
          sortAscending: _ascending,
          columnSpacing: 18,
          columns: [
            for (final entry in ['کد', 'مشتری', 'خدمت', 'پرسنل', 'تاریخ', 'ساعت', 'وضعیت', 'مبلغ'].asMap().entries)
              DataColumn(label: Text(entry.value), onSort: (_, ascending) => _sort(entry.key, ascending)),
          ],
          rows: [for (final item in visible) DataRow(
            onSelectChanged: (_) => _showDetails(item),
            cells: [
              DataCell(Text(item.reference)),
              DataCell(Text(item.customerName)),
              DataCell(Text(item.serviceName)),
              DataCell(Text(item.employeeName)),
              DataCell(Text(item.jalali.short)),
              DataCell(Text('${item.startAt.hour.toString().padLeft(2, '0')}:${item.startAt.minute.toString().padLeft(2, '0')}')),
              DataCell(Text(item.status.label, style: TextStyle(color: item.status.color))),
              DataCell(Text(Fmt.compactMoney(item.price))),
            ],
          )],
        ),
      ),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text('صفحه ${_page + 1} از $pageCount · ${rows.length} ردیف', style: TextStyle(fontSize: 10, color: context.pal.textMuted)),
          DropdownButton<int>(
            value: _pageSize,
            items: const [5, 10, 20, 50].map((value) => DropdownMenuItem(value: value, child: Text('$value ردیف'))).toList(),
            onChanged: (value) => setState(() { _pageSize = value ?? 10; _page = 0; }),
          ),
          TextButton(onPressed: _page > 0 ? () => setState(() => _page--) : null, child: const Text('قبلی')),
          TextButton(onPressed: _page + 1 < pageCount ? () => setState(() => _page++) : null, child: const Text('بعدی')),
        ],
      ),
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
