import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/sensitive_operation_dialog.dart';
import '../../../../core/widgets/jalali_picker.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/business_finance.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../../../../data/models/employee_wallet.dart';
import '../../../../data/models/employee_finance.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/repositories/operations_repository.dart';
import '../providers/reports_provider.dart';
import '../widgets/revenue_chart.dart';
import '../widgets/operational_reports_sections.dart';
import '../widgets/reports_phase_five_panel.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  Future<void> _selectCustomRange(BuildContext context, ReportsProvider provider) async {
    final from = await showJalaliDatePicker(context, initial: provider.range.jalaliStart, title: 'تاریخ شروع گزارش');
    if (from == null || !context.mounted) return;
    final to = await showJalaliDatePicker(context, initial: provider.range.jalaliEnd, minDate: from, title: 'تاریخ پایان گزارش');
    if (to == null || !context.mounted) return;
    await provider.setCustomRange(from, to);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportsProvider>();
    final pal = context.pal;
    final db = context.watch<AppDatabase>();
    final dayIso = GoRouterState.of(context).uri.queryParameters['date'];
    final selectedDay = dayIso == null ? null : JalaliDate.parseIso(dayIso);
    final canViewAll = db.hasPermission('appointments.view_all');
    final canViewOperations = canViewAll || db.hasPermission('appointments.view_self');
    final canViewAllFinancial = db.hasPermission('finance.income.view') &&
      (db.hasPermission('employees.view_list') || canViewAll);
    final visibleAppointments = canViewOperations
      ? db.appointments.where((item) =>
          canViewAll || item.employeeId == db.currentAccessAccount.employeeId).toList()
      : <Appointment>[];
    final availableEmployees = db.employees.where((item) => db.canViewEmployee(item.id)).toList();
    final availableCategories = <String>{
      if (canViewOperations) ...db.services.map((service) => service.category),
      if (canViewOperations) ...db.appointments.expand((appointment) => appointment.serviceSnapshots
        .map((snapshot) => snapshot['category']).whereType<String>()),
    }.toList()..sort();
    final visibleCustomerIds = visibleAppointments.map((item) => item.customerId).toSet();
    final availableCustomers = !canViewOperations || !db.hasPermission('customers.view')
      ? db.customers.where((_) => false).toList()
      : canViewAll
        ? db.customers
        : db.customers.where((item) => visibleCustomerIds.contains(item.id)).toList();
    final dayAppointments = selectedDay == null ? const <Appointment>[] :
      visibleAppointments.where((item) => item.jalali.sameDay(selectedDay) && provider.filter.matches(item)).toList();
    final dayCompleted = dayAppointments.where((item) => item.status == AppointmentStatus.completed);
    final dayFinanceEntries = db.employeeFinanceEntries.where((entry) =>
      selectedDay != null && JalaliDate.fromDateTime(entry.createdAt).sameDay(selectedDay) &&
      (canViewAllFinancial || entry.employeeId == db.currentAccessAccount.employeeId) &&
      db.hasPermission('finance.income.view', employeeId: entry.employeeId) &&
      (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund)).toList();
    final dayRevenue = dayFinanceEntries.fold<num>(0, (sum, item) => sum + item.receivedAmount);
    final dayCommission = dayFinanceEntries.where((item) =>
      db.hasPermission('finance.commission.view', employeeId: item.employeeId)).fold<num>(0, (sum, item) =>
      sum + (item.type == FinanceEntryType.refund ? -item.commissionAmount.abs() : item.commissionAmount));
    final dayOperatingExpense = db.businessExpenses.where((item) =>
      selectedDay != null && JalaliDate.fromDateTime(item.createdAt).sameDay(selectedDay) &&
      item.status == BusinessExpenseStatus.posted).fold<num>(0, (sum, item) => sum + item.amount);
    final dayWalletEntries = db.hasPermission('finance.salary.view') ? db.employeeWalletTransactions.where((item) =>
      selectedDay != null && JalaliDate.fromDateTime(item.createdAt).sameDay(selectedDay) &&
      item.status == EmployeeWalletTransactionStatus.posted &&
      (canViewAllFinancial || item.employeeId == db.currentAccessAccount.employeeId) &&
      db.hasPermission('finance.salary.view', employeeId: item.employeeId)).toList() : <EmployeeWalletTransaction>[];
    final dayPayrollExpense = dayWalletEntries.where((item) => {
      EmployeeWalletTransactionType.fixedSalary, EmployeeWalletTransactionType.bonus,
      EmployeeWalletTransactionType.penalty, EmployeeWalletTransactionType.deduction,
      EmployeeWalletTransactionType.adjustment,
    }.contains(item.type)).fold<num>(0, (sum, item) => sum + item.amount);
    final dayTotalExpense = dayOperatingExpense + dayCommission + dayPayrollExpense;
    final dayEmployeeTotals = <String, ({int count, num revenue})>{};
    for (final item in dayCompleted.where((item) => db.canViewEmployee(item.employeeId))) {
      final current = dayEmployeeTotals[item.employeeName];
      final revenue = dayFinanceEntries.where((entry) => entry.appointmentId == item.id)
        .fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
      dayEmployeeTotals[item.employeeName] = (count: (current?.count ?? 0) + 1, revenue: (current?.revenue ?? 0) + revenue);
    }

    return PageScaffold(
      title: 'گزارش‌ها و تحلیل',
      subtitle: 'نمای یکپارچه عملکرد مالی و عملیاتی مجموعه',
      leading: const HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, size: 22),
      actions: [
        if (db.hasPermission('finance.payment.create') && canViewOperations && db.hasPermission('customers.view'))
          SoftButton(label: 'ثبت دریافت', onTap: () => showDialog<void>(context: context, builder: (_) => _AddAppointmentPaymentDialog(database: db))),
        if (db.hasPermission('finance.payment.create'))
          SoftButton(label: 'ثبت هزینه', onTap: () => showDialog<void>(context: context, builder: (_) => _AddBusinessExpenseDialog(database: db))),
        if (db.hasPermission('employees.view_list') || canViewOperations)
          SoftButton(label: 'تحلیل پرسنل', onTap: () => context.push('/reports/personnel')),
      ],
      child: provider.loading
          ? const LoadingState(kind: SkeletonKind.reports)
          : provider.error != null
              ? ErrorStateView(kind: provider.errorKind ?? AppErrorKind.fetch, description: provider.error, onRetry: provider.load)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (selectedDay != null) ...[
                      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SectionHeader(title: 'گزارش روز ${selectedDay.long}', subtitle: 'جزئیات همان روز انتخاب‌شده از نمودار'),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (canViewOperations) _MetricCard(label: 'کل نوبت‌ها', value: dayAppointments.length, icon: HugeIcons.strokeRoundedAppointment01, color: pal.primaryBright),
                          if (canViewOperations) _MetricCard(label: 'تکمیل‌شده', value: dayCompleted.length, icon: HugeIcons.strokeRoundedCheckmarkCircle01, color: pal.success),
                          _MetricCard(label: 'درآمد ثبت‌شده روز', value: dayRevenue, money: true, icon: HugeIcons.strokeRoundedCash02, color: pal.success),
                          _MetricCard(label: 'هزینه روز', value: dayTotalExpense, money: true, icon: HugeIcons.strokeRoundedWallet01, color: pal.warning),
                          _MetricCard(label: 'هزینه عملیاتی', value: dayOperatingExpense, money: true, icon: HugeIcons.strokeRoundedWallet01, color: pal.warning),
                        ]),
                        const SizedBox(height: 8),
                        if (!canViewOperations)
                          const Text('جزئیات نوبت‌های این روز برای نقش فعلی قابل مشاهده نیست.', style: TextStyle(fontSize: 10))
                        else if (dayAppointments.isEmpty)
                          const EmptyState(title: 'برای این روز نوبتی ثبت نشده', compact: true)
                        else
                          for (final item in dayAppointments)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(item.status.icon, color: item.status.color),
                              title: Text(item.customerName),
                              subtitle: Text('${item.serviceName} · ${item.startAt.hour.toString().padLeft(2, '0')}:${item.startAt.minute.toString().padLeft(2, '0')}'),
                              trailing: StatusBadge.appointment(item.status, dense: true),
                            ),
                        const Divider(height: 18),
                        Text('ترکیب هزینه روز: کمیسیون ${Fmt.compactMoney(dayCommission)} · حقوق و مزایا ${Fmt.compactMoney(dayPayrollExpense)}',
                          style: TextStyle(fontSize: 10, color: pal.textMuted)),
                        if (!db.employees.every((item) => db.hasPermission('finance.income.view', employeeId: item.id)) ||
                            !db.employees.every((item) => db.hasPermission('finance.commission.view', employeeId: item.id)) ||
                            !db.employees.every((item) => db.hasPermission('finance.salary.view', employeeId: item.id)))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('به‌دلیل محدودیت مجوز، بخشی از درآمد یا هزینه‌های پرسنلی در جمع روز لحاظ نشده است.',
                              style: TextStyle(fontSize: 9, color: pal.warning)),
                          ),
                        const SizedBox(height: 8),
                        const SectionHeader(title: 'عملکرد پرسنل در این روز'),
                        if (dayEmployeeTotals.isEmpty)
                          const EmptyState(title: 'عملکردی برای نمایش وجود ندارد', compact: true)
                        else
                          for (final entry in dayEmployeeTotals.entries)
                            ListTile(
                              dense: true, contentPadding: EdgeInsets.zero,
                              leading: const HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 18),
                              title: Text(entry.key, style: const TextStyle(fontSize: 11)),
                              subtitle: Text('${FaNum.ofInt(entry.value.count)} نوبت تکمیل‌شده', style: const TextStyle(fontSize: 9)),
                              trailing: Text(Fmt.compactMoney(entry.value.revenue), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                      ])),
                      const SizedBox(height: 12),
                    ],
                    AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SectionHeader(title: 'بازه گزارش', subtitle: 'تمام کارت‌ها، نمودارها و فهرست‌ها با این بازه به‌روزرسانی می‌شوند'),
                      const SizedBox(height: 10),
                      Wrap(spacing: 7, runSpacing: 7, children: [
                        for (final period in ReportPeriod.values.where((item) => item != ReportPeriod.custom))
                          ChoiceChip(
                            label: Text(period.label),
                            selected: provider.period == period,
                            onSelected: (_) => provider.setPeriod(period),
                            visualDensity: VisualDensity.compact,
                          ),
                        ActionChip(
                          avatar: const HugeIcon(icon: HugeIcons.strokeRoundedCalendar03, size: 16),
                          label: Text(provider.period == ReportPeriod.custom ? provider.range.label : 'انتخاب بازه دلخواه'),
                          onPressed: () => _selectCustomRange(context, provider),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text('از ${provider.range.jalaliStart.long} تا ${provider.range.jalaliEnd.long}', style: TextStyle(fontSize: 11, color: pal.textMuted)),
                    ])),
                    const SizedBox(height: 12),
                    AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionHeader(title: 'فیلترهای ترکیبی مالی و عملیاتی', subtitle: 'ابعاد مرتبط در گزارش‌های مالی، عملیاتی، نمودارها و جزئیات اعمال می‌شوند؛ هزینه عمومی مجموعه به‌صورت کل بازه نمایش داده می‌شود.'),
                      const SizedBox(height: 5),
                      Text('دامنه فعلی: کل مجموعه فعال. در مدل داده فعلی شناسه شعبه/چندشعبه‌ای وجود ندارد؛ بنابراین فیلتر شعبه تا زمان تعریف منبع مرجع آن فعال نمی‌شود.',
                        style: TextStyle(fontSize: 9, color: pal.textMuted)),
                      const SizedBox(height: 10),
                      LayoutBuilder(builder: (context, constraints) {
                        final width = constraints.maxWidth < 440 ? constraints.maxWidth : 205.0;
                        return Wrap(spacing: 9, runSpacing: 9, children: [
                          if (canViewOperations) SizedBox(width: width, child: DropdownButtonFormField<String?>(
                            value: provider.filter.serviceId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'خدمت'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('همه خدمات')),
                              for (final item in db.services)
                                DropdownMenuItem<String?>(value: item.id, child: Text(item.title, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (value) => provider.setFilters(serviceId: value, clearService: value == null),
                          )),
                          if (db.hasPermission('employees.view_list') || db.hasPermission('finance.income.view')) SizedBox(width: width, child: DropdownButtonFormField<String?>(
                            value: provider.filter.employeeId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'پرسنل'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('همه پرسنل')),
                              for (final item in availableEmployees)
                                DropdownMenuItem<String?>(value: item.id, child: Text(item.fullName, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (value) => provider.setFilters(employeeId: value, clearEmployee: value == null),
                          )),
                          if (canViewOperations && db.hasPermission('customers.view')) SizedBox(width: width, child: DropdownButtonFormField<String?>(
                            value: provider.filter.customerId,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'مشتری'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('همه مشتریان')),
                              for (final item in availableCustomers)
                                DropdownMenuItem<String?>(value: item.id, child: Text(item.fullName, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (value) => provider.setFilters(customerId: value, clearCustomer: value == null),
                          )),
                          if (canViewOperations) SizedBox(width: width, child: DropdownButtonFormField<AppointmentStatus?>(
                            value: provider.filter.status,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'وضعیت نوبت'),
                            items: [
                              const DropdownMenuItem<AppointmentStatus?>(value: null, child: Text('همه وضعیت‌ها')),
                              for (final item in AppointmentStatus.values)
                                DropdownMenuItem<AppointmentStatus?>(value: item, child: Text(item.label)),
                            ],
                            onChanged: (value) => provider.setFilters(status: value, clearStatus: value == null),
                          )),
                          if (canViewOperations) SizedBox(width: width, child: DropdownButtonFormField<String?>(
                            value: provider.filter.category,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'دسته‌بندی خدمت'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('همه دسته‌بندی‌ها')),
                              for (final item in availableCategories)
                                DropdownMenuItem<String?>(value: item, child: Text(item, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (value) => provider.setFilters(category: value, clearCategory: value == null),
                          )),
                          SizedBox(width: width, child: DropdownButtonFormField<String?>(
                            value: provider.filter.paymentMethod,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'روش پرداخت'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('همه روش‌ها')),
                              for (final item in BusinessPaymentMethod.values)
                                DropdownMenuItem<String?>(value: item.name, child: Text(item.label)),
                            ],
                            onChanged: (value) => provider.setFilters(paymentMethod: value, clearPaymentMethod: value == null),
                          )),
                          if (db.hasPermission('finance.settlement.view')) SizedBox(width: width, child: DropdownButtonFormField<EmployeeWalletSettlementStatus?>(
                            value: provider.filter.settlementStatus,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'وضعیت تسویه پرسنل'),
                            items: [
                              const DropdownMenuItem<EmployeeWalletSettlementStatus?>(value: null, child: Text('همه وضعیت‌ها')),
                              for (final item in EmployeeWalletSettlementStatus.values)
                                DropdownMenuItem<EmployeeWalletSettlementStatus?>(value: item, child: Text(item == EmployeeWalletSettlementStatus.completed ? 'تسویه کامل' : 'تسویه جزئی')),
                            ],
                            onChanged: (value) => provider.setFilters(settlementStatus: value, clearSettlementStatus: value == null),
                          )),
                        ]);
                      }),
                      if (!provider.filter.isEmpty)
                        Align(alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(onPressed: provider.clearFilters, child: const Text('پاک کردن فیلترها'))),
                    ])),
                    const SizedBox(height: 12),
                    ReportsPhaseFivePanel(database: db, provider: provider),
                    const SizedBox(height: 12),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      _MetricCard(label: 'درآمد خالص', value: provider.totalRevenue, money: true, icon: HugeIcons.strokeRoundedCash02, color: pal.success),
                      _MetricCard(label: 'هزینه ثبت‌شده', value: provider.totalCost, money: true, icon: HugeIcons.strokeRoundedWallet01, color: pal.warning),
                      _MetricCard(label: 'سود خالص تخمینی', value: provider.netProfit, money: true, icon: HugeIcons.strokeRoundedChartLineData01, color: provider.netProfit >= 0 ? pal.success : pal.danger),
                      if (canViewOperations) _MetricCard(label: 'تعداد نوبت', value: provider.totalAppointments, icon: HugeIcons.strokeRoundedAppointment01, color: pal.primaryBright),
                      if (canViewOperations) _MetricCard(label: 'مشتری یکتا', value: provider.totalCustomers, icon: HugeIcons.strokeRoundedUser, color: pal.purple),
                      if (canViewOperations) _MetricCard(label: 'نوبت تکمیل‌شده', value: provider.completedAppointments, icon: HugeIcons.strokeRoundedCheckmarkCircle01, color: pal.success),
                    ]),
                    const SizedBox(height: 8),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(provider.analytics.costNote, style: TextStyle(fontSize: 10, color: pal.textMuted))),
                    const SizedBox(height: 12),
                    AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionHeader(title: 'روند درآمد و هزینه', subtitle: 'میله‌ها درآمد و خطوط، درآمد و هزینه ثبت‌شده را نشان می‌دهند'),
                      const SizedBox(height: 8),
                      const _ChartLegend(),
                      const SizedBox(height: 10),
                      ReportChartEntrance(child: RevenueBarChart(data: provider.revenueSeries, height: 180, onPointTap: (index) => _openDayReport(context, provider, index),)),
                      const SizedBox(height: 12),
                      ReportChartEntrance(child: RevenueLineChart(data: provider.revenueSeries, height: 180, showSecondary: true, onPointTap: (index) => _openDayReport(context, provider, index),)),
                    ])),
                    const SizedBox(height: 12),
                    AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionHeader(title: 'مقایسه با دوره قبل', subtitle: 'درآمد و هزینه ثبت‌شده در دو بازه هم‌طول'),
                      const SizedBox(height: 8),
                      const _ChartLegend(),
                      const SizedBox(height: 8),
                      RevenueLineChart(
                        data: [
                          RevenuePoint(label: 'دوره قبل', value: provider.analytics.previousPeriodRevenue, secondary: provider.analytics.previousPeriodCost),
                          RevenuePoint(label: 'دوره جاری', value: provider.analytics.netRevenue, secondary: provider.analytics.cost),
                        ],
                        height: 150,
                        showSecondary: true,
                      ),
                      Text(
                        'سود دوره قبل: ${Fmt.compactMoney(provider.analytics.previousPeriodRevenue - provider.analytics.previousPeriodCost)}  ·  سود دوره جاری: ${Fmt.compactMoney(provider.analytics.netProfit)}',
                        style: TextStyle(fontSize: 10.5, color: pal.textMuted),
                      ),
                    ])),
                    const SizedBox(height: 12),
                    AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SectionHeader(title: 'تحلیل مالی و سود و زیان', subtitle: 'درآمد شناسایی‌شده، مبالغ وصولی و هزینه‌های ثبت‌شده از هم تفکیک شده‌اند'),
                      const SizedBox(height: 10),
                      Wrap(spacing: 9, runSpacing: 9, children: [
                        GestureDetector(onTap: () => _showFinanceSheet(context, 'جزئیات درآمد ناخالص', [
                          'مبلغ ناخالص خدمات تکمیل‌شده: ${Fmt.compactMoney(provider.analytics.grossRevenue)}',
                          'تخفیف و برگشت ثبت‌شده: ${Fmt.compactMoney(provider.analytics.discounts)}',
                        ]), child: _MetricCard(label: 'درآمد ناخالص', value: provider.analytics.grossRevenue, money: true, icon: HugeIcons.strokeRoundedCash02, color: pal.primaryBright)),
                        _MetricCard(label: 'تخفیف‌ها', value: provider.analytics.discounts, money: true, icon: HugeIcons.strokeRoundedCash02, color: pal.warning),
                        GestureDetector(onTap: () => _showFinanceSheet(context, 'جزئیات درآمد خالص', [
                          for (final item in provider.analytics.services) '${item.name} · ${item.count} نوبت · ${Fmt.compactMoney(item.revenue)}',
                        ]), child: _MetricCard(label: 'درآمد خالص', value: provider.analytics.netRevenue, money: true, icon: HugeIcons.strokeRoundedCash02, color: pal.success)),
                        GestureDetector(onTap: () => _showPaymentSheet(context, db, provider), child: _MetricCard(label: 'وصول‌شده', value: provider.analytics.collectedRevenue, money: true, icon: HugeIcons.strokeRoundedWallet01, color: pal.info)),
                        GestureDetector(onTap: () => _showFinanceSheet(context, 'مطالبات مشتریان', [
                          for (final item in provider.analytics.customerDebts) '${item.customerName} · ${item.appointmentCount} نوبت · ${Fmt.compactMoney(item.amount)}',
                          for (final item in provider.analytics.partialPayments) 'پرداخت ناقص: ${item.description} · ${Fmt.compactMoney(item.signedAmount)}',
                        ]), child: _MetricCard(label: 'مطالبات', value: provider.analytics.receivables, money: true, icon: HugeIcons.strokeRoundedAppointment01, color: pal.warning)),
                        _MetricCard(label: 'سهم مجموعه', value: provider.analytics.companyShare, money: true, icon: HugeIcons.strokeRoundedCash02, color: pal.primaryBright),
                        GestureDetector(onTap: () => _showFinanceSheet(context, 'پورسانت پرسنل', [
                          for (final item in provider.analytics.employees) '${item.name} · ${Fmt.compactMoney(item.commission)}',
                        ]), child: _MetricCard(label: 'پورسانت پرسنل', value: provider.analytics.commissionCost, money: true, icon: HugeIcons.strokeRoundedUser, color: pal.purple)),
                        GestureDetector(onTap: () => _showFinanceSheet(context, 'حقوق پرداخت‌شده', [
                          'مبلغ پرداخت‌شده در بازه: ${Fmt.compactMoney(provider.analytics.staffPaid)}',
                          'مانده خالص کیف پول پرسنل تا پایان بازه: ${Fmt.compactMoney(provider.analytics.staffPayable)}',
                          'مساعده باز: ${Fmt.compactMoney(provider.analytics.advancesOutstanding)}',
                        ]), child: _MetricCard(label: 'حقوق پرداختی', value: provider.analytics.staffPaid, money: true, icon: HugeIcons.strokeRoundedWallet01, color: pal.info)),
                        _MetricCard(label: 'حاشیه سود', value: provider.analytics.profitMarginPercent, icon: HugeIcons.strokeRoundedChartLineData01, color: pal.success),
                        GestureDetector(onTap: () => _showFinanceSheet(context, 'مانده پرداخت پرسنل', [
                          'مانده قابل پرداخت: ${Fmt.compactMoney(provider.analytics.staffPayable)}',
                          'پرداخت‌شده در بازه: ${Fmt.compactMoney(provider.analytics.staffPaid)}',
                          'مساعده باز: ${Fmt.compactMoney(provider.analytics.advancesOutstanding)}',
                          for (final item in provider.analytics.settlements) '${item.receiptNumber} · ${Fmt.compactMoney(item.paidAmount)} · ${item.status.name}',
                        ]), child: _MetricCard(label: 'مانده پرسنل', value: provider.analytics.staffPayable, money: true, icon: HugeIcons.strokeRoundedUser, color: pal.purple)),
                      ]),
                      const SizedBox(height: 12),
                      LayoutBuilder(builder: (context, constraints) {
                        final methodEntries = provider.analytics.paymentsByMethod.entries.toList();
                        final methodChart = AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SectionHeader(title: 'ترکیب روش‌های پرداخت', subtitle: 'مبالغ خالص دریافتی پس از کسر برگشت وجه'),
                          const SizedBox(height: 8),
                          LayoutBuilder(builder: (context, inner) {
                            final legend = Column(children: [
                              for (final item in methodEntries)
                                InkWell(
                                  onTap: () => _showPaymentSheet(context, db, provider, method: item.key),
                                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                                    Expanded(child: Text(item.key, style: TextStyle(fontSize: 10.5, color: pal.textSecondary))),
                                    Text(Fmt.compactMoney(item.value), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: pal.textPrimary)),
                                  ])),
                                ),
                            ]);
                            final donut = StatusDonut(counts: {for (final item in methodEntries) item.key: item.value.round()}, centerLabel: 'وصول', size: 118, onSegmentTap: (method) => _showPaymentSheet(context, db, provider, method: method));
                            if (inner.maxWidth < 340) return Column(children: [Center(child: donut), const SizedBox(height: 8), legend]);
                            return Row(children: [donut, const SizedBox(width: 12), Expanded(child: legend)]);
                          }),
                        ]));
                        final expenseCard = AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SectionHeader(title: 'ترکیب هزینه‌ها', subtitle: 'هر قلم فقط از منبع اصلی خودش شمرده شده است'),
                          const SizedBox(height: 8),
                          for (final item in provider.analytics.expensesByCategory.entries.where((item) => item.value != 0))
                            InkWell(
                              onTap: () => _showFinanceSheet(context, item.key, [
                                for (final expense in provider.analytics.businessExpenses.where((expense) => expense.category.label == item.key)) '${expense.description} · سند ${expense.sourceDocumentId} · ${Fmt.compactMoney(expense.amount)}',
                                if (item.key == 'کمیسیون پرسنل') 'جمع کمیسیون و برگشت کمیسیون: ${Fmt.compactMoney(item.value)}',
                                if (item.key == 'حقوق و مزایا') 'جمع حقوق، پاداش و کسورات ثبت‌شده: ${Fmt.compactMoney(item.value)}',
                              ]),
                              child: Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
                                Expanded(child: Text(item.key, style: TextStyle(fontSize: 10.5, color: pal.textSecondary))),
                                Text(Fmt.compactMoney(item.value), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: pal.textPrimary)),
                              ])),
                            ),
                        ]));
                        if (constraints.maxWidth < 760) return Column(children: [methodChart, const SizedBox(height: 10), expenseCard]);
                        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: methodChart), const SizedBox(width: 10), Expanded(child: expenseCard),
                        ]);
                      }),
                      const SizedBox(height: 10),
                      Text('دوره قبل · درآمد: ${Fmt.compactMoney(provider.analytics.previousPeriodRevenue)} · هزینه: ${Fmt.compactMoney(provider.analytics.previousPeriodCost)} · سود: ${Fmt.compactMoney(provider.analytics.previousPeriodRevenue - provider.analytics.previousPeriodCost)}', style: TextStyle(fontSize: 10.5, color: pal.textMuted)),
                      const SizedBox(height: 5),
                      Text('بهای تمام‌شده خدمات هنوز در مدل Datamonck تعریف نشده؛ سود ناخالص کالا/خدمت در این نسخه قابل محاسبه نیست.', style: TextStyle(fontSize: 10, color: pal.textMuted)),
                    ])),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final statusCard = AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SectionHeader(title: 'توزیع وضعیت نوبت‌ها'),
                        const SizedBox(height: 12),
                        Row(children: [
                          StatusDonut(counts: provider.statusCounts, size: 126),
                          const SizedBox(width: 10),
                          Expanded(child: Column(children: [
                            for (final status in AppointmentStatus.values)
                              Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
                                Container(width: 7, height: 7, decoration: BoxDecoration(color: status.color, shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Expanded(child: Text(status.label, style: TextStyle(fontSize: 10.5, color: pal.textSecondary))),
                                Text(FaNum.ofInt(provider.statusCounts[status.label] ?? 0), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pal.textPrimary)),
                              ])),
                          ])),
                        ]),
                      ]));
                      final employeeCard = AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SectionHeader(title: 'عملکرد پرسنل', subtitle: 'درآمد خدمات و کمیسیون ثبت‌شده'),
                        const SizedBox(height: 12),
                        _RankedList(items: [
                          for (final item in provider.analytics.employees) RevenuePoint(label: item.name, value: item.revenue),
                        ], color: pal.primaryBright),
                      ]));
                      final serviceCard = AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SectionHeader(title: 'خدمات پرفروش'),
                        const SizedBox(height: 12),
                        _RankedList(items: provider.serviceRevenue, color: pal.success),
                      ]));
                      if (!wide) return Column(children: [
                        if (canViewOperations) statusCard,
                        if (canViewOperations) const SizedBox(height: 12),
                        employeeCard,
                        if (canViewOperations) const SizedBox(height: 12),
                        if (canViewOperations) serviceCard,
                      ]);
                      if (!canViewOperations) return employeeCard;
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 4, child: statusCard),
                        const SizedBox(width: 12),
                        Expanded(flex: 5, child: Column(children: [employeeCard, const SizedBox(height: 12), serviceCard])),
                      ]);
                    }),
                    const SizedBox(height: 12),
                    if (canViewOperations)
                      OperationalReportsSections(analytics: provider.analytics, provider: provider)
                    else
                      AppCard(child: Text('دسترسی به جزئیات نوبت‌ها و گزارش‌های عملیاتی برای نقش فعلی فعال نیست؛ گزارش‌های مالی مطابق مجوز شما نمایش داده می‌شوند.',
                        style: TextStyle(fontSize: 11, color: pal.textMuted))),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, constraints) {
                      final appointmentsCard = _RecentAppointments(items: provider.analytics.recentAppointments);
                      final transactionsCard = _RecentTransactions(items: provider.analytics.recentTransactions);
                      if (constraints.maxWidth < 900) return Column(children: [
                        if (canViewOperations) appointmentsCard,
                        if (canViewOperations) const SizedBox(height: 12),
                        transactionsCard,
                      ]);
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (canViewOperations) Expanded(child: appointmentsCard),
                        if (canViewOperations) const SizedBox(width: 12),
                        Expanded(child: transactionsCard),
                      ]);
                    }),
                  ],
                ),
    );
  }
}




