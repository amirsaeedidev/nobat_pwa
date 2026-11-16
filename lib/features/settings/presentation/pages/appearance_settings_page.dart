import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../providers/settings_provider.dart';

/// انتخاب تم برنامه و رنگ نمایشی فیلدهای فرم.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  static const _formColors = <Color>[
    Color(0xFFE6A1BF), Color(0xFF8632E6), Color(0xFF8B5E3C),
    Color(0xFF64748B), Color(0xFF3B82F6), Color(0xFF14A38B),
    Color(0xFFE58B45), Color(0xFFD94A70),
  ];

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
          const SectionHeader(title: 'چهار تم رنگی'),
          const SizedBox(height: 5),
          Text('با انتخاب هر تم، رنگ‌بندی تمام بخش‌های برنامه تغییر می‌کند و انتخاب شما ذخیره می‌شود.',
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
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'رنگ فرم‌ها', subtitle: 'تغییر رنگ فیلدها و حالت انتخاب‌شده'),
          const SizedBox(height: 6),
          Text('این تنظیم فعلاً نمایشی است و روی ظاهر ورودی‌ها و پیش‌نمایش فرم اثر می‌گذارد.',
            style: TextStyle(fontSize: 11, color: pal.textMuted, height: 1.8)),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final color in _formColors)
              InkWell(
                onTap: () => settings.setFormAccent(color),
                borderRadius: BorderRadius.circular(30),
                child: AnimatedContainer(duration: AppDurations.fast, width: 38, height: 38,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                    border: Border.all(color: settings.formAccentColor == color ? pal.textPrimary : pal.border,
                      width: settings.formAccentColor == color ? 3 : 1),
                    boxShadow: settings.formAccentColor == color
                      ? [BoxShadow(color: color.withValues(alpha: .28), blurRadius: 8)] : null),
                  child: settings.formAccentColor == color
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 19) : null),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(labelText: 'پیش‌نمایش فیلد فرم',
              hintText: 'متن نمونه را وارد کنید',
              fillColor: settings.formAccentColor.withValues(alpha: .08),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: settings.formAccentColor.withValues(alpha: .55))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: settings.formAccentColor, width: 1.8)),
              floatingLabelStyle: TextStyle(color: settings.formAccentColor)),
          ),
        ])),
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
