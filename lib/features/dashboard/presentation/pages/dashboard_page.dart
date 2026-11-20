import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../../../../data/repositories/dashboard_repository.dart';
import '../../../activity_logs/presentation/providers/activity_provider.dart';
import '../../../appointments/presentation/widgets/appointment_tile.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/dashboard_sections.dart';
import '../widgets/performance_chart.dart';
import '../widgets/dashboard_insights.dart';

/// پیشخوان مدیریت — بازسازی صفحه مرجع DateTime.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final activity = context.watch<ActivityProvider>();
    final pal = context.pal;
    final stats = provider.stats;

    return PageScaffold(
      title: 'پیشخوان',
      subtitle: 'نمای کلی عملکرد مجموعه',
      icon: Icons.dashboard_rounded,
      showLogo: true,
      onClose: () => context.go('/dashboard'),
      onBell: () => context.push('/activity'),
      onProfile: () => context.push('/settings'),
      actions: [
        SoftButton(label: 'گزارش‌ها', icon: Icons.insights_rounded, onTap: () => context.push('/reports')),
        SoftButton(label: 'صفحه رزرو', icon: Icons.public_rounded, onTap: () => context.push('/book')),
      ],
      scrollable: true,
      child: provider.loading && stats == null
          ? const LoadingState(kind: SkeletonKind.dashboard)
          : stats == null
              ? ErrorStateView(kind: provider.failure?.kind ?? AppErrorKind.fetch, description: provider.failure?.persianMessage, onRetry: provider.load)
              : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (!wide) {
                      return _MobileDashboard(
                        stats: stats,
                        upcoming: provider.upcoming,
                        period: provider.period,
                        onPeriodChanged: provider.setPeriod,
                        revenueSeries: provider.revenueSeries,
                        logs: activity.recent,
                        selectedDay: provider.selectedDay,
                        dayAppointments: provider.dayAppointments,
                        onDaySelected: provider.selectDay,
                      );
                    }
                    return _DesktopDashboard(
                      stats: stats,
                      period: provider.period,
                      onPeriodChanged: provider.setPeriod,
                      revenueSeries: provider.revenueSeries,
                      logs: activity.recent,
                      selectedDay: provider.selectedDay,
                      dayAppointments: provider.dayAppointments,
                      onDaySelected: provider.selectDay,
                    );
                  },
                ),
                if (provider.analytics != null)
                  DashboardInsights(analytics: provider.analytics!, filter: provider.analyticsFilter, onFilterChanged: provider.setAnalyticsFilter)
                else if (provider.analyticsError)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: OutlinedButton.icon(
                    onPressed: provider.load, icon: const Icon(Icons.refresh_rounded), label: const Text('بارگذاری دوباره آمار مالی'))),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'صفحه رزرو عمومی: datetime.app/book/datetime-salon',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 10, color: pal.textMuted),
                  ),
                ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// چیدمان موبایل (مطابق تصویر مرجع)
// -----------------------------------------------------------------------------
class _MobileDashboard extends StatelessWidget {
  const _MobileDashboard({
    required this.stats,
    required this.upcoming,
    required this.period,
    required this.onPeriodChanged,
    required this.revenueSeries,
    required this.logs,
    required this.selectedDay,
    required this.dayAppointments,
    required this.onDaySelected,
  });

