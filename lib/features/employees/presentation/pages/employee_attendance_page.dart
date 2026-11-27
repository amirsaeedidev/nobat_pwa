import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/employee_attendance.dart';
import '../../../../data/repositories/supabase_employee_attendance_repository.dart';
import '../providers/employees_provider.dart';

class EmployeeAttendancePage extends StatefulWidget {
  const EmployeeAttendancePage({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<EmployeeAttendancePage> createState() => _EmployeeAttendancePageState();
}

class _EmployeeAttendancePageState extends State<EmployeeAttendancePage> {
  int _reloadKey = 0;
  bool _busy = false;

  bool _hasOpenSession(List<EmployeeAttendanceRecord> records, DateTime today) {
    final events = records.where((item) =>
      item.workDate.year == today.year &&
      item.workDate.month == today.month &&
      item.workDate.day == today.day &&
      (item.type == EmployeeAttendanceEventType.checkIn ||
       item.type == EmployeeAttendanceEventType.checkOut)).toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return events.isNotEmpty &&
        events.last.type == EmployeeAttendanceEventType.checkIn;
  }

  Future<void> _record(
    SupabaseEmployeeAttendanceRepository repository,
    EmployeeAttendanceEventType type,
  ) async {
    final note = TextEditingController();
    final late = TextEditingController();
    final overtime = TextEditingController();
    final early = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('ثبت ${type.label}'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
            if (type == EmployeeAttendanceEventType.checkIn)
              TextField(controller: late, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'دقایق تأخیر')),
            if (type == EmployeeAttendanceEventType.checkOut) ...[
              TextField(controller: overtime, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'دقایق اضافه‌کاری')),
              TextField(controller: early, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'دقایق خروج زودهنگام')),
            ],
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت')),
        ],
      ),
    );
    if (result != true || !mounted) {
      note.dispose(); late.dispose(); overtime.dispose(); early.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      await repository.record(
        employeeId: widget.employeeId,
        type: type,
        workDate: DateTime(now.year, now.month, now.day),
        occurredAt: now,
        note: note.text,
        lateMinutes: int.tryParse(late.text) ?? 0,
        overtimeMinutes: int.tryParse(overtime.text) ?? 0,
        earlyLeaveMinutes: int.tryParse(early.text) ?? 0,
      );
      if (mounted) {
        AppToast.show(context, 'رویداد حضور و غیاب در سرور ثبت شد.');
        setState(() => _reloadKey++);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت حضور ناموفق بود: $error', success: false);
    } finally {
      note.dispose(); late.dispose(); overtime.dispose(); early.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordSpecial(
    SupabaseEmployeeAttendanceRepository repository,
    EmployeeAttendanceEventType type,
  ) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('ثبت ${type.label}'),
        content: TextField(controller: note, maxLines: 3,
          decoration: const InputDecoration(labelText: 'دلیل ثبت (الزامی)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت')),
        ],
      ),
    );
    if (confirmed != true || !mounted) { note.dispose(); return; }
    if (note.text.trim().isEmpty) {
      note.dispose();
      AppToast.show(context, 'ثبت دلیل الزامی است.', success: false);
      return;
    }
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      await repository.record(
        employeeId: widget.employeeId,
        type: type,
        workDate: DateTime(now.year, now.month, now.day),
        occurredAt: now,
        note: note.text.trim(),
      );
      if (mounted) {
        AppToast.show(context, 'رویداد در دفتر حضور و غیاب ثبت شد.');
        setState(() => _reloadKey++);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت رویداد ناموفق بود: $error', success: false);
    } finally {
      note.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manualCorrection(
    SupabaseEmployeeAttendanceRepository repository,
  ) async {
    final note = TextEditingController();
    final worked = TextEditingController();
    final late = TextEditingController();
    final overtime = TextEditingController();
    final early = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ثبت اصلاح دستی'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: note, decoration: const InputDecoration(labelText: 'دلیل اصلاح (الزامی)')),
          TextField(controller: worked, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'دقایق کارکرد')),
          TextField(controller: late, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'دقایق تأخیر')),
          TextField(controller: overtime, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'دقایق اضافه‌کاری')),
          TextField(controller: early, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'دقایق خروج زودهنگام')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت اصلاح')),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      note.dispose(); worked.dispose(); late.dispose(); overtime.dispose(); early.dispose();
      return;
    }
    if (note.text.trim().isEmpty) {
      AppToast.show(context, 'ثبت دلیل اصلاح الزامی است.', success: false);
      note.dispose(); worked.dispose(); late.dispose(); overtime.dispose(); early.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      await repository.record(
        employeeId: widget.employeeId,
        type: EmployeeAttendanceEventType.manualCorrection,
        workDate: DateTime(now.year, now.month, now.day),
        occurredAt: now,
        note: note.text.trim(),
        workedMinutes: int.tryParse(worked.text) ?? 0,
        lateMinutes: int.tryParse(late.text) ?? 0,
        overtimeMinutes: int.tryParse(overtime.text) ?? 0,
        earlyLeaveMinutes: int.tryParse(early.text) ?? 0,
      );
      if (mounted) {
        AppToast.show(context, 'اصلاح به‌صورت رکورد جدید ثبت شد؛ سابقه اصلی حفظ شد.');
        setState(() => _reloadKey++);
      }
    } catch (error) {
      if (mounted) AppToast.show(context, 'ثبت اصلاح ناموفق بود: $error', success: false);
    } finally {
      note.dispose(); worked.dispose(); late.dispose(); overtime.dispose(); early.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = context.watch<EmployeesProvider>();
    final auth = context.watch<SupabaseAuthStateNotifier?>();
    final repository = context.watch<SupabaseEmployeeAttendanceRepository?>();
    final employee = employees.byIdSync(widget.employeeId);
    final canManage = auth?.role == 'owner' || auth?.permissions['employees.manage'] == true;
    final canRecord = canManage || auth?.employeeId == widget.employeeId;

    if (employee == null) {
      return PageScaffold(
        title: 'حضور و غیاب',
        showBackButton: true,
        child: employees.loading
            ? const LoadingState(kind: SkeletonKind.personnel)
            : employees.error != null
                ? ErrorStateView(description: employees.error, onRetry: employees.load)
                : const EmptyState(title: 'پرسنل پیدا نشد'),
      );
    }

    if (repository == null) {
      return PageScaffold(
        title: 'حضور و غیاب',
        subtitle: employee.fullName,
        showBackButton: true,
        child: const ErrorStateView(
          description: 'Repository حضور و غیاب Supabase در این محیط تزریق نشده است. هیچ داده محلی یا آزمایشی نمایش داده نمی‌شود.',
        ),
      );
    }
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0);
    return PageScaffold(
      title: 'حضور و غیاب',
      subtitle: employee.fullName,
      icon: Icons.access_time_rounded,
      showBackButton: true,
      actions: [
        if (canRecord) OutlinedButton.icon(
          onPressed: _busy ? null : () => _record(repository, EmployeeAttendanceEventType.checkIn),
          icon: const Icon(Icons.login_rounded, size: 17),
          label: const Text('ثبت ورود'),
        ),
      ],
      child: FutureBuilder<List<EmployeeAttendanceRecord>>(
        key: ValueKey(_reloadKey),
        future: repository.fetchRecords(employeeId: employee.id, from: from, to: to),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingState(kind: SkeletonKind.personnel);
          }
          if (snapshot.hasError) {
            return ErrorStateView(
              description: 'دریافت سوابق حضور و غیاب از Supabase ناموفق بود: ${snapshot.error}',
              onRetry: () => setState(() => _reloadKey++),
            );
          }
          final records = snapshot.data ?? const <EmployeeAttendanceRecord>[];
          final summary = repository.summarize(records, from: from, to: to);
          final open = _hasOpenSession(records, now);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth > 700 ? 3 : 2;
              final gap = 8.0;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              final metrics = [
                _metric('روزهای حضور', summary.presentDays.toString()),
                _metric('روزهای غیبت', summary.absentDays.toString()),
                _metric('ساعت کارکرد', (summary.workedMinutes / 60).toStringAsFixed(1)),
                _metric('اضافه‌کاری', '${summary.overtimeMinutes} دقیقه'),
                _metric('تأخیر', '${summary.lateMinutes} دقیقه'),
                _metric('خروج زودهنگام', '${summary.earlyLeaveMinutes} دقیقه'),
              ];
              return Wrap(spacing: gap, runSpacing: gap,
                children: metrics.map((item) => SizedBox(width: width, child: item)).toList());
            }),
            const SizedBox(height: 12),
            if (canRecord) AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionHeader(title: 'ثبت رویداد امروز'),
              Text(open ? 'یک نوبت ورود باز دارید؛ ابتدا خروج را ثبت کنید.' : 'برای ثبت ورود یا خروج از دکمه مربوط استفاده کنید.',
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _busy || open ? null : () => _record(repository, EmployeeAttendanceEventType.checkIn),
                  icon: const Icon(Icons.login_rounded), label: const Text('ورود')),
                OutlinedButton.icon(
                  onPressed: _busy || !open ? null : () => _record(repository, EmployeeAttendanceEventType.checkOut),
                  icon: const Icon(Icons.logout_rounded), label: const Text('خروج')),
              ]),
            ])),
            if (canManage) ...[
              const SizedBox(height: 12),
              AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionHeader(title: 'ثبت مدیریتی'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: _busy ? null : () => _recordSpecial(repository, EmployeeAttendanceEventType.absence),
                    icon: const Icon(Icons.event_busy_rounded), label: const Text('ثبت غیبت')),
                  OutlinedButton.icon(onPressed: _busy ? null : () => _recordSpecial(repository, EmployeeAttendanceEventType.mission),
                    icon: const Icon(Icons.directions_walk_rounded), label: const Text('ثبت مأموریت')),
                  OutlinedButton.icon(onPressed: _busy ? null : () => _manualCorrection(repository),
                    icon: const Icon(Icons.edit_note_rounded), label: const Text('اصلاح دستی')),
                ]),
                const SizedBox(height: 6),
                Text('اصلاحات به‌صورت رکورد جدید ثبت می‌شوند و سابقه قبلی حذف یا بازنویسی نمی‌شود.',
                  style: Theme.of(context).textTheme.bodySmall),
              ])),
            ],
            const SizedBox(height: 12),
            AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader(title: 'سوابق ماه جاری'),
              if (records.isEmpty) const EmptyState(title: 'در این بازه سابقه‌ای ثبت نشده است'),
              for (final item in records) ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_icon(item.type)),
                title: Text(item.type.label),
                subtitle: Text('${item.workDate.year}/${item.workDate.month.toString().padLeft(2, '0')}/${item.workDate.day.toString().padLeft(2, '0')} · ${item.occurredAt.hour.toString().padLeft(2, '0')}:${item.occurredAt.minute.toString().padLeft(2, '0')}\n${item.note}'),
                isThreeLine: item.note.isNotEmpty,
                trailing: item.workedMinutes > 0 ? Text('${item.workedMinutes} دقیقه') : null,
              ),
            ])),
            const SizedBox(height: 8),
            Text('منبع اطلاعات: جدول employee_attendance_records در Supabase؛ بدون داده محلی یا آزمایشی.',
              style: Theme.of(context).textTheme.bodySmall),
          ]);
        },
      ),
    );
  }

  Widget _metric(String label, String value) => AppCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11)),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
    ]),
  );

  IconData _icon(EmployeeAttendanceEventType type) => switch (type) {
    EmployeeAttendanceEventType.checkIn => Icons.login_rounded,
    EmployeeAttendanceEventType.checkOut => Icons.logout_rounded,
    EmployeeAttendanceEventType.absence => Icons.event_busy_rounded,
    EmployeeAttendanceEventType.mission => Icons.directions_walk_rounded,
    EmployeeAttendanceEventType.manualCorrection => Icons.edit_note_rounded,
  };
}
