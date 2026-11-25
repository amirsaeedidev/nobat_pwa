import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/employee_finance.dart';
import '../../../../data/repositories/supabase_employee_wallet_repository.dart';

class EmployeeFinancePage extends StatefulWidget {
  const EmployeeFinancePage({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<EmployeeFinancePage> createState() => _EmployeeFinancePageState();
}

class _EmployeeFinancePageState extends State<EmployeeFinancePage> {
  Future<_FinanceLoad>? _future;

  Future<_FinanceLoad> _load() async {
    final client = context.read<SupabaseClient?>();
    if (client == null) throw StateError('اتصال Supabase برقرار نیست؛ داده محلی یا آزمایشی نمایش داده نمی‌شود.');
    if (client.auth.currentUser == null) throw StateError('برای مشاهده قرارداد مالی وارد حساب شوید.');
    final membership = await client.from('business_memberships').select('business_id,role')
        .eq('user_id', client.auth.currentUser!.id).eq('is_active', true)
        .limit(1).maybeSingle();
    if (membership == null) throw StateError('عضویت فعال مجموعه پیدا نشد.');
    final repository = SupabaseEmployeeWalletRepository(
      client: client, businessId: membership['business_id'] as String);
    final results = await Future.wait<Object?>([
      repository.fetchEmployeeName(widget.employeeId),
      repository.fetchPayProfile(widget.employeeId),
      repository.fetchServices(),
      repository.fetchFinanceEntries(widget.employeeId),
    ]);
    return _FinanceLoad(
      repository: repository,
      employeeName: results[0] as String,
      profile: results[1] as EmployeePayProfile?,
      services: results[2] as List<Map<String, dynamic>>,
      entries: results[3] as List<EmployeeFinanceEntry>,
    );
  }

  @override
  Widget build(BuildContext context) {
    _future ??= _load();
    return FutureBuilder<_FinanceLoad>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return PageScaffold(title: 'حقوق و پورسانت', showBackButton: true,
          child: EmptyState(title: 'دریافت قرارداد مالی ناموفق بود', description: snapshot.error.toString()));
        if (!snapshot.hasData) return const PageScaffold(title: 'حقوق و پورسانت', showBackButton: true,
          child: Center(child: CircularProgressIndicator()));
        return _FinanceEditor(key: ValueKey(widget.employeeId), employeeId: widget.employeeId,
          data: snapshot.data!);
      },
    );
  }
}

class _FinanceLoad {
  const _FinanceLoad({required this.repository, required this.employeeName, required this.profile,
    required this.services, required this.entries});
  final SupabaseEmployeeWalletRepository repository;
  final String employeeName;
  final EmployeePayProfile? profile;
  final List<Map<String, dynamic>> services;
  final List<EmployeeFinanceEntry> entries;
}

class _FinanceEditor extends StatefulWidget {
  const _FinanceEditor({super.key, required this.employeeId, required this.data});
  final String employeeId;
  final _FinanceLoad data;
  @override
  State<_FinanceEditor> createState() => _FinanceEditorState();
}

class _FinanceEditorState extends State<_FinanceEditor> {
  late final TextEditingController salary;
  late final TextEditingController rate;
  late final TextEditingController previewPrice;
  late final TextEditingController previewDiscount;
  late EmployeePaymentMethod method;
  late CommissionBasis basis;
  late List<EmployeeCommissionRule> rules;
  bool saving = false;

