import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_inputs.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/jalali_picker.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/business_settings.dart';
import '../../../../data/models/enums.dart';
import '../providers/settings_provider.dart';

/// تنظیمات پیشرفته: شیفت‌های کاری و تعطیلات هفتگی — بازسازی تصویر مرجع.
class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key});

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  final Map<int, List<Shift>> _schedules = {};
  List<int> _holidays = [];
  List<ScheduleException> _exceptions = [];
  bool _scheduleExpanded = true;
  bool _holidaysExpanded = true;
  bool _saving = false;
  bool _prefilled = false;
  int _activeDay = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final settings = context.read<SettingsProvider>();
    for (var day = 0; day < 7; day++) {
      _schedules[day] = settings.workingHours[day] ?? const [];
    }
    _holidays = [...settings.holidays];
    _exceptions = [...settings.scheduleExceptions];
  }

  Future<void> _save() async {
    final settingsProvider = context.read<SettingsProvider>();
    setState(() => _saving = true);
    await settingsProvider.updateWorkingHours(
          Map<int, List<Shift>>.from(_schedules.map((k, v) => MapEntry(k, [...v]))),
          holidays: _holidays,
        );
    await settingsProvider.updateScheduleExceptions(_exceptions);
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.show(context, 'تغییرات با موفقیت ذخیره شد');
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;

    return PageScaffold(
      title: 'تنظیمات پیشرفته',
      subtitle: 'پیکربندی ۱۴۰۵',
      icon: Icons.tune_rounded,
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExpandablePanel(
            title: 'زمان‌بندی فعالیت',
            subtitle: 'برای بستن کلیک کنید',
            icon: Icons.schedule_rounded,
            accent: pal.primary,
            gradient: [pal.info.withValues(alpha: 0.22), pal.backgroundAlt],
            expanded: _scheduleExpanded,
            onToggle: () => setState(() => _scheduleExpanded = !_scheduleExpanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        final day = 0;
                        _schedules[day] = [...(_schedules[day] ?? const []), const Shift(start: '08:30', end: '13:00')];
                      }),
                      icon: const Icon(Icons.add_rounded, size: 15),
                      label: const Text('شیفت جدید', style: TextStyle(fontSize: 11.5)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pal.primaryBright,
                        side: BorderSide(color: pal.primary.withValues(alpha: 0.6)),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'مدیریت شیفت‌های کاری',
                      style: TextStyle(fontSize: 12, color: pal.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var day = 0; day < 7; day++)
                      GestureDetector(
                        onTap: () => setState(() => _activeDay = day),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _activeDay == day
                                ? pal.primaryBright.withValues(alpha: 0.2)
                                : pal.backgroundAlt.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: _activeDay == day ? pal.primaryBright : pal.border,
                            ),
                          ),
                          child: Text(
                            WeekDay.names[day],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: _activeDay == day ? FontWeight.w700 : FontWeight.w500,
                              color: _activeDay == day ? pal.textPrimary : pal.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildDayShifts(context, _activeDay),
                const SizedBox(height: 4),
                Text(
                  'هر روز می‌توانید چند شیفت مستقل تعریف کنید؛ خانه‌های زمانی بر همین اساس ساخته می‌شوند.',
                  style: TextStyle(fontSize: 10, color: pal.textMuted, height: 1.7),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ExpandablePanel(
            title: 'تعطیلات هفتگی',
            subtitle: 'برای بستن کلیک کنید',
            icon: Icons.event_busy_rounded,
            accent: pal.danger,
            gradient: [const Color(0xFF7F1D3A).withValues(alpha: 0.32), const Color(0xFF2A0F1A).withValues(alpha: 0.9)],
            expanded: _holidaysExpanded,
            onToggle: () => setState(() => _holidaysExpanded = !_holidaysExpanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'روزهای غیرفعال هفته را انتخاب کنید',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: pal.textSecondary),
                ),
                const SizedBox(height: 12),
                ChipSelector(
                  options: WeekDay.names,
                  selected: _holidays,
                  dangerSelected: true,
                  onToggle: (index) => setState(() {
                    _holidays = _holidays.contains(index)
                        ? _holidays.where((d) => d != index).toList()
                        : [..._holidays, index];
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  'روزهای انتخاب شده به عنوان تعطیل نمایش داده می‌شوند و امکان رزرو در آن‌ها وجود ندارد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: pal.textMuted, height: 1.8),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ExpandablePanel(
            title: 'تعطیلات و ساعات ویژه', subtitle: 'بستن روز یا تعریف ساعت کاری متفاوت برای یک تاریخ',
            icon: Icons.event_available_rounded, accent: pal.warning,
            gradient: [pal.warning.withValues(alpha: 0.16), pal.backgroundAlt], expanded: true, onToggle: () {},
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(onPressed: _addScheduleException, icon: const Icon(Icons.add_rounded), label: const Text('افزودن محدودیت تاریخ‌دار')),
              if (_exceptions.isEmpty) Text('محدودیت تاریخ‌داری ثبت نشده است.', style: TextStyle(fontSize: 10, color: pal.textMuted))
              else for (final item in _exceptions) ListTile(dense: true, contentPadding: EdgeInsets.zero,
                leading: Icon(item.isClosed ? Icons.event_busy_rounded : Icons.schedule_rounded, color: item.isClosed ? pal.danger : pal.warning),
                title: Text(item.title.isEmpty ? item.dateKey : item.title, style: TextStyle(fontSize: 11, color: pal.textPrimary)),
                subtitle: Text(item.isClosed ? 'تعطیل کامل' : item.shifts.map((s) => s.label).join(' • '), style: TextStyle(fontSize: 9.5, color: pal.textMuted)),
                trailing: IconButton(tooltip: 'حذف محدودیت', icon: Icon(Icons.delete_outline_rounded, color: pal.danger, size: 19), onPressed: () => setState(() => _exceptions.remove(item))),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          GradientCta(
            title: 'تأیید و ثبت تغییرات',
            subtitle: '${FaNum.ofInt(_holidays.length)} روز تعطیل • ${FaNum.ofInt(_schedules.values.where((s) => s.isNotEmpty).length)} روز فعال',
            icon: Icons.save_rounded,
            height: 66,
            onPressed: _saving ? () {} : _save,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => context.push('/settings/rules'),
            child: Text('تنظیم قواعد رزرو و لغو', style: TextStyle(fontSize: 11.5, color: pal.primaryBright)),
          ),
        ],
      ),
    );
  }

  Future<void> _addScheduleException() async {
    final today = JalaliDate.today();
    final picked = await showJalaliDatePicker(
      context,
      initial: today,
      minDate: JalaliDate(1400, 1, 1),
      maxDate: today.addDays(730),
      title: 'انتخاب تاریخ محدودیت',
    );
    if (picked == null || !mounted) return;
    final selectedDate = picked.toDateTime();
    final dateKey = '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
    final closed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('نوع محدودیت'), content: const Text('برای این تاریخ چه برنامه‌ای ثبت شود؟'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('ساعات ویژه')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تعطیلی کامل'))],
    ));
    if (closed == null || !mounted) return;
    var specialShifts = const <Shift>[];
    if (!closed) {
      final startLite = await showTimePickerSheet(context, initial: const TimeOfDayLite(10, 0), title: 'شروع ساعت ویژه');
      if (startLite == null || !mounted) return;
      final endLite = await showTimePickerSheet(context, initial: const TimeOfDayLite(14, 0), title: 'پایان ساعت ویژه');
      if (endLite == null || !mounted) return;
      final start = TimeOfDay(hour: startLite.hour, minute: startLite.minute);
      final end = TimeOfDay(hour: endLite.hour, minute: endLite.minute);
      final startMinutes = start.hour * 60 + start.minute;
      final endMinutes = end.hour * 60 + end.minute;
      if (endMinutes <= startMinutes) {
        AppToast.show(context, 'ساعت پایان باید بعد از ساعت شروع باشد');
        return;
      }
      String key(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      specialShifts = [Shift(start: key(start), end: key(end))];
    }
    setState(() {
      _exceptions.removeWhere((e) => e.dateKey == dateKey);
      _exceptions.add(ScheduleException(dateKey: dateKey, title: closed ? 'تعطیلی ${picked.numeric}' : 'ساعات ویژه ${picked.numeric}', isClosed: closed, shifts: specialShifts));
    });
  }

  Widget _buildDayShifts(BuildContext context, int day) {
    final pal = context.pal;
    final shifts = _schedules[day] ?? const <Shift>[];
    final isHoliday = _holidays.contains(day);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: pal.backgroundAlt.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: pal.border),
        ),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    WeekDay.names[day],
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: pal.textPrimary),
                  ),
                ),
                Expanded(
                  child: Text(
                    isHoliday ? 'تعطیل هفتگی' : (shifts.isEmpty ? 'بدون شیفت' : '${FaNum.ofInt(shifts.length)} شیفت'),
                    style: TextStyle(fontSize: 10, color: isHoliday ? pal.danger : pal.textMuted),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'افزودن شیفت',
                  onPressed: () => setState(() {
                    _schedules[day] = [...shifts, const Shift(start: '16:00', end: '21:00')];
                  }),
                  icon: Icon(Icons.add_circle_outline_rounded, size: 16, color: pal.primaryBright),
                ),
              ],
            ),
            for (var index = 0; index < shifts.length; index++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TimeDropdown(
                        value: shifts[index].start,
                        onChanged: (v) => setState(() {
                          final list = [..._schedules[day]!];
                          list[index] = list[index].copyWith(start: v);
                          _schedules[day] = list;
                        }),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TimeDropdown(
                        value: shifts[index].end,
                        onChanged: (v) => setState(() {
                          final list = [..._schedules[day]!];
                          list[index] = list[index].copyWith(end: v);
                          _schedules[day] = list;
                        }),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        final list = [..._schedules[day]!]..removeAt(index);
                        _schedules[day] = list;
                      }),
                      icon: Icon(Icons.delete_outline_rounded, size: 17, color: pal.danger),
                    ),
                  ],
                ),
              ),
            if (shifts.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  shifts.map((s) => s.label).join(' • '),
                  style: TextStyle(fontSize: 9.5, color: pal.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpandablePanel extends StatelessWidget {
  const _ExpandablePanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.gradient,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Color> gradient;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Icon(icon, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: pal.textPrimary),
                        ),
                        Text(subtitle, style: TextStyle(fontSize: 10, color: pal.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0 : 0.5,
                    duration: AppDurations.fast,
                    child: Icon(Icons.keyboard_arrow_up_rounded, color: accent, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: AppDurations.normal,
            crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                children: [
                  Divider(color: accent.withValues(alpha: 0.2), height: 1),
                  const SizedBox(height: 12),
                  child,
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