class _AddAppointmentPaymentDialog extends StatefulWidget {
  const _AddAppointmentPaymentDialog({required this.database});
  final AppDatabase database;

  @override
  State<_AddAppointmentPaymentDialog> createState() => _AddAppointmentPaymentDialogState();
}

class _AddAppointmentPaymentDialogState extends State<_AddAppointmentPaymentDialog> {
  late final String _operationKey = 'receipt-${DateTime.now().microsecondsSinceEpoch}';
  final _amount = TextEditingController();
  final _description = TextEditingController(text: 'دریافت وجه نوبت');
  late List<Appointment> _appointments;
  Appointment? _selected;
  BusinessPaymentMethod _method = BusinessPaymentMethod.pos;
  String? _error;

  int _outstanding(Appointment appointment) {
    final revenueDocuments = widget.database.employeeFinanceEntries.where((entry) =>
      entry.appointmentId == appointment.id &&
      (entry.type == FinanceEntryType.commission || entry.type == FinanceEntryType.refund)).toList();
    final recognized = revenueDocuments.fold<int>(0, (sum, entry) => sum + entry.receivedAmount);
    final due = revenueDocuments.isNotEmpty ? recognized : appointment.price.round();
    final paid = widget.database.appointmentPayments.where((payment) =>
      payment.appointmentId == appointment.id).fold<int>(0, (sum, payment) => sum + payment.signedAmount);
    return due - paid;
  }

