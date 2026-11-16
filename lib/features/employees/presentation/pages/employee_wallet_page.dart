import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee_wallet.dart';

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

  DateTime get _endOfDay => DateTime(_to.year, _to.month, _to.day, 23, 59, 59, 999);

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final employee = db.employeeById(widget.employeeId);
    final pal = context.pal;
    if (employee == null) {
      return PageScaffold(title: 'کیف پول و تسویه', showBackButton: true, child: const EmptyState(title: 'پرسنل یافت نشد'));
    }

    final summary = db.walletSummaryFor(employee.id);
    final entries = db.walletTransactionsFor(employee.id, from: _from, to: _endOfDay);
    final settlements = db.walletSettlementsFor(employee.id);
    final periodDue = db.walletPeriodDue(employee.id, _from, _endOfDay);

    return PageScaffold(
      title: 'کیف پول و تسویه',
      subtitle: employee.fullName,
      icon: Icons.account_balance_wallet_rounded,
      showBackButton: true,
      actions: [
        SoftButton(label: 'ثبت تراکنش', icon: Icons.add_card_rounded, onTap: () => _addTransaction(db, employee.id)),
        SolidButton(label: 'ثبت تسویه', icon: Icons.payments_rounded, onPressed: () => _settle(db, employee.id)),
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
                _WalletMetric(label: 'بدهی و کسورات', amount: summary.debits, color: pal.danger),
                _WalletMetric(label: 'در انتظار تأیید', amount: summary.pending, color: pal.warning),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'بازه مالی و مبلغ قابل تسویه'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              DropdownButton<EmployeeWalletPeriodType>(
                value: _period,
                items: [for (final item in EmployeeWalletPeriodType.values) DropdownMenuItem(value: item, child: Text(item.label))],
                onChanged: (value) => value == null ? null : _selectPeriod(value),
              ),
              OutlinedButton.icon(
                onPressed: _chooseRange,
                icon: const Icon(Icons.date_range_rounded, size: 16),
                label: Text('${Fmt.jalaliDate(_from)} تا ${Fmt.jalaliDate(_to)}'),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('قابل پرداخت در این بازه', style: TextStyle(fontSize: 12, color: pal.textMuted))),
              Text(Fmt.money(periodDue), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: periodDue > 0 ? pal.success : pal.textPrimary)),
            ]),
            const SizedBox(height: 10),
            SolidButton(
              block: true,
              label: periodDue > 0 ? 'تسویه این بازه' : 'مبلغی برای تسویه وجود ندارد',
              icon: Icons.receipt_long_rounded,
              onPressed: periodDue > 0 ? () => _settle(db, employee.id) : null,
            ),
          ])),
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(title: 'دفتر کل تراکنش‌ها', subtitle: '${entries.length} سند در بازه انتخاب‌شده'),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const EmptyState(compact: true, title: 'تراکنشی در این بازه ثبت نشده', description: 'با ثبت حقوق، پورسانت یا عملیات مالی، سوابق اینجا نمایش داده می‌شوند.'),
            for (final entry in entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: (entry.amount >= 0 ? pal.success : pal.danger).withValues(alpha: 0.12),
                  child: Icon(_transactionIcon(entry.type), color: entry.amount >= 0 ? pal.success : pal.danger, size: 19),
                ),
                title: Text(entry.type.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                subtitle: Text('${entry.description}\n${Fmt.jalaliDate(entry.createdAt)} • ${entry.id}', style: TextStyle(fontSize: 10, color: pal.textMuted)),
                isThreeLine: true,
                trailing: Text(
                  '${entry.amount > 0 ? '+' : ''}${Fmt.money(entry.amount)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: entry.amount >= 0 ? pal.success : pal.danger),
                ),
                onTap: () => _showTransaction(entry),
              ),
          ])),
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionHeader(title: 'تاریخچه تسویه‌ها', subtitle: '${settlements.length} رسید ثبت‌شده'),
            const SizedBox(height: 8),
            if (settlements.isEmpty)
              const EmptyState(compact: true, title: 'هنوز تسویه‌ای ثبت نشده', description: ''),
            for (final settlement in settlements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.receipt_rounded, color: pal.primaryBright),
                title: Text('رسید ${settlement.receiptNumber}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                subtitle: Text('${settlement.periodType.label} • ${Fmt.jalaliDate(settlement.createdAt)}\nپرداخت: ${Fmt.money(settlement.paidAmount)} • مانده: ${Fmt.money(settlement.remainingAfter)}', style: TextStyle(fontSize: 10, color: pal.textMuted)),
                isThreeLine: true,
                trailing: _SettlementStatus(status: settlement.status),
                onTap: () => _showReceipt(settlement),
              ),
          ])),
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
        case EmployeeWalletPeriodType.weekly:
          final weekday = now.weekday;
          _from = DateTime(now.year, now.month, now.day).subtract(Duration(days: weekday - 1));
          _to = now;
        case EmployeeWalletPeriodType.monthly:
          _from = DateTime(now.year, now.month, 1);
          _to = now;
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
    var type = EmployeeWalletTransactionType.advance;
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
                EmployeeWalletTransactionType.fixedSalary,
                EmployeeWalletTransactionType.advance,
                EmployeeWalletTransactionType.bonus,
                EmployeeWalletTransactionType.penalty,
                EmployeeWalletTransactionType.deduction,
                EmployeeWalletTransactionType.adjustment,
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
    if (result != true || !mounted) { amount.dispose(); description.dispose(); return; }
    final parsed = int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (parsed == null || parsed <= 0 || description.text.trim().isEmpty) {
      AppToast.show(context, 'مبلغ و توضیحات را بررسی کنید.', success: false);
      amount.dispose(); description.dispose(); return;
    }
    final credit = type == EmployeeWalletTransactionType.fixedSalary ||
        type == EmployeeWalletTransactionType.bonus ||
        (type == EmployeeWalletTransactionType.adjustment && positiveAdjustment);
    try {
      db.addWalletTransaction(
        employeeId: employeeId,
        amount: credit ? parsed : -parsed,
        type: type,
        description: description.text.trim(),
        idempotencyKey: 'manual-${employeeId}-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (mounted) AppToast.show(context, 'سند مالی با موفقیت ثبت شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت تراکنش انجام نشد: $error', success: false);
    }
    amount.dispose(); description.dispose();
  }

  Future<void> _settle(AppDatabase db, String employeeId) async {
    final due = db.walletPeriodDue(employeeId, _from, _endOfDay);
    if (due <= 0) {
      AppToast.show(context, 'برای بازه انتخاب‌شده مانده قابل پرداختی وجود ندارد.', success: false);
      return;
    }
    final amount = TextEditingController(text: due.toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ثبت تسویه حساب'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مبلغ قابل پرداخت: ${Fmt.money(due)}'),
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ پرداخت‌شده (تومان)')),
          const SizedBox(height: 8),
          Text('بازه: ${Fmt.jalaliDate(_from)} تا ${Fmt.jalaliDate(_to)}', style: const TextStyle(fontSize: 11)),
          const Text('پرداخت کمتر از مبلغ قابل پرداخت، به‌عنوان تسویه جزئی ثبت می‌شود.', style: TextStyle(fontSize: 11)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت پرداخت و صدور رسید')),
        ],
      ),
    );
    if (result != true || !mounted) { amount.dispose(); return; }
    final paid = int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    amount.dispose();
    if (paid == null || paid <= 0 || paid > due) {
      AppToast.show(context, 'مبلغ پرداخت باید بین یک تومان و مبلغ قابل تسویه باشد.', success: false);
      return;
    }
    try {
      final settlement = db.settleEmployeeWallet(
        employeeId: employeeId,
        periodStart: _from,
        periodEnd: _endOfDay,
        periodType: _period,
        paidAmount: paid,
        idempotencyKey: 'settle-${employeeId}-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (mounted) _showReceipt(settlement);
    } catch (error) {
      if (mounted) AppToast.show(context, 'تسویه انجام نشد: $error', success: false);
    }
  }

  void _showTransaction(EmployeeWalletTransaction entry) {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(entry.type.label),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DetailLine(label: 'شناسه', value: entry.id),
        _DetailLine(label: 'تاریخ', value: Fmt.jalaliDate(entry.createdAt)),
        _DetailLine(label: 'مبلغ', value: Fmt.money(entry.amount)),
        _DetailLine(label: 'وضعیت', value: entry.status.name == 'posted' ? 'قطعی' : 'در انتظار'),
        _DetailLine(label: 'توضیحات', value: entry.description),
        if (entry.sourceFinanceEntryId != null) _DetailLine(label: 'سند پورسانت', value: entry.sourceFinanceEntryId!),
        if (entry.reversalOfId != null) _DetailLine(label: 'سند مرجع', value: entry.reversalOfId!),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
    ));
  }

  void _showReceipt(EmployeeWalletSettlement settlement) {
    showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Row(children: [Icon(Icons.receipt_long_rounded), SizedBox(width: 8), Text('رسید تسویه')]),
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

  IconData _transactionIcon(EmployeeWalletTransactionType type) => switch (type) {
    EmployeeWalletTransactionType.commission => Icons.percent_rounded,
    EmployeeWalletTransactionType.fixedSalary => Icons.account_balance_rounded,
    EmployeeWalletTransactionType.salaryPayment => Icons.payments_rounded,
    EmployeeWalletTransactionType.advance => Icons.request_quote_rounded,
    EmployeeWalletTransactionType.bonus => Icons.stars_rounded,
    EmployeeWalletTransactionType.penalty => Icons.warning_amber_rounded,
    EmployeeWalletTransactionType.deduction => Icons.remove_circle_outline,
    EmployeeWalletTransactionType.refund => Icons.reply_rounded,
    EmployeeWalletTransactionType.adjustment => Icons.edit_note_rounded,
  };
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
      Icon(Icons.verified_user_outlined, size: 15, color: context.pal.success),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
    ]),
  );
}
