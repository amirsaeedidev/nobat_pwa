import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/jalali_picker.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/enums.dart';
import '../providers/reports_provider.dart';
import '../../utils/report_phase_five.dart';
import '../../utils/report_table_export.dart';
import '../../utils/report_executive_pdf_export.dart';
import '../../utils/saved_report_store.dart';

class ReportsPhaseFivePanel extends StatefulWidget {
  const ReportsPhaseFivePanel({super.key, required this.database, required this.provider});
  final AppDatabase database;
  final ReportsProvider provider;

  @override
  State<ReportsPhaseFivePanel> createState() => _ReportsPhaseFivePanelState();
}

class _ReportsPhaseFivePanelState extends State<ReportsPhaseFivePanel> {
  final _store = SavedReportStore();
  static const _allColumns = ['درآمد', 'هزینه', 'سود خالص', 'نوبت', 'تکمیل‌شده', 'مشتری یکتا', 'نرخ بازگشت'];
  final Set<String> _columns = {..._allColumns};
  List<SavedReportView> _saved = [];
  List<ReportHistorySnapshot> _history = [];
  bool _loadingStore = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    try {
      final saved = await _store.loadViews();
      final db = widget.database;
      final allSalary = db.hasPermission('finance.salary.view');
      final allCommission = db.hasPermission('finance.commission.view');
      final history = await _store.loadHistory(
        accountId: db.currentAccessAccount.id,
        canViewSalary: allSalary,
        canViewCommission: allCommission,
      );
      if (!mounted) return;
      setState(() { _saved = saved; _history = history; _loadingStore = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loadingStore = false; });
    }
  }

  Future<void> _saveCurrentView() async {
    final controller = TextEditingController(text: 'گزارش ' + widget.provider.range.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ذخیره گزارش دلخواه'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'نام گزارش')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('ذخیره')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final p = widget.provider;
    final f = p.filter;
    await _store.saveView(SavedReportView(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name, start: p.range.start.toIso8601String(),
      endExclusive: p.range.endExclusive.toIso8601String(),
      columns: _columns.toList(), createdAt: DateTime.now(),
      serviceId: f.serviceId, employeeId: f.employeeId, customerId: f.customerId,
      statusName: f.status?.name,
    ));
    await _loadStore();
    if (mounted) AppToast.show(context, 'گزارش ذخیره شد.');
  }

  Future<void> _applyView(SavedReportView view) async {
    final p = widget.provider;
    final from = JalaliDate.fromDateTime(DateTime.parse(view.start));
    final to = JalaliDate.fromDateTime(DateTime.parse(view.endExclusive).subtract(const Duration(microseconds: 1)));
    await p.setCustomRange(from, to);
    final matches = AppointmentStatus.values.where((item) => item.name == view.statusName).toList();
    await p.setFilters(
      serviceId: view.serviceId, employeeId: view.employeeId, customerId: view.customerId,
      status: matches.isEmpty ? null : matches.first,
      clearService: view.serviceId == null, clearEmployee: view.employeeId == null,
      clearCustomer: view.customerId == null, clearStatus: matches.isEmpty,
    );
    if (!mounted) return;
    setState(() { _columns..clear()..addAll(view.columns); });
  }

  Future<void> _chooseComparisonRange() async {
    final current = widget.provider.comparisonRange;
    final from = await showJalaliDatePicker(context, initial: current.jalaliStart, title: 'شروع بازه مقایسه');
    if (from == null || !mounted) return;
    final to = await showJalaliDatePicker(context, initial: current.jalaliEnd, minDate: from, title: 'پایان بازه مقایسه');
    if (to != null && mounted) await widget.provider.setComparisonRange(from, to);
  }

  Future<void> _saveHistory() async {
    final a = widget.provider.analytics;
    await _store.addHistory(ReportHistorySnapshot(
      id: DateTime.now().microsecondsSinceEpoch.toString(), title: 'گزارش مدیریتی',
      range: a.range.label, createdAt: DateTime.now(), revenue: a.revenue,
      cost: a.cost, appointments: a.totalAppointments,
      accountId: widget.database.currentAccessAccount.id,
      includesSalary: widget.database.hasPermission('finance.salary.view'),
      includesCommission: widget.database.hasPermission('finance.commission.view'),
      profitComplete: a.profitIsComplete,
    ));
    await _loadStore();
    if (mounted) AppToast.show(context, 'نسخه گزارش در تاریخچه ثبت شد.');
  }

  Future<void> _export(String type) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      widget.database.requirePermission('finance.income.view');
      final a = widget.provider.analytics;
      final comparison = widget.provider.comparisonAnalytics ?? a;
      final columns = _allColumns.where(_columns.contains).toList();
      final all = <String, Object?>{
        'درآمد': a.revenue.round(), 'هزینه': a.cost.round(),
        'سود خالص': a.profitIsComplete ? a.netProfit.round() : 'نامشخص', 'نوبت': a.totalAppointments,
        'تکمیل‌شده': a.completedAppointments, 'مشتری یکتا': a.uniqueCustomers,
        'نرخ بازگشت': a.repeatCustomerRate.toStringAsFixed(1) + '٪',
      };
      final generatedAt = JalaliDate.fromDateTime(DateTime.now()).long;
      final headers = ['گزارش', 'بازه', 'تاریخ تولید', 'بخش', 'عنوان', ...columns];
      final rows = <List<Object?>>[
        ['گزارش مدیریتی DateTime', a.range.label, generatedAt, 'شاخص', 'خلاصه',
          for (final key in columns) all[key] ?? ''],
      ];
      for (final item in a.services) {
        rows.add([
          'گزارش مدیریتی DateTime', a.range.label, generatedAt, 'خدمت', item.name,
          for (final key in columns)
            switch (key) {
              'درآمد' => item.revenue.round(),
              'هزینه' => item.directCost?.round() ?? 'ثبت نشده',
              'سود خالص' => item.profit?.round() ?? 'نامشخص',
              'نوبت' || 'تکمیل‌شده' => item.count,
              _ => '—',
            },
        ]);
      }
      for (final item in a.employees) {
        final appointments = a.operationalAppointments.where((entry) =>
          entry.employeeId == item.employeeId && entry.status == AppointmentStatus.completed).toList();
        rows.add([
          'گزارش مدیریتی DateTime', a.range.label, generatedAt, 'پرسنل', item.name,
          for (final key in columns)
            switch (key) {
              'درآمد' => item.revenue.round(),
              'هزینه' => item.commission.round(),
              'سود خالص' => (item.revenue - item.commission).round(),
              'نوبت' || 'تکمیل‌شده' => appointments.length,
              'مشتری یکتا' => appointments.map((entry) => entry.customerId).toSet().length,
              _ => '—',
            },
        ]);
      }
      for (final item in a.customerMetrics) {
        rows.add([
          'گزارش مدیریتی DateTime', a.range.label, generatedAt, 'مشتری', item.name,
          for (final key in columns)
            switch (key) {
              'درآمد' => item.totalSpent.round(),
              'نوبت' => item.lifetimeVisits,
              'تکمیل‌شده' => item.visits,
              'مشتری یکتا' => 1,
              'نرخ بازگشت' => item.repeatVisits,
              _ => '—',
            },
        ]);
      }
      if (type == 'pdf') {
        await ReportExecutivePdfExport.save(
          analytics: a, comparison: comparison, title: 'گزارش مدیریتی DateTime', columns: columns,
        );
      } else if (type == 'excel') {
        await ReportTableExport.saveExcel(name: 'گزارش-مدیریتی', headers: headers, rows: rows);
      } else {
        await ReportTableExport.saveCsv(name: 'گزارش-مدیریتی', headers: headers, rows: rows);
      }
      if (mounted) AppToast.show(context, 'فایل گزارش آماده شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, 'خروجی گزارش ناموفق بود: ' + error.toString(), success: false);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final a = p.analytics;
    final previous = p.comparisonAnalytics;
    final pal = context.pal;
    final alerts = previous == null ? const <ReportInsight>[] :
      ReportInsightEngine.build(current: a, previous: previous, services: widget.database.services);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('خلاصه مدیریتی و مقایسه هوشمند', style: TextStyle(fontWeight: FontWeight.w800))),
          TextButton(onPressed: _saveHistory, child: const Text('ثبت در تاریخچه')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _DeltaCard(label: 'درآمد', value: a.revenue, previous: previous?.revenue, money: true, color: pal.success),
          _DeltaCard(label: 'هزینه', value: a.cost, previous: previous?.cost, money: true, inverse: true, color: pal.warning),
          _DeltaCard(label: 'سود خالص', value: a.profitIsComplete ? a.netProfit : null, previous: previous?.profitIsComplete == true ? previous!.netProfit : null, money: true, color: a.profitIsComplete ? (a.netProfit >= 0 ? pal.success : pal.danger) : pal.textMuted),
          _DeltaCard(label: 'تعداد نوبت', value: a.totalAppointments, previous: previous?.totalAppointments, color: pal.primaryBright),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final comparisonLabel = (p.hasCustomComparison ? 'مقایسه با: ' : 'مقایسه خودکار با دوره قبل: ') + p.comparisonRange.label;
          final actions = Wrap(spacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton(onPressed: _chooseComparisonRange, child: const Text('انتخاب بازه مقایسه')),
            if (p.hasCustomComparison)
              IconButton(tooltip: 'بازگشت به مقایسه خودکار', onPressed: p.clearComparisonRange,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, size: 17)),
          ]);
          if (constraints.maxWidth < 370) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(comparisonLabel, style: TextStyle(fontSize: 10, color: pal.textMuted)),
              actions,
            ]);
          }
          return Row(children: [
            Expanded(child: Text(comparisonLabel, style: TextStyle(fontSize: 10, color: pal.textMuted))),
            actions,
          ]);
        }),
        const Divider(height: 18),
        const Text('عملکرد برتر', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 8, children: [
          _TopSummary(label: 'خدمات پرفروش', value: a.services.isEmpty ? 'داده کافی نیست' : a.services.take(3).map((e) => e.name).join('، ')),
          _TopSummary(label: 'پرسنل برتر', value: a.employees.isEmpty ? 'داده کافی نیست' : a.employees.take(3).map((e) => e.name).join('، ')),
          _TopSummary(label: 'مشتریان برتر', value: a.customerMetrics.isEmpty ? 'داده کافی نیست' : a.customerMetrics.take(3).map((e) => e.name).join('، ')),
        ]),
      ])),
      const SizedBox(height: 10),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('هشدارها و فرصت‌های قابل بررسی', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (previous == null || a.totalAppointments < 5)
          const Text('برای تحلیل مطمئن، داده کافی در این بازه یا بازه مقایسه وجود ندارد.', style: TextStyle(fontSize: 11))
        else if (alerts.isEmpty)
          const Text('با قواعد فعلی هشدار معناداری شناسایی نشد.', style: TextStyle(fontSize: 11))
        else
          for (final alert in alerts)
            Container(
              width: double.infinity, margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _alertColor(alert.level, pal).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _alertColor(alert.level, pal).withValues(alpha: .22)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(alert.title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _alertColor(alert.level, pal))),
                const SizedBox(height: 3),
                Text(alert.reason, style: TextStyle(fontSize: 10, color: pal.textPrimary)),
                const SizedBox(height: 3),
                Text(alert.evidence, style: TextStyle(fontSize: 9, color: pal.textMuted)),
              ]),
            ),
      ])),
      const SizedBox(height: 10),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('گزارش سفارشی و خروجی حرفه‌ای', style: TextStyle(fontWeight: FontWeight.w800))),
          TextButton(onPressed: _saveCurrentView, child: const Text('ذخیره فیلترها')),
        ]),
        Text('ستون‌های موردنیاز برای خلاصه خروجی را انتخاب کنید.', style: TextStyle(fontSize: 10, color: pal.textMuted)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final column in _allColumns)
            FilterChip(
              label: Text(column), selected: _columns.contains(column),
              onSelected: (selected) => setState(() {
                if (selected) { _columns.add(column); } else if (_columns.length > 1) { _columns.remove(column); }
              }),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _exporting ? null : () => _export('pdf'), child: const Text('خروجی PDF')),
          OutlinedButton(onPressed: _exporting ? null : () => _export('excel'), child: const Text('خروجی Excel')),
          OutlinedButton(onPressed: _exporting ? null : () => _export('csv'), child: const Text('خروجی CSV')),
          if (_exporting) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ])),
      const SizedBox(height: 10),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('گزارش‌های ذخیره‌شده', style: TextStyle(fontWeight: FontWeight.w800)),
        if (_loadingStore)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else if (_saved.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('هنوز گزارشی ذخیره نشده است.', style: TextStyle(fontSize: 10)))
        else
          for (final view in _saved)
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text(view.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              subtitle: Text(JalaliDate.fromDateTime(DateTime.parse(view.start)).short + ' تا ' +
                JalaliDate.fromDateTime(DateTime.parse(view.endExclusive).subtract(const Duration(days: 1))).short,
                style: TextStyle(fontSize: 9, color: pal.textMuted)),
              trailing: Wrap(children: [
                IconButton(tooltip: 'اجرای گزارش', onPressed: () => _applyView(view),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, size: 17)),
                IconButton(tooltip: 'حذف گزارش', onPressed: () async {
                  await _store.deleteView(view.id); await _loadStore();
                }, icon: const HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, size: 17)),
              ]),
            ),
      ])),
      const SizedBox(height: 10),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('تاریخچه گزارش‌های تولیدشده', style: TextStyle(fontWeight: FontWeight.w800)),
        if (_history.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('با «ثبت در تاریخچه» یک نسخه از شاخص‌های فعلی ذخیره کنید.', style: TextStyle(fontSize: 10)))
        else
          for (final item in _history.take(5))
            ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(item.title),
                  content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('بازه: ' + item.range),
                    Text('تاریخ ثبت: ' + JalaliDate.fromDateTime(item.createdAt).long),
                    Text('درآمد: ' + Fmt.compactMoney(item.revenue)),
                    Text('هزینه: ' + Fmt.compactMoney(item.cost)),
                    Text('سود خالص: ' + (item.verifiedProfit == null ? 'نامشخص' : Fmt.compactMoney(item.verifiedProfit!))),
                    Text('تعداد نوبت: ' + FaNum.ofInt(item.appointments)),
                  ]),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
                ),
              ),
              title: Text(item.title, style: const TextStyle(fontSize: 11)),
              subtitle: Text(item.range + ' · ' + JalaliDate.fromDateTime(item.createdAt).short,
                style: TextStyle(fontSize: 9, color: pal.textMuted)),
              trailing: Text(item.verifiedProfit == null ? 'نامشخص' : Fmt.compactMoney(item.verifiedProfit!), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: item.verifiedProfit == null ? pal.textMuted : (item.verifiedProfit! >= 0 ? pal.success : pal.danger))),
            ),
      ])),
    ]);
  }

  Color _alertColor(ReportAlertLevel level, AppPalette palette) => switch (level) {
    ReportAlertLevel.info => palette.info,
    ReportAlertLevel.warning => palette.warning,
    ReportAlertLevel.critical => palette.danger,
  };
}