  @override
  void initState() {
    super.initState();
    _appointments = widget.database.appointments.where((item) =>
      item.status == AppointmentStatus.completed && _outstanding(item) > 0).toList();
    if (_appointments.isNotEmpty) _selected = _appointments.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(FaNum.toLatin(_amount.text).replaceAll(RegExp(r'[^0-9]'), ''));
    if (_selected == null || amount == null || amount <= 0 || _description.text.trim().isEmpty) {
      setState(() => _error = 'نوبت، مبلغ و شرح پرداخت را کامل کنید.');
      return;
    }
    final appointment = _selected!;
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید ثبت دریافت مشتری',
      description: 'رسید دریافت به دفتر مالی اضافه می‌شود و به‌صورت مستقیم حذف یا Undo نخواهد شد.',
      recordDetails: {
        'کد نوبت': appointment.reference,
        'مشتری': appointment.customerName,
        'مبلغ دریافت': '${FaNum.ofInt(amount)} تومان',
        'روش پرداخت': _method.label,
        'شرح': _description.text.trim(),
      },
      isReversible: false,
      warning: 'برای اصلاح دریافت باید برگشت وجه و سند مالی معکوس ثبت شود.',
      confirmLabel: 'ثبت رسید دریافت',
    );
    if (!approved || !mounted) return;
    try {
      await OperationsRepository(widget.database).recordAppointmentPayment(
        appointmentId: appointment.id,
        amount: amount,
        method: _method,
        description: _description.text.trim(),
        idempotencyKey: _operationKey,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ثبت دریافت مشتری'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_appointments.isEmpty)
        const Text('نوبت تکمیل‌شده با مانده قابل دریافت وجود ندارد.')
      else
        DropdownButtonFormField<Appointment>(
          value: _selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'نوبت / مشتری'),
          items: [for (final item in _appointments) DropdownMenuItem(
            value: item,
            child: Text('${item.customerName} · ${item.serviceName} · ${Fmt.compactMoney(_outstanding(item))}', overflow: TextOverflow.ellipsis),
          )],
          onChanged: (value) => setState(() => _selected = value),
        ),
      const SizedBox(height: 8),
      TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ دریافتی (تومان)')),
      const SizedBox(height: 8),
      DropdownButtonFormField<BusinessPaymentMethod>(
        value: _method,
        decoration: const InputDecoration(labelText: 'روش پرداخت'),
        items: [for (final item in BusinessPaymentMethod.values) DropdownMenuItem(value: item, child: Text(item.label))],
        onChanged: (value) => setState(() => _method = value ?? _method),
      ),
      const SizedBox(height: 8),
      TextField(controller: _description, decoration: const InputDecoration(labelText: 'شرح')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11))),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
      FilledButton(onPressed: _appointments.isEmpty ? null : _save, child: const Text('ثبت دریافت')),
    ],
  );
}

