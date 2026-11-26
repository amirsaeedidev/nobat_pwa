import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/services/supabase_service.dart';
import 'data/repositories/supabase_auth_repository.dart';
import 'data/repositories/supabase_repository.dart';
import 'data/repositories/supabase_core_repositories.dart';

import 'app/app.dart';
import 'data/mock/app_database.dart';
import 'data/repositories/activity_repository.dart';
import 'data/repositories/operations_repository.dart';
import 'data/repositories/supabase_activity_repository.dart';
import 'data/repositories/supabase_operations_repository.dart';
import 'data/repositories/appointment_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/dashboard_repository.dart';
import 'data/repositories/employee_repository.dart';
import 'data/repositories/service_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/supabase_settings_repository.dart';
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

  // Core operational modules are Supabase-only. Missing configuration or
  // connectivity is surfaced as an explicit unavailable state, never as mock data.
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

  // Legacy local database remains injected only for modules not yet migrated.
  // Core appointments/customers/services/employees never read it as fallback.
  final database = AppDatabase();

  final supabaseClient = SupabaseService.client;
  final tenantScope = supabaseClient == null ? null : SupabaseTenantScope(supabaseClient);
  final AppointmentRepository appointmentRepository = supabaseClient == null
      ? UnavailableAppointmentRepository()
      : SupabaseAppointmentRepository(supabaseClient, tenantScope!);
  final CustomerRepository customerRepository = supabaseClient == null
      ? UnavailableCustomerRepository()
      : SupabaseCustomerRepository(supabaseClient, tenantScope!);
  final ServiceRepository serviceRepository = supabaseClient == null
      ? UnavailableServiceRepository()
      : SupabaseServiceRepository(supabaseClient, tenantScope!);
  final EmployeeRepository employeeRepository = supabaseClient == null
      ? UnavailableEmployeeRepository()
      : SupabaseEmployeeRepository(supabaseClient, tenantScope!);
  final smsRepository = MockSmsRepository(database);
  final SettingsRepository settingsRepository = SupabaseService.client == null
      ? UnavailableSettingsRepository()
      : SupabaseSettingsRepository(SupabaseService.client!);
  final dashboardRepository = MockDashboardRepository(database);
  final ActivityRepository activityRepository = SupabaseService.client == null
      ? UnavailableActivityRepository()
      : SupabaseActivityRepository(SupabaseService.client!);
  final ActivityOperationsRepository activityOperationsRepository =
      SupabaseService.client == null
          ? UnavailableActivityOperationsRepository()
          : SupabaseOperationsRepository(SupabaseService.client!);

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
        Provider<ActivityOperationsRepository>.value(value: activityOperationsRepository),
        ChangeNotifierProvider(create: (_) => SettingsProvider(settingsRepository)),
        ChangeNotifierProvider(create: (_) => DashboardProvider(dashboardRepository, database, appointmentRepository: appointmentRepository)),
        ChangeNotifierProvider(create: (_) => AppointmentsProvider(appointmentRepository)),
        ChangeNotifierProvider(
          create: (_) => CalendarProvider(appointmentRepository, employeeRepository, serviceRepository),
        ),
        ChangeNotifierProvider(create: (_) => CustomersProvider(customerRepository)),
        ChangeNotifierProvider(create: (_) => ServicesProvider(serviceRepository)),
        ChangeNotifierProvider(create: (_) => EmployeesProvider(employeeRepository)),
        ChangeNotifierProvider(create: (_) => SmsProvider(smsRepository, database)),
        ChangeNotifierProvider(create: (_) => ReportsProvider(dashboardRepository, database)),
        ChangeNotifierProvider(create: (_) => ActivityProvider.remote(activityRepository, activityOperationsRepository)),
        ChangeNotifierProvider(
          create: (_) => BookingProvider(
            appointmentRepository,
            serviceRepository,
            employeeRepository,
            customerRepository,
          ),
        ),
      ],
      child: const DateTimeApp(),
    ),
  );
}
