import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/services/supabase_service.dart';
import 'core/services/supabase_auth_state_notifier.dart';
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
  final supabaseClient = SupabaseService.client;
  final supabaseRepository = supabaseClient == null
      ? null
      : SupabaseRepository(supabaseClient);
  final supabaseAuthRepository = supabaseClient == null
      ? null
      : SupabaseAuthRepository(supabaseClient);
  final authStateNotifier = SupabaseAuthStateNotifier(
    supabaseAuthRepository,
    supabaseRepository,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<SupabaseRepository?>.value(value: supabaseRepository),
        Provider<SupabaseAuthRepository?>.value(value: supabaseAuthRepository),
        ChangeNotifierProvider<SupabaseAuthStateNotifier>.value(
          value: authStateNotifier,
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
        ChangeNotifierProvider(create: (_) => SettingsProvider(settingsRepository, database, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => DashboardProvider(dashboardRepository, database, appointmentRepository: appointmentRepository, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => AppointmentsProvider(appointmentRepository, database, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(
          create: (_) => CalendarProvider(appointmentRepository, employeeRepository, serviceRepository, database, authStateNotifier: authStateNotifier),
        ),
        ChangeNotifierProvider(create: (_) => CustomersProvider(customerRepository, database, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => ServicesProvider(serviceRepository, database, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => EmployeesProvider(employeeRepository, database, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => SmsProvider(smsRepository, database, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => ReportsProvider(dashboardRepository, database, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => ActivityProvider(activityRepository, database, authStateNotifier: authStateNotifier)),
      ],
      child: const DateTimeApp(),
    ),
  );
}
