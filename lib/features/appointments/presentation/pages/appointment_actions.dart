import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/sensitive_operation_dialog.dart';
import '../../../activity_logs/presentation/providers/activity_provider.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/enums.dart';
import '../providers/appointments_provider.dart';

/// منوی اقدامات سریع نوبت (تأیید، تکمیل، لغو، حذف).
Future<void> showAppointmentActions(BuildContext context, Appointment appointment) async {
  final pal = context.pal;
  final provider = context.read<AppointmentsProvider>();
  await showAppSheet<void>(
    context,
    title: 'اقدامات نوبت',
    useRootNavigator: true,
    scrollable: false,
    child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.verified_rounded, color: pal.success, size: 20),
            title: const Text('تأیید نوبت'),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).pop();
              await provider.changeStatus(appointment, AppointmentStatus.confirmed);
              if (context.mounted) await _showServerUndo(context, appointment, 'نوبت تأیید شد.');
            },
          ),
          ListTile(
            leading: Icon(Icons.task_alt_rounded, color: pal.accentGlow, size: 20),
            title: const Text('تکمیل نوبت'),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).pop();
              await provider.changeStatus(appointment, AppointmentStatus.completed);
              if (context.mounted) AppToast.show(context, 'نوبت تکمیل شد');
            },
          ),
          ListTile(
            leading: Icon(Icons.person_off_rounded, color: pal.warning, size: 20),
            title: const Text('ثبت عدم حضور'),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).pop();
              await provider.changeStatus(appointment, AppointmentStatus.noShow);
              if (context.mounted) AppToast.show(context, 'عدم حضور ثبت شد', success: false);
            },
          ),
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
                await provider.changeStatus(appointment, AppointmentStatus.cancelled, reason: 'رد / لغو توسط پرسنل');
                if (context.mounted) await _showServerUndo(context, appointment, 'نوبت رد یا لغو شد.');
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
  );

Future<void> _showServerUndo(BuildContext context, Appointment appointment, String message) async {
  final activity = context.read<ActivityProvider>();
  try {
    await activity.load();
    final log = activity.logs.where((item) => item.entityId == appointment.id && item.isReversible && !item.isUndone).firstOrNull;
    if (log == null) {
      if (context.mounted) AppToast.show(context, '$message رویداد قابل بازگردانی در تاریخچه سرور پیدا نشد.');
      return;
    }
    if (!context.mounted) return;
    showUndoableOperationSnackBar(context, message: message, onUndo: () async {
      final restored = await activity.undo(log);
      if (restored) await context.read<AppointmentsProvider>().load();
      else if (context.mounted) AppToast.show(context, 'بازگردانی توسط سرور پذیرفته نشد.', success: false);
    });
  } catch (error) {
    if (context.mounted) AppToast.show(context, '$message خطا در دریافت تاریخچه سرور: $error', success: false);
  }
}
}
