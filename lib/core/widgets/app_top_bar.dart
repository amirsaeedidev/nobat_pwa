import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../app/theme/app_palette.dart';
import 'app_buttons.dart';
import 'badges.dart';

/// نوار بالای صفحه؛ دو حالت: لوگوی DateTime و عنوان ساده.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    this.title,
    this.subtitle,
    this.showLogo = false,
    this.onClose,
    this.onBell,
    this.onSearch,
    this.onProfile,
    this.hasNotification = true,
    this.leading,
    this.actions = const [],
    this.onMenu,
    this.centerTitle = false,
    this.bottom,
  });

  final String? title;
  final String? subtitle;
  final bool showLogo;
  final VoidCallback? onClose;
  final VoidCallback? onBell;
  final VoidCallback? onSearch;
  final VoidCallback? onProfile;
  final bool hasNotification;
  final Widget? leading;
  final List<Widget> actions;
  final VoidCallback? onMenu;
  final bool centerTitle;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final compactActions = MediaQuery.sizeOf(context).width < 480;
    final narrowHeader = MediaQuery.sizeOf(context).width < 360;
    return LiquidGlassLayer(
      settings: LiquidGlassSettings.ios27Regular(
        brightness: Theme.of(context).brightness,
        tintAmount: 0.46,
      ),
      defaultAppearance: LiquidGlassAppearance.ios27Regular(
        brightness: Theme.of(context).brightness,
      ),
      child: LiquidGlass(
        shape: const LiquidRoundedSuperellipse(borderRadius: 22),
        shadows: const [
          BoxShadow(
            color: Color(0x18000000),
            offset: Offset(0, 5),
            blurRadius: 18,
          ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: pal.backgroundAlt.withValues(alpha: 0.085),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(narrowHeader ? 12 : 14, 8, narrowHeader ? 12 : 14, 10),
          child: Column(
            children: [
              if (showLogo)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      const _DateTimeLogo(),
                      const Spacer(),
                      if (onSearch != null && !narrowHeader) ...[
                        HugeIconCircleButton(icon: HugeIcons.strokeRoundedSearch01, size: 30, tooltip: 'جست‌وجوی سراسری', onTap: onSearch),
                      ],
                      if (!compactActions) ...actions,
                      if (!compactActions && actions.isNotEmpty) const SizedBox(width: 8),
                      if (onBell != null) ...[
                        CircleIconButton(
                          icon: Icons.notifications_none_rounded,
                          size: 40,
                          badge: hasNotification,
                          onTap: onBell,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (onProfile != null)
                        GestureDetector(
                          onTap: onProfile,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: pal.surfaceAlt,
                              border: Border.all(color: pal.borderStrong),
                            ),
                            child: Icon(Icons.person_outline_rounded, size: 20, color: pal.textSecondary),
                          ),
                        ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    if (onMenu != null) ...[
                      CircleIconButton(icon: Icons.menu_rounded, size: 40, onTap: onMenu),
                      const SizedBox(width: 10),
                    ],
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 10),
                    ],
                    if (title != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                          children: [
                            Text(
                              title!,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: pal.textPrimary,
                              ),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  subtitle!,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: pal.textMuted,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    else
                      const Spacer(),
                    if (!compactActions) ...actions,
                    if (!compactActions && actions.isNotEmpty) const SizedBox(width: 8),
                    if (onSearch != null && !narrowHeader) ...[
                      HugeIconCircleButton(icon: HugeIcons.strokeRoundedSearch01, size: 30, tooltip: 'جست‌وجوی سراسری', onTap: onSearch),
                    ],
                    if (onBell != null) ...[
                      CircleIconButton(
                        icon: Icons.notifications_none_rounded,
                        size: 40,
                        badge: hasNotification,
                        onTap: onBell,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (onProfile != null)
                      GestureDetector(
                        onTap: onProfile,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: pal.surfaceAlt,
                            border: Border.all(color: pal.borderStrong),
                          ),
                          child: Icon(Icons.person_outline_rounded, size: 20, color: pal.textSecondary),
                        ),
                      ),
                  ],
                ),
              if (actions.isNotEmpty && compactActions) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ),
              ],
              if (bottom != null) ...[
                const SizedBox(height: 10),
                bottom!,
              ],
            ],
          ),
          ),
        ),
      ),
      ),
    );
  }
}

/// لوگوی تصویری برند در نوار بالای برنامه.
class _DateTimeLogo extends StatelessWidget {
  const _DateTimeLogo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'DateTime',
      header: true,
      child: SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Image.asset(
            'assets/image/bria-rmbg3-cutout.png',
            height: 40,
            width: 124,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// سربرگ صفحه در حالت دسکتاپ/تبلت (عنوان بزرگ + توضیح + اقدامات).
class DesktopPageHeader extends StatelessWidget {
  const DesktopPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.icon,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final heading = Row(
      children: [
        if (icon != null) ...[
          IconTile(icon: icon!, color: pal.primaryBright, size: 42),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: pal.textPrimary)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: pal.textMuted)),
                ),
            ],
          ),
        ),
      ],
    );
    final actionRow = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                actionRow,
              ],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 12),
              actionRow,
            ],
          ],
        );
      },
    );
  }
}
