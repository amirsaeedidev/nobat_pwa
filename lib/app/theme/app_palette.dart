import 'package:flutter/material.dart';

/// پالت رنگی به‌صورت ThemeExtension تا همه ویجت‌ها مستقل از تم به رنگ‌ها دسترسی داشته باشند.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.id,
    required this.label,
    required this.isDark,
    required this.background,
    required this.backgroundAlt,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceHigh,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.primaryBright,
    required this.primaryDeep,
    required this.accentGlow,
    required this.success,
    required this.warning,
    required this.danger,
    required this.purple,
    required this.info,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.heroGradient,
    required this.successSoft,
    required this.dangerSoft,
    required this.purpleSoft,
  });

  final String id;
  final String label;
  final bool isDark;
  final Color background;
  final Color backgroundAlt;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceHigh;
  final Color border;
  final Color borderStrong;
  final Color primary;
  final Color primaryBright;
  final Color primaryDeep;
  final Color accentGlow;
  final Color success;
  final Color warning;
  final Color danger;
  final Color purple;
  final Color info;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final List<Color> heroGradient;
  final Color successSoft;
  final Color dangerSoft;
  final Color purpleSoft;

  LinearGradient get primaryGradient => LinearGradient(
        colors: [primary, primaryBright],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );

  LinearGradient get heroFill => LinearGradient(
        colors: heroGradient,
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
      );

  Color get onPrimary => Colors.white;

  /// تم ثابت لوکس با زمینه کرمی و تأکیدهای صورتی/بنفش.
  static const AppPalette luxury = AppPalette(
    id: 'luxury',
    label: 'لوکس صورتی',
    isDark: false,
    background: Color(0xFFFFF8F3),
    backgroundAlt: Color(0xFFFFFDFC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7EEE7),
    surfaceHigh: Color(0xFFEEDFD4),
    border: Color(0xFFE8D8CD),
    borderStrong: Color(0xFFD5BFAF),
    primary: Color(0xFF642CA9),
    primaryBright: Color(0xFFFF36AB),
    primaryDeep: Color(0xFF4E2188),
    accentGlow: Color(0xFFFF74D4),
    success: Color(0xFF8C624B),
    warning: Color(0xFFB88655),
    danger: Color(0xFFD94A70),
    purple: Color(0xFF642CA9),
    info: Color(0xFFFF74D4),
    textPrimary: Color(0xFF38251F),
    textSecondary: Color(0xFF765C50),
    textMuted: Color(0xFFA58D80),
    heroGradient: [Color(0xFF642CA9), Color(0xFFFF36AB), Color(0xFFFF74D4)],
    successSoft: Color(0xFFFFB8DE),
    dangerSoft: Color(0xFFFFDDE1),
    purpleSoft: Color(0xFFF4E8F8),
  );

  static const List<AppPalette> all = [luxury];

  static AppPalette byId(String id) => luxury;

  @override
  AppPalette copyWith({
    String? id,
    String? label,
    bool? isDark,
    Color? background,
    Color? backgroundAlt,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceHigh,
    Color? border,
    Color? borderStrong,
    Color? primary,
    Color? primaryBright,
    Color? primaryDeep,
    Color? accentGlow,
    Color? success,
    Color? warning,
    Color? danger,
    Color? purple,
    Color? info,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    List<Color>? heroGradient,
    Color? successSoft,
    Color? dangerSoft,
    Color? purpleSoft,
  }) {
    return AppPalette(
      id: id ?? this.id,
      label: label ?? this.label,
      isDark: isDark ?? this.isDark,
      background: background ?? this.background,
      backgroundAlt: backgroundAlt ?? this.backgroundAlt,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      primary: primary ?? this.primary,
      primaryBright: primaryBright ?? this.primaryBright,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      accentGlow: accentGlow ?? this.accentGlow,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      purple: purple ?? this.purple,
      info: info ?? this.info,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      heroGradient: heroGradient ?? this.heroGradient,
      successSoft: successSoft ?? this.successSoft,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      purpleSoft: purpleSoft ?? this.purpleSoft,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      id: t < 0.5 ? id : other.id,
      label: t < 0.5 ? label : other.label,
      isDark: t < 0.5 ? isDark : other.isDark,
      background: c(background, other.background),
      backgroundAlt: c(backgroundAlt, other.backgroundAlt),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      primary: c(primary, other.primary),
      primaryBright: c(primaryBright, other.primaryBright),
      primaryDeep: c(primaryDeep, other.primaryDeep),
      accentGlow: c(accentGlow, other.accentGlow),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      purple: c(purple, other.purple),
      info: c(info, other.info),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      heroGradient: [c(heroGradient.first, other.heroGradient.first), c(heroGradient.last, other.heroGradient.last)],
      successSoft: c(successSoft, other.successSoft),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      purpleSoft: c(purpleSoft, other.purpleSoft),
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>() ?? AppPalette.luxury;
}
