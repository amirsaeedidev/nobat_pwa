import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../providers/settings_provider.dart';

/// انتخاب مستقل تم کلی برنامه و تم فرم‌ها.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final pal = context.pal;
    return PageScaffold(
      title: 'ظاهر برنامه',
      subtitle: 'انتخاب تم و شخصی‌سازی فرم‌ها',
      icon: Icons.palette_rounded,
      showBackButton: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader(title: '۱. تم کلی اپلیکیشن'),
          const SizedBox(height: 5),
          Text('این انتخاب رنگ پس‌زمینه، کارت‌ها، متن‌ها و اجزای اصلی تمام صفحات را تغییر می‌دهد.',
            style: TextStyle(fontSize: 11, color: pal.textMuted, height: 1.8)),
          const SizedBox(height: 14),
          for (final palette in AppPalette.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () async {
                  await settings.setPalette(palette.id);
                  if (context.mounted) AppToast.show(context, 'تم «${palette.label}» ذخیره شد');
                },
                child: AnimatedContainer(
                  duration: AppDurations.normal,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: settings.paletteId == palette.id ? palette.primary : palette.border,
                      width: settings.paletteId == palette.id ? 2 : 1),
                  ),
                  child: Row(children: [
                    Container(width: 46, height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [palette.primary, palette.primaryBright]),
                        borderRadius: BorderRadius.circular(13)),
                      child: Icon(settings.paletteId == palette.id ? Icons.check_rounded :
                        (palette.isDark ? Icons.dark_mode_rounded : Icons.palette_outlined),
                        color: Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(palette.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                        color: palette.textPrimary)),
                      const SizedBox(height: 7),
                      Row(children: [for (final color in [palette.primary, palette.primaryBright,
                        palette.accentGlow, palette.surfaceAlt, palette.background])
                        Container(width: 22, height: 17, margin: const EdgeInsets.only(left: 5),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: palette.borderStrong)))])
                    ])),
                    if (settings.paletteId == palette.id)
                      StatusBadge(label: 'فعال', color: palette.primary, dense: true),
                  ]),
                ),
              ),
            ),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader(title: '۲. تم مستقل فرم‌ها',
            subtitle: 'این انتخاب جدا از تم کلی برنامه ذخیره می‌شود'),
          const SizedBox(height: 6),
          Text('رنگ فیلدها، کادر انتخاب، چک‌باکس‌ها و دکمه‌های فرم را از این قسمت تغییر بده.',
            style: TextStyle(fontSize: 11, color: pal.textMuted, height: 1.8)),
          const SizedBox(height: 14),
          for (final formTheme in AppFormTheme.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () async {
                  await settings.setFormTheme(formTheme.id);
                  if (context.mounted) AppToast.show(context, 'تم فرم «${formTheme.label}» فعال شد');
                },
                child: AnimatedContainer(
                  duration: AppDurations.normal,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: formTheme.soft,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: settings.formThemeId == formTheme.id ? formTheme.accent : pal.border,
                      width: settings.formThemeId == formTheme.id ? 2 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: formTheme.accent, borderRadius: BorderRadius.circular(11)),
                      child: Icon(settings.formThemeId == formTheme.id ? Icons.check_rounded : Icons.edit_note_rounded,
                        color: Colors.white)),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(formTheme.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                        color: Color(0xFF332A30))),
                      Text(formTheme.description, style: const TextStyle(fontSize: 10, color: Color(0xFF74636B))),
                    ])),
                    if (settings.formThemeId == formTheme.id)
                      StatusBadge(label: 'فعال', color: formTheme.accent, dense: true),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              labelText: 'پیش‌نمایش فیلد فرم',
              hintText: 'متن نمونه را وارد کنید',
              fillColor: settings.formTheme.soft,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: settings.formAccentColor.withValues(alpha: .55)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: settings.formAccentColor, width: 1.8),
              ),
              floatingLabelStyle: TextStyle(color: settings.formAccentColor),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const Text('دکمه نمونه فرم'),
              style: FilledButton.styleFrom(backgroundColor: settings.formAccentColor,
                foregroundColor: Colors.white),
            ),
          ),
        ])),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'پیش‌نمایش زنده'),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: pal.surfaceAlt, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: pal.border)),
            child: Row(children: [
              Icon(Icons.event_available_rounded, color: settings.formAccentColor, size: 26),
              const SizedBox(width: 10),
              Expanded(child: Text('نمونه کارت و فرم', style: TextStyle(color: pal.textPrimary,
                fontWeight: FontWeight.w700))),
              Container(width: 12, height: 12, decoration: BoxDecoration(
                color: settings.formAccentColor, shape: BoxShape.circle)),
            ])),
        ])),
      ]),
    );
  }
}
