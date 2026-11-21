import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';

/// تأیید یک عملیات حساس با نمایش رکورد و شفاف‌سازی امکان بازگردانی.
Future<bool> showSensitiveOperationDialog(
  BuildContext context, {
  required String title,
  required String description,
  required Map<String, String> recordDetails,
  required bool isReversible,
  String confirmLabel = 'تأیید عملیات',
  String? warning,
}) async {
  final pal = context.pal;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(children: [
        Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(color: pal.danger.withValues(alpha: 0.12), shape: BoxShape.circle), child: Text('!', style: TextStyle(color: pal.danger, fontWeight: FontWeight.w900))),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(color: pal.textPrimary))),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(description, style: TextStyle(color: pal.textSecondary, height: 1.7)),
            if (recordDetails.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: pal.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.border)),
                child: Column(children: [
                  for (final entry in recordDetails.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 104, child: Text(entry.key, style: TextStyle(fontSize: 11, color: pal.textMuted))),
                        Expanded(child: Text(entry.value, style: TextStyle(fontSize: 11, color: pal.textPrimary, fontWeight: FontWeight.w600))),
                      ]),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isReversible ? pal.info : pal.danger).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isReversible ? '↶' : '×', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: isReversible ? pal.info : pal.danger)),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  isReversible
                    ? 'این عملیات قابل بازگردانی است؛ پس از اجرا گزینه بازگردانی در دسترس خواهد بود.'
                    : (warning ?? 'این عملیات قابل بازگردانی نیست. تاریخچه آن برای ممیزی ثبت می‌شود.'),
                  style: TextStyle(fontSize: 11, color: pal.textSecondary, height: 1.6),
                )),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: pal.danger),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return accepted == true;
}

/// پیام موفقیت با دکمه بازگردانی واقعی؛ برای عملیات غیرقابل‌بازگشت callback ندهید.
void showUndoableOperationSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'بازگردانی', onPressed: onUndo),
    ));
}
