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
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/widgets/jalali_picker.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/enums.dart';
import '../../../customers/presentation/providers/customers_provider.dart';
import '../providers/appointments_provider.dart';
import '../widgets/appointment_tile.dart';
import 'appointment_actions.dart';

/// جزئیات کامل یک نوبت با اقدامات مدیریتی.
class AppointmentDetailsPage extends StatelessWidget {
  const AppointmentDetailsPage({super.key, required this.appointmentId});

  final String appointmentId;

  Future<void> _reschedule(BuildContext context, Appointment appointment) async {
    final date = await showJalaliDatePicker(
      context,
      initial: appointment.jalali,
      minDate: JalaliDate.today(),
      maxDate: JalaliDate.today().addDays(90),
      title: 'انتخاب تاریخ جدید',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePickerSheet(context, initial: TimeOfDayLite.fromDate(appointment.startAt));
    if (time == null || !context.mounted) return;

    final provider = context.read<AppointmentsProvider>();
    final newStart = date.toDateTime().add(Duration(hours: time.hour, minutes: time.minute));
    try {
      await provider.reschedule(appointment, newStart);
      if (context.mounted) AppToast.show(context, 'نوبت جابه‌جا شد و در تاریخچه ثبت شد.');
    } catch (error) {
      if (context.mounted) {
        final message = error.toString().contains('APPOINTMENT_RESCHEDULE_LIMIT_REACHED')
            ? 'این نوبت قبلاً یک‌بار جابه‌جا شده است.'
            : 'تغییر زمان توسط سرور تأیید نشد؛ ساعات کاری، مرخصی و ظرفیت را بررسی کنید.';
        AppToast.show(context, message, success: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppointmentsProvider>();
    final appointment = provider.appointmentById(appointmentId);
    final auth = context.watch<SupabaseAuthStateNotifier>();
    final pal = context.pal;
    bool hasPermission(String permission) =>
        auth.hasActiveBusiness &&
        (auth.role == 'owner' || auth.permissions[permission] == true);

    if (appointment == null) {
      return PageScaffold(
        title: 'جزئیات نوبت',
        showBackButton: true,
        child: const EmptyState(title: 'نوبت یافت نشد', description: 'این نوبت حذف شده یا وجود ندارد.'),
      );
    }

    final canEdit = hasPermission('appointments.edit') &&
        (appointment.status == AppointmentStatus.pending || appointment.status == AppointmentStatus.confirmed);
    final canConfirm = appointment.status == AppointmentStatus.pending && hasPermission('appointments.confirm');
    final canReject = appointment.status == AppointmentStatus.pending && hasPermission('appointments.reject');
    final canComplete = appointment.status == AppointmentStatus.confirmed && hasPermission('appointments.complete');
    final canCancel =  (appointment.status == AppointmentStatus.pending || appointment.status == AppointmentStatus.confirmed) && hasPermission('appointments.cancel');
    final canDelete = hasPermission('appointments.cancel');
    final canOpenActions = canConfirm || canReject || canComplete || canCancel || canDelete ||
        (appointment.status == AppointmentStatus.confirmed && hasPermission('appointments.edit'));
    final canReschedule = canEdit && appointment.rescheduleCount < 1 &&
        (appointment.status == AppointmentStatus.pending || appointment.status == AppointmentStatus.confirmed);

    final customer = context.watch<CustomersProvider>().findById(appointment.customerId);
    final history = provider.allAppointments
        .where((a) => a.customerId == appointment.customerId && a.id != appointment.id)
        .toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));

    return PageScaffold(
      title: 'جزئیات نوبت',
      subtitle: 'کد پیگیری ${FaNum.convert(appointment.reference)}',
      icon: Icons.event_available_rounded,
      showBackButton: true,
      actions: [
        if (canEdit)
          SoftButton(
            label: 'ویرایش',
            icon: Icons.edit_rounded,
            onTap: () => context.push('/appointments/${appointment.id}/edit'),
          ),
        if (canOpenActions)
          SoftButton(
            label: 'اقدامات',
            icon: Icons.more_horiz_rounded,
            onTap: () => showAppointmentActions(context, appointment),
          ),
      ],
      mobileActions: [
        if (canEdit)
          CircleIconButton(
            icon: Icons.edit_rounded,
            size: 38,
            onTap: () => context.push('/appointments/${appointment.id}/edit'),
          ),
        if (canOpenActions)
          CircleIconButton(
            icon: Icons.more_horiz_rounded,
            size: 38,
            onTap: () => showAppointmentActions(context, appointment),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusHero(appointment: appointment),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final details = AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'اطلاعات نوبت'),
                    const SizedBox(height: 10),
                    InfoRow(label: 'خدمت', value: appointment.serviceName, icon: Icons.content_cut_rounded),
                    InfoRow(label: 'متخصص', value: appointment.employeeName, icon: Icons.badge_outlined),
                    InfoRow(label: 'تاریخ', value: appointment.jalali.long, icon: Icons.calendar_today_rounded),
                    InfoRow(
                      label: 'ساعت',
                      value: Fmt.range(
                        appointment.startAt.hour,
                        appointment.startAt.minute,
                        appointment.endAt.hour,
                        appointment.endAt.minute,
                      ),
                      icon: Icons.access_time_rounded,
                    ),
                    InfoRow(label: 'مدت', value: Fmt.duration(appointment.durationMinutes), icon: Icons.timelapse_rounded),
                    InfoRow(
                      label: 'مبلغ',
                      value: Fmt.money(appointment.price),
                      icon: Icons.payments_rounded,
                      valueColor: pal.success,
                    ),
                    InfoRow(label: 'ثبت توسط', value: appointment.createdBy, icon: Icons.person_outline_rounded),
                    if (appointment.note.isNotEmpty) ...[
                      const Divider(height: 20),
                      Text('یادداشت', style: TextStyle(fontSize: 11.5, color: pal.textMuted)),
                      const SizedBox(height: 4),
                      Text(
                        appointment.note,
                        style: TextStyle(fontSize: 12, color: pal.textSecondary, height: 1.8),
                      ),
                    ],
                    if (appointment.cancelReason != null) ...[
                      const Divider(height: 20),
                      Text(
                        'دلیل لغو: ${appointment.cancelReason}',
                        style: TextStyle(fontSize: 11.5, color: pal.danger),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (canReschedule)
                          Expanded(
                            child: SoftButton(
                              label: 'جابه‌جایی',
                              icon: Icons.swap_horiz_rounded,
                              onTap: () => _reschedule(context, appointment),
                            ),
                          ),
                        if (canReschedule) const SizedBox(width: 8),
                        Expanded(
                          child: SoftButton(
                            label: 'مشاهده مشتری',
                            icon: Icons.person_rounded,
                            onTap: () => context.push('/customers/${appointment.customerId}'),
                          ),
                        ),
                      ],
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
                        const SectionHeader(title: 'مشتری'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            AvatarBadge(name: appointment.customerName, size: 46, color: pal.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appointment.customerName,
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: pal.textPrimary),
                                  ),
                                  Text(
                                    Fmt.phone(appointment.customerPhone),
                                    style: TextStyle(fontSize: 11, color: pal.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStat(
                                label: 'مراجعه',
                                value: FaNum.ofInt(customer?.visitCount ?? 0),
                                color: pal.primaryBright,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniStat(
                                label: 'خرید کل',
                                value: Fmt.compactMoney(customer?.totalSpent ?? 0).replaceAll(' تومان', ''),
                                color: pal.success,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniStat(
                                label: 'لغو',
                                value: FaNum.ofInt(customer?.cancelCount ?? 0),
                                color: pal.danger,
                              ),
                            ),
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
                        SectionHeader(title: 'تاریخچه نوبت‌های مشتری', subtitle: '${FaNum.ofInt(history.length)} نوبت دیگر'),
                        const SizedBox(height: 8),
                        if (history.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text('نوبت دیگری ثبت نشده است.',
                                style: TextStyle(fontSize: 11.5, color: pal.textMuted)),
                          )
                        else
                          for (final item in history.take(5)) ...[
                            CompactAppointmentRow(
                              appointment: item,
                              showDate: true,
                              onTap: () => context.push('/appointments/${item.id}'),
                            ),
                            const SizedBox(height: 6),
                          ],
                      ],
                    ),
                  ),
                ],
              );

              if (!wide) {
                return Column(children: [details, const SizedBox(height: 12), side]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: details),
                  const SizedBox(width: 12),
                  Expanded(flex: 4, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final status = appointment.status;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [status.color.withValues(alpha: 0.32), pal.surface],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: status.color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusBadge(label: status.label, color: status.color, filled: true, icon: status.icon),
              Text(
                appointment.jalali.relativeLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: pal.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 6,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Fmt.time(appointment.startAt.hour, appointment.startAt.minute),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: pal.textPrimary, height: 1.1),
                  ),
                  Text(
                    appointment.jalali.long,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: pal.textSecondary),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.52),
                    child: Text(
                      appointment.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pal.textPrimary),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.52),
                    child: Text(
                      appointment.employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 11, color: pal.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (canConfirm || canComplete || canCancel)
            Row(
              children: [
                if (canConfirm)
                  Expanded(
                    child: SoftButton(
                      label: 'تأیید',
                      icon: Icons.verified_rounded,
                      color: pal.success,
                      onTap: () async {
                        try {
                          await context.read<AppointmentsProvider>().changeStatus(
                            appointment, AppointmentStatus.confirmed);
                          if (context.mounted) AppToast.show(context, 'نوبت تأیید و در تاریخچه ثبت شد.');
                        } catch (error) {
                          if (context.mounted) AppToast.show(context, 'تأیید نوبت انجام نشد: $error', success: false);
                        }
                      },
                    ),
                  ),
                if (canConfirm && (canComplete || canCancel)) const SizedBox(width: 8),
                if (canComplete)
                  Expanded(
                    child: SoftButton(
                      label: 'تکمیل',
                      icon: Icons.task_alt_rounded,
                      color: pal.accentGlow,
                      onTap: () async {
                        final confirmed = await showSensitiveOperationDialog(
                          context,
                          title: 'تأیید تکمیل نوبت',
                          description: 'وضعیت نوبت نهایی می‌شود و رویداد تکمیل در تاریخچه فعالیت ثبت خواهد شد.',
                          recordDetails: {
                            'کد نوبت': appointment.reference,
                            'مشتری': appointment.customerName,
                            'خدمت': appointment.serviceName,
                            'پرسنل': appointment.employeeName,
                            'مبلغ خدمت': '${FaNum.ofInt(appointment.price.round())} تومان',
                            'زمان': '${appointment.jalali.long}، ${appointment.startAt.hour.toString().padLeft(2, '0')}:${appointment.startAt.minute.toString().padLeft(2, '0')}',
                          },
                          isReversible: false,
                          warning: 'تکمیل نوبت قابل بازگردانی نیست؛ تغییرات بعدی باید با عملیات اصلاحی مجاز انجام شوند.',
                          confirmLabel: 'تکمیل نوبت',
                        );
                        if (!confirmed || !context.mounted) return;
                        try {
                          await context.read<AppointmentsProvider>().changeStatus(
                            appointment, AppointmentStatus.completed);
                          if (context.mounted) AppToast.show(context, 'نوبت تکمیل و در تاریخچه ثبت شد.');
                        } catch (error) {
                          if (context.mounted) AppToast.show(context, 'تکمیل نوبت انجام نشد: $error', success: false);
                        }
                      },
                    ),
                  ),
                if (canCancel) ...[
                  if (canConfirm || canComplete) const SizedBox(width: 8),
                  Expanded(
                    child: SoftButton(
                      label: 'لغو',
                      icon: Icons.event_busy_rounded,
                      color: pal.danger,
                      onTap: () async {
                        final confirmed = await showSensitiveOperationDialog(
                          context,
                          title: 'تأیید لغو نوبت',
                          description: 'وضعیت نوبت به لغوشده تغییر می‌کند. تاریخچه و اسناد مالی مرتبط حذف نمی‌شوند.',
                          recordDetails: {
                            'کد نوبت': appointment.reference,
                            'مشتری': appointment.customerName,
                            'خدمت': appointment.serviceName,
                            'پرسنل': appointment.employeeName,
                            'زمان': '${appointment.jalali.long}، ${appointment.startAt.hour.toString().padLeft(2, '0')}:${appointment.startAt.minute.toString().padLeft(2, '0')}',
                          },
                          isReversible: false,
                          confirmLabel: 'لغو نوبت',
                        );
                        if (!confirmed || !context.mounted) return;
                        try {
                          await context.read<AppointmentsProvider>().changeStatus(
                            appointment, AppointmentStatus.cancelled, reason: 'لغو توسط پرسنل');
                          if (context.mounted) AppToast.show(context, 'نوبت لغو و در تاریخچه ثبت شد.');
                        } catch (error) {
                          if (context.mounted) AppToast.show(context, 'لغو نوبت انجام نشد: $error', success: false);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          if (appointment.status == AppointmentStatus.pending && canReject) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SoftButton(
                label: 'رد درخواست نوبت',
                color: pal.danger,
                onTap: () async {
                  final confirmed = await showSensitiveOperationDialog(
                    context,
                    title: 'تأیید رد درخواست نوبت',
                    description: 'درخواست این نوبت رد می‌شود. سوابق مشتری و هرگونه سند مالی مرتبط حفظ خواهد شد.',
                    recordDetails: {
                      'کد نوبت': appointment.reference,
                      'مشتری': appointment.customerName,
                      'خدمت': appointment.serviceName,
                      'پرسنل': appointment.employeeName,
                      'زمان': '${appointment.jalali.long}، ${appointment.startAt.hour.toString().padLeft(2, '0')}:${appointment.startAt.minute.toString().padLeft(2, '0')}',
                    },
                    isReversible: false,
                    confirmLabel: 'رد درخواست',
                  );
                  if (!confirmed || !context.mounted) return;
                  try {
                    await context.read<AppointmentsProvider>().changeStatus(
                      appointment,
                      AppointmentStatus.cancelled,
                      reason: 'رد درخواست توسط مدیر',
                      operationType: 'appointment_reject',
                    );
                    if (context.mounted) AppToast.show(context, 'درخواست نوبت رد و در تاریخچه ثبت شد.');
                  } catch (error) {
                    if (context.mounted) AppToast.show(context, '$error', success: false);
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 9.5, color: pal.textMuted)),
        ],
      ),
    );
  }
}
