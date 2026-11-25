import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
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
import '../../../../data/models/appointment.dart';
import '../../../../data/models/customer.dart';
import '../../../../data/models/business_finance.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../../../../data/models/employee_wallet.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../data/repositories/business_finance_repository.dart';
import '../../../../data/repositories/appointment_repository.dart';
import '../../../employees/presentation/providers/employees_provider.dart';
import '../../../services/presentation/providers/services_provider.dart';
import '../../../customers/presentation/providers/customers_provider.dart';
import '../providers/reports_provider.dart';
import '../widgets/revenue_chart.dart';
import '../widgets/operational_reports_sections.dart';
import '../widgets/reports_phase_five_panel.dart';

bool _hasFinancePermission(SupabaseAuthStateNotifier? auth, String permission) =>
    auth != null && auth.hasActiveBusiness && (auth.role == 'owner' || auth.permissions[permission] == true);

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
    final auth = context.watch<SupabaseAuthStateNotifier?>();
    final employeesProvider = context.watch<EmployeesProvider?>();
    final servicesProvider = context.watch<ServicesProvider?>();
    final customersProvider = context.watch<CustomersProvider?>();
    final financeRepository = context.read<BusinessFinanceRepository?>();
    final appointmentRepository = context.read<AppointmentRepository?>();
    final dayIso = GoRouterState.of(context).uri.queryParameters['date'];
    final selectedDay = dayIso == null ? null : JalaliDate.parseIso(dayIso);
    final canViewAll = _hasFinancePermission(auth, 'appointments.view_all');
    final canViewOperations = canViewAll || _hasFinancePermission(auth, 'appointments.view_self');
    final visibleAppointments = canViewOperations
      ? provider.analytics.operationalAppointments
      : <Appointment>[];
    final availableEmployees = employeesProvider?.items ?? [];
    final availableServices = servicesProvider?.items ?? [];
    final visibleCustomerIds = visibleAppointments.map((item) => item.customerId).toSet();
    final availableCategories = <String>{
      if (canViewOperations) ...availableServices.map((service) => service.category),
      if (canViewOperations) ...visibleAppointments.expand((appointment) => appointment.serviceSnapshots
        .map((snapshot) => snapshot['category']).whereType<String>()),
    }.toList()..sort();
    final availableCustomers = !canViewOperations || !_hasFinancePermission(auth, 'customers.view')
      ? (customersProvider?.items ?? []).where((_) => false).toList()
      : canViewAll
        ? (customersProvider?.items ?? const <Customer>[])
        : (customersProvider?.items ?? const <Customer>[]).where((item) => visibleCustomerIds.contains(item.id)).toList();
    final dayAppointments = selectedDay == null ? const <Appointment>[] :
      visibleAppointments.where((item) => item.jalali.sameDay(selectedDay) && provider.filter.matches(item)).toList();
    final dayCompleted = dayAppointments.where((item) => item.status == AppointmentStatus.completed);
    final dayPayments = provider.analytics.paymentTransactions.where((item) =>
      selectedDay != null && JalaliDate.fromDateTime(item.createdAt).sameDay(selectedDay)).toList();
    final dayRevenue = dayPayments.fold<num>(0, (sum, item) => sum + item.signedAmount);
    final dayOperatingExpenses = provider.analytics.businessExpenses.where((item) =>
      selectedDay != null &&
      JalaliDate.fromDateTime(item.expenseDate ?? item.createdAt).sameDay(selectedDay) &&
      item.status == BusinessExpenseStatus.posted).toList();
    final dayOperatingExpense = dayOperatingExpenses.fold<num>(0, (sum, item) => sum + item.amount);
    final dayTotalExpense = dayOperatingExpense;
    final dayEmployeeTotals = <String, ({int count, num revenue})>{};
    for (final item in dayCompleted.where((item) => availableEmployees.any((employee) => employee.id == item.employeeId))) {
      final current = dayEmployeeTotals[item.employeeName];
      final revenue = dayPayments.where((payment) => payment.appointmentId == item.id)
        .fold<int>(0, (sum, payment) => sum + payment.signedAmount);
      dayEmployeeTotals[item.employeeName] = (count: (current?.count ?? 0) + 1, revenue: (current?.revenue ?? 0) + revenue);
    }

    return PageScaffold(
      title: 'گزارش‌ها و تحلیل',
      subtitle: 'نمای یکپارچه عملکرد مالی و عملیاتی مجموعه',
      leading: const HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, size: 22),
      actions: [
        if (financeRepository != null && appointmentRepository != null && _hasFinancePermission(auth, 'finance.manage') && canViewOperations && _hasFinancePermission(auth, 'customers.view'))
          SoftButton(label: 'ثبت دریافت', onTap: () => showDialog<void>(context: context, builder: (_) => _AddAppointmentPaymentDialog(repository: financeRepository, appointmentsRepository: appointmentRepository))),
        if (financeRepository != null && _hasFinancePermission(auth, 'finance.manage'))
          SoftButton(label: 'ثبت هزینه', onTap: () => showDialog<void>(context: context, builder: (_) => _AddBusinessExpenseDialog(repository: financeRepository))),
        if (financeRepository != null && (_hasFinancePermission(auth, 'finance.view') || _hasFinancePermission(auth, 'finance.manage')))
          SoftButton(label: 'اسناد مالی', onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: context.pal.surface,
            builder: (_) => _FinanceDocumentsSheet(
              repository: financeRepository,
              appointments: visibleAppointments,
              customers: availableCustomers,
              canManage: _hasFinancePermission(auth, 'finance.manage'),
            ),
          )),
        if (_hasFinancePermission(auth, 'employees.view_list') || canViewOperations)
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
                            Material(color: Colors.transparent, child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(item.status.icon, color: item.status.color),
                              title: Text(item.customerName),
                              subtitle: Text('${item.serviceName} · ${item.startAt.hour.toString().padLeft(2, '0')}:${item.startAt.minute.toString().padLeft(2, '0')}'),
                              trailing: StatusBadge.appointment(item.status, dense: true),
                            )),
                        const Divider(height: 18),
                        Text('هزینه‌های عملیاتی از اسناد ثبت‌شده مجموعه محاسبه شده‌اند.',
                          style: TextStyle(fontSize: 10, color: pal.textMuted)),
                        const SizedBox(height: 8),
                        const SectionHeader(title: 'عملکرد پرسنل در این روز'),
                        if (dayEmployeeTotals.isEmpty)
                          const EmptyState(title: 'عملکردی برای نمایش وجود ندارد', compact: true)
                        else
                          for (final entry in dayEmployeeTotals.entries)
                            Material(color: Colors.transparent, child: ListTile(
                              dense: true, contentPadding: EdgeInsets.zero,
                              leading: const HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 18),
                              title: Text(entry.key, style: const TextStyle(fontSize: 11)),
                              subtitle: Text('${FaNum.ofInt(entry.value.count)} نوبت تکمیل‌شده', style: const TextStyle(fontSize: 9)),
                              trailing: Text(Fmt.compactMoney(entry.value.revenue), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                            )),
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
                              for (final item in availableServices)
                                DropdownMenuItem<String?>(value: item.id, child: Text(item.title, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (value) => provider.setFilters(serviceId: value, clearService: value == null),
                          )),
                          if (_hasFinancePermission(auth, 'employees.view_list') || _hasFinancePermission(auth, 'finance.view')) SizedBox(width: width, child: DropdownButtonFormField<String?>(
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
                          if (canViewOperations && _hasFinancePermission(auth, 'customers.view')) SizedBox(width: width, child: DropdownButtonFormField<String?>(
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
                          if (_hasFinancePermission(auth, 'finance.settlement.view')) SizedBox(width: width, child: DropdownButtonFormField<EmployeeWalletSettlementStatus?>(
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
                    ExpansionPanelList.radio(
                      elevation: 0,
                      expandedHeaderPadding: const EdgeInsets.symmetric(vertical: 4),
                                                                  children: [
                        ExpansionPanelRadio(
                          value: 'salon', canTapOnHeader: true,
                          headerBuilder: (context, expanded) => const ListTile(
                            leading: HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, size: 21),
                            title: Text('گزارش سالن', style: TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('شاخص‌های مالی، نمودارها، خدمات و وضعیت نوبت‌ها'),
                          ),
                          body: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              ReportsPhaseFivePanel(provider: provider),
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
                        GestureDetector(onTap: () => _showPaymentSheet(context, provider, auth!, financeRepository!), child: _MetricCard(label: 'وصول‌شده', value: provider.analytics.collectedRevenue, money: true, icon: HugeIcons.strokeRoundedWallet01, color: pal.info)),
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
                          'مانده قابل پرداخت کیف پول پرسنل: ${Fmt.compactMoney(provider.analytics.staffPayable)}',
                          'بدهی پرسنل: ${Fmt.compactMoney(provider.analytics.staffDebt)}',
                          'مساعده باز: ${Fmt.compactMoney(provider.analytics.advancesOutstanding)}',
                        ]), child: _MetricCard(label: 'حقوق پرداختی', value: provider.analytics.staffPaid, money: true, icon: HugeIcons.strokeRoundedWallet01, color: pal.info)),
                        _MetricCard(label: 'حاشیه سود', value: provider.analytics.profitMarginPercent, icon: HugeIcons.strokeRoundedChartLineData01, color: pal.success),
                        GestureDetector(onTap: () => _showFinanceSheet(context, 'مانده پرداخت پرسنل', [
                          'مانده قابل پرداخت: ${Fmt.compactMoney(provider.analytics.staffPayable)}',
                          'بدهی پرسنل: ${Fmt.compactMoney(provider.analytics.staffDebt)}',
                          'پرداخت‌شده در بازه: ${Fmt.compactMoney(provider.analytics.staffPaid)}',
                          'مساعده باز: ${Fmt.compactMoney(provider.analytics.advancesOutstanding)}',
                          for (final item in provider.analytics.settlements) '${item.receiptNumber} · ${Fmt.compactMoney(item.paidAmount)} · ${item.status.name}',
                        ]), child: _MetricCard(label: 'مانده پرسنل', value: provider.analytics.staffPayable, money: true, icon: HugeIcons.strokeRoundedUser, color: pal.purple)),
                        _MetricCard(label: 'بدهی پرسنل', value: provider.analytics.staffDebt, money: true, icon: HugeIcons.strokeRoundedWallet01, color: pal.danger),
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
                                  onTap: () => _showPaymentSheet(context, provider, auth!, financeRepository!, method: item.key),
                                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                                    Expanded(child: Text(item.key, style: TextStyle(fontSize: 10.5, color: pal.textSecondary))),
                                    Text(Fmt.compactMoney(item.value), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: pal.textPrimary)),
                                  ])),
                                ),
                            ]);
                            final donut = StatusDonut(counts: {for (final item in methodEntries) item.key: item.value.round()}, centerLabel: 'وصول', size: 118, onSegmentTap: (method) => _showPaymentSheet(context, provider, auth!, financeRepository!, method: method));
                            if (inner.maxWidth < 340) return Column(children: [Center(child: donut), const SizedBox(height: 8), legend]);
                            return Row(children: [donut, const SizedBox(width: 12), Expanded(child: legend)]);
                          }),
                        ]));
                        final expenseCard = AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const SectionHeader(title: 'ترکیب هزینه‌ها', subtitle: 'هر قلم فقط از منبع اصلی خودش شمرده شده است'),
                          const SizedBox(height: 8),
                          for (final item in provider.analytics.expensesByCategory.entries.where((item) => item.value != 0))
                            InkWell(
                              onTap: () => _showBusinessExpensesSheet(context, financeRepository!, provider, item.key),
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
                        LayoutBuilder(builder: (context, inner) {
                          final legend = Column(children: [
                            for (final status in AppointmentStatus.values)
                              Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
                                Container(width: 7, height: 7, decoration: BoxDecoration(color: status.color, shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Expanded(child: Text(status.label, style: TextStyle(fontSize: 10.5, color: pal.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                Text(FaNum.ofInt(provider.statusCounts[status.label] ?? 0), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pal.textPrimary)),
                              ])),
                          ]);
                          if (inner.maxWidth < 340) {
                            return Column(children: [
                              Center(child: StatusDonut(counts: provider.statusCounts, size: 126)),
                              const SizedBox(height: 10),
                              legend,
                            ]);
                          }
                          return Row(children: [
                            StatusDonut(counts: provider.statusCounts, size: 126),
                            const SizedBox(width: 10),
                            Expanded(child: legend),
                          ]);
                        }),
                      ]));

                      final serviceCard = AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SectionHeader(title: 'خدمات پرفروش'),
                        const SizedBox(height: 12),
                        _RankedList(items: provider.serviceRevenue, color: pal.success),
                      ]));
                      if (!wide) return Column(children: [
                        if (canViewOperations) statusCard,
                        if (canViewOperations) const SizedBox(height: 12),
                        if (canViewOperations) serviceCard,
                      ]);
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 4, child: statusCard),
                        const SizedBox(width: 12),
                        Expanded(flex: 5, child: serviceCard),
                      ]);
                    }),
                    const SizedBox(height: 12),
                    if (canViewOperations)
                      OperationalReportsSections(analytics: provider.analytics, provider: provider)
                    else
                      AppCard(child: Text('دسترسی به جزئیات نوبت‌ها و گزارش‌های عملیاتی برای نقش فعلی فعال نیست؛ گزارش‌های مالی مطابق مجوز شما نمایش داده می‌شوند.',
                        style: TextStyle(fontSize: 11, color: pal.textMuted))),
                    const SizedBox(height: 12),
                            ])),
                        ),
                        ExpansionPanelRadio(
                          value: 'personnel', canTapOnHeader: true,
                          headerBuilder: (context, expanded) => const ListTile(
                            leading: HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 21),
                            title: Text('گزارش پرسنل', style: TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('عملکرد و درآمد خدمات پرسنل'),
                          ),
                          body: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const SectionHeader(title: 'عملکرد پرسنل', subtitle: 'درآمد خدمات و کمیسیون ثبت‌شده'),
                              const SizedBox(height: 12),
                              _RankedList(items: [
                                for (final item in provider.analytics.employees)
                                  RevenuePoint(label: item.name, value: item.revenue),
                              ], color: pal.primaryBright),
                            ]))),
                        ),
                        ExpansionPanelRadio(
                          value: 'pdf', canTapOnHeader: true,
                          headerBuilder: (context, expanded) => const ListTile(
                            leading: HugeIcon(icon: HugeIcons.strokeRoundedChartLineData01, size: 21),
                            title: Text('خروجی PDF', style: TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('ذخیره گزارش در قالب PDF'),
                          ),
                          body: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: ReportsPhaseFivePanel(provider: provider, exportOnly: true)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (canViewOperations)
                      _BusyHoursCard(items: provider.analytics.operationalAppointments),
                    if (canViewOperations || _hasFinancePermission(auth, 'finance.salary.view'))
                      _RecentTransactions(items: provider.analytics.recentTransactions, appointments: provider.analytics.operationalAppointments),
                  ],
                ),
    );
  }
}




