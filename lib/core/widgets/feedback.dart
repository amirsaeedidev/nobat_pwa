import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_tokens.dart';
import 'async_states.dart';
import '../models/app_failure.dart';

export 'async_states.dart';
export '../models/app_failure.dart';

/// حالت خالی با آیکون و توضیح.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.title = 'موردی یافت نشد',
    this.description = 'فیلترها را تغییر دهید یا داده جدیدی ثبت کنید.',
    this.icon = Icons.inbox_rounded,
    this.action,
    this.compact = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 24 : 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(
                color: pal.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: pal.border),
              ),
              child: Icon(icon, size: compact ? 26 : 32, color: pal.textMuted),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pal.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: pal.textMuted, height: 1.7),
            ),
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// اسکلتون مشترک صفحات با الگوی متناسب با نوع محتوا.
class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    this.label = 'در حال آماده‌سازی...',
    this.compact = false,
    this.kind = SkeletonKind.generic,
  });

  final String label;
  final bool compact;
  final SkeletonKind kind;

  @override
  Widget build(BuildContext context) => PageSkeleton(kind: kind, compact: compact);
}

/// خطای یکپارچه؛ پیام‌ها بر اساس نوع خطا و امکان تلاش مجدد تعیین می‌شوند.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    this.title,
    this.description,
    this.onRetry,
    this.kind = AppErrorKind.fetch,
  });

  final String? title;
  final String? description;
  final VoidCallback? onRetry;
  final AppErrorKind kind;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final message = AppFailure(kind).persianMessage;
    final canRetry = onRetry != null && AppFailure(kind).canRetry;
    final icon = switch (kind) {
      AppErrorKind.connection => Icons.wifi_off_rounded,
      AppErrorKind.fetch => Icons.cloud_download_outlined,
      AppErrorKind.save => Icons.save_outlined,
      AppErrorKind.validation => Icons.rule_rounded,
      AppErrorKind.access => Icons.lock_outline_rounded,
      AppErrorKind.server => Icons.dns_outlined,
      AppErrorKind.unknown => Icons.error_outline_rounded,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 38, color: pal.danger),
          const SizedBox(height: 12),
          Text(title ?? switch (kind) {
            AppErrorKind.connection => 'عدم برقراری ارتباط',
            AppErrorKind.fetch => 'خطا در دریافت اطلاعات',
            AppErrorKind.save => 'ذخیره‌سازی ناموفق بود',
            AppErrorKind.validation => 'اطلاعات نیاز به اصلاح دارد',
            AppErrorKind.access => 'دسترسی مجاز نیست',
            AppErrorKind.server => 'خطای سرور',
            AppErrorKind.unknown => 'عملیات ناموفق بود',
          }, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pal.textPrimary)),
          const SizedBox(height: 6),
          Text(description ?? message, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: pal.textMuted, height: 1.7)),
          if (canRetry) ...[
            const SizedBox(height: 16),
            TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('تلاش مجدد')),
          ],
        ]),
      ),
    );
  }
}

/// اطلاع‌رسانی غیرمسدودکننده هنگام استفاده از نسخه محلی داده‌ها.
class OfflineDataNotice extends StatelessWidget {
  const OfflineDataNotice({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: pal.info.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.info.withValues(alpha: 0.24)),
      ),
      child: Row(children: [
        Icon(Icons.cloud_off_rounded, size: 17, color: pal.info),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(fontSize: 10.5, color: pal.textSecondary, height: 1.6))),
      ]),
    );
  }
}

/// نمایش پیام کوتاه (SnackBar) با استایل اپلیکیشن.
class AppToast {
  const AppToast._();

  static void show(BuildContext context, String message, {bool success = true, IconData? icon}) {
    final pal = context.pal;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.all(16),
          backgroundColor: pal.surfaceHigh,
          content: Row(
            children: [
              Icon(
                icon ?? (success ? Icons.check_circle_rounded : Icons.error_rounded),
                color: success ? pal.success : pal.danger,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(fontSize: 12.5, color: pal.textPrimary, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// دیالوگ تأیید با استایل اختصاصی (RTL).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأیید',
  String cancelLabel = 'انصراف',
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final pal = context.pal;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (destructive ? pal.danger : pal.primary).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: destructive ? pal.danger : pal.primaryBright, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: TextStyle(fontSize: 12.5, color: pal.textSecondary, height: 1.8),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: destructive ? pal.danger : pal.primary,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// نمایش شیت پایین با کشیدن‌کننده و عنوان.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  bool scrollable = true,
}) {
  final pal = context.pal;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.backgroundAlt,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.brTopXxl),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: pal.borderStrong, borderRadius: AppRadius.brPill),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.textPrimary),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, size: 18, color: pal.textMuted),
                  ),
                ],
              ),
            ),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: child,
                    )
                  : Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: child),
            ),
          ],
        ),
      ),
    ),
  );
}
