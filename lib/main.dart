import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'data/mock/app_database.dart';
import 'data/repositories/activity_repository.dart';
import 'data/repositories/appointment_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/dashboard_repository.dart';
import 'data/repositories/employee_repository.dart';
import 'data/repositories/service_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/sms_repository.dart';
import 'features/activity_logs/presentation/providers/activity_provider.dart';
import 'features/appointments/presentation/providers/appointments_provider.dart';
import 'features/booking/presentation/providers/booking_provider.dart';
import 'features/calendar/presentation/providers/calendar_provider.dart';
import 'features/customers/presentation/providers/customers_provider.dart';
import 'features/dashboard/presentation/providers/dashboard_provider.dart';
import 'features/employees/presentation/providers/employees_provider.dart';
import 'features/reports/presentation/providers/reports_provider.dart';
import 'features/services/presentation/providers/services_provider.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/sms/presentation/providers/sms_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (error, stackTrace) {
      debugPrint('Could not set preferred orientations: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // All application data is seeded locally in memory. Startup does not wait
  // for browser storage, network access, or any remote service.
  final database = AppDatabase();

  final appointmentRepository = MockAppointmentRepository(database);
  final customerRepository = MockCustomerRepository(database);
  final serviceRepository = MockServiceRepository(database);
  final employeeRepository = MockEmployeeRepository(database);
  final smsRepository = MockSmsRepository(database);
  final settingsRepository = MockSettingsRepository(database);
  final dashboardRepository = MockDashboardRepository(database);
  final activityRepository = MockActivityRepository(database);

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<AppointmentRepository>.value(value: appointmentRepository),
        Provider<CustomerRepository>.value(value: customerRepository),
        Provider<ServiceRepository>.value(value: serviceRepository),
        Provider<EmployeeRepository>.value(value: employeeRepository),
        Provider<SmsRepository>.value(value: smsRepository),
        Provider<SettingsRepository>.value(value: settingsRepository),
        Provider<DashboardRepository>.value(value: dashboardRepository),
        Provider<ActivityRepository>.value(value: activityRepository),
        ChangeNotifierProvider(create: (_) => SettingsProvider(settingsRepository, database)),
        ChangeNotifierProvider(create: (_) => DashboardProvider(dashboardRepository, database)),
        ChangeNotifierProvider(create: (_) => AppointmentsProvider(appointmentRepository, database)),
        ChangeNotifierProvider(
          create: (_) => CalendarProvider(appointmentRepository, employeeRepository, serviceRepository, database),
        ),
        ChangeNotifierProvider(create: (_) => CustomersProvider(customerRepository, database)),
        ChangeNotifierProvider(create: (_) => ServicesProvider(serviceRepository, database)),
        ChangeNotifierProvider(create: (_) => EmployeesProvider(employeeRepository, database)),
        ChangeNotifierProvider(create: (_) => SmsProvider(smsRepository, database)),
        ChangeNotifierProvider(create: (_) => ReportsProvider(dashboardRepository, database)),
        ChangeNotifierProvider(create: (_) => ActivityProvider(activityRepository, database)),
        ChangeNotifierProvider(
          create: (_) => BookingProvider(
            appointmentRepository,
            serviceRepository,
            employeeRepository,
            customerRepository,
            database,
          ),
        ),
      ],
      child: const OnTimeApp(),
    ),
  );
}
