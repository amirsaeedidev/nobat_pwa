import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/report_export.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee_analytics.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/enums.dart';

enum _RangePreset { today, yesterday, week, month, lastMonth, custom }

class EmployeeAnalyticsPage extends StatefulWidget {
  const EmployeeAnalyticsPage({super.key, this.employeeId});
  final String? employeeId;

  @override
  State<EmployeeAnalyticsPage> createState() => _EmployeeAnalyticsPageState();
}

class _EmployeeAnalyticsPageState extends State<EmployeeAnalyticsPage> {
  late DateTime _from;
  late DateTime _to;
  _RangePreset _preset = _RangePreset.month;
  String? _employeeId;
  String? _serviceId;
  AppointmentStatus? _status;
  final Set<String> _comparisonIds = {};

  @override
  void initState() {
    super.initState();
    _employeeId = widget.employeeId;
    _applyPreset(_RangePreset.month, notify: false);
  }

  void _applyPreset(_RangePreset preset, {bool notify = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final jalali = JalaliDate.fromDateTime(today);
    switch (preset) {
      case _RangePreset.today:
        _from = today; _to = today.add(const Duration(days: 1)); break;
      case _RangePreset.yesterday:
        _from = today.subtract(const Duration(days: 1)); _to = today; break;
      case _RangePreset.week:
        final start = jalali.addDays(-jalali.weekday).toDateTime();
        _from = start; _to = start.add(const Duration(days: 7)); break;
      case _RangePreset.month:
        _from = JalaliDate(jalali.year, jalali.month, 1).toDateTime();
        _to = JalaliDate(jalali.year, jalali.month, 1).addMonths(1).toDateTime(); break;
      case _RangePreset.lastMonth:
        final start = JalaliDate(jalali.year, jalali.month, 1).addMonths(-1);
        _from = start.toDateTime(); _to = start.addMonths(1).toDateTime(); break;
      case _RangePreset.custom:
        break;
    }
    _preset = preset;
    if (notify && mounted) setState(() {});
  }

  Future<void> _chooseCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to.subtract(const Duration(days: 1))),
      helpText: 'انتخاب بازه گزارش',
      saveText: 'اعمال بازه',
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = DateTime(range.start.year, range.start.month, range.start.day);
      _to = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1));
      _preset = _RangePreset.custom;
    });
  }

  String _money(num value) => '${Fmt.compactMoney(value)} تومان';
  String _periodLabel() => '${JalaliDate.fromDateTime(_from).numeric} تا ${JalaliDate.fromDateTime(_to.subtract(const Duration(days: 1))).numeric}';

  Future<void> _exportCsv(Employee employee, EmployeeAnalytics report) async {
    final rows = <List<String>>[
      ['شاخص', 'مقدار', 'واحد'],
      ['پرسنل', employee.fullName, ''],
      ['بازه', _periodLabel(), ''],
      ['کل نوبت‌ها', report.totalAppointments.toString(), 'عدد'],
      ['تکمیل‌شده', report.completed.toString(), 'عدد'],
      ['لغوشده', report.cancelled.toString(), 'عدد'],
      ['عدم حضور', report.noShow.toString(), 'عدد'],
      ['درآمد ناخالص', report.grossRevenue.toString(), 'تومان'],
      ['درآمد پس از تخفیف', report.netRevenue.toString(), 'تومان'],
      ['پورسانت', report.commission.toString(), 'تومان'],
      ['سهم مجموعه', report.companyShare.toString(), 'تومان'],
      ['میانگین هر نوبت', report.averageTicket.toString(), 'تومان'],
      ['مشتریان یکتا', report.uniqueCustomers.toString(), 'نفر'],
      ['استفاده از ساعات کاری', report.utilizationRate.toStringAsFixed(1), 'درصد'],
      ...report.services.map((s) => ['خدمت: ${s.name}', s.revenue.toString(), 'تومان']),
    ];
    final csv = '\uFEFF' + rows.map((row) => row.map((cell) => '"${cell.replaceAll('"', '""')}"').join(',')).join('\r\n');
    final exported = await downloadCsv('employee-analytics-${employee.id}.csv', csv);
    if (!exported && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خروجی فایل در نسخه وب فعال است.')));
    }
  }

  String _escapeHtml(String value) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  Future<void> _exportPdf(Employee employee, EmployeeAnalytics report) async {
    final rows = <List<String>>[
      ['شاخص', 'مقدار'],
      ['کل نوبت‌ها', FaNum.ofInt(report.totalAppointments)],
      ['تکمیل‌شده', FaNum.ofInt(report.completed)],
      ['لغوشده', FaNum.ofInt(report.cancelled)],
      ['عدم حضور', FaNum.ofInt(report.noShow)],
      ['درآمد ناخالص', _money(report.grossRevenue)],
      ['درآمد پس از تخفیف', _money(report.netRevenue)],
      ['پورسانت', _money(report.commission)],
      ['سهم مجموعه', _money(report.companyShare)],
      ['میانگین مبلغ هر نوبت', _money(report.averageTicket)],
      ['مشتریان یکتا', FaNum.ofInt(report.uniqueCustomers)],
      ['استفاده از ساعات کاری', '${FaNum.convert(report.utilizationRate.toStringAsFixed(1))}٪'],
      ...report.services.map((s) => ['خدمت: ${s.name}', _money(s.revenue)]),
    ];
    final table = rows.map((row) => '<tr><td>${_escapeHtml(row[0])}</td><td>${_escapeHtml(row[1])}</td></tr>').join();
    final html = '''
<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>گزارش عملکرد ${_escapeHtml(employee.fullName)}</title>
<style>
@page{size:A4;margin:18mm}*{box-sizing:border-box}body{font-family:Tahoma,Arial,sans-serif;color:#222;direction:rtl}
h1{font-size:22px;margin:0 0 8px}p{color:#666;font-size:12px;margin:0 0 20px}
table{width:100%;border-collapse:collapse;font-size:12px}th,td{padding:10px;border:1px solid #ddd;text-align:right}
th{background:#f2f3f5}tr:nth-child(even){background:#fafafa}.footer{margin-top:18px;font-size:10px;color:#777}
</style></head><body><h1>گزارش عملکرد پرسنل</h1>
<p>${_escapeHtml(employee.fullName)} — ${_escapeHtml(_periodLabel())} — سامانه DateTime</p>
<table><thead><tr><th>شاخص</th><th>مقدار</th></tr></thead><tbody>$table</tbody></table>
<div class="footer">این گزارش به‌صورت آفلاین از داده‌های محلی Datamonck تهیه شده است.</div>
<script>window.onload=function(){window.print();};</script></body></html>''';
    final exported = await printReport(html);
    if (!exported && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ذخیره PDF از طریق نسخه وب و پنجره چاپ انجام می‌شود.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final employees = db.employees.where((employee) => db.canViewEmployee(employee.id) && db.canViewEmployeeIncome(employee.id)).toList();
    final selected = employees.where((e) => e.id == (_employeeId ?? widget.employeeId)).firstOrNull ??
        (employees.isEmpty ? null : employees.first);
    final pal = context.pal;
    if (selected == null) {
      return const PageScaffold(title: 'تحلیل عملکرد پرسنل', child: EmptyState(title: 'پرسنلی برای گزارش وجود ندارد'));
    }
    final filter = EmployeeAnalyticsFilter(from: _from, to: _to, employeeId: selected.id, serviceId: _serviceId, status: _status);
    final report = EmployeeAnalyticsCalculator.calculate(db: db, employee: selected, filter: filter);
    final comparison = employees.where((e) => _comparisonIds.contains(e.id)).toList();
    final comparisonReports = comparison.map((e) => (employee: e, report: EmployeeAnalyticsCalculator.calculate(
      db: db, employee: e, filter: EmployeeAnalyticsFilter(from: _from, to: _to, serviceId: _serviceId, status: _status),
    ))).toList()..sort((a, b) => b.report.netRevenue.compareTo(a.report.netRevenue));

    return PageScaffold(
      title: 'تحلیل عملکرد پرسنل',
      subtitle: selected.fullName,
      icon: Icons.query_stats_rounded,
      showBackButton: true,
      actions: [
        OutlinedButton.icon(onPressed: () => _exportCsv(selected, report), icon: const Icon(Icons.download_rounded, size: 16), label: const Text('خروجی CSV')),
        OutlinedButton.icon(onPressed: () => _exportPdf(selected, report), icon: const Icon(Icons.picture_as_pdf_outlined, size: 16), label: const Text('ذخیره PDF')),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'فیلتر گزارش'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: selected.id,
            decoration: const InputDecoration(labelText: 'پرسنل'),
            items: [for (final e in employees) DropdownMenuItem(value: e.id, child: Text(e.fullName))],
            onChanged: (value) => setState(() => _employeeId = value),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final item in _RangePreset.values)
              ChoiceChip(
                label: Text(switch (item) {
                  _RangePreset.today => 'امروز', _RangePreset.yesterday => 'دیروز',
                  _RangePreset.week => 'هفته جاری', _RangePreset.month => 'ماه جاری',
                  _RangePreset.lastMonth => 'ماه گذشته', _RangePreset.custom => 'بازه دلخواه',
                }),
                selected: _preset == item,
                onSelected: (_) => item == _RangePreset.custom ? _chooseCustomRange() : _applyPreset(item),
              ),
          ]),
          const SizedBox(height: 8),
          Text(_periodLabel(), style: TextStyle(fontSize: 11, color: pal.textMuted)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            value: _serviceId,
            decoration: const InputDecoration(labelText: 'خدمت'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('همه خدمات')), for (final s in db.services) DropdownMenuItem(value: s.id, child: Text(s.title))],
            onChanged: (value) => setState(() => _serviceId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<AppointmentStatus?>(
            value: _status,
            decoration: const InputDecoration(labelText: 'وضعیت نوبت'),
            items: [const DropdownMenuItem<AppointmentStatus?>(value: null, child: Text('همه وضعیت‌ها')), for (final s in AppointmentStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (value) => setState(() => _status = value),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.info_outline, size: 15, color: pal.textMuted),
            const SizedBox(width: 6),
            Expanded(child: Text('فیلتر نوع پرداخت در داده‌های فعلی ثبت نشده است.', style: TextStyle(fontSize: 10, color: pal.textMuted))),
          ]),
        ])),
        const SizedBox(height: 12),
        if (report.totalAppointments == 0)
          const EmptyState(title: 'در این بازه نوبتی ثبت نشده است', description: 'فیلترها یا بازه زمانی را تغییر دهید.')
        else ...[
          LayoutBuilder(builder: (context, constraints) {
            final count = constraints.maxWidth > 850 ? 4 : constraints.maxWidth > 520 ? 3 : 2;
            final width = (constraints.maxWidth - (count - 1) * 9) / count;
            final cards = [
              _Metric('کل نوبت‌ها', FaNum.ofInt(report.totalAppointments), Icons.event_note, pal.primaryBright),
              _Metric('تکمیل‌شده', FaNum.ofInt(report.completed), Icons.check_circle_outline, pal.success),
              _Metric('لغوشده', FaNum.ofInt(report.cancelled), Icons.event_busy, pal.danger),
              _Metric('عدم حضور', FaNum.ofInt(report.noShow), Icons.person_off, pal.warning),
              _Metric('درآمد ناخالص', _money(report.grossRevenue), Icons.payments, pal.info),
              _Metric('پس از تخفیف', _money(report.netRevenue), Icons.account_balance_wallet, pal.success),
              _Metric('پورسانت', _money(report.commission), Icons.percent, pal.purple),
              _Metric('سهم مجموعه', _money(report.companyShare), Icons.business, pal.primary),
              _Metric('میانگین نوبت', _money(report.averageTicket), Icons.receipt_long, pal.primaryBright),
              _Metric('مشتری یکتا', FaNum.ofInt(report.uniqueCustomers), Icons.groups, pal.info),
              _Metric('استفاده از ساعات', '${FaNum.convert(report.utilizationRate.toStringAsFixed(1))}٪', Icons.schedule, pal.warning),
              _Metric('تغییر درآمد', '${report.revenueChange >= 0 ? '+' : ''}${FaNum.convert(report.revenueChange.toStringAsFixed(1))}٪', Icons.trending_up, report.revenueChange >= 0 ? pal.success : pal.danger),
            ];
            return Wrap(spacing: 9, runSpacing: 9, children: [for (final metric in cards) SizedBox(width: width, child: _MetricCard(metric: metric))]);
          }),
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'شاخص‌های تحلیلی'),
            const SizedBox(height: 12),
            _ProgressMetric(label: 'نرخ تکمیل نوبت', value: report.completionRate, color: pal.success),
            _ProgressMetric(label: 'نرخ لغو', value: report.cancellationRate, color: pal.danger),
            _ProgressMetric(label: 'بهره‌وری ساعات کاری', value: report.utilizationRate, color: pal.primaryBright),
            Text('میانگین درآمد روزانه: ${_money(report.dailyRevenue.isEmpty ? 0 : report.netRevenue / report.dailyRevenue.length)}', style: TextStyle(fontSize: 11, color: pal.textSecondary)),
            Text('میانگین درآمد هر مشتری: ${_money(report.revenuePerCustomer)}', style: TextStyle(fontSize: 11, color: pal.textSecondary)),
            const SizedBox(height: 4),
            Text('هدف فروش برای این پرسنل تعریف نشده است.', style: TextStyle(fontSize: 10, color: pal.textMuted)),
          ])),
          const SizedBox(height: 12),
          _ChartCard(title: 'درآمد روزانه', points: report.dailyRevenue, color: pal.success, money: true),
          const SizedBox(height: 12),
          _ChartCard(title: 'درآمد ماهانه', points: report.monthlyRevenue, color: pal.primaryBright, money: true),
          const SizedBox(height: 12),
          _TrendChartCard(points: report.monthlyRevenue, color: pal.primaryBright),
          const SizedBox(height: 12),
          _ChartCard(title: 'تعداد نوبت‌ها', points: report.dailyAppointments, color: pal.info),
          const SizedBox(height: 12),
          _ChartCard(title: 'پورسانت روزانه', points: report.dailyCommission, color: pal.purple, money: true),
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'خدمات پرفروش'),
            const SizedBox(height: 8),
            if (report.services.isEmpty) const EmptyState(compact: true, title: 'داده‌ای وجود ندارد')
            else ...[
              _ChartCard(title: 'درآمد خدمات', points: [for (final s in report.services.take(6)) AnalyticsPoint(s.name, s.revenue)], color: pal.success, money: true),
              for (final item in report.services.take(6))
              ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(item.name, style: const TextStyle(fontSize: 11)), subtitle: Text('${FaNum.ofInt(item.bookings)} نوبت', style: const TextStyle(fontSize: 9)), trailing: Text(_money(item.revenue), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
            ],
          ])),
        ],
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'مقایسه عملکرد پرسنل', subtitle: 'چند نفر را برای مقایسه در همین بازه انتخاب کنید'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final e in employees)
              FilterChip(label: Text(e.fullName), selected: _comparisonIds.contains(e.id), onSelected: (value) => setState(() { value ? _comparisonIds.add(e.id) : _comparisonIds.remove(e.id); })),
          ]),
          if (comparisonReports.isNotEmpty) ...[
            const Divider(height: 20),
            _ChartCard(title: 'مقایسه درآمد پرسنل', points: [for (final item in comparisonReports) AnalyticsPoint(item.employee.fullName, item.report.netRevenue)], color: pal.primaryBright, money: true),
            const SizedBox(height: 8),
            for (var i = 0; i < comparisonReports.length; i++)
              _CompareRow(rank: i + 1, employee: comparisonReports[i].employee, report: comparisonReports[i].report),
          ] else
            const EmptyState(compact: true, title: 'برای مقایسه، پرسنل را انتخاب کنید'),
        ])),
      ]),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final _Metric metric;
  @override
  Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(metric.icon, size: 18, color: metric.color),
    const SizedBox(height: 8),
    Text(metric.value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.pal.textPrimary)),
    Text(metric.label, style: TextStyle(fontSize: 9, color: context.pal.textMuted)),
  ]));
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 10))), Text('${FaNum.convert(value.toStringAsFixed(1))}٪', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))]),
    const SizedBox(height: 5),
    ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (value / 100).clamp(0, 1).toDouble(), minHeight: 7, color: color, backgroundColor: context.pal.surfaceAlt)),
  ]));
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.points, required this.color, this.money = false});
  final String title;
  final List<AnalyticsPoint> points;
  final Color color;
  final bool money;
  @override
  Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHeader(title: title),
    const SizedBox(height: 12),
    if (points.every((p) => p.value == 0)) const EmptyState(compact: true, title: 'در این بازه داده‌ای ثبت نشده است')
    else SizedBox(height: 190, child: BarChart(BarChartData(
      maxY: (points.map((p) => p.value.toDouble()).reduce((a, b) => a > b ? a : b) * 1.2).clamp(1, double.infinity).toDouble(),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 26, interval: (points.length / 7).ceilToDouble(), getTitlesWidget: (v, meta) {
          final i = v.toInt();
          if (i < 0 || i >= points.length) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 5), child: Text(points[i].label, style: const TextStyle(fontSize: 8)));
        })),
      ),
      barGroups: [for (var i = 0; i < points.length; i++) BarChartGroupData(x: i, barRods: [BarChartRodData(toY: points[i].value.toDouble(), width: points.length > 18 ? 5 : 13, color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))])],
      barTouchData: BarTouchData(enabled: true, touchTooltipData: BarTouchTooltipData(getTooltipItem: (g, gi, rod, ri) => BarTooltipItem('${points[g.x].label}\n${FaNum.ofNum(rod.toY)}${money ? ' تومان' : ''}', const TextStyle(fontSize: 10, color: Colors.white)))),
    ))),
  ]));
}

