import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/employee_wallet.dart';
import '../../../../data/repositories/supabase_employee_wallet_repository.dart';
import '../providers/employee_wallet_provider.dart';

class EmployeeWalletPage extends StatefulWidget {
  const EmployeeWalletPage({super.key, required this.employeeId});
  final String employeeId;
  @override
  State<EmployeeWalletPage> createState() => _EmployeeWalletPageState();
}

class _EmployeeWalletPageState extends State<EmployeeWalletPage> {
  Future<_WalletContext>? _future;

  Future<_WalletContext> _load() async {
    final client = context.read<SupabaseClient?>();
    if (client == null) throw StateError('Supabase تنظیم نشده است؛ داده آزمایشی نمایش داده نمی‌شود.');
    final user = client.auth.currentUser;
    if (user == null) throw StateError('برای مشاهده کیف پول وارد حساب شوید.');
    final membership = await client.from('business_memberships').select('business_id')
      .eq('user_id', user.id).eq('is_active', true).limit(1).maybeSingle();
    if (membership == null) throw StateError('مجموعه فعالی برای حساب پیدا نشد.');
    final businessId = membership['business_id'] as String;
    final employee = await client.from('employees').select('full_name')
      .eq('business_id', businessId).eq('id', widget.employeeId).maybeSingle();
    if (employee == null) throw StateError('پرسنل در مجموعه فعلی پیدا نشد.');
    return _WalletContext(employee['full_name'] as String? ?? 'پرسنل',
      SupabaseEmployeeWalletRepository(client: client, businessId: businessId));
  }

  @override
  Widget build(BuildContext context) {
    _future ??= _load();
    return FutureBuilder<_WalletContext>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return PageScaffold(title: 'کیف پول و تسویه', showBackButton: true,
          child: EmptyState(title: 'دریافت اطلاعات ممکن نشد', description: snapshot.error.toString()));
        if (!snapshot.hasData) return const PageScaffold(title: 'کیف پول و تسویه', showBackButton: true,
          child: Center(child: CircularProgressIndicator()));
        final data = snapshot.data!;
        return ChangeNotifierProvider(
          create: (_) => EmployeeWalletProvider(data.repository, widget.employeeId),
          child: _WalletBody(name: data.name),
        );
      },
    );
  }
}

class _WalletContext {
  const _WalletContext(this.name, this.repository);
  final String name;
  final SupabaseEmployeeWalletRepository repository;
}

