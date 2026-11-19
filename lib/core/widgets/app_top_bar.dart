import 'package:flutter/material.dart';

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
    final compactLogoHeader = MediaQuery.sizeOf(context).width < 400;
    return Container(
      decoration: BoxDecoration(
        color: pal.backgroundAlt,
        border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: pal.isDark ? 0.6 : 1))),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Column(
            children: [
              if (showLogo)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      const _DateTimeLogo(),
                      const Spacer(),
                      if (!compactLogoHeader) ...actions,
                      if (!compactLogoHeader && actions.isNotEmpty) const SizedBox(width: 8),
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                    ...actions,
                    if (actions.isNotEmpty) const SizedBox(width: 8),
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
              if (bottom != null) ...[
                const SizedBox(height: 10),
                bottom!,
              ],
            ],
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
    return SizedBox(
      width: 116,
      height: 40,
      child: Image.asset(
        'assets/image/Logotopbar.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        semanticLabel: 'DateTime',
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
    return Row(
      children: [
        if (icon != null) ...[
          IconTile(icon: icon!, color: pal.primaryBright, size: 42),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: pal.textPrimary),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(subtitle!, style: TextStyle(fontSize: 12, color: pal.textMuted)),
                ),
            ],
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
      ],
    );
  }
}