  int _number(TextEditingController controller) =>
      int.tryParse(FaNum.toLatin(controller.text).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  @override
  void initState() {
    super.initState();
    final profile = widget.data.profile ?? EmployeePayProfile(employeeId: widget.employeeId);
    method = profile.method;
    basis = profile.basis;
    rules = List.of(profile.rules);
    salary = TextEditingController(text: profile.monthlySalary.toString());
    rate = TextEditingController(text: (profile.generalRateBps / 100).toStringAsFixed(2));
    previewPrice = TextEditingController(text: '10000000');
    previewDiscount = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    salary.dispose(); rate.dispose(); previewPrice.dispose(); previewDiscount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final now = DateTime.now();
    final monthly = widget.data.entries.where((e) =>
      e.createdAt.year == now.year && e.createdAt.month == now.month).toList();
    final commission = monthly.fold<int>(0, (sum, e) => sum + e.commissionAmount);
    final company = monthly.fold<int>(0, (sum, e) => sum + e.companyShare);
    final gross = _number(previewPrice);
    final discount = _number(previewDiscount).clamp(0, gross).toInt();
    final rateValue = double.tryParse(FaNum.toLatin(rate.text).replaceAll(',', '.')) ?? 0;
    final base = CommissionCalculator.base(basis: basis, grossAmount: gross,
      discountAmount: discount, receivedAmount: gross - discount);
    final commissionPreview = method == EmployeePaymentMethod.fixedMonthly
      ? 0 : CommissionCalculator.commission(baseAmount: base,
          rateBps: (rateValue * 100).round().clamp(0, 10000));

    return PageScaffold(
      title: 'حقوق و پورسانت',
      subtitle: widget.data.employeeName,
      showBackButton: true,
      actions: [SolidButton(label: saving ? 'در حال ذخیره...' : 'ذخیره قرارداد',
        icon: Icons.save_rounded, onPressed: saving ? null : _save)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.data.profile == null)
          const AppCard(child: Text('برای این پرسنل هنوز قرارداد مالی ثبت نشده است. می‌توانید قرارداد جدید ایجاد کنید.')),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'عملکرد مالی این ماه'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Metric(label: 'پورسانت ثبت‌شده', amount: commission, color: pal.success)),
            Expanded(child: _Metric(label: 'سهم مجموعه', amount: company, color: pal.primaryBright)),
          ]),
          const SizedBox(height: 8),
          Text('تعداد اسناد: ${monthly.length}', style: TextStyle(color: pal.textMuted, fontSize: 11)),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'قرارداد پرداخت و حقوق'),
          const SizedBox(height: 12),
          DropdownButtonFormField<EmployeePaymentMethod>(value: method, isExpanded: true,
            decoration: const InputDecoration(labelText: 'مدل پرداخت'),
            items: EmployeePaymentMethod.values.map((v) => DropdownMenuItem(value: v, child: Text(v.label))).toList(),
            onChanged: (v) => setState(() => method = v ?? method)),
          const SizedBox(height: 10),
          TextField(controller: salary, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'حقوق ثابت ماهانه (تومان)')),
          const SizedBox(height: 10),
          TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'پورسانت عمومی (درصد)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<CommissionBasis>(value: basis, isExpanded: true,
            decoration: const InputDecoration(labelText: 'مبنای محاسبه پورسانت'),
            items: CommissionBasis.values.map((v) => DropdownMenuItem(value: v, child: Text(v.label))).toList(),
            onChanged: (v) => setState(() => basis = v ?? basis)),
          const Divider(height: 24),
          Row(children: [const Expanded(child: SectionHeader(title: 'قوانین اختصاصی خدمات')),
            TextButton.icon(onPressed: _addRule, icon: const Icon(Icons.add), label: const Text('افزودن'))]),
          if (rules.isEmpty) const Text('قانون اختصاصی تعریف نشده؛ نرخ عمومی قرارداد اعمال می‌شود.',
            style: TextStyle(fontSize: 11)),
          for (final rule in rules)
            ListTile(contentPadding: EdgeInsets.zero,
              title: Text(_serviceName(rule.serviceId, rule.category)),
              subtitle: Text('${(rule.rateBps / 100).toStringAsFixed(2)}٪ + ${Fmt.money(rule.fixedAmount)}'),
              trailing: IconButton(icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => rules.removeWhere((r) => r.id == rule.id)))),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'پیش‌نمایش محاسبه پورسانت'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: previewPrice, keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'مبلغ خدمت'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: previewDiscount, keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'تخفیف'))),
          ]),
          const SizedBox(height: 10),
          _MoneyLine(label: 'مبنای محاسبه', amount: base),
          _MoneyLine(label: 'سهم پرسنل', amount: commissionPreview, highlight: true),
          _MoneyLine(label: 'سهم مجموعه', amount: gross - discount - commissionPreview),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'دفتر اسناد پورسانت و حقوق'),
          if (widget.data.entries.isEmpty) const EmptyState(compact: true, title: 'سند مالی ثبت نشده است'),
          for (final entry in widget.data.entries)
            ListTile(contentPadding: EdgeInsets.zero, dense: true,
              title: Text(switch (entry.type) {
                FinanceEntryType.commission => 'پورسانت خدمت',
                FinanceEntryType.refund => 'برگشت پورسانت',
                FinanceEntryType.correction => 'اصلاح مالی',
                FinanceEntryType.salary => 'حقوق',
              }),
              subtitle: Text('${Fmt.jalaliDate(entry.createdAt)} • مبنا: ${Fmt.money(entry.calculationBase)}'),
              trailing: Text(Fmt.money(entry.commissionAmount),
                style: TextStyle(fontWeight: FontWeight.w800, color: entry.commissionAmount < 0 ? pal.danger : pal.success))),
        ])),
      ]),
    );
  }

  String _serviceName(String? serviceId, String? category) {
    if (serviceId == null) return 'دسته‌بندی ${category ?? 'عمومی'}';
    for (final service in widget.data.services) {
      if (service['id'] == serviceId) return service['title'] as String? ?? 'خدمت';
    }
    return 'خدمت حذف‌شده';
  }

  Future<void> _addRule() async {
    if (widget.data.services.isEmpty) {
      AppToast.show(context, 'برای تعریف قانون اختصاصی، ابتدا خدمت واقعی در مجموعه ثبت کنید.', success: false);
      return;
    }
    String? selected = widget.data.services.first['id'] as String;
    final percent = TextEditingController(text: '30');
    final fixed = TextEditingController(text: '0');
    final result = await showDialog<EmployeeCommissionRule>(context: context,
      builder: (dialog) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: const Text('قانون اختصاصی پورسانت'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: selected, isExpanded: true,
            items: widget.data.services.map((s) => DropdownMenuItem(value: s['id'] as String,
              child: Text(s['title'] as String? ?? 'خدمت'))).toList(),
            onChanged: (v) => update(() => selected = v)),
          TextField(controller: percent, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'درصد پورسانت')),
          TextField(controller: fixed, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'مبلغ ثابت (تومان)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('انصراف')),
          FilledButton(onPressed: () {
            final p = double.tryParse(FaNum.toLatin(percent.text).replaceAll(',', '.'));
            final f = int.tryParse(FaNum.toLatin(fixed.text).replaceAll(RegExp(r'[^0-9]'), ''));
            if (p == null || p < 0 || p > 100 || f == null || f < 0 || selected == null) return;
            Navigator.pop(dialog, EmployeeCommissionRule(id: 'new-${DateTime.now().microsecondsSinceEpoch}',
              serviceId: selected, rateBps: (p * 100).round(), fixedAmount: f));
          }, child: const Text('ثبت قانون')),
        ],
      )));
    percent.dispose(); fixed.dispose();
    if (result != null && mounted) setState(() => rules = [...rules, result]);
  }

  Future<void> _save() async {
    final parsedRate = double.tryParse(FaNum.toLatin(rate.text).replaceAll(',', '.'));
    final salaryValue = _number(salary);
    if (parsedRate == null || parsedRate < 0 || parsedRate > 100 || salaryValue < 0) {
      AppToast.show(context, 'مقادیر حقوق و پورسانت معتبر نیستند.', success: false);
      return;
    }
    final profile = EmployeePayProfile(employeeId: widget.employeeId, method: method,
      monthlySalary: salaryValue, generalRateBps: (parsedRate * 100).round(),
      basis: basis, rules: List.unmodifiable(rules));
    final confirmed = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('تأیید ذخیره قرارداد'),
      content: Text('قرارداد مالی ${widget.data.employeeName} با مدل «${method.label}» ذخیره شود؟ این تغییر روی محاسبات بعدی اعمال می‌شود.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('تأیید و ذخیره')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.data.repository.savePayProfile(profile);
      if (mounted) AppToast.show(context, 'قرارداد حقوق و پورسانت در Supabase ذخیره شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, 'ذخیره قرارداد ناموفق بود: $error', success: false);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.amount, required this.color});
  final String label; final int amount; final Color color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 10, color: context.pal.textMuted)),
    const SizedBox(height: 5),
    Text(Fmt.money(amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
  ]);
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({required this.label, required this.amount, this.highlight = false});
  final String label; final int amount; final bool highlight;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
      Text(Fmt.money(amount), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
        color: highlight ? context.pal.success : context.pal.textPrimary)),
    ]));
}