class _WalletBody extends StatelessWidget {
  const _WalletBody({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmployeeWalletProvider>();
    if (state.loading && state.wallet == null) return const PageScaffold(title: 'کیف پول و تسویه',
      showBackButton: true, child: Center(child: CircularProgressIndicator()));
    if (state.error != null && state.wallet == null) return PageScaffold(title: 'کیف پول و تسویه',
      showBackButton: true, child: EmptyState(title: 'خطا در دریافت دفتر کل', description: state.error!));
    final wallet = state.wallet;
    if (wallet == null) return const PageScaffold(title: 'کیف پول و تسویه',
      showBackButton: true, child: EmptyState(title: 'اطلاعات کیف پول موجود نیست'));
    final summary = wallet.summary;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final due = state.transactions.where((e) => !e.createdAt.isBefore(start) &&
      e.status == EmployeeWalletTransactionStatus.posted).fold<int>(0, (sum, e) => sum + e.amount);
    return PageScaffold(
      title: 'کیف پول و تسویه',
      subtitle: name,
      showBackButton: true,
      actions: [
        SoftButton(label: 'ثبت سند مالی', icon: Icons.add, onTap: () => _add(context)),
        SoftButton(label: 'ثبت حقوق', icon: Icons.account_balance_wallet_outlined, onTap: () => _salary(context)),
        SolidButton(label: 'تسویه ماه', onPressed: state.saving || due <= 0 ? null : () => _settle(context, due, start, now)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (state.error != null) Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('مانده کیف پول'),
          const SizedBox(height: 6),
          Text(Fmt.money(summary.balance), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 10, children: [
            _Metric('درآمد', summary.earned), _Metric('پرداخت', summary.paid),
            _Metric('مساعده', summary.advances), _Metric('پاداش', summary.bonuses),
            _Metric('بدهی و کسورات', summary.debits),
          ]),
        ]))),
        Card(child: ListTile(title: const Text('قابل تسویه ماه جاری'),
          subtitle: Text(Fmt.money(due > 0 ? due : 0)))),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('دفتر کل تراکنش‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
          if (state.transactions.isEmpty) const Text('سندی ثبت نشده است.'),
          for (final entry in state.transactions)
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: HugeIcon(icon: entry.amount < 0 ? HugeIcons.strokeRoundedArrowDown01 : HugeIcons.strokeRoundedArrowUp01),
              title: Text(entry.type.label),
              subtitle: Text(entry.description),
              trailing: Text(Fmt.money(entry.amount)),
            ),
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('رسیدهای تسویه', style: TextStyle(fontWeight: FontWeight.bold)),
          if (state.settlements.isEmpty) const Text('تسویه‌ای ثبت نشده است.'),
          for (final item in state.settlements)
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
              leading: const HugeIcon(icon: HugeIcons.strokeRoundedInvoice01),
              title: Text('رسید ${item.receiptNumber}'),
              subtitle: Text('${item.periodType.label} • ${Fmt.jalaliDate(item.createdAt)}'),
              trailing: Text(Fmt.money(item.paidAmount))),
        ]))),
      ]),
    );
  }

  Future<void> _add(BuildContext context) async {
    final state = context.read<EmployeeWalletProvider>();
    final amount = TextEditingController();
    final note = TextEditingController();
    var type = EmployeeWalletTransactionType.advance;
    final accepted = await showDialog<bool>(context: context, builder: (dialog) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(title: const Text('ثبت سند مالی'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<EmployeeWalletTransactionType>(value: type,
            items: [EmployeeWalletTransactionType.advance, EmployeeWalletTransactionType.bonus,
              EmployeeWalletTransactionType.penalty, EmployeeWalletTransactionType.deduction,
              EmployeeWalletTransactionType.refund, EmployeeWalletTransactionType.adjustment]
              .map((e) => DropdownMenuItem(value: e, child: Text(e.label))).toList(),
            onChanged: (v) => setDialog(() => type = v ?? type)),
          TextField(controller: amount, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'مبلغ به تومان')),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'شرح')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('ثبت'))]));
    if (accepted != true || !context.mounted) { amount.dispose(); note.dispose(); return; }
    final value = int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (value == null || value <= 0 || note.text.trim().isEmpty) {
      AppToast.show(context, 'مبلغ و شرح معتبر وارد کنید.', success: false);
      amount.dispose(); note.dispose(); return;
    }
    final credit = type == EmployeeWalletTransactionType.bonus || type == EmployeeWalletTransactionType.adjustment;
    try {
      await state.record(amount: credit ? value : -value, type: type, description: note.text.trim(),
        idempotencyKey: 'wallet-${DateTime.now().microsecondsSinceEpoch}');
      if (context.mounted) AppToast.show(context, 'سند در دفتر کل ثبت شد.');
    } catch (e) { if (context.mounted) AppToast.show(context, 'ثبت ناموفق بود: $e', success: false); }
    amount.dispose(); note.dispose();
  }

  Future<void> _salary(BuildContext context) async {
    final state = context.read<EmployeeWalletProvider>();
    try {
      await state.accrueSalary(idempotencyKey: 'salary-${DateTime.now().year}-${DateTime.now().month}');
      if (context.mounted) AppToast.show(context, 'درخواست ثبت حقوق انجام شد.');
    } catch (e) { if (context.mounted) AppToast.show(context, 'ثبت حقوق ناموفق بود: $e', success: false); }
  }

  Future<void> _settle(BuildContext context, int due, DateTime start, DateTime end) async {
    final state = context.read<EmployeeWalletProvider>();
    final controller = TextEditingController(text: due.toString());
    final amount = await showDialog<int>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('ثبت تسویه'),
      content: TextField(controller: controller, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'مبلغ پرداخت به تومان')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialog,
          int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), ''))), child: const Text('تأیید'))]));
    controller.dispose();
    if (amount == null || !context.mounted) return;
    if (amount <= 0 || amount > due) {
      AppToast.show(context, 'مبلغ باید از مانده بیشتر نباشد.', success: false);
      return;
    }
    try {
      await state.settle(periodType: EmployeeWalletPeriodType.monthly, start: start, end: end,
        amount: amount, method: EmployeeWalletPaymentMethod.bankTransfer,
        description: 'تسویه حقوق پرسنل',
        idempotencyKey: 'settlement-${DateTime.now().microsecondsSinceEpoch}');
      if (context.mounted) AppToast.show(context, 'تسویه اتمیک ثبت شد.');
    } catch (e) { if (context.mounted) AppToast.show(context, 'تسویه ناموفق بود: $e', success: false); }
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.amount);
  final String label;
  final int amount;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 10)),
    Text(Fmt.money(amount), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
  ]);
}
