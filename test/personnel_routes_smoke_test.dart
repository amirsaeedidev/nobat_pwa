import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    tester.view.physicalSize = const Size(320, 844);
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
    final employeeId = db.employees.first.id;
    final customerId = db.customers.first.id;
    final serviceId = db.services.first.id;
    final appointmentId = db.appointments.first.id;
    final paths = [
      '/dashboard',
      '/appointments',
      '/appointments/new',
      '/appointments/$appointmentId',
      '/calendar',
      '/customers',
      '/customers/new',
      '/customers/$customerId',
      '/services',
      '/services/new',
      '/services/$serviceId',
      '/employees',
      '/employees/new',
      '/employees/$employeeId',
      '/employees/$employeeId/edit',
      '/employees/$employeeId/finance',
      '/employees/$employeeId/wallet',
      '/employees/$employeeId/schedule',
      '/employees/$employeeId/analytics',
      '/employees/$employeeId/attendance',
      '/employees/$employeeId/records',
      '/employees/$employeeId/leaves',
      '/employees/$employeeId/notices',
      '/reports',
      '/reports/personnel',
      '/search',
      '/activity',
      '/settings',
      '/settings/permissions',
      '/settings/appearance',
      '/settings/business',
      '/settings/hours',
      '/settings/rules',
      '/settings/location',
      '/settings/notifications',
      '/settings/link',
      '/sms',
      '/sms/settings',
      '/sms/templates',
      '/book',
      '/book/manage',
    ];

    const widths = [320.0, 360.0, 375.0, 390.0, 414.0, 768.0, 1280.0];
    for (final width in widths) {
      tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
      tester.view.devicePixelRatio = 1;
      await tester.pump();
      for (final path in paths) {
        router.go(path);
        try {
          await tester.pump(const Duration(milliseconds: 90));
        } catch (error) {
          debugPrint('Responsive route failure at ${width.toInt()}px $path');
          debugDumpRenderTree();
          fail('Responsive route failure at ${width.toInt()}px $path: $error');
        }
        final exception = tester.takeException();
        if (exception != null) {
          final details = exception is FlutterError ? exception.toStringDeep() : exception.toString();
          debugPrint('Responsive route failure at ${width.toInt()}px $path');
          debugDumpRenderTree();
          fail('Responsive route failure at ${width.toInt()}px $path: $details');
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