class _AddAppointmentPaymentDialog extends StatefulWidget {
  const _AddAppointmentPaymentDialog({
    required this.repository,
    required this.appointmentsRepository,
  });
  final BusinessFinanceRepository repository;
  final AppointmentRepository appointmentsRepository;

  @override
  State<_AddAppointmentPaymentDialog> createState() => _AddAppointmentPaymentDialogState();
}

class _AddAppointmentPaymentDialogState extends State<_AddAppointmentPaymentDialog> {
  late final String _operationKey = 'receipt-${DateTime.now().microsecondsSinceEpoch}';
  final _amount = TextEditingController();
  final _description = TextEditingController(text: 'دریافت وجه نوبت');
  List<Appointment> _appointments = const [];
  List<AppointmentPayment> _payments = const [];
  Appointment? _selected;
  BusinessPaymentMethod _method = BusinessPaymentMethod.pos;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  int _outstanding(Appointment appointment) {
    final paid = _payments.where((payment) => payment.appointmentId == appointment.id)
        .fold<int>(0, (sum, payment) => sum + payment.signedAmount);
    return (appointment.price.round() - paid).clamp(0, 1 << 62);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<dynamic>([
        widget.appointmentsRepository.fetchAll(),
        widget.repository.fetchPayments(),
      ]);
      if (!mounted) return;
      _payments = values[1] as List<AppointmentPayment>;
      _appointments = (values[0] as List<Appointment>)
          .where((item) => item.status == AppointmentStatus.completed && _outstanding(item) > 0)
          .toList(growable: false);
      _selected = _appointments.isEmpty ? null : _appointments.first;
    } catch (error) {
      if (mounted) _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(FaNum.toLatin(_amount.text).replaceAll(RegExp(r'[^0-9]'), ''));
    if (_selected == null || amount == null || amount <= 0 ||
        amount > _outstanding(_selected!) || _description.text.trim().isEmpty) {
      setState(() => _error = 'نوبت، مبلغ معتبر در محدوده مانده و شرح پرداخت را کامل کنید.');
      return;
    }
    final appointment = _selected!;
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید ثبت دریافت مشتری',
      description: 'رسید دریافت به دفتر مالی Supabase افزوده می‌شود و رسید قبلی حذف یا بازنویسی نخواهد شد.',
      recordDetails: {
        'کد نوبت': appointment.reference,
        'مشتری': appointment.customerName,
        'مبلغ دریافت': '${FaNum.ofInt(amount)} تومان',
        'روش پرداخت': _method.label,
        'شرح': _description.text.trim(),
      },
      isReversible: false,
      warning: 'اصلاح دریافت فقط از طریق ثبت برگشت وجه مرتبط با رسید اصلی انجام می‌شود.',
      confirmLabel: 'ثبت رسید دریافت',
    );
    if (!approved || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repository.recordAppointmentPayment(
        appointmentId: appointment.id,
        amount: amount,
        method: _method,
        description: _description.text.trim(),
        idempotencyKey: _operationKey,
      );
      if (mounted) {
        context.read<ReportsProvider>().load();
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ثبت دریافت مشتری'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_loading)
        const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())
      else if (_error != null && _appointments.isEmpty)
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11))
      else if (_appointments.isEmpty)
        const Text('نوبت تکمیل‌شده با مانده قابل دریافت در داده‌های واقعی وجود ندارد.')
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
      if (_error != null && _appointments.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11))),
    ])),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('انصراف')),
      FilledButton(onPressed: _loading || _saving || _appointments.isEmpty ? null : _save, child: Text(_saving ? 'در حال ثبت…' : 'ثبت دریافت')),
    ],
  );
}

