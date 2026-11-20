import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:datetime/app/app.dart';
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
  testWidgets('برنامه بدون خطا بالا می‌آید و پیشخوان رندر می‌شود', (tester) async {
    final db = AppDatabase();
    final appointments = MockAppointmentRepository(db);
    final customers = MockCustomerRepository(db);
    final services = MockServiceRepository(db);
    final employees = MockEmployeeRepository(db);
    final settings = MockSettingsRepository(db);

    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
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

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('پیشخوان'), findsWidgets);

    // پوسته اصلی در عرض‌های موبایل کوچک، موبایل معمولی، تبلت و دسکتاپ باید بدون overflow بماند.
    for (final width in [320.0, 360.0, 375.0, 390.0, 414.0, 600.0, 768.0, 1024.0, 1280.0, 1440.0]) {
      tester.view.physicalSize = Size(width * 2, 800 * 2);
      tester.view.devicePixelRatio = 2;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final exception = tester.takeException();
      if (exception != null) {
        debugPrint('--- RENDER TREE AT VIEWPORT $width ---');
        debugDumpRenderTree();
        final details = exception is FlutterError ? exception.toStringDeep() : exception.toString();
        fail('Viewport width: $width\\n$details');
      }
    }
  });
}
