import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:datetime/app/app.dart';
import 'package:datetime/core/responsive/app_shell.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/repositories/appointment_repository.dart';
import 'package:datetime/data/repositories/customer_repository.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';
import 'package:datetime/data/repositories/employee_repository.dart';
import 'package:datetime/data/repositories/service_repository.dart';
import 'package:datetime/data/repositories/settings_repository.dart';
import 'package:datetime/data/repositories/sms_repository.dart';
import 'package:datetime/data/repositories/activity_repository.dart';
import 'package:datetime/features/activity_logs/presentation/providers/activity_provider.dart';
import 'package:datetime/features/appointments/presentation/providers/appointments_provider.dart';
import 'package:datetime/features/booking/presentation/providers/booking_provider.dart';
import 'package:datetime/features/calendar/presentation/providers/calendar_provider.dart';
import 'package:datetime/features/customers/presentation/providers/customers_provider.dart';
import 'package:datetime/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:datetime/features/employees/presentation/providers/employees_provider.dart';
import 'package:datetime/features/reports/presentation/providers/reports_provider.dart';
import 'package:datetime/features/services/presentation/providers/services_provider.dart';
import 'package:datetime/features/settings/presentation/providers/settings_provider.dart';
import 'package:datetime/features/sms/presentation/providers/sms_provider.dart';

void main() {
  testWidgets('تمام مسیرهای اصلی پرسنل و صفحات وابسته بدون Runtime exception باز می‌شوند', (tester) async {
    final db = AppDatabase();
    final appointments = MockAppointmentRepository(db);
    final customers = MockCustomerRepository(db);
    final services = MockServiceRepository(db);
    final employees = MockEmployeeRepository(db);
    final settings = MockSettingsRepository(db);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppDatabase>.value(value: db),
          ChangeNotifierProvider(create: (_) => SettingsProvider(settings, db)),
          ChangeNotifierProvider(create: (_) => DashboardProvider(MockDashboardRepository(db), db)),
          ChangeNotifierProvider(create: (_) => AppointmentsProvider(appointments, db)),
          ChangeNotifierProvider(create: (_) => CalendarProvider(appointments, employees, services, db)),
          ChangeNotifierProvider(create: (_) => CustomersProvider(customers, db)),
          ChangeNotifierProvider(create: (_) => ServicesProvider(services, db)),
          ChangeNotifierProvider(create: (_) => EmployeesProvider(employees, db)),
          ChangeNotifierProvider(create: (_) => SmsProvider(MockSmsRepository(db), db)),
          ChangeNotifierProvider(create: (_) => ReportsProvider(MockDashboardRepository(db), db)),
          ChangeNotifierProvider(create: (_) => ActivityProvider(MockActivityRepository(db), db)),
          ChangeNotifierProvider(create: (_) => BookingProvider(appointments, services, employees, customers, db)),
        ],
        child: const DateTimeApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    final shell = find.byType(AppShell);
    expect(shell, findsOneWidget);
    final router = GoRouter.of(tester.element(shell));
    const paths = [
      '/employees',
      '/employees/new',
      '/employees/emp-fateme',
      '/employees/emp-fateme/edit',
      '/employees/emp-fateme/finance',
      '/employees/emp-fateme/wallet',
      '/employees/emp-fateme/schedule',
      '/employees/emp-fateme/analytics',
      '/employees/emp-fateme/attendance',
      '/employees/emp-fateme/records',
      '/employees/emp-fateme/leaves',
      '/employees/emp-fateme/notices',
      '/calendar',
      '/appointments',
      '/services',
      '/reports/personnel',
      '/settings/permissions',
    ];

    for (final path in paths) {
      router.go(path);
      await tester.pumpAndSettle(const Duration(milliseconds: 40), timeout: const Duration(seconds: 4));
      expect(tester.takeException(), isNull, reason: 'Route failed: $path');
    }
  });
}
