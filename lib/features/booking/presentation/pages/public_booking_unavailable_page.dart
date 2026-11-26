import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';

/// Public booking remains routed but fails closed until secure anonymous
/// booking/catalog RPCs are installed in Supabase. Never show demo records.
class PublicBookingUnavailablePage extends StatelessWidget {
  const PublicBookingUnavailablePage({super.key, this.manage = false});

  final bool manage;

  @override
  Widget build(BuildContext context) {
    final palette = context.pal;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 54, color: palette.textMuted),
                  const SizedBox(height: 18),
                  Text(
                    manage ? 'پیگیری عمومی نوبت فعلاً در دسترس نیست' : 'رزرو عمومی فعلاً در دسترس نیست',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: palette.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'برای جلوگیری از نمایش اطلاعات آزمایشی یا ثبت نوبت ناامن، این بخش تا نصب و تأیید سرویس عمومی امن در Supabase غیرفعال است. اطلاعات واقعی برنامه تغییری نمی‌کند.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.9, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