  final DashboardStats stats;
  final List<Appointment> upcoming;
  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onPeriodChanged;
  final List<RevenuePoint> revenueSeries;
  final List logs;
  final DateTime selectedDay;
  final List<Appointment> dayAppointments;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroStatsCard(stats: stats, period: period, onPeriodChanged: onPeriodChanged),
        const SizedBox(height: 14),
        GradientCta(
          title: 'ثبت نوبت جدید',
          subtitle: 'رزرو سریع در چند ثانیه',
          onPressed: () => context.push('/appointments/new'),
        ),
        const SizedBox(height: 14),
        _DashboardDayPicker(selectedDay: selectedDay, onSelected: onDaySelected),
        const SizedBox(height: 18),
        SectionHeader(
          title: 'نوبت‌های روز انتخاب‌شده',
          actionLabel: 'مشاهده همه',
          onAction: () => context.go('/appointments'),
        ),
        const SizedBox(height: 10),
        if (dayAppointments.isEmpty)
          const EmptyState(
            title: 'برای این روز نوبتی ثبت نشده است',
            description: 'روز دیگری را انتخاب کنید یا نوبت جدیدی ثبت کنید.',
            compact: true,
          )
        else
          for (final appointment in dayAppointments) ...[
            AppointmentTile(
              appointment: appointment,
              onTap: () => context.push('/appointments/${appointment.id}'),
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 8),
        SectionHeader(title: 'دسترسی سریع'),
        const SizedBox(height: 10),
        const QuickActionsRow(),
        const SizedBox(height: 18),
        KpiGrid(stats: stats),
        const SizedBox(height: 12),
        StatusBreakdownCard(counts: stats.statusBreakdown),
        const SizedBox(height: 12),
        RevenueCard(data: revenueSeries),
        const SizedBox(height: 12),
        RecentActivityCard(logs: logs.cast()),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// چیدمان دسکتاپ/تبلت.
// -----------------------------------------------------------------------------
class _DesktopDashboard extends StatelessWidget {
  const _DesktopDashboard({
    required this.stats,
    required this.period,
    required this.onPeriodChanged,
    required this.revenueSeries,
    required this.logs,
    required this.selectedDay,
    required this.dayAppointments,
    required this.onDaySelected,
  });

  final DashboardStats stats;
  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onPeriodChanged;
  final List<RevenuePoint> revenueSeries;
  final List logs;
  final DateTime selectedDay;
  final List<Appointment> dayAppointments;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _HeroStatsCard(stats: stats, period: period, onPeriodChanged: onPeriodChanged),
                  const SizedBox(height: 12),
                  GradientCta(
                    title: 'ثبت نوبت جدید',
                    subtitle: 'رزرو سریع در چند ثانیه',
                    height: 68,
                    compact: true,
                    onPressed: () => context.push('/appointments/new'),
                  ),
                  const SizedBox(height: 12),
                  const QuickActionsRow(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  KpiGrid(stats: stats, compact: true),
                  const SizedBox(height: 12),
                  StatusBreakdownCard(counts: stats.statusBreakdown),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DashboardDayPicker(selectedDay: selectedDay, onSelected: onDaySelected),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: 'نوبت‌های روز انتخاب‌شده',
                      actionLabel: 'مشاهده همه',
                      onAction: () => context.go('/appointments'),
                    ),
                    const SizedBox(height: 12),
                    if (dayAppointments.isEmpty)
                      const EmptyState(compact: true, title: 'برای این روز نوبتی ثبت نشده است')
                    else
                      for (final appointment in dayAppointments) ...[
                        AppointmentTile(
                          appointment: appointment,
                          onTap: () => context.push('/appointments/${appointment.id}'),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  RevenueCard(data: revenueSeries),
                  const SizedBox(height: 12),
                  RecentActivityCard(logs: logs.cast(), maxItems: 5),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// کارت اصلی آمار + نمودار (بازسازی دقیق تصویر مرجع)
// -----------------------------------------------------------------------------
class _HeroStatsCard extends StatelessWidget {
  const _HeroStatsCard({
    required this.stats,
    required this.period,
    required this.onPeriodChanged,
  });

  final DashboardStats stats;
  final StatsPeriod period;
  final ValueChanged<StatsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final completionRate = stats.totalAppointments == 0
        ? 0
        : (stats.completedAppointments / stats.totalAppointments * 100).round();

    return AppCard(
      radius: AppRadius.xl,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('آمار نوبت‌ها و عملکرد', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: pal.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        TweenAnimationBuilder<double>(
                          key: ValueKey('dashboard-total-${period.name}-${stats.totalAppointments}'),
                          tween: Tween(begin: 0, end: stats.totalAppointments.toDouble()),
                          duration: const Duration(milliseconds: 850),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => Text('${FaNum.ofInt(value.round())} نوبت', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: pal.textPrimary, height: 1.3)),
                        ),
                        TrendChip(value: '${FaNum.ofInt(completionRate)}٪', positive: true),
                      ],
                    ),
                  ],
                ),
                PillToggle(
                  dense: constraints.maxWidth < 360,
                  options: const ['روزانه', 'هفتگی', 'ماهانه'],
                  selectedIndex: switch (period) {
                    StatsPeriod.daily => 0,
                    StatsPeriod.weekly => 1,
                    StatsPeriod.monthly => 2,
                  },
                  onChanged: (i) => onPeriodChanged(switch (i) {
                    0 => StatsPeriod.daily,
                    1 => StatsPeriod.weekly,
                    _ => StatsPeriod.monthly,
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final completed = StatTile(
                label: 'تکمیل شده',
                value: '${FaNum.ofInt(stats.completedAppointments)} نوبت',
                icon: Icons.assignment_turned_in_rounded,
                tint: pal.primaryBright,
                background: pal.surfaceAlt.withValues(alpha: 0.55),
                borderColor: pal.borderStrong.withValues(alpha: 0.6),
              );
              final revenue = StatTile(
                label: 'درآمد تخمینی',
                value: Fmt.compactMoneyShort(stats.monthRevenue),
                icon: Icons.account_balance_wallet_rounded,
                tint: pal.success,
                background: pal.successSoft,
                borderColor: pal.success.withValues(alpha: 0.28),
                valueSize: 13.5,
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [completed, const SizedBox(height: 8), revenue],
                );
              }
              return Row(
                children: [
                  Expanded(child: completed),
                  const SizedBox(width: 10),
                  Expanded(child: revenue),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: pal.primary.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 5),
              Text('حجم نوبت', style: TextStyle(fontSize: 9.5, color: pal.textMuted)),
              const SizedBox(width: 16),
              Container(width: 15, height: 2.5, decoration: BoxDecoration(color: pal.accentGlow, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 5),
              Text('درآمد', style: TextStyle(fontSize: 9.5, color: pal.textMuted)),
            ],
          ),
          const SizedBox(height: 4),
          PerformanceChart(
            key: ValueKey('performance-chart-${period.name}'),
            data: stats.weekdayPerformance,
            height: 208,
            onPointTap: (point) {
              final date = point.dateIso;
              if (date != null) context.push('/reports?date=$date');
            },
          ),
        ],
      ),
    );
  }
}