class _AddBusinessExpenseDialog extends StatefulWidget {
  const _AddBusinessExpenseDialog({required this.database});
  final AppDatabase database;

  @override
  State<_AddBusinessExpenseDialog> createState() => _AddBusinessExpenseDialogState();
}

class _AddBusinessExpenseDialogState extends State<_AddBusinessExpenseDialog> {
  late final String _expenseId = widget.database.nextId('expense');
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _source = TextEditingController();
  BusinessExpenseCategory _category = BusinessExpenseCategory.operating;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(FaNum.toLatin(_amount.text).replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null || amount <= 0 || _description.text.trim().isEmpty || _source.text.trim().isEmpty) {
      setState(() => _error = 'مبلغ، شرح و شناسه سند منبع را کامل و معتبر وارد کنید.');
      return;
    }
    final expense = BusinessExpense(
      id: _expenseId,
      createdAt: DateTime.now(),
      amount: amount,
      category: _category,
      description: _description.text.trim(),
      sourceDocumentId: _source.text.trim(),
      createdBy: widget.database.currentAccessAccount.name,
    );
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید ثبت هزینه مجموعه',
      description: 'هزینه به دفتر مالی ثبت می‌شود و سند اصلی حذف یا Undo نمی‌شود.',
      recordDetails: {
        'دسته‌بندی': _category.label,
        'مبلغ': '${FaNum.ofInt(amount)} تومان',
        'شرح': expense.description,
        'سند منبع': expense.sourceDocumentId,
        'ثبت‌کننده': expense.createdBy,
      },
      isReversible: false,
      warning: 'سند هزینه پس از ثبت تغییرناپذیر است؛ اصلاح آن باید با سند مالی جداگانه انجام شود.',
      confirmLabel: 'ثبت هزینه',
    );
    if (!approved || !mounted) return;
    try {
      await OperationsRepository(widget.database).addBusinessExpense(expense);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ثبت هزینه مجموعه'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
      const SizedBox(height: 8),
      DropdownButtonFormField<BusinessExpenseCategory>(
        value: _category,
        decoration: const InputDecoration(labelText: 'دسته هزینه'),
        items: [for (final item in BusinessExpenseCategory.values) DropdownMenuItem(value: item, child: Text(item.label))],
        onChanged: (value) => setState(() => _category = value ?? _category),
      ),
      const SizedBox(height: 8),
      TextField(controller: _description, decoration: const InputDecoration(labelText: 'شرح هزینه')),
      const SizedBox(height: 8),
      TextField(controller: _source, decoration: const InputDecoration(labelText: 'شناسه سند منبع')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11))),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
      FilledButton(onPressed: _save, child: const Text('ثبت هزینه')),
    ],
  );
}



