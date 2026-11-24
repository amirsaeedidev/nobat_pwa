import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/enums.dart';
import '../providers/appointments_provider.dart';

/// منوی اقدامات نوبت؛ نمایش بر اساس عضویت واقعی Supabase و اجرای نهایی با کنترل مجوز دیتابیس.
Future<void> showAppointmentActions(BuildContext context, Appointment appointment) async {
  final pal = context.pal;
  final provider = context.read<AppointmentsProvider>();
  final auth = context.read<SupabaseAuthStateNotifier>();
  bool hasPermission(String permission) =>
      auth.hasActiveBusiness &&
      (auth.role == 'owner' || auth.permissions[permission] == true);

  final canConfirm = appointment.status == AppointmentStatus.pending &&
      hasPermission('appointments.confirm');
  final canReject = appointment.status == AppointmentStatus.pending &&
      hasPermission('appointments.reject');
  final canComplete = appointment.status == AppointmentStatus.confirmed &&
      hasPermission('appointments.complete');
  final canCancel = appointment.status != AppointmentStatus.completed &&
      appointment.status != AppointmentStatus.cancelled &&
      hasPermission('appointments.cancel');
  final canNoShow = canComplete && hasPermission('appointments.edit');

  await showAppSheet<void>(
    context,
    title: 'اقدامات نوبت',
    useRootNavigator: true,
    scrollable: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canConfirm)
          ListTile(
            leading: Icon(Icons.verified_rounded, color: pal.success, size: 20),
            title: const Text('تأیید نوبت'),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).pop();
              try {
                await provider.changeStatus(appointment, AppointmentStatus.confirmed);
                if (context.mounted) {
                  AppToast.show(context, 'نوبت تأیید شد و در تاریخچه فعالیت ثبت شد.');
                }
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, 'تأیید نوبت در سرور انجام نشد؛ دسترسی یا وضعیت نوبت را بررسی کنید.', success: false);
                }
              }
            },
          ),
        if (canComplete)
          ListTile(
            leading: Icon(Icons.task_alt_rounded, color: pal.accentGlow, size: 20),
            title: const Text('تکمیل نوبت'),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).pop();
              try {
                await provider.changeStatus(appointment, AppointmentStatus.completed);
                if (context.mounted) AppToast.show(context, 'نوبت تکمیل و در تاریخچه ثبت شد.');
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, 'تکمیل نوبت در سرور انجام نشد؛ دسترسی یا وضعیت نوبت را بررسی کنید.', success: false);
                }
              }
            },
          ),
        if (canNoShow)
          ListTile(
            leading: Icon(Icons.person_off_rounded, color: pal.warning, size: 20),
            title: const Text('ثبت عدم حضور'),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).pop();
              try {
                await provider.changeStatus(appointment, AppointmentStatus.noShow);
                if (context.mounted) AppToast.show(context, 'عدم حضور ثبت و در تاریخچه ذخیره شد.', success: false);
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, 'ثبت عدم حضور در سرور انجام نشد؛ دسترسی یا وضعیت نوبت را بررسی کنید.', success: false);
                }
              }
            },
          ),
        if (canCancel || canReject)
          ListTile(
            leading: Icon(Icons.event_busy_rounded, color: pal.danger, size: 20),
            title: const Text('لغو نوبت'),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).pop();
              final confirmed = await showConfirmDialog(
                context,
                title: 'لغو نوبت',
                message: 'آیا از لغو نوبت ${appointment.customerName} مطمئن هستید؟ این اقدام در گزارش فعالیت ثبت می‌شود.',
                confirmLabel: 'لغو نوبت',
                destructive: true,
                icon: Icons.event_busy_rounded,
              );
              if (confirmed) {
                try {
                  await provider.changeStatus(
                    appointment,
                    AppointmentStatus.cancelled,
                    reason: 'رد / لغو توسط پرسنل',
                    operationType: appointment.status == AppointmentStatus.pending && canReject
                        ? 'appointment_reject'
                        : null,
                  );
                  if (context.mounted) AppToast.show(context, 'نوبت رد یا لغو و در تاریخچه ثبت شد.');
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, 'لغو نوبت در سرور انجام نشد؛ دسترسی یا وضعیت نوبت را بررسی کنید.', success: false);
                  }
                }
              }
            },
          ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
