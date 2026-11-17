import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee_finance.dart';
import '../../../../data/models/employee_payroll.dart';

class EmployeeFinancePage extends StatefulWidget {
  const EmployeeFinancePage({super.key, required this.employeeId});
  final String employeeId;
  @override
  State<EmployeeFinancePage> createState() => _EmployeeFinancePageState();
}
class _EmployeeFinancePageState extends State<EmployeeFinancePage> {
  final salary = TextEditingController();
  final rate = TextEditingController();
  final price = TextEditingController(text: '10000000');
  final discount = TextEditingController(text: '0');
  EmployeePaymentMethod method = EmployeePaymentMethod.commissionOnly;
  CommissionBasis basis = CommissionBasis.afterDiscount;
  List<EmployeeCommissionRule> rules = [];
  bool initialized = false;
  @override
  void dispose() { salary.dispose(); rate.dispose(); price.dispose(); discount.dispose(); super.dispose(); }
  int value(TextEditingController c) => int.tryParse(FaNum.toLatin(c.text).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final employee = db.employeeById(widget.employeeId);
    if (employee == null) return PageScaffold(title: 'حقوق و پورسانت', showBackButton: true, child: const EmptyState(title: 'پرسنل یافت نشد'));
    final profile = db.payProfileFor(employee.id);
    final payroll = db.payrollFor(employee.id);
    final salaryHistory = db.salaryContractsFor(employee.id);
    final payrollTargets = db.performanceTargets.where((target) => target.employeeId == employee.id).toList();
    final payrollItems = db.payrollAdjustments.where((item) => item.employeeId == employee.id).toList();
    final payrollAdvances = db.payrollAdvances.where((item) => item.employeeId == employee.id).toList();
    if (!initialized) {
      initialized = true; method = profile.method; basis = profile.basis;
      salary.text = profile.monthlySalary.toString(); rate.text = (profile.generalRateBps / 100).toStringAsFixed(2);
      rules = List.of(profile.rules);
    }
    final entries = db.financeEntriesFor(employee.id);
    final month = DateTime.now();
    final filtered = entries.where((e) => e.createdAt.year == month.year && e.createdAt.month == month.month).toList();
    final earned = filtered.fold<int>(0, (sum, e) => sum + e.commissionAmount);
    final company = filtered.fold<int>(0, (sum, e) => sum + e.companyShare);
    final gross = value(price);
    final off = value(discount).clamp(0, gross).toInt();
    final rateBps = ((double.tryParse(FaNum.toLatin(rate.text).replaceAll(',', '.')) ?? 0) * 100).round().clamp(0, 10000).toInt();
    final base = CommissionCalculator.base(basis: basis, grossAmount: gross, discountAmount: off, receivedAmount: gross - off);
    final share = method == EmployeePaymentMethod.fixedMonthly ? 0 : CommissionCalculator.commission(baseAmount: base, rateBps: rateBps);
    final pal = context.pal;
    return PageScaffold(
      title: 'حقوق و پورسانت', subtitle: employee.fullName, icon: Icons.account_balance_wallet_rounded, showBackButton: true,
      actions: [SolidButton(label: 'ذخیره قرارداد', icon: Icons.save_rounded, onPressed: () => _save(db, employee.id))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'خلاصه مالی این ماه'), const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Metric(label: 'پورسانت خالص', value: Fmt.compactMoney(earned), color: pal.success)),
            Expanded(child: _Metric(label: 'سهم مجموعه', value: Fmt.compactMoney(company), color: pal.primaryBright)),
          ]),
          const Divider(height: 24),
          _Metric(label: 'حقوق پایه ماهانه', value: Fmt.money(profile.monthlySalary), color: pal.textPrimary),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'پیش‌نمایش فیش حقوقی ماه جاری'),
          const SizedBox(height: 10),
          _MoneyLine(label: 'حقوق پایه معتبر', amount: payroll.baseSalary),
          _MoneyLine(label: 'پورسانت تأییدشده', amount: payroll.approvedCommission),
          _MoneyLine(label: 'پاداش تأییدشده', amount: payroll.approvedBonuses),
          _MoneyLine(label: 'کسورات', amount: -payroll.deductions),
          _MoneyLine(label: 'مساعده کسرشده', amount: -payroll.advanceDeducted),
          _MoneyLine(label: 'پرداخت‌های قبلی', amount: -payroll.previousPayments),
          const Divider(height: 20),
          _MoneyLine(label: payroll.payable < 0 ? 'بدهی پرسنل' : 'مانده قابل پرداخت',
            amount: payroll.payable.abs(), highlight: true),
          if (salaryHistory.isNotEmpty)
            Text('تاریخچه حقوق: ${salaryHistory.length} قرارداد ثبت‌شده', style: TextStyle(fontSize: 10, color: pal.textMuted)),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'اهداف عملکردی'),
          if (payrollTargets.isEmpty) const Text('هدفی برای این پرسنل تعریف نشده.', style: TextStyle(fontSize: 11)),
          for (final target in payrollTargets) Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(target.type.name == 'monthlyRevenue' ? 'هدف درآمد ماهانه' : target.type.name, style: const TextStyle(fontSize: 11))),
                Text('${(target.progress(0) * 100).toStringAsFixed(0)}٪', style: const TextStyle(fontSize: 10))]),
              const SizedBox(height: 5),
              LinearProgressIndicator(value: target.progress(0)),
              Text('هدف: ${Fmt.money(target.targetValue)}', style: TextStyle(fontSize: 9, color: pal.textMuted)),
            ]),
          ),
          const Divider(height: 18),
          Text('آیتم‌های پاداش و کسورات: ${payrollItems.length} مورد', style: const TextStyle(fontSize: 11)),
          Text('سوابق مساعده: ${payrollAdvances.length} مورد', style: const TextStyle(fontSize: 11)),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'قرارداد پرداخت'), const SizedBox(height: 10),
          DropdownButtonFormField<EmployeePaymentMethod>(value: method, isExpanded: true, decoration: const InputDecoration(labelText: 'روش پرداخت'),
            items: [for (final item in EmployeePaymentMethod.values) DropdownMenuItem(value: item, child: Text(item.label))],
            onChanged: (v) => setState(() => method = v ?? method)),
          const SizedBox(height: 10),
          TextField(controller: salary, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حقوق ثابت ماهانه (تومان)')),
          const SizedBox(height: 10),
          TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'پورسانت عمومی (درصد)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<CommissionBasis>(value: basis, isExpanded: true, decoration: const InputDecoration(labelText: 'مبنای محاسبه'),
            items: [for (final item in CommissionBasis.values) DropdownMenuItem(value: item, child: Text(item.label))],
            onChanged: (v) => setState(() => basis = v ?? basis)),
          const SizedBox(height: 12),
          Row(children: [const Expanded(child: SectionHeader(title: 'قوانین اختصاصی خدمات')), TextButton.icon(onPressed: () => _addRule(db), icon: const Icon(Icons.add), label: const Text('افزودن'))]),
          if (rules.isEmpty) const Text('در حال حاضر درصد عمومی برای همه خدمات اعمال می‌شود.', style: TextStyle(fontSize: 11)),
          for (final rule in rules) ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(rule.serviceId == null ? 'دسته ' + (rule.category ?? '') : (db.serviceById(rule.serviceId!)?.title ?? 'خدمت'), style: const TextStyle(fontSize: 12)),
            subtitle: Text((rule.rateBps / 100).toStringAsFixed(2) + '٪  •  ' + Fmt.money(rule.fixedAmount)),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => rules.removeWhere((r) => r.id == rule.id))),
          ),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'ماشین‌حساب پورسانت'), const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'مبلغ خدمت'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: discount, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'تخفیف'))),
          ]),
          const SizedBox(height: 12),
          _MoneyLine(label: 'مبنای محاسبه', amount: base),
          _MoneyLine(label: 'سهم پرسنل', amount: share, highlight: true),
          _MoneyLine(label: 'سهم مجموعه', amount: gross - off - share),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'سوابق مالی این ماه'), const SizedBox(height: 8),
          if (filtered.isEmpty) const EmptyState(title: 'سند مالی ثبت نشده', description: 'با تکمیل نوبت، پورسانت به‌صورت خودکار ثبت می‌شود.'),
          for (final entry in filtered) ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(entry.type == FinanceEntryType.refund ? Icons.reply : Icons.receipt_long, color: entry.commissionAmount < 0 ? pal.danger : pal.success),
            title: Text('نوبت ' + entry.appointmentId, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            subtitle: Text(entry.rateBps.toString() + ' bps • ' + Fmt.jalaliDate(entry.createdAt), style: const TextStyle(fontSize: 9)),
            trailing: Text(Fmt.money(entry.commissionAmount), style: TextStyle(fontSize: 10, color: entry.commissionAmount < 0 ? pal.danger : pal.success)),
          ),
        ])),
      ]),
    );
  }

  void _save(AppDatabase db, String employeeId) {
    final parsedRate = double.tryParse(FaNum.toLatin(rate.text).replaceAll(',', '.'));
    if (parsedRate == null || parsedRate < 0 || parsedRate > 100 || value(salary) < 0) {
      AppToast.show(context, 'حقوق و درصد پورسانت را بررسی کنید.', success: false); return;
    }
    try {
      db.savePayProfile(EmployeePayProfile(employeeId: employeeId, method: method, monthlySalary: value(salary), generalRateBps: (parsedRate * 100).round(), basis: basis, rules: List.unmodifiable(rules)));
      AppToast.show(context, 'قرارداد مالی ذخیره شد.');
    } catch (error) { AppToast.show(context, 'ذخیره انجام نشد: ' + error.toString(), success: false); }
  }

  Future<void> _addRule(AppDatabase db) async {
    if (db.services.isEmpty) { AppToast.show(context, 'ابتدا یک خدمت آزمایشی ایجاد کنید.', success: false); return; }
    String? serviceId = db.services.first.id;
    final percent = TextEditingController(text: '30');
    final fixed = TextEditingController(text: '0');
    final result = await showDialog<EmployeeCommissionRule>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: const Text('قانون اختصاصی پورسانت'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: serviceId, isExpanded: true, items: [for (final s in db.services) DropdownMenuItem(value: s.id, child: Text(s.title))], onChanged: (v) => update(() => serviceId = v)),
        TextField(controller: percent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'درصد پورسانت')),
        TextField(controller: fixed, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ ثابت (تومان)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
        FilledButton(onPressed: () {
          final p = double.tryParse(FaNum.toLatin(percent.text).replaceAll(',', '.'));
          final f = int.tryParse(FaNum.toLatin(fixed.text));
          if (p == null || p < 0 || p > 100 || f == null || f < 0 || serviceId == null) return;
          Navigator.pop(dialogContext, EmployeeCommissionRule(id: 'rule-' + DateTime.now().microsecondsSinceEpoch.toString(), serviceId: serviceId, rateBps: (p * 100).round(), fixedAmount: f));
        }, child: const Text('ثبت')),
      ],
    )));
    percent.dispose(); fixed.dispose();
    if (result != null && mounted) setState(() => rules = [...rules, result]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});
  final String label, value; final Color color;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 10, color: context.pal.textMuted)),
    const SizedBox(height: 5), Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
  ]);
}
class _MoneyLine extends StatelessWidget {
  const _MoneyLine({required this.label, required this.amount, this.highlight = false});
  final String label; final int amount; final bool highlight;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
    Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
    Text(Fmt.money(amount), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: highlight ? context.pal.success : context.pal.textPrimary)),
  ]));
}