void _showPaymentSheet(BuildContext context, AppDatabase database, ReportsProvider provider, {String? method}) {
  final payments = provider.analytics.paymentTransactions.where((item) => method == null || item.method.label == method).toList();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.pal.surface,
    builder: (sheetContext) => SafeArea(child: SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.65,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(title: method == null ? 'رسیدها و برگشت وجه' : 'پرداخت‌های $method', subtitle: 'رسیدهای این بازه؛ امکان ثبت برگشت وجه برای هر دریافت'),
          const SizedBox(height: 8),
          Expanded(child: payments.isEmpty
            ? const EmptyState(title: 'پرداختی در این بازه وجود ندارد', compact: true)
            : ListView.separated(
                itemCount: payments.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final payment = payments[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(payment.description, style: const TextStyle(fontSize: 12)),
                    subtitle: Text('${payment.method.label} · ${payment.type == BusinessPaymentType.refund ? 'برگشت وجه' : 'دریافت'}', style: const TextStyle(fontSize: 10)),
                    trailing: payment.type == BusinessPaymentType.receipt
                      ? TextButton(onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => _RefundPaymentDialog(database: database, payment: payment),
                        ), child: const Text('برگشت وجه'))
                      : Text(Fmt.compactMoney(payment.signedAmount), style: TextStyle(color: context.pal.danger, fontSize: 11)),
                  );
                },
              )),
        ]),
      ),
    )),
  );
}

