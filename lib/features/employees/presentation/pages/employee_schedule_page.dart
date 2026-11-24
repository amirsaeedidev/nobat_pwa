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
import '../../../../core/widgets/jalali_picker.dart';
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
  late Future<({List<EmployeeScheduleException> exceptions, List<EmployeeLeave> leaves})> _dataFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataFuture = _loadData();
  }

  Future<({List<EmployeeScheduleException> exceptions, List<EmployeeLeave> leaves})> _loadData() async {
    final repository = context.read<EmployeesProvider>();
    final now = DateTime.now();
    final from = DateTime(now.year - 1, 1, 1);
    final to = DateTime(now.year + 2, 12, 31);
    final results = await Future.wait([
      repository.fetchScheduleExceptions(employeeId: widget.employeeId, from: from, to: to),
      repository.fetchLeaves(widget.employeeId),
    ]);
    return (
      exceptions: results[0] as List<EmployeeScheduleException>,
      leaves: results[1] as List<EmployeeLeave>,
    );
  }

  EmployeeScheduleException? _exceptionForDate(List<EmployeeScheduleException> values, String key) {
    for (final item in values) {
      if (item.dateKey == key) return item;
    }
    return null;
  }

  void _refreshData() {
    if (mounted) setState(() => _dataFuture = _loadData());
  }

  Future<TimeOfDay?> _time(TimeOfDay? initial) async {
    final picked = await showTimePickerSheet(
      context,
      initial: initial == null
          ? const TimeOfDayLite(9, 0)
          : TimeOfDayLite(initial.hour, initial.minute),
      title: 'انتخاب ساعت کاری',
    );
    if (picked == null) return null;
    return TimeOfDay(hour: picked.hour, minute: picked.minute);
  }

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

  Future<void> _saveEmployee(Employee employee, {Map<int, List<Shift>>? schedule, bool? enabled, int? bufferMinutes}) async {
    try {
      final updated = employee.copyWith(
        schedule: schedule ?? employee.schedule,
        scheduleEnabled: enabled ?? employee.scheduleEnabled,
        bufferMinutes: bufferMinutes ?? employee.bufferMinutes,
      );
      final saved = await context.read<EmployeesProvider>().update(updated);
      if (!saved) throw StateError('شماره تماس تکراری است.');
      _refreshData();
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    }
  }

  Future<void> _addShift(Employee employee, int weekday) async {
    final shift = await _pickShift();
    if (shift == null || !mounted) return;
    final schedule = employee.schedule.map((key, value) => MapEntry(key, [...value]));
    final shifts = [...(schedule[weekday] ?? const <Shift>[]), shift];
    try {
      EmployeeScheduleRules.validateShifts(shifts);
      schedule[weekday] = shifts..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
      await _saveEmployee(employee, schedule: schedule);
      if (mounted) AppToast.show(context, 'شیفت در Supabase ذخیره شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString().replaceFirst('ArgumentError: ', ''), success: false);
    }
  }

  Future<void> _removeShift(Employee employee, int weekday, Shift shift) async {
    final schedule = employee.schedule.map((key, value) => MapEntry(key, [...value]));
    schedule[weekday] = (schedule[weekday] ?? []).where((item) => item.start != shift.start || item.end != shift.end).toList();
    await _saveEmployee(employee, schedule: schedule);
  }

  Future<void> _addException(Employee employee) async {
    final today = JalaliDate.today();
    final pickedDate = await showJalaliDatePicker(
      context, initial: today, minDate: today.addDays(-365),
      maxDate: today.addDays(730), title: 'انتخاب تاریخ تعطیلی یا ساعت ویژه',
    );
    if (pickedDate == null || !mounted) return;
    final date = pickedDate.toDateTime();
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
      await context.read<EmployeesProvider>().saveScheduleException(EmployeeScheduleException(
        employeeId: employee.id, dateKey: EmployeeScheduleRules.dateKey(date),
        title: title.trim().isEmpty ? 'ساعات ویژه' : title.trim(),
        isClosed: closed, shifts: shifts,
      ));
      _refreshData();
      if (mounted) AppToast.show(context, 'استثنا در Supabase ذخیره شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    }
  }

  Future<void> _deleteException(EmployeeScheduleException exception) async {
    try {
      await context.read<EmployeesProvider>().deleteScheduleException(exception.employeeId, exception.dateKey);
      _refreshData();
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    }
  }

  Future<void> _addLeave(Employee employee) async {
    final today = JalaliDate.today();
    final startJalali = await showJalaliDatePicker(
      context, initial: today, minDate: today.addDays(-365),
      maxDate: today.addDays(730), title: 'شروع مرخصی',
    );
    if (startJalali == null || !mounted) return;
    final endJalali = await showJalaliDatePicker(
      context, initial: startJalali, minDate: startJalali,
      maxDate: today.addDays(730), title: 'پایان مرخصی',
    );
    if (endJalali == null || !mounted) return;
    final startDate = startJalali.toDateTime();
    final endDate = endJalali.toDateTime();
    var type = EmployeeLeaveType.daily;
    var description = '';
    final details = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
      title: const Text('ثبت درخواست مرخصی'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<EmployeeLeaveType>(
          value: type,
          decoration: const InputDecoration(labelText: 'نوع مرخصی'),
          items: EmployeeLeaveType.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
          onChanged: (value) { if (value != null) setDialogState(() => type = value); },
        ),
        TextField(decoration: const InputDecoration(labelText: 'توضیحات'), onChanged: (value) => description = value),
        const SizedBox(height: 8),
        const Text('درخواست پس از ثبت در وضعیت «در انتظار تأیید» قرار می‌گیرد.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت درخواست')),
      ],
    )));
    if (details != true || !mounted) return;
    if (description.trim().isEmpty) {
      AppToast.show(context, 'توضیحات درخواست الزامی است.', success: false);
      return;
    }
    var start = DateTime(startDate.year, startDate.month, startDate.day);
    var end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
    if (type == EmployeeLeaveType.hourly) {
      final from = await _time(const TimeOfDay(hour: 9, minute: 0));
      if (from == null || !mounted) return;
      final to = await _time(const TimeOfDay(hour: 13, minute: 0));
      if (to == null || !mounted) return;
      start = DateTime(startDate.year, startDate.month, startDate.day, from.hour, from.minute);
      end = DateTime(startDate.year, startDate.month, startDate.day, to.hour, to.minute);
      if (!end.isAfter(start)) {
        AppToast.show(context, 'پایان مرخصی باید بعد از شروع باشد.', success: false);
        return;
      }
    }
    try {
      await context.read<EmployeesProvider>().createLeave(EmployeeLeave(
        id: '', employeeId: employee.id, startAt: start, endAt: end,
        type: type, status: EmployeeLeaveStatus.pending,
        description: description.trim(), createdAt: DateTime.now(),
      ));
      _refreshData();
      if (mounted) AppToast.show(context, 'درخواست مرخصی در Supabase ثبت شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    }
  }

  Widget _buildMonthlyCalendar(
    Employee employee,
    List<EmployeeScheduleException> exceptions,
    List<EmployeeLeave> leaves,
    AppPalette pal,
  ) {
    final first = JalaliDate(_visibleMonth.year, _visibleMonth.month, 1);
    final days = List.generate(42, (index) => first.addDays(index - first.weekday));
    final selected = _selectedDate ?? JalaliDate.today();
    final selectedStart = selected.toDateTime();
    final selectedEnd = selectedStart.add(const Duration(days: 1));
    final selectedKey = EmployeeScheduleRules.dateKey(selectedStart);
    final selectedException = _exceptionForDate(exceptions, selectedKey);
    final selectedShifts = selectedException != null
        ? selectedException.shifts
        : employee.scheduleEnabled ? employee.shiftsFor(selected.weekday - 1) : const <Shift>[];
    final selectedLeave = leaves.where((leave) => leave.overlaps(selectedStart, selectedEnd)).toList();

    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: SectionHeader(title: 'تقویم کاری ماهانه')),
        IconButton(onPressed: () => setState(() => _visibleMonth = _visibleMonth.addMonths(-1)), icon: const Icon(Icons.chevron_right_rounded)),
        Text(_visibleMonth.monthName + ' ' + FaNum.ofInt(_visibleMonth.year), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.textPrimary)),
        IconButton(onPressed: () => setState(() => _visibleMonth = _visibleMonth.addMonths(1)), icon: const Icon(Icons.chevron_left_rounded)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        for (final name in WeekDay.shortNames)
          Expanded(child: Center(child: Text(name, style: TextStyle(fontSize: 10, color: pal.textMuted, fontWeight: FontWeight.w700)))),
      ]),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 1.2,
        children: [
          for (final day in days)
            Builder(builder: (context) {
              final inMonth = day.month == _visibleMonth.month;
              final dateStart = day.toDateTime();
              final dateEnd = dateStart.add(const Duration(days: 1));
              final key = EmployeeScheduleRules.dateKey(dateStart);
              final exception = _exceptionForDate(exceptions, key);
              final onLeave = leaves.any((leave) => leave.overlaps(dateStart, dateEnd));
              final hasShift = exception != null
                  ? !exception.isClosed && exception.shifts.isNotEmpty
                  : employee.scheduleEnabled && employee.shiftsFor(day.weekday - 1).isNotEmpty;
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
    final provider = context.watch<EmployeesProvider>();
    final employee = provider.byIdSync(widget.employeeId);
    final pal = context.pal;
    if (employee == null) {
      return PageScaffold(title: 'برنامه کاری پرسنل', showBackButton: true,
        child: provider.loading ? const LoadingState(kind: SkeletonKind.personnel)
          : provider.error != null ? ErrorStateView(description: provider.error, onRetry: provider.load)
          : const EmptyState(title: 'پرسنل یافت نشد'));
    }
    return FutureBuilder(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return PageScaffold(title: 'برنامه کاری پرسنل', subtitle: employee.fullName, showBackButton: true,
            child: const LoadingState(kind: SkeletonKind.personnel));
        }
        if (snapshot.hasError) {
          return PageScaffold(title: 'برنامه کاری پرسنل', subtitle: employee.fullName, showBackButton: true,
            child: ErrorStateView(description: snapshot.error.toString(), onRetry: () => setState(() => _dataFuture = _loadData())));
        }
        final exceptions = snapshot.data!.exceptions..sort((a, b) => a.dateKey.compareTo(b.dateKey));
        final leaves = snapshot.data!.leaves;
        return PageScaffold(
          title: 'برنامه کاری پرسنل',
          subtitle: employee.fullName,
          icon: Icons.calendar_month_rounded,
          showBackButton: true,
          actions: [SoftButton(label: employee.scheduleEnabled ? 'برنامه فعال' : 'برنامه غیرفعال', icon: Icons.toggle_on_rounded,
            onTap: () => _saveEmployee(employee, enabled: !employee.scheduleEnabled))],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final item in const [(0, 'برنامه هفتگی'), (1, 'استثناها'), (2, 'مرخصی‌ها')])
                ChoiceChip(label: Text(item.$2), selected: _tab == item.$1, onSelected: (_) => setState(() => _tab = item.$1)),
            ]),
            const SizedBox(height: 12),
            if (_tab == 0) ...[
              _buildMonthlyCalendar(employee, exceptions, leaves, pal),
              const SizedBox(height: 10),
              AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionHeader(title: 'تنظیمات برنامه'),
                Material(color: Colors.transparent, child: SwitchListTile(contentPadding: EdgeInsets.zero,
                  title: const Text('فعال بودن برنامه کاری'), value: employee.scheduleEnabled,
                  onChanged: (value) => _saveEmployee(employee, enabled: value))),
                Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8, runSpacing: 4, children: [
                    const Text('فاصله بین نوبت‌ها', style: TextStyle(fontSize: 12)),
                    DropdownButton<int>(value: employee.bufferMinutes,
                      items: [0, 5, 10, 15, 20, 30, 45, 60].map((value) => DropdownMenuItem(value: value, child: Text('$value دقیقه'))).toList(),
                      onChanged: (value) { if (value != null) _saveEmployee(employee, bufferMinutes: value); }),
                  ]),
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
                    Text(DateTime.tryParse(item.dateKey) == null ? item.dateKey : Fmt.jalaliDate(DateTime.parse(item.dateKey)), style: TextStyle(color: pal.textMuted, fontSize: 11)),
                    Text(item.isClosed ? 'تعطیل کامل' : item.shifts.map((s) => s.label).join('، '), style: const TextStyle(fontSize: 11)),
                  ])),
                  IconButton(onPressed: () => _deleteException(item), icon: const Icon(Icons.delete_outline_rounded)),
                ])),
            ] else ...[
              SectionHeader(title: 'درخواست‌ها و مرخصی‌ها', actionLabel: 'ثبت مرخصی', onAction: () => _addLeave(employee)),
              const SizedBox(height: 8),
              if (leaves.isEmpty) const EmptyState(compact: true, title: 'مرخصی ثبت نشده')
              else for (final leave in leaves)
                AppCard(margin: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(leave.type.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                    StatusBadge(label: leave.status.label, color: leave.status == EmployeeLeaveStatus.approved ? pal.success : leave.status == EmployeeLeaveStatus.rejected ? pal.danger : leave.status == EmployeeLeaveStatus.cancelled ? pal.textMuted : pal.warning),
                  ]),
                  Text('${Fmt.jalaliDate(leave.startAt)} تا ${Fmt.jalaliDate(leave.endAt)}', style: TextStyle(color: pal.textSecondary, fontSize: 11)),
                  if (leave.description.isNotEmpty) Text(leave.description, style: TextStyle(color: pal.textMuted, fontSize: 11)),
                ])),
            ],
          ]),
        );
      },
    );
  }
}
