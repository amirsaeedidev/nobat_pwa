import 'package:flutter/material.dart';

/// پالت‌های سراسری برنامه؛ تمام صفحات از ThemeExtension مشترک استفاده می‌کنند.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.id, required this.label, required this.isDark,
    required this.background, required this.backgroundAlt, required this.surface,
    required this.surfaceAlt, required this.surfaceHigh, required this.border,
    required this.borderStrong, required this.primary, required this.primaryBright,
    required this.primaryDeep, required this.accentGlow, required this.success,
    required this.warning, required this.danger, required this.purple, required this.info,
    required this.textPrimary, required this.textSecondary, required this.textMuted,
    required this.heroGradient, required this.successSoft, required this.dangerSoft,
    required this.purpleSoft,
  });

  final String id, label;
  final bool isDark;
  final Color background, backgroundAlt, surface, surfaceAlt, surfaceHigh;
  final Color border, borderStrong, primary, primaryBright, primaryDeep, accentGlow;
  final Color success, warning, danger, purple, info;
  final Color textPrimary, textSecondary, textMuted;
  final List<Color> heroGradient;
  final Color successSoft, dangerSoft, purpleSoft;

  LinearGradient get primaryGradient => LinearGradient(colors: [primary, primaryBright]);
  LinearGradient get heroFill => LinearGradient(
    colors: heroGradient, begin: Alignment.centerRight, end: Alignment.centerLeft);
  Color get onPrimary => Colors.white;

  static const pastelPink = AppPalette(
    id: 'pastel_pink', label: 'صورتی پاستیلی', isDark: false,
    background: Color(0xFFFFF7FA), backgroundAlt: Color(0xFFFFFBFD),
    surface: Color(0xFFFFFFFF), surfaceAlt: Color(0xFFFFEEF4), surfaceHigh: Color(0xFFF9DCE8),
    border: Color(0xFFF1D5E1), borderStrong: Color(0xFFE7BFD0),
    primary: Color(0xFFE6A1BF), primaryBright: Color(0xFFF2B9D0),
    primaryDeep: Color(0xFFC77D9E), accentGlow: Color(0xFFF6C9DC),
    success: Color(0xFFB77E98), warning: Color(0xFFC69A75), danger: Color(0xFFD889A0),
    purple: Color(0xFFB99BCF), info: Color(0xFFE9B5CF),
    textPrimary: Color(0xFF493541), textSecondary: Color(0xFF806879),
    textMuted: Color(0xFFAD96A3),
    heroGradient: [Color(0xFFE6A1BF), Color(0xFFF2B9D0), Color(0xFFF6C9DC)],
    successSoft: Color(0xFFF6E4EC), dangerSoft: Color(0xFFFFE8ED), purpleSoft: Color(0xFFF2EAF7),
  );

  static const creamBrown = AppPalette(
    id: 'cream_brown', label: 'کرم و قهوه‌ای', isDark: false,
    background: Color(0xFFFFF8F0), backgroundAlt: Color(0xFFFFFCF8),
    surface: Color(0xFFFFFFFF), surfaceAlt: Color(0xFFF5EBDD), surfaceHigh: Color(0xFFEAD8C4),
    border: Color(0xFFE6D5C3), borderStrong: Color(0xFFCDB49C),
    primary: Color(0xFF8B5E3C), primaryBright: Color(0xFFB8875C),
    primaryDeep: Color(0xFF67432E), accentGlow: Color(0xFFD6B18D),
    success: Color(0xFF8B7658), warning: Color(0xFFB8875C), danger: Color(0xFFB66D62),
    purple: Color(0xFF927A9F), info: Color(0xFF9B8A78),
    textPrimary: Color(0xFF38291F), textSecondary: Color(0xFF725B49),
    textMuted: Color(0xFFA18A77),
    heroGradient: [Color(0xFF67432E), Color(0xFF8B5E3C), Color(0xFFB8875C)],
    successSoft: Color(0xFFEAE3D6), dangerSoft: Color(0xFFF5E3DF), purpleSoft: Color(0xFFECE6F0),
  );

  static const white = AppPalette(
    id: 'white', label: 'سفید مینیمال', isDark: false,
    background: Color(0xFFF8FAFC), backgroundAlt: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF), surfaceAlt: Color(0xFFF1F5F9), surfaceHigh: Color(0xFFE2E8F0),
    border: Color(0xFFE2E8F0), borderStrong: Color(0xFFCBD5E1),
    primary: Color(0xFF64748B), primaryBright: Color(0xFF94A3B8),
    primaryDeep: Color(0xFF475569), accentGlow: Color(0xFFCBD5E1),
    success: Color(0xFF668B78), warning: Color(0xFFB18A54), danger: Color(0xFFC47777),
    purple: Color(0xFF8B7AAE), info: Color(0xFF7296B5),
    textPrimary: Color(0xFF1E293B), textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    heroGradient: [Color(0xFF64748B), Color(0xFF94A3B8), Color(0xFFCBD5E1)],
    successSoft: Color(0xFFE7F0EA), dangerSoft: Color(0xFFF8E8E8), purpleSoft: Color(0xFFF0ECF7),
  );

  static const purpleDark = AppPalette(
    id: 'purple_dark', label: 'بنفش تیره', isDark: true,
    background: Color(0xFF171222), backgroundAlt: Color(0xFF20182F),
    surface: Color(0xFF261D38), surfaceAlt: Color(0xFF302442), surfaceHigh: Color(0xFF3B2C50),
    border: Color(0xFF453653), borderStrong: Color(0xFF665078),
    primary: Color(0xFF8632E6), primaryBright: Color(0xFFA45CF0),
    primaryDeep: Color(0xFF6824BD), accentGlow: Color(0xFFC08BFA),
    success: Color(0xFF78B99A), warning: Color(0xFFE2B56D), danger: Color(0xFFE58B9A),
    purple: Color(0xFFB68AF0), info: Color(0xFF82AEE8),
    textPrimary: Color(0xFFF7F1FF), textSecondary: Color(0xFFD0C2E2),
    textMuted: Color(0xFFA797BA),
    heroGradient: [Color(0xFF6824BD), Color(0xFF8632E6), Color(0xFFA45CF0)],
    successSoft: Color(0xFF294638), dangerSoft: Color(0xFF4B2B3A), purpleSoft: Color(0xFF3A2B50),
  );

  static const List<AppPalette> all = [pastelPink, creamBrown, white, purpleDark];
  static AppPalette byId(String id) => all.firstWhere((p) => p.id == id, orElse: () => pastelPink);

  @override
  AppPalette copyWith({String? id, String? label, bool? isDark, Color? background,
    Color? backgroundAlt, Color? surface, Color? surfaceAlt, Color? surfaceHigh,
    Color? border, Color? borderStrong, Color? primary, Color? primaryBright,
    Color? primaryDeep, Color? accentGlow, Color? success, Color? warning,
    Color? danger, Color? purple, Color? info, Color? textPrimary, Color? textSecondary,
    Color? textMuted, List<Color>? heroGradient, Color? successSoft, Color? dangerSoft,
    Color? purpleSoft}) => AppPalette(
      id: id ?? this.id, label: label ?? this.label, isDark: isDark ?? this.isDark,
      background: background ?? this.background, backgroundAlt: backgroundAlt ?? this.backgroundAlt,
      surface: surface ?? this.surface, surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh, border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong, primary: primary ?? this.primary,
      primaryBright: primaryBright ?? this.primaryBright, primaryDeep: primaryDeep ?? this.primaryDeep,
      accentGlow: accentGlow ?? this.accentGlow, success: success ?? this.success,
      warning: warning ?? this.warning, danger: danger ?? this.danger, purple: purple ?? this.purple,
      info: info ?? this.info, textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary, textMuted: textMuted ?? this.textMuted,
      heroGradient: heroGradient ?? this.heroGradient, successSoft: successSoft ?? this.successSoft,
      dangerSoft: dangerSoft ?? this.dangerSoft, purpleSoft: purpleSoft ?? this.purpleSoft);

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return copyWith(
      id: t < .5 ? id : other.id, label: t < .5 ? label : other.label,
      isDark: t < .5 ? isDark : other.isDark,
      background: c(background, other.background), backgroundAlt: c(backgroundAlt, other.backgroundAlt),
      surface: c(surface, other.surface), surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh), border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong), primary: c(primary, other.primary),
      primaryBright: c(primaryBright, other.primaryBright), primaryDeep: c(primaryDeep, other.primaryDeep),
      accentGlow: c(accentGlow, other.accentGlow), success: c(success, other.success),
      warning: c(warning, other.warning), danger: c(danger, other.danger), purple: c(purple, other.purple),
      info: c(info, other.info), textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary), textMuted: c(textMuted, other.textMuted),
      heroGradient: [c(heroGradient.first, other.heroGradient.first), c(heroGradient.last, other.heroGradient.last)],
      successSoft: c(successSoft, other.successSoft), dangerSoft: c(dangerSoft, other.dangerSoft),
      purpleSoft: c(purpleSoft, other.purpleSoft));
  }
}