class _RefundPaymentDialog extends StatefulWidget {
  const _RefundPaymentDialog({required this.database, required this.payment});
  final AppDatabase database;
  final AppointmentPayment payment;

  @override
  State<_RefundPaymentDialog> createState() => _RefundPaymentDialogState();
}

class _RefundPaymentDialogState extends State<_RefundPaymentDialog> {
  late final String _operationKey = 'refund-${widget.payment.id}-${DateTime.now().microsecondsSinceEpoch}';
  final _amount = TextEditingController();
  final _description = TextEditingController(text: 'برگشت وجه مشتری');
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(FaNum.toLatin(_amount.text).replaceAll(RegExp(r'[^0-9]'), ''));
    if (amount == null || amount <= 0 || _description.text.trim().isEmpty) {
      setState(() => _error = 'مبلغ و شرح برگشت وجه را وارد کنید.');
      return;
    }
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید برگشت وجه',
      description: 'سند برگشت وجه به‌عنوان رکورد مالی جدید ثبت می‌شود و رسید اصلی دست‌نخورده باقی می‌ماند.',
      recordDetails: {
        'شناسه رسید': widget.payment.id,
        'مبلغ برگشتی': '${FaNum.ofInt(amount)} تومان',
        'روش پرداخت': widget.payment.method.label,
        'شرح': _description.text.trim(),
      },
      isReversible: false,
      warning: 'برگشت وجه یک سند مالی قطعی است و Undo ندارد.',
      confirmLabel: 'ثبت برگشت وجه',
    );
    if (!approved || !mounted) return;
    try {
      await OperationsRepository(widget.database).refundAppointmentPayment(
        paymentId: widget.payment.id,
        amount: amount,
        description: _description.text.trim(),
        idempotencyKey: _operationKey,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ثبت برگشت وجه'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('رسید: ${widget.payment.description}', style: const TextStyle(fontSize: 11)),
      TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ برگشتی (تومان)')),
      TextField(controller: _description, decoration: const InputDecoration(labelText: 'شرح برگشت')),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11)),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
      FilledButton(onPressed: _save, child: const Text('ثبت برگشت')),
    ],
  );
}