class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({required this.points, required this.color});
  final List<AnalyticsPoint> points;
  final Color color;
  @override
  Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SectionHeader(title: 'روند رشد درآمد'),
    const SizedBox(height: 10),
    if (points.isEmpty || points.every((p) => p.value == 0))
      const EmptyState(compact: true, title: 'داده‌ای برای نمایش روند وجود ندارد')
    else
      SizedBox(height: 165, child: LineChart(LineChartData(
        minY: 0,
        maxY: (points.map((p) => p.value.toDouble()).fold<double>(0, (a, b) => a > b ? a : b) * 1.2).clamp(1, double.infinity).toDouble(),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, interval: 1, getTitlesWidget: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= points.length) return const SizedBox.shrink();
            return Text(points[i].label, style: const TextStyle(fontSize: 8));
          })),
        ),
        lineBarsData: [LineChartBarData(
          spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value.toDouble())],
          isCurved: true, barWidth: 2.5, color: color,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: color.withValues(alpha: .12)),
        )],
      ))),
  ]));
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.rank, required this.employee, required this.report});
  final int rank;
  final Employee employee;
  final EmployeeAnalytics report;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
    CircleAvatar(radius: 13, child: Text(FaNum.ofInt(rank), style: const TextStyle(fontSize: 10))),
    const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(employee.fullName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      Text('${FaNum.ofInt(report.completed)} تکمیل • میانگین ${Fmt.compactMoney(report.averageTicket)} • ${FaNum.ofInt(report.uniqueCustomers)} مشتری • لغو ${FaNum.convert(report.cancellationRate.toStringAsFixed(0))}٪ • بهره‌وری ${FaNum.convert(report.utilizationRate.toStringAsFixed(0))}٪', style: TextStyle(fontSize: 8.5, color: context.pal.textMuted)),
    ])),
    Text('${Fmt.compactMoney(report.netRevenue)} تومان', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
  ]));
}
