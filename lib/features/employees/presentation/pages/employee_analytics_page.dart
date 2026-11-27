import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/employee_performance_report.dart';
import '../../../../data/repositories/supabase_employee_analytics_repository.dart';
import '../providers/employees_provider.dart';

class EmployeeAnalyticsPage extends StatefulWidget {
  const EmployeeAnalyticsPage({super.key, this.employeeId});
  final String? employeeId;

  @override
  State<EmployeeAnalyticsPage> createState() => _EmployeeAnalyticsPageState();
}

class _EmployeeAnalyticsPageState extends State<EmployeeAnalyticsPage> {
  late DateTime _from;
  late DateTime _to;
  int _reloadKey = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
  }

  String _money(int value) => '${value.toString()} تومان';
  String _periodLabel() => '${_from.year}/${_from.month.toString().padLeft(2, '0')}/${_from.day.toString().padLeft(2, '0')} تا ${_to.year}/${_to.month.toString().padLeft(2, '0')}/${_to.day.toString().padLeft(2, '0')}';

  Future<void> _preset(String preset) async {
    final now = DateTime.now();
    setState(() {
      switch (preset) {
        case 'today':
          _from = DateTime(now.year, now.month, now.day);
          _to = _from;
          break;
        case 'week':
          _from = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
          _to = DateTime(now.year, now.month, now.day);
          break;
        case 'last':
          _from = DateTime(now.year, now.month - 1, 1);
          _to = DateTime(now.year, now.month, 0);
          break;
        default:
          _from = DateTime(now.year, now.month, 1);
          _to = DateTime(now.year, now.month + 1, 0);
      }
      _reloadKey++;
    });
  }

  Future<void> _chooseRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'انتخاب بازه گزارش عملکرد',
      saveText: 'اعمال بازه',
    );
    if (result == null || !mounted) return;
    setState(() {
      _from = DateTime(result.start.year, result.start.month, result.start.day);
      _to = DateTime(result.end.year, result.end.month, result.end.day);
      _reloadKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final employees = context.watch<EmployeesProvider>();
    final auth = context.watch<SupabaseAuthStateNotifier?>();
    final repository = context.read<SupabaseEmployeeAnalyticsRepository>();
    final employee = widget.employeeId == null
        ? (employees.items.isEmpty ? null : employees.items.first)
        : employees.byIdSync(widget.employeeId!);
    final canViewPayroll = auth?.role == 'owner' ||
        auth?.permissions['finance.payroll.view'] == true ||
        auth?.permissions['finance.salary.view'] == true;
    if (employee == null) {
      return PageScaffold(
        title: 'تحلیل عملکرد پرسنل',
        showBackButton: true,
        child: employees.loading
            ? const LoadingState(kind: SkeletonKind.personnel)
            : employees.error != null
                ? ErrorStateView(description: employees.error, onRetry: employees.load)
                : const EmptyState(title: 'پرسنلی برای گزارش وجود ندارد'),
      );
    }

    return PageScaffold(
      title: 'تحلیل عملکرد پرسنل',
      subtitle: employee.fullName,
      icon: Icons.query_stats_rounded,
      showBackButton: true,
      actions: [
        IconButton(
          tooltip: 'بروزرسانی گزارش',
          onPressed: () => setState(() => _reloadKey++),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'بازه گزارش'),
          Text(_periodLabel(), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => _preset('today'), child: const Text('امروز')),
            OutlinedButton(onPressed: () => _preset('week'), child: const Text('این هفته')),
            OutlinedButton(onPressed: () => _preset('month'), child: const Text('ماه جاری')),
            OutlinedButton(onPressed: () => _preset('last'), child: const Text('ماه گذشته')),
            OutlinedButton.icon(onPressed: _chooseRange, icon: const Icon(Icons.date_range_rounded), label: const Text('بازه دلخواه')),
          ]),
        ])),
        const SizedBox(height: 12),
        FutureBuilder<EmployeePerformanceReport>(
          key: ValueKey(_reloadKey),
          future: repository.fetchReport(employeeId: employee.id, from: _from, to: _to),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingState(kind: SkeletonKind.dashboard);
            }
            if (snapshot.hasError) {
              return ErrorStateView(
                description: 'گزارش عملکرد از داده‌های واقعی Supabase دریافت نشد: ${snapshot.error}',
                onRetry: () => setState(() => _reloadKey++),
              );
            }
            final report = snapshot.data!;
            final metrics = <(String, String, IconData)>[
              ('کل نوبت‌ها', report.totalAppointments.toString(), Icons.event_note_rounded),
              ('تکمیل‌شده', report.completed.toString(), Icons.check_circle_outline_rounded),
              ('لغوشده', report.cancelled.toString(), Icons.event_busy_rounded),
              ('عدم حضور', report.noShow.toString(), Icons.person_off_rounded),
              ('مشتری یکتا', report.uniqueCustomers.toString(), Icons.people_alt_outlined),
              ('درآمد ناخالص', _money(report.grossRevenue), Icons.payments_outlined),
              ('درآمد پس از تخفیف', _money(report.netRevenue), Icons.account_balance_wallet_outlined),
              ('پورسانت', _money(report.commission), Icons.percent_rounded),
              ('سهم مجموعه', _money(report.companyShare), Icons.business_outlined),
              ('میانگین هر نوبت', _money(report.averageTicket), Icons.calculate_outlined),
              ('زمان رزروشده', '${report.bookedMinutes} دقیقه', Icons.event_available_outlined),
              ('ظرفیت برنامه', '${report.scheduledMinutes} دقیقه', Icons.schedule_rounded),
              ('بهره‌وری برنامه', '${report.utilizationRate.toStringAsFixed(1)}٪', Icons.speed_rounded),
              ('روزهای حضور', report.attendanceAvailable ? report.presentDays.toString() : 'ثبت نشده', Icons.fingerprint_rounded),
              ('ساعت کارکرد واقعی', report.attendanceAvailable ? (report.workedMinutes / 60).toStringAsFixed(1) : 'ثبت نشده', Icons.access_time_rounded),
              ('روزهای غیبت', report.attendanceAvailable ? report.absentDays.toString() : 'ثبت نشده', Icons.event_busy_outlined),
              ('مرخصی تأییدشده', report.leaveCount.toString(), Icons.beach_access_outlined),
              ('تأخیر', report.attendanceAvailable ? '${report.lateMinutes} دقیقه' : 'ثبت نشده', Icons.timer_off_outlined),
              ('اضافه‌کاری', report.attendanceAvailable ? '${report.overtimeMinutes} دقیقه' : 'ثبت نشده', Icons.more_time_rounded),
            ];
            if (canViewPayroll) {
              metrics.addAll([
                ('درآمد ثبت‌شده کیف پول', _money(report.earned), Icons.account_balance_outlined),
                ('پاداش', _money(report.bonus), Icons.card_giftcard_rounded),
                ('کسورات', _money(report.deduction), Icons.remove_circle_outline_rounded),
                ('مساعده', _money(report.advance), Icons.money_off_csred_outlined),
                ('پرداخت حقوق', _money(report.salaryPaid), Icons.receipt_long_outlined),
                ('تغییر خالص کیف پول', _money(report.walletBalanceDelta), Icons.wallet_outlined),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (report.days.isEmpty)
                const EmptyState(title: 'در این بازه داده‌ای از سرور ثبت نشده است',
                  description: 'برای این پرسنل در بازه انتخابی نوبت، حضور، مرخصی یا تراکنش قابل مشاهده‌ای وجود ندارد.'),
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 580 ? 3 : 2;
                final gap = 8.0;
                final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(spacing: gap, runSpacing: gap, children: [
                  for (final item in metrics)
                    SizedBox(width: width, child: _metric(item.$1, item.$2, item.$3)),
                ]);
              }),
              if (report.days.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionHeader(title: 'روند روزانه عملکرد'),
                  for (final day in report.days.reversed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${day.date.year}/${day.date.month.toString().padLeft(2, '0')}/${day.date.day.toString().padLeft(2, '0')}'),
                      subtitle: Text('نوبت: ${day.appointments} · تکمیل: ${day.completed} · حضور: ${day.attendanceAvailable ? day.workedMinutes.toString() + ' دقیقه' : 'ثبت نشده'}'),
                      trailing: Text(_money(day.netRevenue), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ])),
              ],
              const SizedBox(height: 8),
              Text('منابع: نوبت‌ها، دفتر مالی پرسنل، کیف پول، برنامه کاری، مرخصی و دفتر حضور و غیاب Supabase. اطلاعات مالی تابع مجوزهای حساب است.',
                style: Theme.of(context).textTheme.bodySmall),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _metric(String label, String value, IconData icon) => AppCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 19),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(fontSize: 11)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
    ]),
  );
}