void _openDayReport(BuildContext context, ReportsProvider provider, int index) {
  final points = provider.analytics.trend;
  if (index < 0 || index >= points.length) return;
  final date = JalaliDate.fromDateTime(points[index].start);
  context.go('/reports?date=${date.iso}');
}

void _showFinanceSheet(BuildContext context, String title, List<String> details) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.pal.surface,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.55,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(title: title, subtitle: 'اسناد مرتبط با بازه انتخاب‌شده'),
            const SizedBox(height: 10),
            Expanded(child: details.isEmpty
              ? const EmptyState(title: 'سندی برای نمایش وجود ندارد', compact: true)
              : ListView.separated(
                  itemCount: details.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(details[index], style: TextStyle(fontSize: 12, color: context.pal.textPrimary)),
                  ),
                )),
          ]),
        ),
      ),
    ),
  );
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend();
  @override
  Widget build(BuildContext context) => Wrap(spacing: 16, runSpacing: 6, children: [
    _LegendItem(color: context.pal.primaryBright, label: 'درآمد'),
    _LegendItem(color: context.pal.warning, label: 'هزینه'),
  ]);
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(fontSize: 10, color: context.pal.textSecondary)),
  ]);
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color, this.money = false});
  final String label;
  final num value;
  final List<List<dynamic>> icon;
  final Color color;
  final bool money;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      width: 164,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: pal.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HugeIcon(icon: icon, color: color, size: 25),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          key: ValueKey('$label-$value'),
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, current, _) => Text(
            money ? Fmt.compactMoney(current.round()) : FaNum.ofInt(current.round()),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: pal.textPrimary),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: pal.textMuted)),
      ]),
    );
  }
}

