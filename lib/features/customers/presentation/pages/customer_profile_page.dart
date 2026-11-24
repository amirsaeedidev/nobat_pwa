import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import '../../../../data/models/customer.dart';
import '../../../appointments/presentation/widgets/appointment_tile.dart';
import '../providers/customers_provider.dart';

/// پروفایل حرفه‌ای مشتری با تاریخچه، آمار و شاخص پایبندی.
class CustomerProfilePage extends StatefulWidget {
  const CustomerProfilePage({super.key, required this.customerId});

  final String customerId;

  @override
  State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _CustomerProfilePageState extends State<CustomerProfilePage> {
  late Future<CustomerProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = context.read<CustomersProvider>().fetchProfile(widget.customerId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CustomerProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return PageScaffold(
            title: 'پروفایل مشتری',
            showBackButton: true,
            child: const LoadingState(kind: SkeletonKind.customers),
          );
        }
        if (snapshot.hasError) {
          return PageScaffold(
            title: 'پروفایل مشتری',
            showBackButton: true,
            child: ErrorStateView(
              description: 'دریافت پروفایل از Supabase ناموفق بود. اطلاعات محلی جایگزین نمی‌شود.',
              onRetry: () => setState(() {
                _profileFuture = context.read<CustomersProvider>().fetchProfile(widget.customerId);
              }),
            ),
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return PageScaffold(
            title: 'پروفایل مشتری',
            showBackButton: true,
            child: const EmptyState(title: 'مشتری یافت نشد', description: 'این مشتری در مجموعه فعلی وجود ندارد یا قابل مشاهده نیست.'),
          );
        }
        final pal = context.pal;
        final customer = profile.customer;
        final appointments = profile.appointments;
        final services = profile.services;
        final upcoming = appointments.where((a) => a.status.isActive && a.startAt.isAfter(DateTime.now())).toList();

    Future<void> deleteCustomer() async {
      final confirmed = await showSensitiveOperationDialog(
        context,
        title: 'حذف یا بایگانی مشتری',
        description: 'پروفایل مشتری در Supabase بایگانی می‌شود و سوابق نوبت و پرداخت‌های مرتبط حفظ می‌شوند. هر زمان امکان بازیابی وجود دارد.',
        recordDetails: {
          'نام مشتری': customer.fullName,
          'شماره تماس': customer.phone,
          'تعداد سوابق نوبت': appointments.length.toString(),
          'مجموع خرید': profile.financeVisible ? '${FaNum.ofInt(customer.totalSpent.round())} تومان' : 'بدون مجوز مشاهده مالی',
        },
        isReversible: true,
        confirmLabel: 'ادامه عملیات',
      );
      if (!confirmed || !context.mounted) return;
      final customersProvider = context.read<CustomersProvider>();
      try {
        await customersProvider.delete(customer.id);
        if (context.mounted) {
          AppToast.show(context, 'پروفایل مشتری در Supabase بایگانی شد.');
          context.pop();
        }
      } catch (error) {
        if (context.mounted) AppToast.show(context, '$error', success: false);
      }
    }

    return PageScaffold(
      title: 'پروفایل مشتری',
      subtitle: Fmt.phone(customer.phone),
      icon: Icons.person_rounded,
      showBackButton: true,
      actions: [
        if (customer.isArchived)
          SoftButton(label: 'بازیابی از بایگانی', icon: Icons.unarchive_rounded, onTap: () async {
            try {
              await context.read<CustomersProvider>().update(customer.copyWith(isArchived: false));
              if (!context.mounted) return;
              AppToast.show(context, 'مشتری از بایگانی بازیابی شد.');
              setState(() => _profileFuture = context.read<CustomersProvider>().fetchProfile(widget.customerId));
            } catch (error) {
              if (context.mounted) AppToast.show(context, 'بازیابی مشتری انجام نشد: $error', success: false);
            }
          })
        else
          SoftButton(label: 'حذف / بایگانی', color: pal.danger, onTap: deleteCustomer),
        SoftButton(label: 'ویرایش', icon: Icons.edit_rounded, onTap: () => context.push('/customers/${customer.id}/edit')),
        SolidButton(
          label: 'نوبت جدید',
          icon: Icons.add_rounded,
          height: 42,
          onPressed: () => context.push('/appointments/new'),
        ),
      ],
      mobileActions: [
        if (!customer.isArchived) TextButton(onPressed: deleteCustomer, child: const Text('بایگانی')),
        CircleIconButton(icon: Icons.edit_rounded, size: 38, onTap: () => context.push('/customers/${customer.id}/edit')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            gradient: LinearGradient(
              colors: [pal.primary.withValues(alpha: 0.24), pal.surface],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderColor: pal.primary.withValues(alpha: 0.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: pal.primaryGradient,
                        boxShadow: AppShadows.glow(pal.primary, opacity: 0.3, blur: 18),
                      ),
                      child: Text(
                        customer.initials,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.fullName,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: pal.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(Fmt.phone(customer.phone), style: TextStyle(fontSize: 12, color: pal.textSecondary)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final tag in customer.tags)
                                StatusBadge(label: tag, color: pal.primaryBright, dense: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ReliabilityBar(customer: customer),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _Stat(label: 'مراجعه', value: FaNum.ofInt(customer.visitCount), color: pal.primaryBright)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Stat(
                        label: 'خرید کل',
                        value: profile.financeVisible ? Fmt.compactMoney(customer.totalSpent).replaceAll(' تومان', '') : '—',
                        color: pal.success,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _Stat(label: 'لغو', value: FaNum.ofInt(customer.cancelCount), color: pal.danger)),
                    const SizedBox(width: 8),
                    Expanded(child: _Stat(label: 'عدم حضور', value: FaNum.ofInt(customer.noShowCount), color: pal.warning)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final history = AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: 'تاریخچه نوبت‌ها',
                      subtitle: '${FaNum.ofInt(appointments.length)} نوبت ثبت‌شده',
                    ),
                    const SizedBox(height: 10),
                    if (appointments.isEmpty)
                      const EmptyState(compact: true, title: 'نوبتی ثبت نشده', description: '')
                    else
                      for (final appointment in appointments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: CompactAppointmentRow(
                            appointment: appointment,
                            showDate: true,
                            onTap: () => context.push('/appointments/${appointment.id}'),
                          ),
                        ),
                  ],
                ),
              );

              final side = Column(
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'اطلاعات مشتری'),
                        const SizedBox(height: 8),
                        InfoRow(
                          label: 'تاریخ ثبت',
                          value: customer.createdAt == null ? '—' : JalaliDate.fromDateTime(customer.createdAt!).long,
                          icon: Icons.calendar_today_rounded,
                        ),
                        InfoRow(
                          label: 'آخرین مراجعه',
                          value: customer.lastVisitAt == null ? 'ندارد' : JalaliDate.fromDateTime(customer.lastVisitAt!).long,
                          icon: Icons.history_rounded,
                        ),
                        if (profile.financeVisible) ...[
                          InfoRow(
                            label: 'مبلغ خدمات انجام‌شده',
                            value: '${FaNum.ofInt((profile.totalBilled ?? 0).round())} تومان',
                            icon: Icons.receipt_long_rounded,
                          ),
                          InfoRow(
                            label: 'دریافتی خالص',
                            value: '${FaNum.ofInt((profile.totalPaid ?? 0).round())} تومان',
                            icon: Icons.payments_outlined,
                          ),
                          InfoRow(
                            label: 'مانده حساب',
                            value: '${FaNum.ofInt((profile.outstanding ?? 0).round())} تومان',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                        ] else
                          const InfoRow(
                            label: 'اطلاعات مالی',
                            value: 'دسترسی مشاهده مالی ندارید',
                            icon: Icons.lock_outline_rounded,
                          ),
                        InfoRow(
                          label: 'نوبت آینده',
                          value: upcoming.isEmpty ? 'ندارد' : upcoming.first.jalali.long,
                          icon: Icons.event_available_rounded,
                          valueColor: upcoming.isEmpty ? null : pal.success,
                        ),
                        const Divider(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('یادداشت داخلی', style: TextStyle(fontSize: 11.5, color: pal.textMuted)),
                            SoftButton(
                              label: 'ویرایش',
                              icon: Icons.edit_rounded,
                              dense: true,
                              onTap: () => context.push('/customers/${customer.id}/edit'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          customer.notes.isEmpty ? 'یادداشتی ثبت نشده است.' : customer.notes,
                          style: TextStyle(fontSize: 11.5, color: pal.textSecondary, height: 1.9),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'خدمات دریافت‌شده'),
                        const SizedBox(height: 10),
                        if (services.isEmpty)
                          Text('خدمتی ثبت نشده است.', style: TextStyle(fontSize: 11, color: pal.textMuted))
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final service in services)
                                StatusBadge(label: service, color: pal.success, dense: true),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              );

              if (!wide) {
                return Column(children: [side, const SizedBox(height: 12), history]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: history),
                  const SizedBox(width: 12),
                  Expanded(flex: 4, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
      },
    );
  }
}

class _ReliabilityBar extends StatelessWidget {
  const _ReliabilityBar({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final value = customer.reliability / 100;
    final color = customer.reliability >= 70 ? pal.success : (customer.reliability >= 50 ? pal.warning : pal.danger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.workspace_premium_rounded, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              customer.reliabilityLabel,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
            ),
            const Spacer(),
            Text(
              '${FaNum.ofInt(customer.reliability)}٪',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: pal.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 7,
            backgroundColor: pal.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 9, color: pal.textMuted)),
        ],
      ),
    );
  }
}
