import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/services/supabase_service.dart';
import 'core/services/supabase_auth_state_notifier.dart';
import 'data/repositories/supabase_auth_repository.dart';
import 'data/repositories/supabase_repository.dart';

import 'app/app.dart';
import 'data/repositories/activity_repository.dart';
import 'data/repositories/supabase_activity_repository.dart';
import 'data/repositories/operations_repository.dart';
import 'data/repositories/supabase_operations_repository.dart';
import 'data/repositories/supabase_employee_wallet_repository.dart';
import 'data/repositories/supabase_employee_attendance_repository.dart';
import 'data/repositories/supabase_employee_analytics_repository.dart';
import 'data/repositories/appointment_repository.dart';
import 'data/repositories/supabase_relational_appointment_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/supabase_customer_repository.dart';
import 'data/repositories/dashboard_repository.dart';
import 'data/repositories/business_finance_repository.dart';
import 'data/repositories/supabase_business_finance_repository.dart';
import 'data/repositories/supabase_dashboard_repository.dart';
import 'data/repositories/employee_repository.dart';
import 'data/repositories/supabase_relational_employee_repository.dart';
import 'data/repositories/service_repository.dart';
import 'data/repositories/supabase_relational_service_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/supabase_settings_repository.dart';
import 'data/repositories/sms_repository.dart';
import 'data/repositories/supabase_sms_repository.dart';
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

  // Cloud data is mandatory. Never fall back to seeded or in-memory demo data
  // when Supabase is not configured or cannot initialize.
  final cloudReady = await SupabaseService.initialize();
  if (!cloudReady) {
    runApp(const SupabaseUnavailableApp());
    return;
  }

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

  final supabaseClient = SupabaseService.client!;
  final supabaseRepository = SupabaseRepository(supabaseClient);
  final supabaseAuthRepository = SupabaseAuthRepository(supabaseClient);
  final authStateNotifier = SupabaseAuthStateNotifier(
    supabaseAuthRepository,
    supabaseRepository,
  );

  // Customer CRUD is backed by the normalized public.customers table.
  final customerRepository = SupabaseCustomerRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
    canViewFinance: () => authStateNotifier.role == 'owner' || authStateNotifier.permissions['finance.view'] == true,
  );
  // Primary business data modules use tenant-scoped Supabase repositories.
  // SMS stays explicitly unavailable until a real gateway is configured.
  final appointmentRepository = SupabaseRelationalAppointmentRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );
  final serviceRepository = SupabaseRelationalServiceRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );
  final employeeRepository = SupabaseRelationalEmployeeRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );
  final smsRepository = const SupabaseSmsRepository();
  final settingsRepository = SupabaseSettingsRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );
  final dashboardRepository = SupabaseDashboardRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
    appointments: appointmentRepository,
  );
  final businessFinanceRepository = SupabaseBusinessFinanceRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );
  final activityRepository = SupabaseActivityRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );
  final activityOperationsRepository = SupabaseOperationsRepository(supabaseClient);
  final employeeWalletRepository = SupabaseEmployeeWalletRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );
  final employeeAttendanceRepository = SupabaseEmployeeAttendanceRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );
  final employeeAnalyticsRepository = SupabaseEmployeeAnalyticsRepository(
    client: supabaseClient,
    businessId: () => authStateNotifier.businessId,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<SupabaseRepository?>.value(value: supabaseRepository),
        Provider<SupabaseAuthRepository?>.value(value: supabaseAuthRepository),
        ChangeNotifierProvider<SupabaseAuthStateNotifier>.value(
          value: authStateNotifier,
        ),
        Provider<AppointmentRepository>.value(value: appointmentRepository),
        Provider<CustomerRepository>.value(value: customerRepository),
        Provider<ServiceRepository>.value(value: serviceRepository),
        Provider<EmployeeRepository>.value(value: employeeRepository),
        Provider<SmsRepository>.value(value: smsRepository),
        Provider<SettingsRepository>.value(value: settingsRepository),
        Provider<DashboardRepository>.value(value: dashboardRepository),
        Provider<BusinessFinanceRepository>.value(value: businessFinanceRepository),
        Provider<ActivityRepository>.value(value: activityRepository),
        Provider<ActivityOperationsRepository>.value(value: activityOperationsRepository),
        Provider<SupabaseEmployeeWalletRepository>.value(value: employeeWalletRepository),
        Provider<SupabaseEmployeeAttendanceRepository>.value(value: employeeAttendanceRepository),
        Provider<SupabaseEmployeeAnalyticsRepository>.value(value: employeeAnalyticsRepository),
        ChangeNotifierProvider(create: (_) => SettingsProvider(settingsRepository, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => DashboardProvider(dashboardRepository, null, appointmentRepository: appointmentRepository, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => AppointmentsProvider(appointmentRepository, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(
          create: (_) => CalendarProvider(appointmentRepository, employeeRepository, serviceRepository, settingsRepository: settingsRepository, authStateNotifier: authStateNotifier),
        ),
        ChangeNotifierProvider(create: (_) => CustomersProvider(customerRepository, null, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => ServicesProvider(serviceRepository, null, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => EmployeesProvider(employeeRepository, null, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => SmsProvider(smsRepository, null, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => ReportsProvider(dashboardRepository, null, authStateNotifier: authStateNotifier)),
        ChangeNotifierProvider(create: (_) => ActivityProvider(activityRepository, null, operationsRepository: activityOperationsRepository, authStateNotifier: authStateNotifier)),
      ],
      child: const DateTimeApp(),
    ),
  );
}


class SupabaseUnavailableApp extends StatelessWidget {
  const SupabaseUnavailableApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa', 'IR'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.cloud_off_rounded, size: 52),
                        SizedBox(height: 18),
                        Text(
                          'اتصال امن به Supabase در دسترس نیست',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'برای جلوگیری از نمایش اطلاعات ساختگی، برنامه بدون اتصال معتبر به پایگاه داده اجرا نمی‌شود. تنظیمات اتصال و اینترنت را بررسی کنید.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
