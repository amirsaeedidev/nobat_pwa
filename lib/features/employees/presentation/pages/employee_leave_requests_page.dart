import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/employee_schedule.dart';
import '../providers/employees_provider.dart';

class EmployeeLeaveRequestsPage extends StatefulWidget {
  const EmployeeLeaveRequestsPage({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<EmployeeLeaveRequestsPage> createState() => _EmployeeLeaveRequestsPageState();
}

class _EmployeeLeaveRequestsPageState extends State<EmployeeLeaveRequestsPage> {
  Future<Employee?>? _employeeFuture;
  Future<List<EmployeeLeave>>? _leavesFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _employeeFuture ??= context.read<EmployeesProvider>().byId(widget.employeeId);
    _leavesFuture ??= context.read<EmployeesProvider>().leaves(widget.employeeId);
  }

  void _reload() {
    final provider = context.read<EmployeesProvider>();
    setState(() {
      _employeeFuture = provider.byId(widget.employeeId);
      _leavesFuture = provider.leaves(widget.employeeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Employee?>(
      future: _employeeFuture,
      builder: (context, employeeSnapshot) {
        final employee = employeeSnapshot.data;
        if (employeeSnapshot.connectionState != ConnectionState.done) {
          return const PageScaffold(title: 'درخواست‌های مرخصی', showBackButton: true, child: Center(child: CircularProgressIndicator()));
        }
        if (employeeSnapshot.hasError || employee == null) {
          return const PageScaffold(title: 'درخواست‌های مرخصی', showBackButton: true, child: EmptyState(title: 'پرسنل یافت نشد یا دریافت اطلاعات ناموفق بود.'));
        }
        return FutureBuilder<List<EmployeeLeave>>(
          future: _leavesFuture,
          builder: (context, leavesSnapshot) {
            final leaves = leavesSnapshot.data ?? const <EmployeeLeave>[];
            return PageScaffold(
              title: 'درخواست‌های مرخصی',
              subtitle: employee.fullName,
              showBackButton: true,
              actions: [SolidButton(label: 'ثبت درخواست', icon: Icons.add, onPressed: () => _request(context, widget.employeeId))],
              mobileHeader: Wrap(spacing: 8, children: [SoftButton(label: 'ثبت درخواست مرخصی', icon: Icons.add, onTap: () => _request(context, widget.employeeId))]),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionHeader(title: 'تاریخچه درخواست‌ها'),
                  if (leavesSnapshot.connectionState != ConnectionState.done)
                    const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                  else if (leavesSnapshot.hasError)
                    EmptyState(title: 'دریافت مرخصی‌ها از سرور ناموفق بود', description: leavesSnapshot.error.toString())
                  else if (leaves.isEmpty)
                    const EmptyState(title: 'درخواستی وجود ندارد', description: 'درخواست‌های مرخصی این پرسنل در این قسمت نمایش داده می‌شود.'),
                  for (final leave in leaves) Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
                          Text(leave.type.label, style: Theme.of(context).textTheme.titleSmall),
                          _status(context, leave.status),
                        ]),
                        const SizedBox(height: 6),
                        Text('از ${_date(leave.startAt)} تا ${_date(leave.endAt)}', style: Theme.of(context).textTheme.bodySmall),
                        if (leave.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(leave.description)),
                        if (leave.approvedBy != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('بررسی توسط: ${leave.approvedBy!}', style: Theme.of(context).textTheme.bodySmall)),
                        if (leave.status == EmployeeLeaveStatus.pending) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            SoftButton(label: 'تأیید', icon: Icons.check_circle_outline, color: Colors.green, onTap: () => _decide(leave, EmployeeLeaveStatus.approved)),
                            SoftButton(label: 'رد', icon: Icons.cancel_outlined, color: Theme.of(context).colorScheme.error, onTap: () => _decide(leave, EmployeeLeaveStatus.rejected)),
                          ]),
                        ],
                      ]),
                    ),
                  ),
                ])),
                const SizedBox(height: 8),
                Text('فقط مرخصی تأییدشده برنامه کاری و امکان رزرو را مسدود می‌کند. مجوز تأیید توسط Supabase بررسی می‌شود.', style: Theme.of(context).textTheme.bodySmall),
              ]),
            );
          },
        );
      },
    );
  }

  Widget _status(BuildContext context, EmployeeLeaveStatus status) {
    final color = switch (status) {
      EmployeeLeaveStatus.pending => Colors.orange,
      EmployeeLeaveStatus.approved => Colors.green,
      EmployeeLeaveStatus.rejected => Theme.of(context).colorScheme.error,
      EmployeeLeaveStatus.cancelled => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  String _date(DateTime value) => '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

  Future<void> _request(BuildContext context, String employeeId) async {
    final now = DateTime.now();
    final note = TextEditingController();
    var type = EmployeeLeaveType.daily;
    final start = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (start == null || !context.mounted) { note.dispose(); return; }
    final end = await showDatePicker(context: context, initialDate: start, firstDate: start, lastDate: now.add(const Duration(days: 365)));
    if (end == null || !context.mounted) { note.dispose(); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('ثبت درخواست مرخصی'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<EmployeeLeaveType>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'نوع مرخصی'),
            items: EmployeeLeaveType.values.map((value) => DropdownMenuItem(value: value, child: Text(value.label))).toList(),
            onChanged: (value) { if (value != null) setDialogState(() => type = value); },
          ),
          TextField(controller: note, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'توضیحات و دلیل درخواست *')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت درخواست')),
        ],
      )),
    );
    if (ok == true && context.mounted) {
      try {
        if (note.text.trim().isEmpty) throw ArgumentError('توضیحات درخواست الزامی است.');
        var leaveStart = DateTime(start.year, start.month, start.day);
        var leaveEnd = DateTime(end.year, end.month, end.day, 23, 59);
        if (type == EmployeeLeaveType.hourly) {
          final fromTime = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
          if (fromTime == null || !context.mounted) { note.dispose(); return; }
          final toTime = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
          if (toTime == null || !context.mounted) { note.dispose(); return; }
          leaveStart = DateTime(start.year, start.month, start.day, fromTime.hour, fromTime.minute);
          leaveEnd = DateTime(end.year, end.month, end.day, toTime.hour, toTime.minute);
        }
        await context.read<EmployeesProvider>().createLeave(EmployeeLeave(
          id: 'leave-' + DateTime.now().microsecondsSinceEpoch.toString(),
          employeeId: employeeId,
          startAt: leaveStart,
          endAt: leaveEnd,
          type: type,
          status: EmployeeLeaveStatus.pending,
          description: note.text.trim(),
          createdAt: now,
        ));
        if (context.mounted) { _reload(); AppToast.show(context, 'درخواست مرخصی در سرور ثبت شد.'); }
      } catch (error) {
        if (context.mounted) AppToast.show(context, error.toString(), success: false);
      }
    }
    note.dispose();
  }

  Future<void> _decide(EmployeeLeave leave, EmployeeLeaveStatus status) async {
    try {
      await context.read<EmployeesProvider>().updateLeave(leave.copyWith(status: status));
      if (!mounted) return;
      _reload();
      AppToast.show(context, status == EmployeeLeaveStatus.approved ? 'مرخصی تأیید شد.' : 'مرخصی رد شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    }
  }
}
