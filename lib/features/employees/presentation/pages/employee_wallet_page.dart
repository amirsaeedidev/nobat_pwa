import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/sensitive_operation_dialog.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee_wallet.dart';
import '../../../../data/repositories/operations_repository.dart';
import '../../../../data/repositories/employee_wallet_repository.dart';
import '../../../../data/services/employee_wallet_service.dart';

class EmployeeWalletPage extends StatefulWidget {
  const EmployeeWalletPage({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<EmployeeWalletPage> createState() => _EmployeeWalletPageState();
}

class _EmployeeWalletPageState extends State<EmployeeWalletPage> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  EmployeeWalletPeriodType _period = EmployeeWalletPeriodType.monthly;
  bool _isAddingTransaction = false;
  bool _isSettling = false;
  EmployeeWalletTransactionType? _typeFilter;

  DateTime get _endOfDay => DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999, 999);

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final employee = db.employeeById(widget.employeeId);
    final pal = context.pal;
    if (employee == null) {
      return PageScaffold(title: 'کیف پول و تسویه', showBackButton: true, child: const EmptyState(title: 'پرسنل یافت نشد'));
    }

    final walletService = EmployeeWalletService(EmployeeWalletRepository(db));
    final wallet = walletService.readWallet(employee.id);
    final summary = wallet.summary;
    final canViewSalary = db.hasPermission('finance.salary.view', employeeId: employee.id);
    final canViewAllSalary = db.hasPermission('finance.salary.view');
    final canViewSettlementHistory = canViewSalary && db.hasPermission('finance.settlement.view', employeeId: employee.id);
    final canSettle = canViewSalary && db.hasPermission('finance.payment.create', employeeId: employee.id);
    final canAddTransaction = db.hasPermission('finance.payment.create', employeeId: employee.id) ||
        db.hasPermission('finance.advance.create', employeeId: employee.id);
    final canAccruePayroll = canViewSalary && canSettle;
    final allEntries = walletService.readTransactions(employee.id, from: _from, to: _endOfDay);
    final entries = allEntries.where((entry) => _typeFilter == null || entry.type == _typeFilter).toList();
    final settlements = canViewSettlementHistory ? walletService.readSettlements(employee.id) : <EmployeeWalletSettlement>[];
    final payments = canViewSettlementHistory ? walletService.readPayments(employee.id) : <EmployeeWalletPayment>[];
    final periodDue = canSettle ? walletService.readPeriodDue(employee.id, _from, _endOfDay) : 0;
    final debtReport = canViewSalary && canViewAllSalary ? walletService.readDebtAndReceivables() : <EmployeeWallet>[];