class _AddBusinessExpenseDialog extends StatefulWidget {
  const _AddBusinessExpenseDialog({required this.repository});
  final BusinessFinanceRepository repository;

  @override
  State<_AddBusinessExpenseDialog> createState() => _AddBusinessExpenseDialogState();
}

class _AddBusinessExpenseDialogState extends State<_AddBusinessExpenseDialog> {
  late final String _idempotencyKey = 'expense-${DateTime.now().microsecondsSinceEpoch}';
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _source = TextEditingController();
  BusinessExpenseCategory _category = BusinessExpenseCategory.operating;
  BusinessPaymentMethod? _method = BusinessPaymentMethod.bankTransfer;
  bool _saving = false;
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
    if (amount == null || amount <= 0 || _description.text.trim().isEmpty) {
      setState(() => _error = 'مبلغ و شرح هزینه را کامل و معتبر وارد کنید.');
      return;
    }
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید ثبت هزینه مجموعه',
      description: 'هزینه در دفتر مالی واقعی مجموعه ثبت می‌شود و سابقه آن قابل حذف فیزیکی نیست.',
      recordDetails: {
        'دسته‌بندی': _category.label,
        'مبلغ': '${FaNum.ofInt(amount)} تومان',
        'روش پرداخت': _method?.label ?? 'ثبت‌نشده',
        'شرح': _description.text.trim(),
        if (_source.text.trim().isNotEmpty) 'شناسه مرجع': _source.text.trim(),
      },
      isReversible: false,
      warning: 'اصلاح هزینه با ابطال مستند و ثبت رویداد حسابرسی انجام می‌شود.',
      confirmLabel: 'ثبت هزینه',
    );
    if (!approved || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repository.recordBusinessExpense(
        amount: amount,
        category: _category,
        description: _description.text.trim(),
        expenseDate: DateTime.now(),
        paymentMethod: _method,
        sourceDocumentId: _source.text.trim().isEmpty ? null : _source.text.trim(),
        idempotencyKey: _idempotencyKey,
      );
      if (mounted) {
        context.read<ReportsProvider>().load();
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
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
      DropdownButtonFormField<BusinessPaymentMethod?>(
        value: _method,
        decoration: const InputDecoration(labelText: 'روش پرداخت'),
        items: [
          const DropdownMenuItem<BusinessPaymentMethod?>(value: null, child: Text('ثبت‌نشده')),
          for (final item in BusinessPaymentMethod.values) DropdownMenuItem(value: item, child: Text(item.label)),
        ],
        onChanged: (value) => setState(() => _method = value),
      ),
      const SizedBox(height: 8),
      TextField(controller: _description, decoration: const InputDecoration(labelText: 'شرح هزینه')),
      const SizedBox(height: 8),
      TextField(controller: _source, decoration: const InputDecoration(labelText: 'شماره مرجع (اختیاری)')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11))),
    ])),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('انصراف')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'در حال ثبت…' : 'ثبت هزینه')),
    ],
  );
}

