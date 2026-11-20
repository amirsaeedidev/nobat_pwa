import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../data/mock/app_database.dart';

class ServiceDetailsPage extends StatelessWidget {
  const ServiceDetailsPage({super.key, required this.serviceId});
  final String serviceId;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final service = db.serviceById(serviceId);
    if (service == null) return const PageScaffold(title: 'جزئیات خدمت', child: Center(child: Text('خدمت پیدا نشد.')));
    final appointments = db.appointments.where((item) => item.serviceIds.contains(serviceId)).toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    final entries = db.employeeFinanceEntries.where((item) => item.serviceId == serviceId);
    final revenue = entries.fold<int>(0, (sum, item) => sum + item.receivedAmount);
    final employees = service.employeeIds.map(db.employeeById).whereType<dynamic>().toList();
    final pal = context.pal;
    return PageScaffold(
      title: service.title,
      subtitle: 'جزئیات خدمت و سوابق مرتبط',
      icon: Icons.content_cut_rounded,
      showBackButton: true,
      actions: [TextButton.icon(onPressed: () => context.push('/services/' + serviceId + '/edit'), icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(service.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: pal.textPrimary))), Chip(label: Text(service.isActive ? 'فعال' : 'غیرفعال'))]),
          if (service.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(service.description)),
          const Divider(height: 24),
          Wrap(spacing: 18, runSpacing: 12, children: [
            _Metric(label: 'قیمت اصلی', value: Fmt.money(service.price)),
            _Metric(label: 'قیمت فعلی', value: Fmt.money(service.priceAt(DateTime.now()))),
            _Metric(label: 'مدت خدمت', value: Fmt.duration(service.durationMinutes)),
            _Metric(label: 'دسته‌بندی', value: service.category),
          ]),
          if (service.imageUrl != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('تصویر: ' + service.imageUrl!)),
        ])),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _MetricCard(title: 'تعداد نوبت‌ها', value: FaNum.ofInt(appointments.length))),
          const SizedBox(width: 10),
          Expanded(child: _MetricCard(title: 'دریافتی ثبت‌شده', value: Fmt.money(revenue))),
        ]),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('پرسنل ارائه‌دهنده', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (employees.isEmpty) const Text('پرسنلی به این خدمت متصل نیست.')
          else Wrap(spacing: 8, children: [for (final employee in employees) Chip(label: Text(employee.fullName))]),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('آخرین نوبت‌ها', style: TextStyle(fontWeight: FontWeight.w800)),
          if (appointments.isEmpty) const Text('هنوز نوبتی ثبت نشده است.')
          else for (final item in appointments.take(8)) ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.customerName),
            subtitle: Text(item.employeeName + ' • ' + item.startAt.toLocal().toString()),
            trailing: Text(FaNum.ofInt(item.price.toInt())),
          ),
        ])),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 11, color: context.pal.textMuted)),
    const SizedBox(height: 3),
    Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: context.pal.textPrimary)),
  ]);
}
class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    Text(title, style: TextStyle(fontSize: 11, color: context.pal.textMuted)),
  ]));
}
