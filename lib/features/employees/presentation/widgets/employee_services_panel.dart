import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/employee_service_config.dart';
import '../../../../data/models/service.dart';

class EmployeeServicesPanel extends StatelessWidget {
  const EmployeeServicesPanel({super.key, required this.employee});
  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final configs = db.employeeServiceConfigsFor(employee.id);
    final pal = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('خدمات قابل ارائه', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
          TextButton.icon(onPressed: () => _editService(context, db, employee, null), icon: const Icon(Icons.add, size: 17), label: const Text('افزودن خدمت')),
        ]),
        Text(FaNum.ofInt(configs.where((item) => item.active).length) + ' خدمت فعال از ' + FaNum.ofInt(configs.length) + ' خدمت اختصاص‌یافته',
          style: TextStyle(fontSize: 10.5, color: pal.textMuted)),
        const SizedBox(height: 10),
        if (configs.isEmpty)
          Text('هنوز خدمتی به این پرسنل اختصاص داده نشده است.', style: TextStyle(fontSize: 11, color: pal.textMuted))
        else
          for (final config in configs) ...[
            _ServiceConfigTile(service: db.serviceById(config.serviceId), config: config,
              onEdit: () => _editService(context, db, employee, config)),
            const Divider(height: 14),
          ],
      ])),
      const SizedBox(height: 12),
      AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('تخصص‌ها و مهارت‌ها', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
          TextButton.icon(onPressed: () => _editSpecialties(context, db, employee), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('ویرایش')),
        ]),
        if (employee.specialties.isEmpty)
          Text('تخصصی ثبت نشده است.', style: TextStyle(fontSize: 11, color: pal.textMuted))
        else
          Wrap(spacing: 7, runSpacing: 7, children: [
            for (final skill in employee.specialties) StatusBadge(label: skill, color: pal.primaryBright),
          ]),
      ])),
    ]);
  }

  Future<void> _editService(BuildContext context, AppDatabase db, Employee employee, EmployeeServiceConfig? current) async {
    final available = db.services.where((item) => item.isActive &&
      (current != null ? item.id == current.serviceId : db.employeeServiceConfig(employee.id, item.id) == null)).toList();
    Service? selected = current == null ? (available.isEmpty ? null : available.first) : db.serviceById(current.serviceId);
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خدمت جدیدی برای اختصاص وجود ندارد.')));
      return;
    }
    final price = TextEditingController(text: current?.customPrice?.toString() ?? '');
    final duration = TextEditingController(text: current?.customDurationMinutes?.toString() ?? '');
    final rate = TextEditingController(text: current?.commissionRateBps == null ? '' : (current!.commissionRateBps! / 100).toStringAsFixed(2));
    final fixed = TextEditingController(text: current?.fixedCommissionAmount?.toString() ?? '');
    final note = TextEditingController(text: current?.specialtyNote ?? '');
    var active = current?.active ?? true;
    final formKey = GlobalKey<FormState>();
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setState) => AlertDialog(
      title: Text(current == null ? 'اختصاص خدمت' : 'تنظیم خدمت اختصاصی'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (current == null) DropdownButtonFormField<Service>(
          value: selected, isExpanded: true, decoration: const InputDecoration(labelText: 'انتخاب خدمت'),
          items: [for (final item in available) DropdownMenuItem(value: item, child: Text(item.title))],
          onChanged: (value) => setState(() => selected = value),
        ) else ListTile(contentPadding: EdgeInsets.zero, title: Text(selected!.title), subtitle: Text(selected!.category)),
        TextFormField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قیمت اختصاصی (تومان)', hintText: 'خالی = قیمت عمومی'),
          validator: (v) => v != null && v.trim().isNotEmpty && (int.tryParse(FaNum.toLatin(v)) == null || int.parse(FaNum.toLatin(v)) < 0) ? 'قیمت معتبر وارد کنید' : null),
        TextFormField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مدت اختصاصی (دقیقه)', hintText: 'خالی = مدت عمومی'),
          validator: (v) => v != null && v.trim().isNotEmpty && (int.tryParse(FaNum.toLatin(v)) == null || int.parse(FaNum.toLatin(v)) <= 0) ? 'مدت معتبر وارد کنید' : null),
        TextFormField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'پورسانت اختصاصی (%)', hintText: 'خالی = قانون عمومی پرسنل'),
          validator: (v) { if (v == null || v.trim().isEmpty) return null; final n = double.tryParse(FaNum.toLatin(v).replaceAll(',', '.')); return n == null || n < 0 || n > 100 ? 'درصد باید بین صفر تا صد باشد' : null; }),
        TextFormField(controller: fixed, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ ثابت پورسانت (تومان)'),
          validator: (v) => v != null && v.trim().isNotEmpty && (int.tryParse(FaNum.toLatin(v)) == null || int.parse(FaNum.toLatin(v)) < 0) ? 'مبلغ معتبر وارد کنید' : null),
        TextFormField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات تخصصی')),
        SwitchListTile(value: active, contentPadding: EdgeInsets.zero, title: const Text('ارائه این خدمت فعال باشد'), onChanged: (v) => setState(() => active = v)),
      ])))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
        FilledButton(onPressed: () {
          if (!formKey.currentState!.validate() || selected == null) return;
          final rateValue = rate.text.trim().isEmpty ? null : (double.parse(FaNum.toLatin(rate.text).replaceAll(',', '.')) * 100).round();
          db.saveEmployeeServiceConfig(EmployeeServiceConfig(
            employeeId: employee.id, serviceId: selected!.id, active: active,
            customPrice: price.text.trim().isEmpty ? null : int.parse(FaNum.toLatin(price.text)),
            customDurationMinutes: duration.text.trim().isEmpty ? null : int.parse(FaNum.toLatin(duration.text)),
            commissionRateBps: rateValue,
            fixedCommissionAmount: fixed.text.trim().isEmpty ? null : int.parse(FaNum.toLatin(fixed.text)),
            specialtyNote: note.text.trim(),
          ));
          Navigator.pop(dialogContext);
        }, child: const Text('ذخیره')),
      ],
    )));
    price.dispose(); duration.dispose(); rate.dispose(); fixed.dispose(); note.dispose();
  }

  Future<void> _editSpecialties(BuildContext context, AppDatabase db, Employee employee) async {
    final controller = TextEditingController(text: employee.specialties.join('، '));
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('تخصص‌ها و مهارت‌ها'),
      content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: 'مهارت‌ها را با ویرگول جدا کنید')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('ذخیره')),
      ],
    ));
    if (result != null) {
      final specialties = result.split(RegExp(r'[,،]')).map((item) => item.trim()).where((item) => item.isNotEmpty).toSet().toList();
      db.updateEmployee(employee.copyWith(specialties: specialties));
    }
    controller.dispose();
  }
}

class _ServiceConfigTile extends StatelessWidget {
  const _ServiceConfigTile({required this.service, required this.config, required this.onEdit});
  final Service? service;
  final EmployeeServiceConfig config;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final details = [
      config.active ? 'فعال' : 'غیرفعال',
      config.customPrice == null ? 'قیمت عمومی' : Fmt.money(config.customPrice!),
      config.customDurationMinutes == null ? 'مدت عمومی' : FaNum.ofInt(config.customDurationMinutes!) + ' دقیقه',
      config.commissionRateBps == null ? 'پورسانت عمومی' : (config.commissionRateBps! / 100).toStringAsFixed(2) + '٪',
    ].join(' • ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: pal.surfaceAlt, child: Icon(Icons.design_services_outlined, color: pal.primary)),
      title: Text(service?.title ?? 'خدمت حذف‌شده', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      subtitle: Text(details, style: TextStyle(fontSize: 10, color: pal.textMuted)),
      trailing: IconButton(onPressed: onEdit, icon: const Icon(Icons.tune_rounded)),
    );
  }
}
