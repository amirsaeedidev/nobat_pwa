import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_page.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/jalali_picker.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../data/models/employee_schedule.dart';
import '../providers/employees_provider.dart';

class EmployeeLeaveRequestsPage extends StatefulWidget {
  const EmployeeLeaveRequestsPage({super.key, required this.employeeId});
  final String employeeId;

  @override
  State<EmployeeLeaveRequestsPage> createState() => _EmployeeLeaveRequestsPageState();
}

class _EmployeeLeaveRequestsPageState extends State<EmployeeLeaveRequestsPage> {
  late Future<List<EmployeeLeave>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<EmployeesProvider>().fetchLeaves(widget.employeeId);
  }

  void _refresh() {
    if (mounted) setState(() => _future = context.read<EmployeesProvider>().fetchLeaves(widget.employeeId));
  }

  Future<void> _request() async {
    final today = JalaliDate.today();
    final startJalali = await showJalaliDatePicker(
      context, initial: today, minDate: today,
      maxDate: today.addDays(365), title: 'شروع مرخصی',
    );
    if (startJalali == null || !mounted) return;
    final endJalali = await showJalaliDatePicker(
      context, initial: startJalali, minDate: startJalali,
      maxDate: today.addDays(365), title: 'پایان مرخصی',
    );
    if (endJalali == null || !mounted) return;

    var type = EmployeeLeaveType.daily;
    final note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('ثبت درخواست مرخصی'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<EmployeeLeaveType>(
            value: type,
            decoration: const InputDecoration(labelText: 'نوع مرخصی'),
            items: EmployeeLeaveType.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
            onChanged: (value) { if (value != null) setDialogState(() => type = value); },
          ),
          TextField(controller: note, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'توضیحات و دلیل درخواست *')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ثبت درخواست')),
        ],
      )));
    if (ok != true || !mounted) { note.dispose(); return; }
    if (note.text.trim().isEmpty) {
      note.dispose();
      AppToast.show(context, 'توضیحات درخواست الزامی است.', success: false);
      return;
    }

    final startDate = startJalali.toDateTime();
    final endDate = endJalali.toDateTime();
    var start = DateTime(startDate.year, startDate.month, startDate.day);
    var end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
    if (type == EmployeeLeaveType.hourly) {
      final from = await showTimePickerSheet(context,
        initial: const TimeOfDayLite(9, 0), title: 'ساعت شروع مرخصی');
      if (from == null || !mounted) { note.dispose(); return; }
      final to = await showTimePickerSheet(context,
        initial: const TimeOfDayLite(13, 0), title: 'ساعت پایان مرخصی');
      if (to == null || !mounted) { note.dispose(); return; }
      start = DateTime(startDate.year, startDate.month, startDate.day, from.hour, from.minute);
      end = DateTime(startDate.year, startDate.month, startDate.day, to.hour, to.minute);
      if (!end.isAfter(start)) {
        note.dispose();
        AppToast.show(context, 'پایان مرخصی باید بعد از شروع باشد.', success: false);
        return;
      }
    }
    try {
      await context.read<EmployeesProvider>().createLeave(EmployeeLeave(
        id: '', employeeId: widget.employeeId, startAt: start, endAt: end,
        type: type, status: EmployeeLeaveStatus.pending,
        description: note.text.trim(), createdAt: DateTime.now(),
      ));
      _refresh();
      if (mounted) AppToast.show(context, 'درخواست مرخصی در Supabase ثبت شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    } finally {
      note.dispose();
    }
  }

  Future<void> _decide(EmployeeLeave leave, EmployeeLeaveStatus status) async {
    try {
      await context.read<EmployeesProvider>().reviewLeave(leave.copyWith(status: status));
      _refresh();
      if (mounted) AppToast.show(context, status == EmployeeLeaveStatus.approved ? 'درخواست تأیید شد.' : 'درخواست رد شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmployeesProvider>();
    final auth = context.watch<SupabaseAuthStateNotifier>();
    final canApprove = auth.role == 'owner' || auth.permissions['employees.leave.manage'] == true;
    final employee = provider.byIdSync(widget.employeeId);
    if (employee == null) {
      return PageScaffold(title: 'درخواست‌های مرخصی', showBackButton: true,
        child: provider.loading ? const LoadingState(kind: SkeletonKind.personnel)
          : provider.error != null ? ErrorStateView(description: provider.error, onRetry: provider.load)
          : const EmptyState(title: 'پرسنل یافت نشد'));
    }
    return PageScaffold(
      title: 'درخواست‌های مرخصی',
      subtitle: employee.fullName,
      showBackButton: true,
      actions: [SolidButton(label: 'ثبت درخواست', icon: Icons.add, onPressed: _request)],
      mobileHeader: Wrap(spacing: 8, children: [
        SoftButton(label: 'ثبت درخواست مرخصی', icon: Icons.add, onTap: _request),
      ]),
      child: FutureBuilder<List<EmployeeLeave>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingState(kind: SkeletonKind.personnel);
          }
          if (snapshot.hasError) {
            return ErrorStateView(description: snapshot.error.toString(), onRetry: _refresh);
          }
          final leaves = snapshot.data ?? const <EmployeeLeave>[];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader(title: 'تاریخچه درخواست‌ها'),
              if (leaves.isEmpty)
                const EmptyState(title: 'درخواستی وجود ندارد', description: 'درخواست‌های واقعی مرخصی این پرسنل در این قسمت نمایش داده می‌شود.'),
              for (final leave in leaves)
                Padding(padding: const EdgeInsets.only(top: 10), child: Container(
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
                    if (leave.approvedBy != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('شناسه بررسی‌کننده: ${leave.approvedBy}', style: Theme.of(context).textTheme.bodySmall)),
                    if (canApprove && leave.status == EmployeeLeaveStatus.pending) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        SoftButton(label: 'تأیید', icon: Icons.check_circle_outline, color: Colors.green,
                          onTap: () => _decide(leave, EmployeeLeaveStatus.approved)),
                        SoftButton(label: 'رد', icon: Icons.cancel_outlined, color: Theme.of(context).colorScheme.error,
                          onTap: () => _decide(leave, EmployeeLeaveStatus.rejected)),
                      ]),
                    ],
                  ]),
                )),
            ])),
            const SizedBox(height: 8),
            Text('فقط مرخصی تأییدشده برنامه کاری و امکان رزرو را مسدود می‌کند.', style: Theme.of(context).textTheme.bodySmall),
          ]);
        },
      ),
    );
  }

  static Widget _status(BuildContext context, EmployeeLeaveStatus status) {
    final color = switch (status) {
      EmployeeLeaveStatus.pending => Colors.orange,
      EmployeeLeaveStatus.approved => Colors.green,
      EmployeeLeaveStatus.rejected => Theme.of(context).colorScheme.error,
      EmployeeLeaveStatus.cancelled => Theme.of(context).disabledColor,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  static String _date(DateTime value) => JalaliDate.fromDateTime(value).numeric;
}