void _showPaymentSheet(BuildContext context, ReportsProvider provider, SupabaseAuthStateNotifier auth, BusinessFinanceRepository financeRepository, {String? method}) {
  final payments = provider.analytics.paymentTransactions.where((item) => method == null || item.method.label == method).toList();
  final appointments = provider.analytics.operationalAppointments;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.pal.surface,
    builder: (sheetContext) => SafeArea(child: SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.65,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(title: method == null ? 'رسیدها و برگشت وجه' : 'پرداخت‌های $method', subtitle: 'رسیدهای واقعی این بازه؛ استرداد به رسید اصلی متصل می‌شود'),
          const SizedBox(height: 8),
          Expanded(child: payments.isEmpty
            ? const EmptyState(title: 'پرداختی در این بازه وجود ندارد', compact: true)
            : ListView.separated(
                itemCount: payments.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final payment = payments[index];
                  final matches = appointments.where((item) => item.id == payment.appointmentId).toList();
                  final appointment = matches.isEmpty ? null : matches.first;
                  return Material(color: Colors.transparent, child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('جزئیات تراکنش'),
                        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('شناسه رسید: ${payment.id}'),
                          Text('تاریخ: ${JalaliDate.fromDateTime(payment.createdAt).long}'),
                          Text('نوع: ${payment.type == BusinessPaymentType.refund ? 'برگشت وجه' : 'دریافت'}'),
                          Text('روش: ${payment.method.label}'),
                          Text('مبلغ: ${Fmt.compactMoney(payment.signedAmount)}'),
                          if (_hasFinancePermission(auth, 'customers.view') && appointment != null)
                            Text('مشتری: ${appointment.customerName}'),
                          Text('شرح: ${payment.description}'),
                        ]),
                        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
                      ),
                    ),
                    title: Text(payment.description, style: const TextStyle(fontSize: 12)),
                    subtitle: Text('${JalaliDate.fromDateTime(payment.createdAt).short} · ${payment.method.label} · ${payment.type == BusinessPaymentType.refund ? 'برگشت وجه' : 'دریافت'}', style: const TextStyle(fontSize: 10)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(Fmt.compactMoney(payment.signedAmount), style: TextStyle(
                        color: payment.signedAmount < 0 ? context.pal.danger : context.pal.success, fontSize: 11)),
                      if (payment.type == BusinessPaymentType.receipt && _hasFinancePermission(auth, 'finance.manage'))
                        TextButton(onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => _RefundPaymentDialog(repository: financeRepository, payment: payment),
                        ), child: const Text('برگشت وجه')),
                    ]),
                  ));
                },
              )),
        ]),
      ),
    )),
  );
}

