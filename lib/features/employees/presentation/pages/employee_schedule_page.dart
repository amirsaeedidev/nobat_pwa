import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/employee_schedule.dart';
import '../../../../data/models/enums.dart';
import '../providers/employees_provider.dart';

class EmployeeSchedulePage extends StatefulWidget {
  const EmployeeSchedulePage({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<EmployeeSchedulePage> createState() => _EmployeeSchedulePageState();
}

class _EmployeeSchedulePageState extends State<EmployeeSchedulePage> {
  int _tab = 0;
  late JalaliDate _visibleMonth = JalaliDate.today();
  JalaliDate? _selectedDate;

  Future<TimeOfDay?> _time(TimeOfDay? initial) => showTimePicker(
    context: context,
    initialTime: initial ?? const TimeOfDay(hour: 9, minute: 0),
    helpText: 'انتخاب ساعت',
  );

  Future<Shift?> _pickShift() async {
    final start = await _time(const TimeOfDay(hour: 9, minute: 0));
    if (start == null || !mounted) return null;
    final end = await _time(TimeOfDay(hour: (start.hour + 1).clamp(0, 23).toInt(), minute: start.minute));
    if (end == null || !mounted) return null;
    final shift = Shift(
      start: '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
      end: '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
    );
    if (shift.startMinutes >= shift.endMinutes) {
      AppToast.show(context, 'ساعت پایان باید بعد از شروع باشد.', success: false);
      return null;
    }
    return shift;
  }

  Future<void> _addShift(Employee employee, int weekday) async {
    final shift = await _pickShift();
    if (shift == null || !mounted) return;
    final schedule = employee.schedule.map((key, value) => MapEntry(key, [...value]));
    final shifts = [...(schedule[weekday] ?? const <Shift>[]), shift];
    try {
      EmployeeScheduleRules.validateShifts(shifts);
      schedule[weekday] = shifts..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
      context.read<AppDatabase>().saveEmployeeWeeklySchedule(employee.id, schedule, enabled: employee.scheduleEnabled, bufferMinutes: employee.bufferMinutes);
      AppToast.show(context, 'شیفت اضافه شد.');
    } catch (error) {
      AppToast.show(context, error.toString().replaceFirst('ArgumentError: ', ''), success: false);
    }
  }

  Future<void> _removeShift(Employee employee, int weekday, Shift shift) async {
    final schedule = employee.schedule.map((key, value) => MapEntry(key, [...value]));
    schedule[weekday] = (schedule[weekday] ?? []).where((item) => item.start != shift.start || item.end != shift.end).toList();
    context.read<AppDatabase>().saveEmployeeWeeklySchedule(employee.id, schedule, enabled: employee.scheduleEnabled, bufferMinutes: employee.bufferMinutes);
  }

  Future<void> _addException(Employee employee) async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (date == null || !mounted) return;
    var closed = true;
    var title = 'تعطیلی اختصاصی';
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('استثنای برنامه کاری'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(Fmt.jalaliDate(date)),
        TextField(decoration: const InputDecoration(labelText: 'عنوان'), onChanged: (value) => title = value),
        SwitchListTile(value: closed, title: const Text('تعطیلی کامل'), onChanged: (value) => setDialogState(() => closed = value)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ادامه')),
      ],
    )));
    if (confirmed != true || !mounted) return;
    var shifts = <Shift>[];
    if (!closed) {
      final shift = await _pickShift();
      if (shift == null || !mounted) return;
      shifts = [shift];
    }
    try {
      context.read<AppDatabase>().saveEmployeeScheduleException(EmployeeScheduleException(
        employeeId: employee.id, dateKey: EmployeeScheduleRules.dateKey(date), title: title,
        isClosed: closed, shifts: shifts,
      ));
      AppToast.show(context, 'استثنای تاریخ‌دار ذخیره شد.');
    } catch (error) {
      AppToast.show(context, error.toString(), success: false);
    }
  }

  Future<void> _addLeave(Employee employee) async {
    final startDate = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (startDate == null || !mounted) return;
    final endDate = await showDatePicker(context: context, initialDate: startDate, firstDate: startDate, lastDate: DateTime.now().add(const Duration(days: 730)));
    if (endDate == null || !mounted) return;
    var type = EmployeeLeaveType.daily;
    var description = '';
    final details = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('ثبت مرخصی پرسنل'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<EmployeeLeaveType>(
          value: type,
          decoration: const InputDecoration(labelText: 'نوع مرخصی'),
          items: EmployeeLeaveType.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
          onChanged: (value) { if (value != null) type = value; },
        ),
        TextField(decoration: const InputDecoration(labelText: 'توضیحات'), onChanged: (value) => description = value),
        const SizedBox(height: 8),
        const Text('درخواست پس از ثبت در وضعیت «در انتظار تأیید» قرار می‌گیرد.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت درخواست')),
      ],
    ));
    if (details != true || !mounted) return;
    var start = DateTime(startDate.year, startDate.month, startDate.day);
    var end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
    if (type == EmployeeLeaveType.hourly) {
      final from = await _time(const TimeOfDay(hour: 9, minute: 0));
      if (from == null || !mounted) return;
      final to = await _time(const TimeOfDay(hour: 13, minute: 0));
      if (to == null || !mounted) return;
      start = DateTime(startDate.year, startDate.month, startDate.day, from.hour, from.minute);
      end = DateTime(startDate.year, startDate.month, startDate.day, to.hour, to.minute);
    }
    try {
      context.read<AppDatabase>().addEmployeeLeave(EmployeeLeave(
        id: 'leave-${DateTime.now().microsecondsSinceEpoch}', employeeId: employee.id,
        startAt: start, endAt: end, type: type, status: EmployeeLeaveStatus.pending,
        description: description, createdAt: DateTime.now(),
      ));
      AppToast.show(context, 'درخواست مرخصی ثبت شد.');
    } catch (error) {
      AppToast.show(context, error.toString().replaceFirst('ArgumentError: ', ''), success: false);
    }
  }

  Widget _buildMonthlyCalendar(Employee employee, AppDatabase db, AppPalette pal) {
    final first = JalaliDate(_visibleMonth.year, _visibleMonth.month, 1);
    final days = List.generate(42, (index) => first.addDays(index - first.weekday));
    final selected = _selectedDate ?? JalaliDate.today();
    final selectedStart = selected.toDateTime();
    final selectedEnd = selectedStart.add(const Duration(days: 1));
    final selectedShifts = db.employeeShiftsForDate(employee.id, selectedStart);
    final selectedLeave = db.leavesForEmployee(employee.id).where((leave) => leave.overlaps(selectedStart, selectedEnd)).toList();

    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: SectionHeader(title: 'تقویم کاری ماهانه')),
        IconButton(
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _visibleMonth = _visibleMonth.addMonths(-1)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        Text(_visibleMonth.monthName + ' ' + FaNum.ofInt(_visibleMonth.year), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.textPrimary)),
        IconButton(
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _visibleMonth = _visibleMonth.addMonths(1)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        for (final name in WeekDay.shortNames)
          Expanded(child: Center(child: Text(name, style: TextStyle(fontSize: 10, color: pal.textMuted, fontWeight: FontWeight.w700)))),
      ]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.2,
        children: [
          for (final day in days)
            Builder(builder: (context) {
              final inMonth = day.month == _visibleMonth.month;
              final dateStart = day.toDateTime();
              final dateEnd = dateStart.add(const Duration(days: 1));
              final exception = db.employeeScheduleException(employee.id, dateStart);
              final onLeave = db.leavesForEmployee(employee.id).any((leave) => leave.overlaps(dateStart, dateEnd));
              final hasShift = db.employeeShiftsForDate(employee.id, dateStart).isNotEmpty;
              final selectedDay = day.year == selected.year && day.month == selected.month && day.day == selected.day;
              final tint = onLeave ? pal.danger : (exception?.isClosed ?? false) ? pal.warning : hasShift ? pal.success : pal.textMuted;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: inMonth ? () => setState(() => _selectedDate = day) : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: selectedDay ? pal.primary.withValues(alpha: 0.14) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selectedDay ? pal.primary : pal.border.withValues(alpha: inMonth ? 0.65 : 0.25)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(FaNum.ofInt(day.day), style: TextStyle(fontSize: 10.5, height: 1.1, color: inMonth ? pal.textPrimary : pal.textMuted.withValues(alpha: 0.45), fontWeight: selectedDay ? FontWeight.w800 : FontWeight.w500)),
                    if (inMonth && (hasShift || onLeave || exception != null)) ...[
                      const SizedBox(height: 1),
                      Container(width: 4, height: 4, decoration: BoxDecoration(color: tint, shape: BoxShape.circle)),
                    ],
                  ]),
                ),
              );
            }),
        ],
      ),
      const Divider(height: 20),
      Text(Fmt.jalaliDate(selectedStart), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.textPrimary)),
      const SizedBox(height: 6),
      if (selectedShifts.isEmpty)
        Text('برای این روز شیفت کاری ثبت نشده است.', style: TextStyle(fontSize: 11, color: pal.textMuted))
      else
        Wrap(spacing: 6, runSpacing: 6, children: [for (final shift in selectedShifts) StatusBadge(label: shift.label, color: pal.success, dense: true)]),
      if (selectedLeave.isNotEmpty) ...[
        const SizedBox(height: 6),
        for (final leave in selectedLeave)
          Text(leave.type.label + ' • ' + Fmt.time(leave.startAt.hour, leave.startAt.minute) + ' تا ' + Fmt.time(leave.endAt.hour, leave.endAt.minute), style: TextStyle(fontSize: 10.5, color: pal.danger)),
      ],
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final employee = context.watch<EmployeesProvider>().byIdSync(widget.employeeId);
    final db = context.watch<AppDatabase>();
    final pal = context.pal;
    if (employee == null) return PageScaffold(title: 'برنامه کاری پرسنل', showBackButton: true, child: const EmptyState(title: 'پرسنل یافت نشد'));
    final exceptions = db.employeeScheduleExceptions.where((item) => item.employeeId == employee.id).toList()..sort((a, b) => a.dateKey.compareTo(b.dateKey));
    final leaves = db.leavesForEmployee(employee.id);
    return PageScaffold(
      title: 'برنامه کاری پرسنل',
      subtitle: employee.fullName,
      icon: Icons.calendar_month_rounded,
      showBackButton: true,
      actions: [SoftButton(label: employee.scheduleEnabled ? 'برنامه فعال' : 'برنامه غیرفعال', icon: Icons.toggle_on_rounded, onTap: () => db.saveEmployeeWeeklySchedule(employee.id, employee.schedule, enabled: !employee.scheduleEnabled, bufferMinutes: employee.bufferMinutes))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final item in const [(0, 'برنامه هفتگی'), (1, 'استثناها'), (2, 'مرخصی‌ها')])
            ChoiceChip(label: Text(item.$2), selected: _tab == item.$1, onSelected: (_) => setState(() => _tab = item.$1)),
        ]),
        const SizedBox(height: 12),
        if (_tab == 0) ...[
          _buildMonthlyCalendar(employee, db, pal),
          const SizedBox(height: 10),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'تنظیمات برنامه'),
            Material(
              color: Colors.transparent,
              child: SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('فعال بودن برنامه کاری'), value: employee.scheduleEnabled, onChanged: (value) => db.saveEmployeeWeeklySchedule(employee.id, employee.schedule, enabled: value, bufferMinutes: employee.bufferMinutes)),
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                const Text('فاصله بین نوبت‌ها', style: TextStyle(fontSize: 12)),
                DropdownButton<int>(value: employee.bufferMinutes, items: [0, 5, 10, 15, 20, 30, 45, 60].map((value) => DropdownMenuItem(value: value, child: Text('$value دقیقه'))).toList(), onChanged: (value) { if (value != null) db.saveEmployeeWeeklySchedule(employee.id, employee.schedule, enabled: employee.scheduleEnabled, bufferMinutes: value); }),
              ],
            ),
          ])),
          const SizedBox(height: 10),
          for (var day = 0; day < 7; day++)
            AppCard(margin: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionHeader(title: WeekDay.names[day], actionLabel: 'افزودن شیفت', onAction: () => _addShift(employee, day)),
              const SizedBox(height: 8),
              if (employee.shiftsFor(day).isEmpty)
                Text('روز تعطیل', style: TextStyle(color: pal.textMuted, fontSize: 12))
              else Wrap(spacing: 6, runSpacing: 6, children: [
                for (final shift in employee.shiftsFor(day))
                  InputChip(label: Text(shift.label), onDeleted: () => _removeShift(employee, day, shift)),
              ]),
            ])),
        ] else if (_tab == 1) ...[
          SectionHeader(title: 'استثناهای تاریخ‌دار', actionLabel: 'افزودن', onAction: () => _addException(employee)),
          const SizedBox(height: 8),
          if (exceptions.isEmpty) const EmptyState(compact: true, title: 'استثنایی ثبت نشده')
          else for (final item in exceptions)
            AppCard(margin: const EdgeInsets.only(bottom: 8), child: Row(children: [
              const Icon(Icons.event_busy_rounded),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(item.dateKey, style: TextStyle(color: pal.textMuted, fontSize: 11)),
                Text(item.isClosed ? 'تعطیل کامل' : item.shifts.map((s) => s.label).join('، '), style: const TextStyle(fontSize: 11)),
              ])),
              IconButton(onPressed: () => db.deleteEmployeeScheduleException(employee.id, item.dateKey), icon: const Icon(Icons.delete_outline_rounded)),
            ])),
        ] else ...[
          SectionHeader(title: 'درخواست‌ها و مرخصی‌ها', actionLabel: 'ثبت مرخصی', onAction: () => _addLeave(employee)),
          const SizedBox(height: 8),
          if (leaves.isEmpty) const EmptyState(compact: true, title: 'مرخصی ثبت نشده')
          else for (final leave in leaves)
            AppCard(margin: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(leave.type.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                StatusBadge(label: leave.status.label, color: leave.status == EmployeeLeaveStatus.approved ? pal.success : leave.status == EmployeeLeaveStatus.rejected ? pal.danger : pal.warning),
                IconButton(onPressed: () => db.deleteEmployeeLeave(leave.id), icon: const Icon(Icons.delete_outline_rounded)),
              ]),
              Text('${Fmt.jalaliDate(leave.startAt)} تا ${Fmt.jalaliDate(leave.endAt)}', style: TextStyle(color: pal.textSecondary, fontSize: 11)),
              if (leave.description.isNotEmpty) Text(leave.description, style: TextStyle(color: pal.textMuted, fontSize: 11)),
              if (leave.status == EmployeeLeaveStatus.pending) Wrap(spacing: 8, children: [
                TextButton(onPressed: () => db.updateEmployeeLeave(leave.copyWith(status: EmployeeLeaveStatus.approved, approvedBy: 'مدیر')), child: const Text('تأیید')),
                TextButton(onPressed: () => db.updateEmployeeLeave(leave.copyWith(status: EmployeeLeaveStatus.rejected, approvedBy: 'مدیر')), child: const Text('رد درخواست')),
              ]),
            ])),
        ],
      ]),
    );
  }
}
