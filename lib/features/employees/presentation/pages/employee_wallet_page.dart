import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/employee_wallet.dart';
import '../../../../data/repositories/supabase_employee_wallet_repository.dart';
import '../providers/employees_provider.dart';

class EmployeeWalletPage extends StatefulWidget {
  const EmployeeWalletPage({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<EmployeeWalletPage> createState() => _EmployeeWalletPageState();
}

class _WalletSnapshot {
  const _WalletSnapshot({required this.wallet, required this.entries, required this.settlements, required this.payments});
  final EmployeeWallet wallet;
  final List<EmployeeWalletTransaction> entries;
  final List<EmployeeWalletSettlement> settlements;
  final List<EmployeeWalletPayment> payments;
}

class _EmployeeWalletPageState extends State<EmployeeWalletPage> {
  Future<_WalletSnapshot>? _snapshot;
  bool _busy = false;

  Future<_WalletSnapshot> _load(SupabaseEmployeeWalletRepository repository) async {
    final values = await Future.wait([
      repository.fetchTransactions(widget.employeeId),
      repository.fetchSettlements(widget.employeeId),
      repository.fetchPayments(widget.employeeId),
    ]);
    final entries = values[0] as List<EmployeeWalletTransaction>;
    return _WalletSnapshot(
      wallet: EmployeeWallet.fromTransactions(widget.employeeId, entries),
      entries: entries,
      settlements: values[1] as List<EmployeeWalletSettlement>,
      payments: values[2] as List<EmployeeWalletPayment>,
    );
  }

  void _refresh(SupabaseEmployeeWalletRepository repository) {
    setState(() => _snapshot = _load(repository));
  }

  bool _can(SupabaseAuthStateNotifier? auth, String permission) =>
      auth?.role == 'owner' || auth?.permissions[permission] == true;

  Future<void> _record(
    SupabaseEmployeeWalletRepository repository,
    EmployeeWalletTransactionType type,
    bool credit,
  ) async {
    if (_busy) return;
    final amount = TextEditingController();
    final description = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('ثبت ${type.label}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ به تومان')),
          const SizedBox(height: 8),
          TextField(controller: description, decoration: const InputDecoration(labelText: 'توضیحات')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ادامه')),
        ],
      ),
    );
    if (ok != true || !mounted) { amount.dispose(); description.dispose(); return; }
    final parsed = int.tryParse(FaNum.toLatin(amount.text).replaceAll(',', '').trim());
    if (parsed == null || parsed <= 0) {
      AppToast.show(context, 'مبلغ معتبر وارد کنید.', success: false);
      amount.dispose(); description.dispose(); return;
    }
    setState(() => _busy = true);
    try {
      await repository.recordTransaction(
        employeeId: widget.employeeId,
        amount: parsed,
        type: type,
        credit: credit,
        description: description.text.trim(),
        idempotencyKey: 'wallet:${widget.employeeId}:${type.name}:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (mounted) {
        AppToast.show(context, 'تراکنش در دفتر کل ثبت شد.');
        _refresh(repository);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت تراکنش ناموفق بود: $error', success: false);
    } finally {
      amount.dispose(); description.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accrueSalary(SupabaseEmployeeWalletRepository repository) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await repository.accrueMonthlySalary(widget.employeeId);
      if (mounted) {
        AppToast.show(context, 'حقوق ثابت در دفتر کل ثبت شد.');
        _refresh(repository);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت حقوق انجام نشد: $error', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settle(
    SupabaseEmployeeWalletRepository repository,
    int payable,
  ) async {
    if (_busy || payable <= 0) return;
    final amount = TextEditingController(text: payable.toString());
    final description = TextEditingController(text: 'پرداخت تسویه پرسنل');
    var method = EmployeeWalletPaymentMethod.bankTransfer;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('ثبت تسویه'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ پرداخت')),
          const SizedBox(height: 8),
          DropdownButtonFormField<EmployeeWalletPaymentMethod>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'روش پرداخت'),
            items: const [
              DropdownMenuItem(value: EmployeeWalletPaymentMethod.cash, child: Text('نقدی')),
              DropdownMenuItem(value: EmployeeWalletPaymentMethod.bankTransfer, child: Text('کارت به کارت / بانکی')),
              DropdownMenuItem(value: EmployeeWalletPaymentMethod.pos, child: Text('کارتخوان')),
              DropdownMenuItem(value: EmployeeWalletPaymentMethod.cheque, child: Text('چک')),
              DropdownMenuItem(value: EmployeeWalletPaymentMethod.other, child: Text('سایر')),
            ],
            onChanged: (value) { if (value != null) update(() => method = value); },
          ),
          const SizedBox(height: 8),
          TextField(controller: description, decoration: const InputDecoration(labelText: 'توضیحات')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت پرداخت')),
        ],
      )),
    );
    if (ok != true || !mounted) { amount.dispose(); description.dispose(); return; }
    final parsed = int.tryParse(FaNum.toLatin(amount.text).replaceAll(',', '').trim());
    if (parsed == null || parsed <= 0 || parsed > payable) {
      AppToast.show(context, 'مبلغ تسویه باید مثبت و حداکثر برابر مانده قابل پرداخت باشد.', success: false);
      amount.dispose(); description.dispose(); return;
    }
    setState(() => _busy = true);
    final now = DateTime.now();
    try {
      await repository.settle(
        employeeId: widget.employeeId,
        periodStart: DateTime(now.year, now.month, 1),
        periodEnd: DateTime(now.year, now.month + 1, 0),
        periodType: EmployeeWalletPeriodType.monthly,
        amount: parsed,
        method: method,
        description: description.text.trim(),
        idempotencyKey: 'settlement:${widget.employeeId}:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (mounted) {
        AppToast.show(context, 'تسویه و رسید به‌صورت اتمیک در Supabase ثبت شد.');
        _refresh(repository);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت تسویه ناموفق بود: $error', success: false);
    } finally {
      amount.dispose(); description.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverse(
    SupabaseEmployeeWalletRepository repository,
    EmployeeWalletTransaction entry,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('برگشت سند مالی'),
        content: Text('برای سند «${entry.type.label}» به مبلغ ${Fmt.money(entry.amount)} یک سند اصلاحی معکوس در دفتر کل ثبت می‌شود. سند اصلی حذف یا ویرایش نخواهد شد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأیید برگشت')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await repository.reverseTransaction(employeeId: widget.employeeId, transactionId: entry.id);
      if (mounted) {
        AppToast.show(context, 'سند معکوس در دفتر کل ثبت شد.');
        _refresh(repository);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, 'برگشت سند ناموفق بود: $error', success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = Provider.of<SupabaseEmployeeWalletRepository?>(context);
    final auth = context.watch<SupabaseAuthStateNotifier?>();
    final employees = context.watch<EmployeesProvider>();
    final employee = employees.byIdSync(widget.employeeId);
    final palette = context.pal;
    if (repository == null) {
      return PageScaffold(title: 'کیف پول و تسویه', showBackButton: true,
        child: const ErrorStateView(description: 'اتصال کیف پول به Supabase در دسترس نیست؛ هیچ داده محلی یا آزمایشی نمایش داده نمی‌شود.'));
    }
    if (employee == null) {
      return PageScaffold(title: 'کیف پول و تسویه', showBackButton: true,
        child: employees.loading ? const LoadingState(kind: SkeletonKind.personnel)
          : employees.error != null ? ErrorStateView(description: employees.error, onRetry: employees.load)
          : const EmptyState(title: 'پرسنل پیدا نشد'));
    }
    _snapshot ??= _load(repository);
    final canView = _can(auth, 'finance.view') ||
        auth?.permissions['finance.wallet.view_self'] == true;
    if (!canView) {
      return PageScaffold(title: 'کیف پول و تسویه', subtitle: employee.fullName, showBackButton: true,
        child: const ErrorStateView(description: 'مجوز مشاهده اطلاعات مالی این پرسنل را ندارید.'));
    }
    return PageScaffold(
      title: 'کیف پول و تسویه',
      subtitle: employee.fullName,
      showBackButton: true,
      actions: [
        if (_can(auth, 'finance.manage')) SoftButton(label: 'ثبت پاداش', onTap: _busy ? null : () => _record(repository, EmployeeWalletTransactionType.bonus, true)),
        if (_can(auth, 'finance.manage')) SoftButton(label: 'ثبت کسورات', onTap: _busy ? null : () => _record(context, repository, EmployeeWalletTransactionType.deduction, false)),
        if (_can(auth, 'finance.manage')) SoftButton(label: 'ثبت حقوق ماه', onTap: _busy ? null : () => _accrueSalary(repository)),
      ],
      child: FutureBuilder<_WalletSnapshot>(
        future: _snapshot,
        builder: (context, state) {
          if (state.connectionState != ConnectionState.done) return const LoadingState(kind: SkeletonKind.personnel);
          if (state.hasError) return ErrorStateView(description: state.error.toString(), onRetry: () => _refresh(repository));
          final snapshot = state.data!;
          final summary = snapshot.wallet.summary;
          final payable = summary.payableBalance;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('مانده قابل پرداخت'),
              const SizedBox(height: 6),
              Text(Fmt.money(payable), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: palette.success)),
              const SizedBox(height: 14),
              Wrap(spacing: 18, runSpacing: 12, children: [
                _Metric(label: 'درآمد محاسبه‌شده', value: summary.earned, color: palette.primary),
                _Metric(label: 'پرداخت‌شده', value: summary.paid, color: palette.success),
                _Metric(label: 'مساعده و کسورات', value: summary.debits, color: palette.danger),
                _Metric(label: 'پاداش', value: summary.bonuses, color: palette.success),
                _Metric(label: 'مانده نهایی', value: summary.balance, color: palette.textPrimary),
              ]),
            ])),
            const SizedBox(height: 12),
            if (_can(auth, 'finance.manage')) ...[
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: _busy || payable <= 0 ? null : () => _settle(repository, payable),
                  icon: const Icon(Icons.payments_outlined), label: const Text('ثبت تسویه و صدور رسید'),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _record(context, repository, EmployeeWalletTransactionType.adjustment, true),
                  icon: const Icon(Icons.add_circle_outline), label: const Text('اصلاح مثبت'),
                )),
              ]),
              const SizedBox(height: 12),
            ],
            SectionHeader(title: 'دفتر کل تراکنش‌ها', subtitle: '${snapshot.entries.length} سند'),
            const SizedBox(height: 8),
            if (snapshot.entries.isEmpty) const EmptyState(compact: true, title: 'تراکنشی در دفتر کل ثبت نشده است')
            else for (final entry in snapshot.entries)
              AppCard(margin: const EdgeInsets.only(bottom: 7), child: Row(children: [
                Icon(entry.amount >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: entry.amount >= 0 ? palette.success : palette.danger),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.type.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${Fmt.jalaliDate(entry.createdAt)} • ${entry.description}', style: TextStyle(fontSize: 11, color: palette.textMuted)),
                ])),
                Text(Fmt.money(entry.amount), style: TextStyle(fontWeight: FontWeight.w700, color: entry.amount >= 0 ? palette.success : palette.danger)),
                if (_can(auth, 'finance.manage') &&
                    entry.status == EmployeeWalletTransactionStatus.posted &&
                    !(entry.idempotencyKey?.startsWith('wallet-reversal:') ?? false) &&
                    !snapshot.entries.any((candidate) => candidate.referenceId == entry.id))
                  IconButton(
                    tooltip: 'ثبت سند معکوس',
                    onPressed: _busy ? null : () => _reverse(repository, entry),
                    icon: const Icon(Icons.undo_rounded),
                  ),
              ])),
            const SizedBox(height: 12),
            SectionHeader(title: 'تاریخچه تسویه‌ها', subtitle: '${snapshot.settlements.length} رسید'),
            const SizedBox(height: 8),
            if (snapshot.settlements.isEmpty) const EmptyState(compact: true, title: 'تسویه‌ای ثبت نشده است')
            else for (final item in snapshot.settlements)
              AppCard(margin: const EdgeInsets.only(bottom: 7), child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('رسید ${item.receiptNumber}'),
                subtitle: Text('${item.periodType.label} • ${Fmt.jalaliDate(item.createdAt)}'),
                trailing: Text(Fmt.money(item.paidAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
            const SizedBox(height: 12),
            SectionHeader(title: 'پرداخت‌های ثبت‌شده', subtitle: '${snapshot.payments.length} پرداخت'),
            if (snapshot.payments.isEmpty) const EmptyState(compact: true, title: 'پرداختی ثبت نشده است')
            else for (final item in snapshot.payments)
              AppCard(margin: const EdgeInsets.only(bottom: 7), child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('رسید ${item.receiptNumber}'),
                subtitle: Text('${item.method.name} • ${Fmt.jalaliDate(item.createdAt)}'),
                trailing: Text(Fmt.money(item.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
          ]);
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 11, color: context.pal.textMuted)),
    const SizedBox(height: 3),
    Text(Fmt.money(value), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
  ]);
}
