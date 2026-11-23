import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/feedback.dart';
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
              final previousStatus = appointment.status;
              await provider.changeStatus(appointment, AppointmentStatus.confirmed);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('نوبت تأیید شد'),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(label: 'برگشت', onPressed: () => provider.changeStatus(appointment, previousStatus, reason: 'بازگردانی تأیید نوبت')),
                ));
              }
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
                final previousStatus = appointment.status;
                await provider.changeStatus(
                  appointment,
                  AppointmentStatus.cancelled,
                  reason: 'رد / لغو توسط پرسنل',
                  operationType: appointment.status == AppointmentStatus.pending ? 'appointment_reject' : null,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('نوبت رد یا لغو شد'),
                    behavior: SnackBarBehavior.floating,
                    action: SnackBarAction(label: 'برگشت', onPressed: () => provider.changeStatus(appointment, previousStatus, reason: 'بازگردانی رد نوبت')),
                  ));
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
  );
}