/// انتخابگر هفت‌روزه پیشخوان؛ روز جاری در شروع انتخاب می‌شود.
class _DashboardDayPicker extends StatelessWidget {
  const _DashboardDayPicker({required this.selectedDay, required this.onSelected});
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 3));
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = start.add(Duration(days: index));
          final jalali = JalaliDate.fromDateTime(day);
          final selected = day.year == selectedDay.year && day.month == selectedDay.month && day.day == selectedDay.day;
          return Semantics(
            button: true, selected: selected,
            label: '${jalali.weekdayName} ${FaNum.ofInt(jalali.day)}',
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelected(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic,
                width: 66, padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
                decoration: BoxDecoration(
                  gradient: selected ? pal.primaryGradient : null,
                  color: selected ? null : pal.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: selected ? pal.primaryBright : pal.border),
                  boxShadow: selected ? AppShadows.glow(pal.primary, opacity: 0.18, blur: 12) : const [],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(jalali.weekdayName.length > 3 ? jalali.weekdayName.substring(0, 3) : jalali.weekdayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: selected ? Colors.white.withValues(alpha: 0.86) : pal.textMuted)),
                  const SizedBox(height: 4),
                  Text(FaNum.ofInt(jalali.day), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: selected ? Colors.white : pal.textPrimary)),
                  const SizedBox(height: 2),
                  Text(jalali.monthName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: selected ? Colors.white.withValues(alpha: 0.82) : pal.textMuted)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
