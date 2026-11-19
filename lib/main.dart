import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/services/supabase_service.dart';
import 'data/repositories/supabase_auth_repository.dart';
import 'data/repositories/supabase_repository.dart';

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

  // Keep the fallback error UI safe even when the failure happens before
  // MaterialApp has installed Directionality. This prevents error-widget
  // failures from recursively producing more errors on Flutter Web.
  ErrorWidget.builder = (details) => Directionality(
        textDirection: TextDirection.rtl,
        child: ColoredBox(
          color: const Color(0xFF0A1227),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                kDebugMode
                    ? 'خطا در نمایش این بخش\\n${details.exceptionAsString()}'
                    : 'خطایی در نمایش این بخش رخ داد.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
              ),
            ),
          ),
        ),
      );

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    debugPrint('[DateTime][FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }
  };

  // Supabase is opt-in and initialized locally only. No network request is
  // required for startup; if configuration or local session restoration fails,
  // the app continues in its Datamonck offline mode.
  await SupabaseService.initialize();

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
        Provider<SupabaseRepository?>.value(
          value: SupabaseService.client == null
              ? null
              : SupabaseRepository(SupabaseService.client!),
        ),
        Provider<SupabaseAuthRepository?>.value(
          value: SupabaseService.client == null
              ? null
              : SupabaseAuthRepository(SupabaseService.client!),
        ),
        ChangeNotifierProvider<AppDatabase>.value(value: database),
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
      child: const DateTimeApp(),
    ),
  );
}