class _DeltaCard extends StatelessWidget {
  const _DeltaCard({required this.label, required this.value, required this.previous, required this.color, this.money = false, this.inverse = false});
  final String label;
  final num? value;
  final num? previous;
  final Color color;
  final bool money;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final currentValue = value;
    final previousValue = previous;
    final delta = currentValue == null || previousValue == null
      ? null : ReportInsightEngine.compare(currentValue, previousValue);
    final change = delta?.percent;
    return Container(
      constraints: const BoxConstraints(minWidth: 130, maxWidth: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: context.pal.textMuted)),
        const SizedBox(height: 4),
        if (value != null)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value!.toDouble()),
            duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic,
            builder: (context, animated, _) => Text(
              money ? Fmt.compactMoney(animated) : FaNum.ofInt(animated.round()),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
            ),
          )
        else
          Text('نامشخص', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        if (change != null)
          Text((delta!.increased ? '▲ ' : delta.decreased ? '▼ ' : '• ') +
            change.abs().toStringAsFixed(1) + '٪ نسبت به قبل',
            style: TextStyle(fontSize: 9, color: (inverse ? delta.increased : delta.decreased) ? context.pal.danger : context.pal.success)),
      ]),
    );
  }
}

class _TopSummary extends StatelessWidget {
  const _TopSummary({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 9, color: context.pal.textMuted)),
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.pal.textPrimary)),
    ]),
  );
}
