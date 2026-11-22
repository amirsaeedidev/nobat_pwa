import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_tokens.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../../data/mock/app_database.dart';
import '../utils/fa_num.dart';
import '../widgets/app_card.dart';
import '../widgets/badges.dart';
import 'nav_destinations.dart';

void _showMockAccountPicker(BuildContext context, AppDatabase database) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Text('حساب‌های آزمایشی Datamonck', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final account in database.accessAccounts)
            ListTile(
              leading: Icon(account.id == database.currentAccessAccount.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
              title: Text(account.name),
              subtitle: Text(database.accessRoleById(account.roleId)?.name ?? 'نقش نامشخص'),
              onTap: () {
                database.switchMockAccount(account.id);
                Navigator.pop(sheetContext);
              },
            ),
        ],
      ),
    ),
  );
}

/// پوسته اصلی برنامه: سایدبار در دسکتاپ/تبلت بزرگ، ناوبری پایین در موبایل.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  void _navigate(BuildContext context, String route) {
    if (location == route) return;
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final database = context.watch<AppDatabase>();
    final destinations = appDestinations.where((item) => database.canOpenNavigation(item.route)).toList();
    final selectedIndex = destinations.indexWhere((item) => location.startsWith(item.route));
    final useSidebar = width >= Breakpoints.tablet;

    if (!useSidebar) {
      return Scaffold(
        backgroundColor: context.pal.background,
        body: child,
        bottomNavigationBar: MobileBottomNav(
          destinations: destinations,
          currentIndex: selectedIndex < 0 ? 0 : selectedIndex,
          showAdd: database.hasPermission('appointments.create'),
          onSelect: (i) => _navigate(context, destinations[i].route),
          onAdd: () => context.push('/appointments/new'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.pal.background,
      body: Row(
        children: [
          AppSidebar(
            destinations: destinations,
            currentIndex: selectedIndex < 0 ? 0 : selectedIndex,
            expanded: width >= Breakpoints.desktop,
            onSelect: (i) => _navigate(context, destinations[i].route),
            onAdd: () => context.push('/appointments/new'),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// ناوبری پایین شناور با دکمه میانی (مطابق تصویر مرجع).
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onAdd,
    required this.destinations,
    required this.showAdd,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final List<NavDestination> destinations;
  final bool showAdd;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: pal.background,
        border: Border(top: BorderSide(color: pal.border.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 92,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: LiquidGlassLayer(
                  settings: LiquidGlassSettings.ios27Regular(
                    brightness: Theme.of(context).brightness,
                    tintAmount: 0.55,
                  ),
                  defaultAppearance: LiquidGlassAppearance.ios27Regular(
                    brightness: Theme.of(context).brightness,
                  ),
                  child: LiquidGlass(
                    shape: const LiquidRoundedSuperellipse(borderRadius: 24),
                    shadows: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        offset: Offset(0, 5),
                        blurRadius: 18,
                      ),
                    ],
                    child: Container(
                      height: 68,
                      decoration: BoxDecoration(
                        color: pal.backgroundAlt.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: pal.border.withValues(alpha: 0.8)),
                      ),
                      child: Row(
                        children: [
                          for (var slot = 0; slot < 5; slot++)
                            Expanded(child: _buildSlot(context, slot)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (showAdd) Positioned(bottom: 36, child: _AddButton(onTap: onAdd)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlot(BuildContext context, int slot) {
    final pal = context.pal;
    if (slot == 2) return const SizedBox.shrink();
    if (slot == 4 && destinations.length > 4) {
      final selected = currentIndex >= 3;
      return InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.28),
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: LiquidGlassLayer(
                settings: LiquidGlassSettings.ios27Regular(
                  brightness: Theme.of(sheetContext).brightness,
                  tintAmount: 0.62,
                ),
                defaultAppearance: LiquidGlassAppearance.ios27Regular(
                  brightness: Theme.of(sheetContext).brightness,
                ),
                child: LiquidGlass(
                  shape: const LiquidRoundedSuperellipse(borderRadius: 26),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.68,
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                    decoration: BoxDecoration(
                      color: pal.backgroundAlt.withValues(alpha: 0.76),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: pal.border.withValues(alpha: 0.85)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedLayer,
                              size: 22,
                              color: pal.primaryBright,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'دسترسی به همه بخش‌ها',
                                maxLines: 2,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: pal.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'بستن',
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: Icon(Icons.close_rounded, color: pal.textMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: destinations.length - 3,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: pal.border.withValues(alpha: 0.55),
                            ),
                            itemBuilder: (context, index) {
                              final destinationIndex = index + 3;
                              final destination = destinations[destinationIndex];
                              final isSelected = currentIndex == destinationIndex;
                              return ListTile(
                                dense: false,
                                minVerticalPadding: 10,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                leading: HugeIcon(
                                  icon: _navIcon(destinationIndex),
                                  size: 22,
                                  color: isSelected ? pal.primaryBright : pal.textMuted,
                                ),
                                title: Text(
                                  destination.label,
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(
                                    height: 1.35,
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: isSelected ? pal.primaryBright : pal.textPrimary,
                                  ),
                                ),
                                selected: isSelected,
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  onSelect(destinationIndex);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          HugeIcon(icon: HugeIcons.strokeRoundedLayer, size: 22, color: selected ? pal.primaryBright : pal.textMuted),
          const SizedBox(height: 2),
          Text('بیشتر', style: TextStyle(fontSize: 10, color: selected ? pal.primaryBright : pal.textMuted)),
        ]),
      );
    }
    final navIndex = slot < 2 ? slot : slot - 1;
    if (navIndex >= destinations.length) return const SizedBox.shrink();
    final dest = destinations[navIndex];
    final selected = currentIndex == navIndex;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onSelect(navIndex),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSlide(
            duration: const Duration(milliseconds: 260), curve: Curves.easeOutBack,
            offset: selected ? const Offset(0, -0.22) : Offset.zero,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic,
              width: selected ? 42 : 36, height: selected ? 42 : 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? pal.primary : Colors.transparent, shape: BoxShape.circle,
                boxShadow: selected ? AppShadows.glow(pal.primary, opacity: 0.24, blur: 12) : const [],
              ),
              child: HugeIcon(icon: _navIcon(navIndex), size: selected ? 23 : 21, color: selected ? Colors.white : pal.textMuted),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dest.label,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? pal.primaryBright : pal.textMuted,
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [pal.primary, pal.primaryBright],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          shape: BoxShape.circle,
          border: Border.all(color: pal.background, width: 4),
          boxShadow: AppShadows.glow(pal.primary, opacity: 0.45, blur: 22),
        ),
        child: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, color: Colors.white, size: 28),
      ),
    );
  }
}

/// سایدبار دسکتاپ.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.expanded,
    required this.onAdd,
    required this.destinations,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool expanded;
  final VoidCallback onAdd;
  final List<NavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final settings = context.watch<SettingsProvider>();
    final database = context.watch<AppDatabase>();
    final width = expanded ? 246.0 : 84.0;

    return AnimatedContainer(
      duration: AppDurations.normal,
      width: width,
      decoration: BoxDecoration(
        color: pal.backgroundAlt,
        border: Border(left: BorderSide(color: pal.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: expanded ? 18 : 10, vertical: 18),
              child: Row(
                textDirection: TextDirection.ltr,
                mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: pal.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const HugeIcon(icon: HugeIcons.strokeRoundedHome01, color: Colors.white, size: 20),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Date',
                                style: TextStyle(
                                  fontFamily: 'Lalezar',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: pal.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: 'Time',
                                style: TextStyle(
                                  fontFamily: 'Lalezar',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: pal.primaryBright,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'مدیریت نوبت‌دهی',
                          style: TextStyle(fontSize: 9.5, color: pal.textMuted),
                        ),
                      ],
                    )),
                  ],
                ],
              ),
            ),
            Divider(color: pal.border, height: 1),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 8, vertical: 4),
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    _SidebarItem(
                      destination: destinations[i],
                      selected: currentIndex == i,
                      expanded: expanded,
                      onTap: () => onSelect(i),
                    ),
                  const SizedBox(height: 14),
                  if (expanded)
                    _BookingLinkCard(onTap: () => context.push('/book'))
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: IconButton(
                        tooltip: 'صفحه رزرو عمومی',
                        onPressed: () => context.push('/book'),
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedHome01, color: Colors.blue),
                      ),
                    ),
                ],
              ),
            ),
            if (database.hasPermission('appointments.create'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Tooltip(
                  message: 'افزودن نوبت جدید',
                  child: Material(
                    color: pal.primary,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAdd,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedAdd01,
                            color: Colors.white,
                            size: 23,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Divider(color: pal.border, height: 1),
            Padding(
              padding: EdgeInsets.all(expanded ? 12 : 8),
              child: expanded
                  ? InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showMockAccountPicker(context, database),
                      child: LayoutBuilder(builder: (context, constraints) {
                        if (constraints.maxWidth < 150) {
                          return Center(child: AvatarBadge(name: database.currentAccessAccount.name, size: 36, color: pal.primaryBright));
                        }
                        return Row(
                          children: [
                            AvatarBadge(name: database.currentAccessAccount.name, size: 36, color: pal.primaryBright),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(database.currentAccessAccount.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.textPrimary), overflow: TextOverflow.ellipsis),
                                  Text(database.currentAccessRoleName, style: TextStyle(fontSize: 10, color: pal.textMuted), overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            if (constraints.maxWidth >= 205) CountPill(value: settings.totalUnread, icon: Icons.notifications_none_rounded),
                          ],
                        );
                      }),
                    )
                  : Center(
                      child: IconButton(
                        tooltip: 'تغییر حساب آزمایشی',
                        onPressed: () => _showMockAccountPicker(context, database),
                        icon: AvatarBadge(name: database.currentAccessAccount.name, size: 34, color: pal.primaryBright),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0, vertical: 11),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(colors: [pal.primary.withValues(alpha: 0.26), pal.primary.withValues(alpha: 0.06)])
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? pal.primary.withValues(alpha: 0.4) : Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? destination.iconResolved : destination.icon,
                  size: 19,
                  color: selected ? pal.primaryBright : pal.textMuted,
                ),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? pal.textPrimary : pal.textSecondary,
                      ),
                    ),
                  ),
                  if (selected)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: pal.primaryBright, shape: BoxShape.circle),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingLinkCard extends StatelessWidget {
  const _BookingLinkCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [pal.primary.withValues(alpha: 0.22), pal.purple.withValues(alpha: 0.12)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public_rounded, size: 15, color: pal.primaryBright),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'صفحه رزرو عمومی',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: pal.textPrimary),
                )),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'datetime.app/book',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 10, color: pal.textMuted),
            ),
            const SizedBox(height: 6),
            Text(
              'مشاهده صفحه مشتری',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: pal.primaryBright, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// نمایش شماره صفحه‌ها برای هدر‌ها.
String faCount(int value) => FaNum.ofInt(value);

/// آیکون‌های ناوبری با خانواده Stroke Rounded از Hugeicons.
List<List> _navIcon(int index) {
  switch (index) {
    case 0:
      return HugeIcons.strokeRoundedHome01;
    case 3:
      return HugeIcons.strokeRoundedUser;
    case 9:
      return HugeIcons.strokeRoundedSettings01;
    default:
      return HugeIcons.strokeRoundedAirplaneSeat;
  }
}
