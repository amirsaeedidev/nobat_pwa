import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../providers/employees_provider.dart';

/// The old analytics calculator read seeded AppDatabase collections.
/// Keep the route, but fail closed until the real Supabase analytics
/// repository is available rather than presenting local figures as live data.
class EmployeeAnalyticsPage extends StatelessWidget {
  const EmployeeAnalyticsPage({super.key, this.employeeId});
  final String? employeeId;

  @override
  Widget build(BuildContext context) {
    final employees = context.watch<EmployeesProvider>();
    final employee = employeeId == null
        ? (employees.items.isEmpty ? null : employees.items.first)
        : employees.byIdSync(employeeId!);
    if (employee == null) {
      return PageScaffold(
        title: 'تحلیل عملکرد پرسنل',
        showBackButton: true,
        child: employees.loading
            ? const LoadingState(kind: SkeletonKind.personnel)
            : employees.error != null
                ? ErrorStateView(description: employees.error, onRetry: employees.load)
                : const EmptyState(title: 'پرسنلی برای گزارش وجود ندارد'),
      );
    }
    return PageScaffold(
      title: 'تحلیل عملکرد پرسنل',
      subtitle: employee.fullName,
      icon: Icons.query_stats_rounded,
      showBackButton: true,
      child: const ErrorStateView(
        description: 'محاسبه‌گر قبلی از داده‌های محلی و آزمایشی استفاده می‌کرد. برای جلوگیری از نمایش گزارش غیرواقعی، این صفحه تا زمان اتصال Repository گزارش عملکرد به نوبت‌ها، دفتر کل مالی، ساعات کاری و مرخصی‌های Supabase داده‌ای نمایش نمی‌دهد.',
      ),
    );
  }
}
