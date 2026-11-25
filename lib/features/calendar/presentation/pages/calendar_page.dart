import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/enums.dart';
import '../../../appointments/presentation/widgets/appointment_tile.dart';
import '../providers/calendar_provider.dart';
import '../widgets/calendar_widgets.dart';

/// تقویم شمسی نوبت‌ها با نمای روزانه، هفتگی و ماهانه.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CalendarProvider>();
    final pal = context.pal;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    final controls = AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (provider.loading) const LoadingState(kind: SkeletonKind.generic, compact: true),
          if (provider.error != null)
            ErrorStateView(description: provider.error, onRetry: provider.load),
          CalendarHeader(
            title: switch (provider.view) {
              CalendarView.monthly => '${provider.anchor.monthName} ${FaNum.ofInt(provider.anchor.year)}',
              CalendarView.weekly => 'هفته ${provider.weekDays.first.short} تا ${provider.weekDays.last.short}',
              CalendarView.daily => provider.selected.relativeLabel(),
            },
            onPrevious: provider.previous,
            onNext: provider.next,
            onToday: provider.selectToday,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PillToggle(
                options: const ['روزانه', 'هفتگی', 'ماهانه'],
                selectedIndex: provider.view.index,
                onChanged: (i) => provider.setView(CalendarView.values[i]),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ChoiceChip(label: const Text('همه خدمات'), selected: provider.serviceId == null, onSelected: (_) => provider.setService(null)),
              for (final service in provider.services) ...[
                const SizedBox(width: 6),
                ChoiceChip(label: Text(service.title), selected: provider.serviceId == service.id, onSelected: (_) => provider.setService(service.id)),
              ],
            ]),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<AppointmentStatus?>(
              value: provider.statusFilter,
              isExpanded: true,
              isDense: true,
              dropdownColor: pal.surfaceAlt,
              style: TextStyle(fontSize: 11.5, color: pal.textPrimary),
              icon: Icon(Icons.filter_alt_outlined, size: 16, color: pal.textMuted),
              items: [
                const DropdownMenuItem<AppointmentStatus?>(
                  value: null,
                  child: Text('فیلتر وضعیت: همه وضعیت‌ها'),
                ),
                for (final status in AppointmentStatus.values)
                  DropdownMenuItem<AppointmentStatus?>(
                    value: status,
                    child: Text(status.label),
                  ),
              ],
              onChanged: provider.setStatus,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: provider.employeeId,
              isExpanded: true,
              isDense: true,
              dropdownColor: pal.surfaceAlt,
              style: TextStyle(fontSize: 11.5, color: pal.textPrimary),
              icon: Icon(Icons.filter_list_rounded, size: 16, color: pal.textMuted),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('فیلتر پرسنل: همه متخصصان')),
                for (final employee in provider.employees)
                  DropdownMenuItem<String?>(value: employee.id, child: Text(employee.fullName)),
              ],
              onChanged: provider.setEmployee,
            ),
          ),
        ],
      ),
    );

    return PageScaffold(
      title: 'تقویم نوبت‌ها',
      subtitle: 'نمای روزانه، هفتگی و ماهانه',
      icon: Icons.calendar_month_rounded,
      actions: [
        SoftButton(label: 'بازآوری', icon: Icons.refresh_rounded, onTap: provider.load),
        SolidButton(
          label: 'نوبت جدید',
          icon: Icons.add_rounded,
          height: 42,
          onPressed: () => context.push('/appointments/new'),
        ),
      ],
      mobileActions: [
        CircleIconButton(icon: Icons.refresh_rounded, size: 38, onTap: provider.load),
      ],
      showBackButton: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isDesktop) ...[
            Row(
              children: [
                Expanded(
                  child: SolidButton(
                    label: 'نوبت جدید',
                    icon: Icons.add_rounded,
                    gradient: true,
                    height: 52,
                    onPressed: () => context.push('/appointments/new'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: Column(children: [controls, const SizedBox(height: 12), _MonthOrDayView(provider: provider)])),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: _AgendaView(provider: provider)),
              ],
            )
          else
            Column(
              children: [
                controls,
                const SizedBox(height: 12),
                _MonthOrDayView(provider: provider),
                const SizedBox(height: 12),
                _AgendaView(provider: provider),
              ],
            ),
          const SizedBox(height: 12),
          const SizedBox(height: 6),
          Text(
            provider.holidayFor(provider.selected)?.title ??
                (provider.isHoliday(provider.selected) ? 'این روز طبق برنامه واقعی تعطیل است' : 'برنامه کاری بر اساس اطلاعات ثبت‌شده مجموعه است'),
            style: TextStyle(fontSize: 10, color: pal.textMuted),
          ),
        ],
      ),
    );
  }
}