class _RefundPaymentDialog extends StatefulWidget {
  const _RefundPaymentDialog({required this.repository, required this.payment});
  final BusinessFinanceRepository repository;
  final AppointmentPayment payment;

  @override
  State<_RefundPaymentDialog> createState() => _RefundPaymentDialogState();
}

class _RefundPaymentDialogState extends State<_RefundPaymentDialog> {
  late final String _operationKey = 'refund-${widget.payment.id}-${DateTime.now().microsecondsSinceEpoch}';
  final _amount = TextEditingController();
  final _description = TextEditingController(text: 'برگشت وجه مشتری');
  bool _saving = false;
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
      description: 'سند استرداد جدید به رسید اصلی متصل می‌شود و رسید اولیه تغییر نمی‌کند.',
      recordDetails: {
        'شناسه رسید': widget.payment.id,
        'مبلغ برگشتی': '${FaNum.ofInt(amount)} تومان',
        'روش پرداخت': widget.payment.method.label,
        'شرح': _description.text.trim(),
      },
      isReversible: false,
      warning: 'مجموع استردادها در دیتابیس کنترل می‌شود و از مبلغ رسید اصلی بیشتر نخواهد شد.',
      confirmLabel: 'ثبت برگشت وجه',
    );
    if (!approved || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repository.recordAppointmentPayment(
        appointmentId: widget.payment.appointmentId,
        amount: amount,
        method: widget.payment.method,
        description: _description.text.trim(),
        idempotencyKey: _operationKey,
        type: BusinessPaymentType.refund,
        reversesPaymentId: widget.payment.id,
      );
      if (mounted) {
        context.read<ReportsProvider>().load();
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
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
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('انصراف')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'در حال ثبت…' : 'ثبت برگشت')),
    ],
  );
}

