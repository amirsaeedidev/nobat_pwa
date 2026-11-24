import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/service.dart';
import '../../../../data/repositories/service_repository.dart';
import '../../../employees/presentation/providers/employees_provider.dart';
import '../providers/services_provider.dart';

class ServiceDetailsPage extends StatefulWidget {
  const ServiceDetailsPage({super.key, required this.serviceId});
  final String serviceId;

  @override
  State<ServiceDetailsPage> createState() => _ServiceDetailsPageState();
}

class _ServiceDetailsPageState extends State<ServiceDetailsPage> {
  late Future<_ServiceDetailsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ServiceDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serviceId != widget.serviceId) _future = _load();
  }

  Future<_ServiceDetailsData> _load() async {
    final provider = context.read<ServicesProvider>();
    final service = await provider.byId(widget.serviceId);
    if (service == null) {
      throw StateError('خدمت در Supabase پیدا نشد یا دسترسی مشاهده آن وجود ندارد.');
    }
    final history = await provider.fetchServiceHistory(widget.serviceId);
    return _ServiceDetailsData(service: service, history: history);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    final employeesProvider = context.watch<EmployeesProvider>();
    final pal = context.pal;

    return FutureBuilder<_ServiceDetailsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const PageScaffold(
            title: 'جزئیات خدمت',
            showBackButton: true,
            child: LoadingState(kind: SkeletonKind.services),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return PageScaffold(
            title: 'جزئیات خدمت',
            showBackButton: true,
            child: ErrorStateView(
              description: snapshot.error?.toString() ?? 'اطلاعات خدمت در دسترس نیست.',
              onRetry: _refresh,
            ),
          );
        }

        final service = snapshot.data!.service;
        final history = snapshot.data!.history;
        final employees = employeesProvider.items
            .where((employee) => service.employeeIds.contains(employee.id))
            .toList(growable: false);
        final status = service.archivedAt != null
            ? 'بایگانی'
            : (service.isActive ? 'فعال' : 'غیرفعال');

        return PageScaffold(
          title: service.title,
          subtitle: 'جزئیات ثبت‌شده در پایگاه داده',
          icon: Icons.content_cut_rounded,
          showBackButton: true,
          actions: [
            TextButton.icon(
              onPressed: () => context.push('/services/${widget.serviceId}/edit'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('ویرایش'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            service.title,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: pal.textPrimary,
                            ),
                          ),
                        ),
                        Chip(label: Text(status)),
                      ],
                    ),
                    if (service.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(service.description),
                      ),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 18,
                      runSpacing: 12,
                      children: [
                        _Metric(label: 'قیمت اصلی', value: Fmt.money(service.price)),
                        _Metric(label: 'قیمت امروز', value: Fmt.money(service.priceAt(DateTime.now()))),
                        _Metric(label: 'مدت کل', value: Fmt.duration(service.totalMinutes)),
                        _Metric(label: 'دسته‌بندی', value: service.category),
                        _Metric(label: 'مهلت رزرو', value: '${FaNum.ofInt(service.advanceDays)} روز'),
                        if (service.maxPerDay != null)
                          _Metric(label: 'ظرفیت روزانه', value: FaNum.ofInt(service.maxPerDay!)),
                        _Metric(
                          label: 'تأیید دستی',
                          value: service.requiresConfirmation ? 'الزامی' : 'نیست',
                        ),
                      ],
                    ),
                    if (service.discountPrice != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'قیمت تخفیفی: ${Fmt.money(service.discountPrice!)}',
                        style: TextStyle(color: pal.success, fontWeight: FontWeight.w700),
                      ),
                      if (service.discountStartsAt != null || service.discountEndsAt != null)
                        Text(
                          'بازه تخفیف: ${service.discountStartsAt == null ? 'بدون شروع' : _date(service.discountStartsAt!)} تا ${service.discountEndsAt == null ? 'بدون پایان' : _date(service.discountEndsAt!)}',
                          style: TextStyle(fontSize: 11, color: pal.textMuted),
                        ),
                    ],
                    if (service.imageUrl != null && service.imageUrl!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: service.imageUrl!.startsWith('assets/')
                              ? Image.asset(
                                  service.imageUrl!,
                                  height: 170,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                )
                              : Image.network(
                                  service.imageUrl!,
                                  height: 170,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _MetricCard(
                title: 'سوابق نوبت قابل مشاهده',
                value: FaNum.ofInt(history.totalCount),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('پرسنل ارائه‌دهنده', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (service.employeeIds.isEmpty)
                      const Text('هیچ پرسنل فعالی برای این خدمت ثبت نشده است.')
                    else if (employees.isEmpty && employeesProvider.loading)
                      const LoadingState(kind: SkeletonKind.personnel, compact: true)
                    else if (employees.isEmpty)
                      const Text('اطلاعات پرسنل متصل به این خدمت برای حساب فعلی قابل مشاهده نیست.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final employee in employees)
                            Chip(label: Text(employee.fullName)),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('آخرین نوبت‌ها', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (history.items.isEmpty)
                      const Text('نوبت قابل مشاهده‌ای برای این خدمت ثبت نشده است.')
                    else
                      for (final item in history.items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.reference.isEmpty ? item.title : item.reference),
                          subtitle: Text(
                            '${_date(item.startsAt)} • ${_statusLabel(item.status)}',
                          ),
                          trailing: Text(Fmt.money(item.price)),
                        ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _date(DateTime value) {
    final jalali = JalaliDate.fromDateTime(value);
    final time = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '${jalali.numeric} $time';
  }

  static String _statusLabel(String status) => switch (status) {
    'pending' => 'در انتظار',
    'confirmed' => 'تأییدشده',
    'completed' => 'تکمیل‌شده',
    'cancelled' => 'لغوشده',
    'rejected' => 'ردشده',
    'no_show' => 'عدم مراجعه',
    _ => status,
  };
}

class _ServiceDetailsData {
  const _ServiceDetailsData({required this.service, required this.history});
  final Service service;
  final ServiceHistoryPage history;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: context.pal.textMuted)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: context.pal.textPrimary)),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text(title, style: TextStyle(fontSize: 11, color: context.pal.textMuted)),
      ],
    ),
  );
}
