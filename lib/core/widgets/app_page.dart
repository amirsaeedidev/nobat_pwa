import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_tokens.dart';
import 'app_buttons.dart';
import 'app_top_bar.dart';

/// پوسته استاندارد صفحه‌ها: نوار بالای موبایل، سربرگ دسکتاپ و محتوای واکنش‌گرا.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.child,
    this.showLogo = false,
    this.onClose,
    this.showBackButton = false,
    this.mobileActions = const [],
    this.bottomBar,
    this.scrollable = true,
    this.padding,
    this.header,
    this.floatingAction,
    this.mobileHeader,
    this.onHeaderAction,
    this.headerActionLabel,
    this.centerTitle = false,
    this.onBell,
    this.onProfile,
    this.hasNotification = true,
    this.onMenu,
    this.leading,
    this.showGlobalSearch = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget? child;
  final bool showLogo;
  final VoidCallback? onClose;
  final bool showBackButton;
  final List<Widget> mobileActions;
  final PreferredSizeWidget? bottomBar;
  final bool scrollable;
  final EdgeInsets? padding;
  final Widget? header;
  final Widget? floatingAction;
  final Widget? mobileHeader;
  final VoidCallback? onHeaderAction;
  final String? headerActionLabel;
  final bool centerTitle;
  final VoidCallback? onBell;
  final VoidCallback? onProfile;
  final bool hasNotification;
  final VoidCallback? onMenu;
  final Widget? leading;
  final bool showGlobalSearch;

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
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: pal.textPrimary),
              ),
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

class _HeaderTextAction extends StatelessWidget {
  const _HeaderTextAction({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, color: pal.primaryBright, fontWeight: FontWeight.w600)),
    );
  }
}

/// ستون واکنش‌گرا (۱ تا ۴ ستون بر اساس عرض).
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 240,
    this.spacing = 12,
    this.runSpacing = 12,
    this.maxColumns = 4,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final double runSpacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = (width / minItemWidth).floor().clamp(1, maxColumns);
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children) SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// فاصله عمودی استاندارد بین بخش‌ها.
class Gap extends StatelessWidget {
  const Gap(this.height, {super.key});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}