void _showBusinessExpensesSheet(
  BuildContext context,
  BusinessFinanceRepository repository,
  ReportsProvider provider,
  String categoryLabel,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.pal.surface,
    builder: (_) => _BusinessExpensesSheet(
      repository: repository,
      provider: provider,
      categoryLabel: categoryLabel,
    ),
  );
}

class _BusinessExpensesSheet extends StatefulWidget {
  const _BusinessExpensesSheet({
    required this.repository,
    required this.provider,
    required this.categoryLabel,
  });
  final BusinessFinanceRepository repository;
  final ReportsProvider provider;
  final String categoryLabel;

  @override
  State<_BusinessExpensesSheet> createState() => _BusinessExpensesSheetState();
}

class _BusinessExpensesSheetState extends State<_BusinessExpensesSheet> {
  List<BusinessExpense> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await widget.repository.fetchExpenses();
      if (!mounted) return;
      _items = items.where((item) => item.category.label == widget.categoryLabel).toList();
    } catch (error) {
      if (mounted) _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reverse(BusinessExpense expense) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ابطال سند هزینه'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('هزینه «${expense.description}» با مبلغ ${Fmt.compactMoney(expense.amount)} ابطال شود؟'),
          TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'علت ابطال (اجباری)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, reason.text.trim()), child: const Text('تأیید ابطال')),
        ],
      ),
    );
    reason.dispose();
    if (value == null || value.length < 3 || !mounted) return;
    try {
      await widget.repository.reverseBusinessExpense(expenseId: expense.id, reason: value);
      await widget.provider.load();
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ابطال سند ناموفق بود: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(title: 'هزینه‌های ${widget.categoryLabel}', subtitle: 'اسناد ابطال‌شده نیز برای حفظ سابقه نمایش داده می‌شوند'),
          const SizedBox(height: 10),
          if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null) Expanded(child: Center(child: Text(_error!, textAlign: TextAlign.center)))
          else if (_items.isEmpty) const Expanded(child: EmptyState(title: 'هزینه‌ای برای این دسته ثبت نشده است'))
          else Expanded(child: ListView.separated(
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final expense = _items[index];
              final canManage = _hasFinancePermission(context.read<SupabaseAuthStateNotifier?>(), 'finance.manage');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(expense.description),
                subtitle: Text('${JalaliDate.fromDateTime(expense.expenseDate ?? expense.createdAt).short} · ${expense.paymentMethod?.label ?? 'روش ثبت‌نشده'} · ${expense.status == BusinessExpenseStatus.reversed ? 'ابطال‌شده' : 'ثبت‌شده'}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(Fmt.compactMoney(expense.amount), style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: expense.status == BusinessExpenseStatus.reversed ? context.pal.textMuted : context.pal.warning,
                  )),
                  if (canManage && expense.status == BusinessExpenseStatus.posted)
                    IconButton(
                      tooltip: 'ابطال سند',
                      onPressed: () => _reverse(expense),
                      icon: const Icon(Icons.block_rounded),
                    ),
                ]),
              );
            },
          )),
        ]),
      ),
    ),
  );
}

class _FinanceDocumentsSheet extends StatefulWidget {
  const _FinanceDocumentsSheet({
    required this.repository,
    required this.appointments,
    required this.customers,
    required this.canManage,
  });
  final BusinessFinanceRepository repository;
  final List<Appointment> appointments;
  final List<Customer> customers;
  final bool canManage;

  @override
  State<_FinanceDocumentsSheet> createState() => _FinanceDocumentsSheetState();
}