/// تم مستقل فرم‌ها؛ از تم کلی برنامه جدا ذخیره و اعمال می‌شود.
@immutable
class AppFormTheme {
  const AppFormTheme({required this.id, required this.label, required this.description,
    required this.accent, required this.soft});
  final String id, label, description;
  final Color accent, soft;

  static const pastelPink = AppFormTheme(id: 'pastel_pink', label: 'صورتی پاستیلی',
    description: 'صورتی ملایم با تأکید رز', accent: Color(0xFFC45C87), soft: Color(0xFFFFEDF3));
  static const creamBrown = AppFormTheme(id: 'cream_brown', label: 'کرم و قهوه‌ای',
    description: 'قهوه‌ای گرم و کرم روشن', accent: Color(0xFF8B5E3C), soft: Color(0xFFF5EBDD));
  static const white = AppFormTheme(id: 'white', label: 'سفید مینیمال',
    description: 'خاکستری و آبی ملایم', accent: Color(0xFF52657D), soft: Color(0xFFF1F5F9));
  static const purple = AppFormTheme(id: 'purple', label: 'بنفش',
    description: 'بنفش شاخص و روشن', accent: Color(0xFF8632E6), soft: Color(0xFFF1E7FF));
  static const List<AppFormTheme> all = [pastelPink, creamBrown, white, purple];
  static AppFormTheme byId(String id) =>
      all.firstWhere((theme) => theme.id == id, orElse: () => pastelPink);
}

extension PaletteContext on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>() ?? AppPalette.pastelPink;
}
