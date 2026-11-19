import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/enums.dart';
import '../providers/appointments_provider.dart';

Future<int?> _askAppointmentDiscount(BuildContext context, Appointment appointment) async {
  final controller = TextEditingController(text: '0');
  String? error;
  final result = await showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('تکمیل نوبت'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('مبلغ ناخالص: ${FaNum.ofInt(appointment.price.round())} تومان'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'تخفیف (تومان)',
                errorText: error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              final raw = FaNum.toLatin(controller.text).replaceAll(',', '').replaceAll('٬', '').trim();
              final amount = int.tryParse(raw);
              if (amount == null || amount < 0 || amount > appointment.price.round()) {
                setDialogState(() => error = 'تخفیف باید بین صفر و مبلغ ناخالص باشد.');
                return;
              }
              Navigator.pop(dialogContext, amount);
            },
            child: const Text('تأیید تکمیل'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

/// منوی اقدامات سریع نوبت (تأیید، تکمیل، لغو، حذف).
Future<void> showAppointmentActions(BuildContext context, Appointment appointment) async {
  final pal = context.pal;
  final provider = context.read<AppointmentsProvider>();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal.backgroundAlt,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(color: pal.borderStrong, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.verified_rounded, color: pal.success, size: 20),
            title: const Text('تأیید نوبت'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
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
          if (appointment.status != AppointmentStatus.completed && appointment.status != AppointmentStatus.cancelled && appointment.status != AppointmentStatus.noShow)
            ListTile(
            leading: Icon(Icons.task_alt_rounded, color: pal.accentGlow, size: 20),
            title: const Text('تکمیل نوبت'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final discount = await _askAppointmentDiscount(context, appointment);
              if (discount == null || !context.mounted) return;
              try {
                await provider.changeStatus(
                  appointment,
                  AppointmentStatus.completed,
                  discountAmount: discount,
                );
                if (context.mounted) AppToast.show(context, 'نوبت تکمیل شد و مبلغ خالص ثبت شد');
              } catch (error) {
                if (context.mounted) AppToast.show(context, 'تکمیل نوبت انجام نشد: $error', success: false);
              }
            },
          ),
          if (appointment.status != AppointmentStatus.completed && appointment.status != AppointmentStatus.cancelled && appointment.status != AppointmentStatus.noShow)
            ListTile(
            leading: Icon(Icons.person_off_rounded, color: pal.warning, size: 20),
            title: const Text('ثبت عدم حضور'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              await provider.changeStatus(appointment, AppointmentStatus.noShow);
              if (context.mounted) AppToast.show(context, 'عدم حضور ثبت شد', success: false);
            },
          ),
          if (appointment.status != AppointmentStatus.completed && appointment.status != AppointmentStatus.cancelled && appointment.status != AppointmentStatus.noShow)
            ListTile(
            leading: Icon(Icons.event_busy_rounded, color: pal.danger, size: 20),
            title: const Text('لغو نوبت'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
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
                await provider.changeStatus(appointment, AppointmentStatus.cancelled, reason: 'رد / لغو توسط پرسنل');
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
    ),
  );
}