    return PageScaffold(
      title: 'کیف پول و تسویه',
      subtitle: employee.fullName,
      showBackButton: true,
      mobileActions: [
        if (canAddTransaction) IconButton(tooltip: 'ثبت تراکنش', onPressed: () => _addTransaction(db, employee.id), icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 21)),
        if (canAccruePayroll) IconButton(tooltip: 'ثبت حقوق ماه جاری', onPressed: () => _accruePayroll(db, employee.id), icon: const HugeIcon(icon: HugeIcons.strokeRoundedPayment01, size: 21)),
        if (canSettle) IconButton(tooltip: 'ثبت تسویه', onPressed: () => _settle(db, employee.id), icon: const HugeIcon(icon: HugeIcons.strokeRoundedPayment01, size: 21)),
      ],
      actions: [
        if (canAddTransaction) SoftButton(label: 'ثبت تراکنش', onTap: () => _addTransaction(db, employee.id)),
        if (canAccruePayroll) SoftButton(label: 'ثبت حقوق ماه جاری', icon: Icons.account_balance_wallet_outlined, onTap: () => _accruePayroll(db, employee.id)),
        if (canSettle) SolidButton(label: 'ثبت تسویه', onPressed: () => _settle(db, employee.id)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            gradient: LinearGradient(
              colors: [pal.primary.withValues(alpha: 0.16), pal.surface],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader(title: 'مانده کیف پول', subtitle: 'محاسبه‌شده از مجموع اسناد قطعی دفتر کل'),
              const SizedBox(height: 8),
              Text(Fmt.money(summary.balance), style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: summary.balance < 0 ? pal.danger : pal.success)),
              const SizedBox(height: 4),
              Text(summary.balance < 0 ? 'بدهی / کسری حساب پرسنل' : 'مانده قابل پرداخت', style: TextStyle(fontSize: 11, color: pal.textMuted)),
              const Divider(height: 24),
              Wrap(spacing: 20, runSpacing: 14, children: [
                _WalletMetric(label: 'درآمد محاسبه‌شده', amount: summary.earned, color: pal.success),
                _WalletMetric(label: 'پرداخت‌های انجام‌شده', amount: summary.paid, color: pal.primaryBright),
                _WalletMetric(label: 'مساعده', amount: summary.advances, color: pal.warning),
                _WalletMetric(label: 'پاداش', amount: summary.bonuses, color: pal.success),
                _WalletMetric(label: 'بدهی و کسورات', amount: summary.debits, color: pal.danger),
                _WalletMetric(label: 'در انتظار تأیید', amount: summary.pending, color: pal.warning),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(title: canSettle ? 'بازه مالی و مبلغ قابل تسویه' : 'بازه مالی',
              subtitle: canSettle ? 'تسویه فقط با مجوز پرداخت و مشاهده حقوق فعال است.' : 'نمایش اطلاعات مطابق سطح دسترسی حساب فعال'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<EmployeeWalletPeriodType>(
                value: _period,
                items: [for (final item in EmployeeWalletPeriodType.values) DropdownMenuItem(value: item, child: Text(item.label))],
                onChanged: (value) { if (value != null) _selectPeriod(value); },
              ),
              OutlinedButton(
                onPressed: _chooseRange,
                child: SizedBox(
                  width: 210,
                  child: Row(children: [
                    const HugeIcon(icon: HugeIcons.strokeRoundedCalendarRange, size: 17),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      '${Fmt.jalaliDate(_from)} تا ${Fmt.jalaliDate(_to)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (canSettle) ...[
              Row(children: [
                Expanded(child: Text('قابل پرداخت در این بازه', style: TextStyle(fontSize: 12, color: pal.textMuted))),
                Text(Fmt.money(periodDue), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: periodDue > 0 ? pal.success : pal.textPrimary)),
              ]),
              const SizedBox(height: 10),
              SolidButton(label: periodDue > 0 ? 'تسویه این بازه' : 'مبلغی برای تسویه وجود ندارد',
                onPressed: periodDue > 0 && !_isSettling ? () => _settle(db, employee.id) : null),
            ] else
              Text('برای مشاهده مانده قابل تسویه و ثبت پرداخت، دسترسی حقوق و تسویه لازم است.',
                style: TextStyle(fontSize: 11, color: pal.textMuted)),
          ])),
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(title: 'دفتر کل تراکنش‌ها', subtitle: '${entries.length} سند از ${allEntries.length} سند در بازه انتخاب‌شده'),
            const SizedBox(height: 8),
            DropdownButtonFormField<EmployeeWalletTransactionType?>(
              value: _typeFilter, isExpanded: true,
              decoration: const InputDecoration(labelText: 'فیلتر نوع تراکنش', isDense: true),
              items: [
                const DropdownMenuItem<EmployeeWalletTransactionType?>(value: null, child: Text('همه انواع')),
                for (final type in EmployeeWalletTransactionType.values)
                  DropdownMenuItem<EmployeeWalletTransactionType?>(value: type, child: Text(type.label)),
              ],
              onChanged: (value) => setState(() => _typeFilter = value),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const EmptyState(compact: true, title: 'تراکنشی در این بازه ثبت نشده', description: 'با ثبت حقوق، پورسانت یا عملیات مالی، سوابق اینجا نمایش داده می‌شوند.'),
            for (final entry in entries)
              Material(color: Colors.transparent, child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: (entry.amount >= 0 ? pal.success : pal.danger).withValues(alpha: 0.12),
                  child: _transactionIcon(entry.type, color: entry.amount >= 0 ? pal.success : pal.danger),
                ),
                title: Text(entry.type.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                subtitle: Text('${entry.description}\n${Fmt.jalaliDate(entry.createdAt)} • ${entry.id}', style: TextStyle(fontSize: 10, color: pal.textMuted)),
                isThreeLine: true,
                trailing: Text(
                  '${entry.amount > 0 ? '+' : ''}${Fmt.money(entry.amount)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: entry.amount >= 0 ? pal.success : pal.danger),
                ),
                onTap: () => _showTransaction(db, entry),
              )),
          ])),
          if (canViewSettlementHistory) ...[
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(title: 'تاریخچه تسویه‌ها', subtitle: '${settlements.length} رسید ثبت‌شده'),
            const SizedBox(height: 8),
            if (settlements.isEmpty)
              const EmptyState(compact: true, title: 'هنوز تسویه‌ای ثبت نشده', description: ''),
            for (final settlement in settlements)
              Material(color: Colors.transparent, child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const HugeIcon(icon: HugeIcons.strokeRoundedInvoice01, size: 22),
                title: Text('رسید ${settlement.receiptNumber}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                subtitle: Text('${settlement.periodType.label} • ${Fmt.jalaliDate(settlement.createdAt)}\nپرداخت: ${Fmt.money(settlement.paidAmount)} • مانده: ${Fmt.money(settlement.remainingAfter)}', style: TextStyle(fontSize: 10, color: pal.textMuted)),
                isThreeLine: true,
                trailing: _SettlementStatus(status: settlement.status),
                onTap: () => _showReceipt(settlement),
              )),
          ])),
          const SizedBox(height: 8),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'پرداخت‌های ثبت‌شده', subtitle: 'هر پرداخت به رسید تسویه و سند دفتر کل متصل است'),
            if (payments.isEmpty) const EmptyState(compact: true, title: 'پرداختی ثبت نشده'),
            for (final payment in payments)
              ListTile(contentPadding: EdgeInsets.zero,
                leading: const HugeIcon(icon: HugeIcons.strokeRoundedPayment01, size: 21),
                title: Text(Fmt.money(payment.amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                subtitle: Text('${_paymentMethodLabel(payment.method)} • ${Fmt.jalaliDate(payment.createdAt)}\nرسید ${payment.receiptNumber} • سند ${payment.walletTransactionId}',
                  style: TextStyle(fontSize: 10, color: pal.textMuted)),
                isThreeLine: true, onTap: () => _showPayment(payment)),
          ])),
          ],
          if (canViewSalary && canViewAllSalary && debtReport.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader(title: 'گزارش بدهی و مطالبات پرسنل', subtitle: 'محاسبه مستقیم از دفتر کل؛ بدون داده مستقل'),
              for (final item in debtReport)
                ListTile(contentPadding: EdgeInsets.zero,
                  title: Text(db.employeeById(item.employeeId)?.fullName ?? item.employeeId,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  subtitle: Text(item.debt > 0 ? 'بدهی پرسنل' : 'مطالبه پرسنل',
                    style: TextStyle(fontSize: 10, color: pal.textMuted)),
                  trailing: Text(Fmt.money(item.debt > 0 ? item.debt : item.payableBalance),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                      color: item.debt > 0 ? pal.danger : pal.success))),
            ])),
          ],
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'شفافیت و ردپای مالی'),
            const SizedBox(height: 8),
            _RuleLine(text: 'سندهای ثبت‌شده از دفتر کل حذف نمی‌شوند.'),
            _RuleLine(text: 'اصلاح سند با ثبت معکوس و اصلاحیه انجام می‌شود.'),
            _RuleLine(text: 'هر پرداخت رسید مستقل دارد و پرداخت تکراری مسدود می‌شود.'),
            _RuleLine(text: 'تغییر قرارداد پورسانت، snapshotهای قطعی قبلی را تغییر نمی‌دهد.'),
          ])),
        ],
      ),
    );
  }

  void _selectPeriod(EmployeeWalletPeriodType value) {
    final now = DateTime.now();
    setState(() {
      _period = value;
      switch (value) {
        case EmployeeWalletPeriodType.daily:
          _from = DateTime(now.year, now.month, now.day);
          _to = now;
          break;
        case EmployeeWalletPeriodType.weekly:
          final weekday = now.weekday;
          _from = DateTime(now.year, now.month, now.day).subtract(Duration(days: weekday - 1));
          _to = now;
          break;
        case EmployeeWalletPeriodType.monthly:
          _from = DateTime(now.year, now.month, 1);
          _to = now;
          break;
        case EmployeeWalletPeriodType.manual:
          break;
      }
    });
  }

  Future<void> _chooseRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to.isBefore(_from) ? _from : _to),
      helpText: 'انتخاب بازه مالی',
      cancelText: 'انصراف',
      confirmText: 'تأیید بازه',
    );
    if (selected != null && mounted) {
      setState(() {
        _from = selected.start;
        _to = selected.end;
        _period = EmployeeWalletPeriodType.manual;
      });
    }
  }

  Future<void> _addTransaction(AppDatabase db, String employeeId) async {
    if (_isAddingTransaction) return;
    _isAddingTransaction = true;
    final operationKey = 'manual-$employeeId-${DateTime.now().microsecondsSinceEpoch}';
    var type = db.hasPermission('finance.advance.create', employeeId: employeeId) ? EmployeeWalletTransactionType.advance : EmployeeWalletTransactionType.bonus;
    var positiveAdjustment = true;
    final amount = TextEditingController();
    final description = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('ثبت تراکنش مالی'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<EmployeeWalletTransactionType>(
            value: type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'نوع تراکنش'),
            items: [
              for (final item in [
                if (db.hasPermission('finance.advance.create', employeeId: employeeId))
                EmployeeWalletTransactionType.advance,
              if (db.hasPermission('finance.payment.create', employeeId: employeeId)) ...[
                EmployeeWalletTransactionType.bonus,
                EmployeeWalletTransactionType.penalty,
                EmployeeWalletTransactionType.deduction,
                EmployeeWalletTransactionType.adjustment,
              ],
            ]) DropdownMenuItem(value: item, child: Text(item.label)),
            ],
            onChanged: (value) => update(() => type = value ?? type),
          ),
          if (type == EmployeeWalletTransactionType.adjustment)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اصلاحیه بستانکار است', style: TextStyle(fontSize: 12)),
              value: positiveAdjustment,
              onChanged: (value) => update(() => positiveAdjustment = value),
            ),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
          TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات و علت ثبت')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت سند')),
        ],
      )),
    );
    if (result != true || !mounted) { amount.dispose(); description.dispose(); _isAddingTransaction = false; return; }
    final parsed = int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (parsed == null || parsed <= 0 || description.text.trim().isEmpty) {
      AppToast.show(context, 'مبلغ و توضیحات را بررسی کنید.', success: false);
      amount.dispose(); description.dispose(); _isAddingTransaction = false; return;
    }
    final credit = type == EmployeeWalletTransactionType.fixedSalary ||
        type == EmployeeWalletTransactionType.bonus ||
        (type == EmployeeWalletTransactionType.adjustment && positiveAdjustment);
    final signedAmount = credit ? parsed : -parsed;
    final employee = db.employeeById(employeeId);
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید ثبت سند مالی',
      description: 'این سند به دفتر کل کیف پول اضافه می‌شود و به‌صورت مستقیم حذف یا Undo نمی‌شود؛ اصلاح بعدی فقط با سند معکوس و اصلاحیه امکان‌پذیر است.',
      recordDetails: {
        'پرسنل': employee?.fullName ?? employeeId,
        'نوع سند': type.label,
        'مبلغ': '${FaNum.ofInt(signedAmount)} تومان',
        'شرح': description.text.trim(),
      },
      isReversible: false,
      warning: 'سند مالی پس از ثبت تغییرناپذیر است. برای اصلاح باید سند معکوس و اصلاحیه جدید ثبت شود.',
      confirmLabel: 'ثبت سند مالی',
    );
    if (!approved || !mounted) { amount.dispose(); description.dispose(); _isAddingTransaction = false; return; }
    try {
      await EmployeeWalletService(EmployeeWalletRepository(db)).recordTransaction(
        employeeId: employeeId, amount: signedAmount, type: type,
        description: description.text.trim(), idempotencyKey: operationKey,
      );
      if (mounted) AppToast.show(context, 'سند مالی با موفقیت ثبت شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت تراکنش انجام نشد: $error', success: false);
    }
    amount.dispose(); description.dispose();
    _isAddingTransaction = false;
  }

  Future<void> _accruePayroll(AppDatabase db, String employeeId) async {
    final at = DateTime.now();
    final payroll = db.payrollFor(employeeId, at: at);
    final employee = db.employeeById(employeeId);
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید ثبت حقوق ماه جاری',
      description: 'حقوق پایه و اثر قانون حضور و غیاب به دفتر کل کیف پول اضافه می‌شود. سند ثبت‌شده حذف یا Undo نمی‌شود.',
      recordDetails: {
        'پرسنل': employee?.fullName ?? employeeId,
        'حقوق پایه': '${FaNum.ofInt(payroll.baseSalary)} تومان',
        'اثر حضور و غیاب': '${FaNum.ofInt(payroll.attendanceAdjustment)} تومان',
        'جمع انتقال': '${FaNum.ofInt(payroll.baseSalary + payroll.attendanceAdjustment)} تومان',
        'دوره': '${at.year}/${at.month.toString().padLeft(2, '0')}',
      },
      isReversible: false,
      warning: 'ثبت حقوق در دفتر کل قطعی است؛ برای اصلاح باید سند مالی جدید ثبت شود.',
      confirmLabel: 'ثبت حقوق ماه جاری',
    );
    if (!approved || !mounted) return;
    try {
      final count = await EmployeeWalletService(EmployeeWalletRepository(db)).accruePayroll(employeeId, at: at);
      if (mounted) AppToast.show(context, count == 0
          ? 'حقوق پایه قبلاً ثبت شده یا مبلغ جدیدی برای انتقال وجود ندارد.'
          : 'حقوق پایه و اثر حضور و غیاب به کیف پول منتقل شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت حقوق انجام نشد: $error', success: false);
    }
  }

  Future<void> _settle(AppDatabase db, String employeeId) async {
    if (_isSettling) return;
    _isSettling = true;
    final operationKey = 'settle-$employeeId-${DateTime.now().microsecondsSinceEpoch}';
    final service = EmployeeWalletService(EmployeeWalletRepository(db));
    final due = service.readPeriodDue(employeeId, _from, _endOfDay);
    if (due <= 0) {
      AppToast.show(context, 'برای بازه انتخاب‌شده مانده قابل پرداختی وجود ندارد.', success: false);
      _isSettling = false;
      return;
    }
    final amount = TextEditingController(text: due.toString());
    final description = TextEditingController(text: 'تسویه حقوق پرسنل');
    var method = EmployeeWalletPaymentMethod.bankTransfer;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('ثبت تسویه حساب'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مبلغ قابل پرداخت: ${Fmt.money(due)}'),
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ پرداخت‌شده (تومان)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<EmployeeWalletPaymentMethod>(
            value: method, isExpanded: true,
            decoration: const InputDecoration(labelText: 'روش پرداخت'),
            items: [for (final item in EmployeeWalletPaymentMethod.values)
              DropdownMenuItem(value: item, child: Text(_paymentMethodLabel(item)))],
            onChanged: (value) => update(() => method = value ?? method),
          ),
          const SizedBox(height: 10),
          TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات پرداخت')),
          const SizedBox(height: 8),
          Text('بازه: ${Fmt.jalaliDate(_from)} تا ${Fmt.jalaliDate(_to)}', style: const TextStyle(fontSize: 11)),
          const Text('پرداخت کمتر از مبلغ قابل پرداخت، به‌عنوان تسویه جزئی ثبت می‌شود.', style: TextStyle(fontSize: 11)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت پرداخت و صدور رسید')),
        ],
      )),
    );
    if (result != true || !mounted) { amount.dispose(); description.dispose(); _isSettling = false; return; }
    final paid = int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    amount.dispose();
    if (paid == null || paid <= 0 || paid > due || description.text.trim().isEmpty) {
      AppToast.show(context, 'مبلغ پرداخت و توضیحات را بررسی کنید.', success: false);
      description.dispose(); _isSettling = false; return;
    }
    final currentDue = service.readPeriodDue(employeeId, _from, _endOfDay);
    if (currentDue <= 0 || paid > currentDue) {
      AppToast.show(context, 'این بازه قبلاً تسویه شده یا مانده آن تغییر کرده است؛ اطلاعات را تازه‌سازی کنید.', success: false);
      description.dispose(); _isSettling = false; return;
    }
    final employee = db.employeeById(employeeId);
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید پرداخت و تسویه',
      description: 'پرداخت در دفتر کل ثبت می‌شود و رسید مالی تغییرناپذیر ایجاد می‌کند.',
      recordDetails: {
        'پرسنل': employee?.fullName ?? employeeId,
        'بازه': '${Fmt.jalaliDate(_from)} تا ${Fmt.jalaliDate(_endOfDay)}',
        'مبلغ قابل پرداخت': '${FaNum.ofInt(currentDue)} تومان',
        'مبلغ پرداخت': '${FaNum.ofInt(paid)} تومان',
        'روش پرداخت': _paymentMethodLabel(method),
        'توضیحات': description.text.trim(),
        'مانده پس از پرداخت': '${FaNum.ofInt(currentDue - paid)} تومان',
      },
      isReversible: false,
      warning: 'پرداخت و رسید تسویه قابل حذف یا Undo نیستند؛ اصلاح مالی باید با سند جداگانه انجام شود.',
      confirmLabel: 'ثبت پرداخت و صدور رسید',
    );
    if (!approved || !mounted) { description.dispose(); _isSettling = false; return; }
    try {
      final settlement = await service.settle(
        employeeId: employeeId,
        period: EmployeeWalletPeriod(type: _period, start: _from, end: _endOfDay),
        amount: paid, idempotencyKey: operationKey, method: method,
        description: description.text.trim(),
      );
      if (mounted) {
        AppToast.show(context, 'پرداخت با سند مالی و رسید ثبت شد.');
        _showReceipt(settlement);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, 'تسویه انجام نشد: $error', success: false);
    }
    description.dispose();
    _isSettling = false;
  }

  void _showTransaction(AppDatabase db, EmployeeWalletTransaction entry) {
    final canCorrect = entry.status == EmployeeWalletTransactionStatus.posted &&
        !db.employeeWalletTransactions.any((item) => item.reversalOfId == entry.id);
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(entry.type.label),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DetailLine(label: 'شناسه', value: entry.id),
        _DetailLine(label: 'تاریخ', value: Fmt.jalaliDate(entry.createdAt)),
        _DetailLine(label: 'مبلغ', value: Fmt.money(entry.amount)),
        _DetailLine(label: 'وضعیت', value: entry.status.name == 'posted' ? 'قطعی' : 'در انتظار'),
        _DetailLine(label: 'توضیحات', value: entry.description),
        if (entry.sourceFinanceEntryId != null) _DetailLine(label: 'سند مالی مبنا', value: entry.sourceFinanceEntryId!),
        if (entry.appointmentId != null) _DetailLine(label: 'شناسه نوبت', value: entry.appointmentId!),
        if (entry.paymentId != null) _DetailLine(label: 'شناسه پرداخت', value: entry.paymentId!),
        if (entry.settlementId != null) _DetailLine(label: 'شناسه تسویه', value: entry.settlementId!),
        if (entry.referenceType != null) _DetailLine(label: 'نوع مرجع', value: entry.referenceType!),
        if (entry.referenceId != null) _DetailLine(label: 'شناسه مرجع', value: entry.referenceId!),
        if (entry.reversalOfId != null) _DetailLine(label: 'سند مرجع', value: entry.reversalOfId!),
      ]),
      actions: [
        if (canCorrect)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _correctTransaction(db, entry);
            },
            child: const Text('اصلاح سند'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
      ],
    ));
  }

  Future<void> _correctTransaction(AppDatabase db, EmployeeWalletTransaction entry) async {
    final amount = TextEditingController(text: entry.amount.toString());
    final description = TextEditingController(text: 'اصلاح سند ${entry.id}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اصلاح تراکنش مالی'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('سند قبلی حذف نمی‌شود؛ یک سند معکوس و یک اصلاحیه جدید ثبت خواهد شد.', style: TextStyle(fontSize: 11)),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: 'مبلغ نهایی با علامت مثبت یا منفی')),
          TextField(controller: description, decoration: const InputDecoration(labelText: 'علت اصلاح')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت اصلاحیه')),
        ],
      ),
    );
    if (confirmed != true || !mounted) { amount.dispose(); description.dispose(); return; }
    final parsed = int.tryParse(FaNum.toLatin(amount.text).replaceAll(',', '').trim());
    if (parsed == null || parsed == 0 || description.text.trim().isEmpty) {
      AppToast.show(context, 'مبلغ نهایی و علت اصلاح را بررسی کنید.', success: false);
      amount.dispose(); description.dispose(); return;
    }
    final approved = await showSensitiveOperationDialog(
      context,
      title: 'تأیید اصلاح سند مالی',
      description: 'سند اصلی حذف یا ویرایش نمی‌شود. این عملیات دو سند جدید و غیرقابل‌بازگشت مستقیم ایجاد می‌کند: یک سند معکوس و یک اصلاحیه.',
      recordDetails: {
        'شناسه سند': entry.id,
        'پرسنل': db.employeeById(entry.employeeId)?.fullName ?? entry.employeeId,
        'مبلغ قبلی': '${FaNum.ofInt(entry.amount)} تومان',
        'مبلغ اصلاح‌شده': '${FaNum.ofInt(parsed)} تومان',
        'علت اصلاح': description.text.trim(),
      },
      isReversible: false,
      warning: 'Undo برای سند مالی ثبت نمی‌شود. در صورت نیاز به تغییر مجدد، باید اصلاحیه مالی تازه ثبت شود.',
      confirmLabel: 'ثبت سند معکوس و اصلاحیه',
    );
    if (!approved || !mounted) { amount.dispose(); description.dispose(); return; }
    try {
      await OperationsRepository(db).correctWalletTransaction(
        transactionId: entry.id,
        correctedAmount: parsed,
        description: description.text.trim(),
      );
      if (mounted) AppToast.show(context, 'سند معکوس و اصلاحیه ثبت شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, 'اصلاح سند انجام نشد: $error', success: false);
    }
    amount.dispose(); description.dispose();
  }

  void _showPayment(EmployeeWalletPayment payment) {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('جزئیات پرداخت'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DetailLine(label: 'شماره رسید', value: payment.receiptNumber),
        _DetailLine(label: 'شناسه پرداخت', value: payment.id),
        _DetailLine(label: 'شناسه تسویه', value: payment.settlementId),
        _DetailLine(label: 'سند دفتر کل', value: payment.walletTransactionId),
        _DetailLine(label: 'مبلغ', value: Fmt.money(payment.amount)),
        _DetailLine(label: 'روش پرداخت', value: _paymentMethodLabel(payment.method)),
        _DetailLine(label: 'تاریخ', value: Fmt.jalaliDate(payment.createdAt)),
        _DetailLine(label: 'توضیحات', value: payment.description.isEmpty ? '—' : payment.description),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
    ));
  }

  String _paymentMethodLabel(EmployeeWalletPaymentMethod method) => switch (method) {
    EmployeeWalletPaymentMethod.cash => 'نقدی',
    EmployeeWalletPaymentMethod.bankTransfer => 'کارت به کارت / واریز بانکی',
    EmployeeWalletPaymentMethod.pos => 'دستگاه کارت‌خوان',
    EmployeeWalletPaymentMethod.cheque => 'چک',
    EmployeeWalletPaymentMethod.other => 'سایر',
  };

  void _showReceipt(EmployeeWalletSettlement settlement) {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Row(children: [HugeIcon(icon: HugeIcons.strokeRoundedInvoice01, size: 22), SizedBox(width: 8), Text('رسید تسویه')]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DetailLine(label: 'شماره رسید', value: settlement.receiptNumber),
        _DetailLine(label: 'شناسه تسویه', value: settlement.id),
        _DetailLine(label: 'نوع دوره', value: settlement.periodType.label),
        _DetailLine(label: 'بازه', value: '${Fmt.jalaliDate(settlement.periodStart)} تا ${Fmt.jalaliDate(settlement.periodEnd)}'),
        _DetailLine(label: 'مبلغ قابل پرداخت', value: Fmt.money(settlement.dueAmount)),
        _DetailLine(label: 'مبلغ پرداخت‌شده', value: Fmt.money(settlement.paidAmount)),
        _DetailLine(label: 'مانده پس از پرداخت', value: Fmt.money(settlement.remainingAfter)),
        _DetailLine(label: 'وضعیت', value: settlement.status == EmployeeWalletSettlementStatus.completed ? 'تسویه کامل' : 'تسویه جزئی'),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن رسید'))],
    ));
  }

  Widget _transactionIcon(EmployeeWalletTransactionType type, {required Color color}) {
    final icon = switch (type) {
      EmployeeWalletTransactionType.commission => HugeIcons.strokeRoundedPercent,
      EmployeeWalletTransactionType.fixedSalary => HugeIcons.strokeRoundedMoney01,
      EmployeeWalletTransactionType.salaryPayment => HugeIcons.strokeRoundedPayment01,
      EmployeeWalletTransactionType.advance => HugeIcons.strokeRoundedCash01,
      EmployeeWalletTransactionType.bonus => HugeIcons.strokeRoundedAward01,
      EmployeeWalletTransactionType.penalty => HugeIcons.strokeRoundedAlert01,
      EmployeeWalletTransactionType.deduction => HugeIcons.strokeRoundedArrowDown01,
      EmployeeWalletTransactionType.refund => HugeIcons.strokeRoundedArrowDown01,
      EmployeeWalletTransactionType.adjustment => HugeIcons.strokeRoundedFileEdit,
    };
    return HugeIcon(icon: icon, color: color, size: 19);
  }
}

class _WalletMetric extends StatelessWidget {
  const _WalletMetric({required this.label, required this.amount, required this.color});
  final String label;
  final int amount;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 135,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, color: context.pal.textMuted)),
      const SizedBox(height: 3),
      Text(Fmt.compactMoney(amount), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
    ]),
  );
}

class _SettlementStatus extends StatelessWidget {
  const _SettlementStatus({required this.status});
  final EmployeeWalletSettlementStatus status;
  @override
  Widget build(BuildContext context) {
    final complete = status == EmployeeWalletSettlementStatus.completed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (complete ? context.pal.success : context.pal.warning).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(complete ? 'کامل' : 'جزئی', style: TextStyle(fontSize: 10, color: complete ? context.pal.success : context.pal.warning)),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 105, child: Text(label, style: TextStyle(fontSize: 11, color: context.pal.textMuted))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
    ]),
  );
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 15),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
    ]),
  );
}
