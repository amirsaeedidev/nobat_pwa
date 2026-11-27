import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../data/repositories/supabase_auth_repository.dart';
import '../providers/settings_provider.dart';

/// مرکز تنظیمات؛ دسترسی به همه پیکربندی‌ها و ماژول‌های مدیریتی.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final business = settings.settings;
    final pal = context.pal;
    final authRepository = context.read<SupabaseAuthRepository?>();
    final authSession = context.watch<SupabaseAuthStateNotifier?>();
    final cloudUser = authRepository?.currentUser;

    final items = <_SettingEntry>[
      _SettingEntry('تعویض تم', 'انتخاب تم کلی برنامه و تم مستقل فرم‌ها', Icons.palette_rounded, pal.primaryBright, '/settings/appearance'),
      _SettingEntry('اطلاعات مجموعه', 'نام، تماس، آدرس و شبکه‌های اجتماعی', Icons.storefront_rounded, pal.primaryBright, '/settings/business'),
      _SettingEntry('ساعات کاری و تعطیلات', 'مدیریت شیفت‌ها و روزهای تعطیل', Icons.schedule_rounded, pal.accentGlow, '/settings/hours'),
      _SettingEntry('قواعد رزرو و لغو', 'محدودیت لغو، جابه‌جایی و تداخل', Icons.rule_rounded, pal.success, '/settings/rules'),
      _SettingEntry('تنظیمات پیامک', 'پنل پیامک، قالب‌ها و یادآوری', Icons.sms_rounded, pal.purple, '/sms/settings'),
      _SettingEntry('اطلاع‌رسانی', 'پیامک‌های خودکار و زمان‌بندی', Icons.notifications_active_outlined, pal.warning, '/settings/notifications'),
      _SettingEntry('موقعیت مکانی', 'نقشه، مختصات و آدرس', Icons.location_on_rounded, pal.danger, '/settings/location'),
      _SettingEntry('مدیریت دسترسی پرسنل', 'مدیریت دسترسی پرسنل؛ مدیر کل دسترسی کامل دارد', Icons.security_rounded, pal.info, '/settings/permissions'),
      _SettingEntry('مدیریت خدمات', 'خدمات، قیمت و زمان‌بندی', Icons.content_cut_rounded, pal.primaryBright, '/services'),
      _SettingEntry('مدیریت پرسنل', 'پرسنل، برنامه کاری و مجوزها', Icons.badge_rounded, pal.purple, '/employees'),
      _SettingEntry('گزارش فعالیت‌ها', 'ردگیری رویدادهای سیستم', Icons.history_rounded, pal.textSecondary, '/activity'),
    ];

    return PageScaffold(
      title: 'تنظیمات',
      subtitle: 'پیکربندی کامل مجموعه',
      icon: Icons.settings_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            gradient: LinearGradient(
              colors: [pal.primary.withValues(alpha: 0.22), pal.surface],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            child: Row(
              children: [
                AvatarBadge(name: cloudUser?.email ?? settings.ownerName, size: 52, color: pal.primaryBright),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authSession?.businessName ?? business?.name ?? 'مجموعه',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: pal.textPrimary),
                      ),
                      Text(
                        '${cloudUser?.email ?? settings.ownerName} • ${cloudUser != null ? authSession?.roleLabel ?? settings.ownerRole : settings.ownerRole}',
                        style: TextStyle(fontSize: 11, color: pal.textMuted),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.verified_rounded, size: 12, color: pal.success),
                          const SizedBox(width: 4),
                          Expanded(child: Text(
                            'پنل پیامک: ${settings.smsProvider.status.label}',
                            style: TextStyle(fontSize: 10, color: pal.success),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    CountPill(value: settings.totalUnread, icon: Icons.notifications_none_rounded),
                    const SizedBox(height: 6),
                    Text('نسخه ۱٫۰٫۰', style: TextStyle(fontSize: 9.5, color: pal.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          if (cloudUser != null) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'حساب متصل به Supabase',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: pal.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cloudUser.email ?? 'کاربر واردشده',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 12, color: pal.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${authSession?.businessName ?? 'مجموعه'} • ${authSession?.roleLabel ?? settings.ownerRole}',
                    style: TextStyle(fontSize: 11, color: pal.textMuted),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await authRepository!.signOut();
                          if (context.mounted) context.go('/login');
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('خروج از حساب انجام نشد.')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.logout_rounded, size: 17),
                      label: const Text('خروج از حساب'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1100 ? 3 : (width >= 700 ? 2 : 1);
              final itemWidth = (width - 10 * (columns - 1)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: itemWidth,
                      child: AppCard(
                        onTap: () => context.push(item.route),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            IconTile(icon: item.icon, color: item.color, size: 38, radius: 12),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: pal.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    item.subtitle,
                                    style: TextStyle(fontSize: 10, color: pal.textMuted, height: 1.6),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_left_rounded, size: 18, color: pal.textMuted),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

        ],
      ),
    );
  }
}

class _SettingEntry {
  const _SettingEntry(this.title, this.subtitle, this.icon, this.color, this.route);

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
}