class _FinanceDocumentsSheetState extends State<_FinanceDocumentsSheet> {
  List<BusinessFinanceDocument> _documents = const [];
  List<BusinessExpense> _expenses = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final values = await Future.wait<dynamic>([
        widget.repository.fetchDocuments(activeOnly: false),
        widget.repository.fetchExpenses(),
      ]);
      if (!mounted) return;
      _documents = values[0] as List<BusinessFinanceDocument>;
      _expenses = values[1] as List<BusinessExpense>;
    } catch (error) {
      if (mounted) _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addDocument() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UploadFinanceDocumentDialog(
        repository: widget.repository,
        appointments: widget.appointments,
        customers: widget.customers,
        expenses: _expenses,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _voidDocument(BusinessFinanceDocument document) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ابطال سند مالی'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('سند «${document.fileName ?? document.documentType}» باطل شود؟ فایل حذف فیزیکی نمی‌شود.'),
          TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'علت ابطال (اجباری)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, reason.text.trim()), child: const Text('تأیید ابطال')),
        ],
      ),
    );
    reason.dispose();
    if (value == null || value.length < 3 || !mounted) return;
    try {
      await widget.repository.voidDocument(documentId: document.id, reason: value);
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ابطال سند ناموفق بود: $error')));
    }
  }

  Future<void> _copySignedUrl(BusinessFinanceDocument document) async {
    final path = document.storagePath;
    if (path == null) return;
    try {
      final url = await widget.repository.createDocumentDownloadUrl(path);
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('پیوند موقت سند کپی شد؛ این پیوند پس از چند دقیقه منقضی می‌شود.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('دریافت پیوند سند ناموفق بود: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: SectionHeader(title: 'اسناد مالی', subtitle: 'فایل‌ها به نوبت، مشتری یا هزینه واقعی متصل می‌شوند')),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
            FilledButton.icon(onPressed: _addDocument, icon: const Icon(Icons.attach_file_rounded), label: const Text('افزودن سند')),
          ]),
          const SizedBox(height: 10),
          if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null) Expanded(child: Center(child: Text(_error!, textAlign: TextAlign.center)))
          else if (_documents.isEmpty) const Expanded(child: EmptyState(title: 'سند مالی ثبت‌شده‌ای وجود ندارد', description: 'سند جدید را به یکی از رکوردهای واقعی متصل کنید.'))
          else Expanded(child: ListView.separated(
            itemCount: _documents.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final document = _documents[index];
              final source = document.expenseId != null
                  ? 'هزینه ${document.expenseId}'
                  : document.appointmentId != null
                      ? 'نوبت ${document.appointmentId}'
                      : 'مشتری ${document.customerId ?? ''}';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(document.status == 'active' ? Icons.description_outlined : Icons.description),
                title: Text(document.fileName ?? document.documentNumber ?? document.documentType),
                subtitle: Text('${document.documentType} · $source · ${JalaliDate.fromDateTime(document.createdAt).short}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (document.storagePath != null)
                    IconButton(onPressed: () => _copySignedUrl(document), icon: const Icon(Icons.link_rounded)),
                  if (widget.canManage && document.status == 'active')
                    IconButton(onPressed: () => _voidDocument(document), icon: const Icon(Icons.block_rounded), tooltip: 'ابطال سند'),
                ]),
              );
            },
          )),
        ]),
      ),
    ),
  );
}

class _UploadFinanceDocumentDialog extends StatefulWidget {
  const _UploadFinanceDocumentDialog({
    required this.repository,
    required this.appointments,
    required this.customers,
    required this.expenses,
  });
  final BusinessFinanceRepository repository;
  final List<Appointment> appointments;
  final List<Customer> customers;
  final List<BusinessExpense> expenses;

  @override
  State<_UploadFinanceDocumentDialog> createState() => _UploadFinanceDocumentDialogState();
}

class _UploadFinanceDocumentDialogState extends State<_UploadFinanceDocumentDialog> {
  String _documentType = 'invoice';
  String _sourceType = 'appointment';
  String? _sourceId;
  String _documentNumber = '';
  String _notes = '';
  String? _fileName;
  String? _mimeType;
  Uint8List? _bytes;
  bool _saving = false;
  String? _error;

  List<DropdownMenuItem<String>> get _sourceItems => switch (_sourceType) {
    'appointment' => [
      for (final item in widget.appointments)
        DropdownMenuItem(value: item.id, child: Text('${item.reference} · ${item.customerName} · ${item.serviceName}', overflow: TextOverflow.ellipsis)),
    ],
    'customer' => [
      for (final item in widget.customers)
        DropdownMenuItem(value: item.id, child: Text('${item.fullName} · ${item.phone}', overflow: TextOverflow.ellipsis)),
    ],
    _ => [
      for (final item in widget.expenses)
        DropdownMenuItem(value: item.id, child: Text('${item.description} · ${Fmt.compactMoney(item.amount)}', overflow: TextOverflow.ellipsis)),
    ],
  };

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf','jpg','jpeg','png','webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      final extension = file.extension?.toLowerCase();
      final mime = switch (extension) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => null,
      };
      if (mime == null || bytes == null || bytes.isEmpty || bytes.length > 26214400) {
        setState(() => _error = 'فقط PDF یا تصویر JPG/PNG/WEBP تا سقف ۲۵ مگابایت پذیرفته می‌شود.');
        return;
      }
      setState(() { _fileName = file.name; _mimeType = mime; _bytes = bytes; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = 'انتخاب فایل ناموفق بود: $error');
    }
  }

  Future<void> _save() async {
    if (_bytes == null || _fileName == null || _mimeType == null || _sourceId == null) {
      setState(() => _error = 'فایل و یک مرجع واقعی از نوع نوبت، مشتری یا هزینه را انتخاب کنید.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.repository.uploadDocument(
        bytes: _bytes!,
        fileName: _fileName!,
        mimeType: _mimeType!,
        documentType: _documentType,
        idempotencyKey: 'finance-doc-${DateTime.now().microsecondsSinceEpoch}',
        documentNumber: _documentNumber.trim().isEmpty ? null : _documentNumber.trim(),
        appointmentId: _sourceType == 'appointment' ? _sourceId : null,
        customerId: _sourceType == 'customer' ? _sourceId : null,
        expenseId: _sourceType == 'expense' ? _sourceId : null,
        notes: _notes,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('افزودن سند مالی'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(
        value: _documentType,
        decoration: const InputDecoration(labelText: 'نوع سند'),
        items: const [
          DropdownMenuItem(value: 'invoice', child: Text('فاکتور')),
          DropdownMenuItem(value: 'receipt', child: Text('رسید')),
          DropdownMenuItem(value: 'refund', child: Text('سند استرداد')),
          DropdownMenuItem(value: 'expense_receipt', child: Text('رسید هزینه')),
          DropdownMenuItem(value: 'discount_note', child: Text('سند تخفیف')),
          DropdownMenuItem(value: 'payment_proof', child: Text('مدرک پرداخت')),
          DropdownMenuItem(value: 'other', child: Text('سایر')),
        ],
        onChanged: (value) => setState(() => _documentType = value ?? _documentType),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _sourceType,
        decoration: const InputDecoration(labelText: 'اتصال سند به'),
        items: const [
          DropdownMenuItem(value: 'appointment', child: Text('نوبت')),
          DropdownMenuItem(value: 'customer', child: Text('مشتری')),
          DropdownMenuItem(value: 'expense', child: Text('هزینه')),
        ],
        onChanged: (value) => setState(() { _sourceType = value ?? _sourceType; _sourceId = null; }),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: _sourceId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'مرجع واقعی'),
        items: _sourceItems,
        onChanged: (value) => setState(() => _sourceId = value),
      ),
      const SizedBox(height: 8),
      TextField(
        decoration: const InputDecoration(labelText: 'شماره سند (اختیاری)'),
        onChanged: (value) => _documentNumber = value,
      ),
      const SizedBox(height: 8),
      TextField(
        decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
        onChanged: (value) => _notes = value,
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _saving ? null : _pickFile,
        icon: const Icon(Icons.attach_file_rounded),
        label: Text(_fileName ?? 'انتخاب فایل PDF یا تصویر'),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11))),
    ])),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('انصراف')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'در حال بارگذاری…' : 'ثبت سند')),
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