class _RankedList extends StatelessWidget {
  const _RankedList({required this.items, required this.color});
  final List<RevenuePoint> items;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    if (items.isEmpty) return const EmptyState(compact: true, title: 'داده‌ای موجود نیست', description: '');
    final maxValue = items.map((item) => item.value).reduce((a, b) => a > b ? a : b);
    return Column(children: [
      for (var i = 0; i < items.length; i++)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 18, height: 18, alignment: Alignment.center, decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
              child: Text(FaNum.ofInt(i + 1), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color))),
            const SizedBox(width: 6),
            Expanded(child: Text(items[i].label, style: TextStyle(fontSize: 11.5, color: pal.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(Fmt.compactMoney(items[i].value), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: pal.textPrimary)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
            value: maxValue == 0 ? 0 : items[i].value / maxValue,
            minHeight: 5, backgroundColor: pal.surfaceAlt, valueColor: AlwaysStoppedAnimation(color),
          )),
        ])),
    ]);
  }
}

class _RecentAppointments extends StatelessWidget {
  const _RecentAppointments({required this.items});
  final List<Appointment> items;
  @override
  Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const SectionHeader(title: 'آخرین نوبت‌های بازه'),
    const SizedBox(height: 8),
    if (items.isEmpty) const EmptyState(compact: true, title: 'نوبتی در این بازه ثبت نشده')
    else for (final item in items)
      ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: HugeIcon(icon: HugeIcons.strokeRoundedAppointment01, color: item.status.color, size: 19),
        title: Text(item.customerName, style: const TextStyle(fontSize: 12)),
        subtitle: Text('${item.serviceName} · ${JalaliDate.fromDateTime(item.startAt).short}', style: const TextStyle(fontSize: 10)),
        trailing: StatusBadge.appointment(item.status, dense: true),
      ),
  ]));
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions({required this.items});
  final List<EmployeeWalletTransaction> items;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader(title: 'آخرین تراکنش‌های حقوقی'),
      const SizedBox(height: 8),
      if (items.isEmpty) const EmptyState(compact: true, title: 'تراکنش قابل نمایشی وجود ندارد')
      else for (final item in items)
        ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          leading: HugeIcon(icon: HugeIcons.strokeRoundedWallet01, color: item.amount >= 0 ? pal.success : pal.danger, size: 20),
          title: Text(item.description, style: const TextStyle(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${item.type.label} · ${JalaliDate.fromDateTime(item.createdAt).short}', style: TextStyle(fontSize: 10, color: pal.textMuted)),
          trailing: Text(Fmt.compactMoney(item.amount.abs()), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: item.amount >= 0 ? pal.success : pal.danger)),
        ),
    ]));
  }
}