/// نمای ماهانه یا جدول روز (بسته به حالت انتخاب‌شده).
class _MonthOrDayView extends StatelessWidget {
  const _MonthOrDayView({required this.provider});

  final CalendarProvider provider;

  Future<void> _reschedule(
    BuildContext context,
    Appointment appointment,
    DateTime newStart,
  ) async {
    final date = JalaliDate.fromDateTime(newStart);
    final time = '${newStart.hour.toString().padLeft(2, '0')}:${newStart.minute.toString().padLeft(2, '0')}';
    final confirmed = await showConfirmDialog(
      context,
      title: 'تأیید جابه‌جایی نوبت',
      message: 'نوبت ${appointment.customerName} به ${date.long} ساعت ${FaNum.convert(time)} منتقل شود؟',
      confirmLabel: 'تغییر زمان',
      icon: Icons.event_repeat_rounded,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await provider.rescheduleAppointment(appointment, newStart);
      if (context.mounted) AppToast.show(context, 'زمان نوبت با موفقیت تغییر کرد.');
    } catch (error) {
      if (context.mounted) AppToast.show(context, error.toString(), success: false);
    }
  }

  Widget _timeline(BuildContext context, JalaliDate date) {
    final slots = provider.slotsFor(date, employee: provider.employeeId);
    return DayTimeline(
      slots: slots,
      onSlotTap: (slot) {
        if (slot.appointment != null) {
          context.push('/appointments/${slot.appointment!.id}');
        } else {
          final date = slot.date.toDateTime().toIso8601String().substring(0, 10);
          context.push('/appointments/new?date=$date&time=${slot.label}');
        }
      },
      onReschedule: (appointment, newStart) =>
          _reschedule(context, appointment, newStart),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (provider.view == CalendarView.daily) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'برنامه ${provider.selected.weekdayName}',
              subtitle: provider.selected.long,
            ),
            const SizedBox(height: 12),
            _timeline(context, provider.selected),
          ],
        ),
      );
    }

    if (provider.view == CalendarView.weekly) {
      return Column(
        children: [
          for (final date in provider.weekDays) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: date.weekdayName,
                    subtitle: date.long,
                  ),
                  const SizedBox(height: 10),
                  _timeline(context, date),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    return AppCard(
      child: JalaliMonthGrid(
        provider: provider,
        onSelect: provider.setSelected,
        compact: MediaQuery.sizeOf(context).width < 400,
      ),
    );
  }
}

/// فهرست کارت‌های روز (نمای هفتگی/روزانه) — مطابق تصویر مرجع.
class _AgendaView extends StatelessWidget {
  const _AgendaView({required this.provider});

  final CalendarProvider provider;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final days = provider.view == CalendarView.weekly
        ? provider.weekDays
        : provider.view == CalendarView.daily
            ? [provider.selected]
            : [for (var i = 0; i < provider.selected.monthLength; i++) JalaliDate(provider.anchor.year, provider.anchor.month, i + 1)];

    final withAppointments = days.where((d) => provider.appointmentsOn(d).isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: provider.view == CalendarView.monthly ? 'نوبت‌های ${provider.anchor.monthName}' : 'نوبت‌های هفته',
          subtitle: '${FaNum.ofInt(provider.appointments.length)} نوبت در بازه نمایش',
          actionLabel: 'نوبت جدید',
          onAction: () => context.push('/appointments/new'),
        ),
        const SizedBox(height: 10),
        if (withAppointments.isEmpty)
          const EmptyState(
            title: 'نوبتی در این بازه ثبت نشده',
            description: 'برای ثبت نوبت جدید از دکمه بالا استفاده کنید.',
            compact: true,
          )
        else
          for (final date in withAppointments) ...[
            CalendarDayCard(
              date: date,
              appointments: provider.appointmentsOn(date),
              onAdd: () => context.push('/appointments/new'),
              onBroadcast: () => AppToast.show(context, 'ارسال پیام همگانی در فاز بعدی فعال می‌شود'),
              onTapAppointment: (appointment) => context.push('/appointments/${appointment.id}'),
            ),
            const SizedBox(height: 10),
          ],
        if (provider.view == CalendarView.monthly)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(title: 'نوبت‌های ${provider.selected.long}'),
                const SizedBox(height: 10),
                if (provider.appointmentsOn(provider.selected).isEmpty)
                  Text(
                    'نوبتی نیست',
                    style: TextStyle(fontSize: 11.5, color: pal.textMuted),
                  )
                else
                  for (final appointment in provider.appointmentsOn(provider.selected))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppointmentTile(
                        appointment: appointment,
                        dense: true,
                        onTap: () => context.push('/appointments/${appointment.id}'),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}