class _BusyHoursCard extends StatelessWidget {
  const _BusyHoursCard({required this.items});
  final List<Appointment> items;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final counts = <int, int>{};
    for (final item in items) {
      if (item.status == AppointmentStatus.cancelled || item.status == AppointmentStatus.noShow) continue;
      counts.update(item.startAt.hour, (value) => value + 1, ifAbsent: () => 1);
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return AppCard(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'ساعت‌های پرتردد', subtitle: 'بر اساس نوبت‌های بازه و فیلترهای انتخاب‌شده'),
        const SizedBox(height: 8),
        if (ranked.isEmpty)
          const EmptyState(title: 'داده‌ای برای تحلیل ساعت‌های پرتردد وجود ندارد', compact: true)
        else
          for (final entry in ranked.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 52, child: Text('${FaNum.convert(entry.key.toString().padLeft(2, '0'))}:۰۰',
                  style: TextStyle(fontSize: 11, color: pal.textSecondary, fontWeight: FontWeight.w700))),
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: entry.value / ranked.first.value,
                    minHeight: 8,
                    backgroundColor: pal.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(pal.primaryBright),
                  ),
                )),
                const SizedBox(width: 8),
                Text('${FaNum.ofInt(entry.value)} نوبت',
                  style: TextStyle(fontSize: 10, color: pal.textPrimary, fontWeight: FontWeight.w700)),
              ]),
            ),
      ],
    ));
  }
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions({required this.items, required this.appointments});
  final List<EmployeeWalletTransaction> items;
  final List<Appointment> appointments;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader(title: 'آخرین تراکنش‌های کیف پول'),
      const SizedBox(height: 8),
      if (items.isEmpty) const EmptyState(compact: true, title: 'تراکنش قابل نمایشی وجود ندارد')
      else for (final item in items)
        Material(color: Colors.transparent, child: ListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          onTap: () {
            final matches = item.appointmentId == null ? <Appointment>[] : appointments.where((value) => value.id == item.appointmentId).toList();
            final appointment = matches.isEmpty ? null : matches.first;
            showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
              title: const Text('جزئیات تراکنش کیف پول'),
              content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('نوع: ${item.type.label}'),
                Text('تاریخ: ${JalaliDate.fromDateTime(item.createdAt).long}'),
                Text('مبلغ: ${Fmt.compactMoney(item.amount)}'),
                Text('وضعیت: ${item.status.name}'),
                Text('شرح: ${item.description}'),
                if (item.settlementId != null) Text('شناسه تسویه: ${item.settlementId}'),
                if (item.sourceFinanceEntryId != null) Text('سند مالی منبع: ${item.sourceFinanceEntryId}'),
                if (item.paymentId != null) Text('شناسه رسید: ${item.paymentId}'),
                if (_hasFinancePermission(context.read<SupabaseAuthStateNotifier?>(), 'customers.view') && appointment != null)
                  Text('مشتری: ${appointment.customerName}'),
              ])),
              actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن'))],
            ));
          },
          leading: HugeIcon(icon: HugeIcons.strokeRoundedWallet01, color: item.amount >= 0 ? pal.success : pal.danger, size: 20),
          title: Text(item.description, style: const TextStyle(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${item.type.label} · ${JalaliDate.fromDateTime(item.createdAt).short}', style: TextStyle(fontSize: 10, color: pal.textMuted)),
          trailing: Text(Fmt.compactMoney(item.amount.abs()), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: item.amount >= 0 ? pal.success : pal.danger)),
        )),
    ]));
  }
}
