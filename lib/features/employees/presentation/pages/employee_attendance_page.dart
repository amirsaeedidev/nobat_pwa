import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../providers/employees_provider.dart';

/// Attendance is deliberately fail-closed until its Supabase tables and RPCs
/// are deployed. Never render the former local/demo attendance ledger.
class EmployeeAttendancePage extends StatelessWidget {
  const EmployeeAttendancePage({super.key, required this.employeeId});
  final String employeeId;

  @override
  Widget build(BuildContext context) {
    final employees = context.watch<EmployeesProvider>();
    final employee = employees.byIdSync(employeeId);
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
    return PageScaffold(
      title: 'حضور و غیاب',
      subtitle: employee.fullName,
      showBackButton: true,
      child: const ErrorStateView(
        description: 'برای جلوگیری از نمایش اطلاعات آزمایشی، حضور و غیاب تا زمان ایجاد جدول‌ها و عملیات امن Supabase غیرفعال است. در پایگاه داده فعلی جدول یا RPC حضور و غیاب وجود ندارد؛ هیچ داده محلی یا ساختگی نمایش داده نمی‌شود.',
      ),
    );
  }
}
