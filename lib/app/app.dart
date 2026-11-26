import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../features/settings/presentation/providers/settings_provider.dart';
import '../data/mock/app_database.dart';
import '../core/services/supabase_auth_state_notifier.dart';
import '../data/repositories/supabase_auth_repository.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// ریشه برنامه با پشتیبانی کامل RTL و تم پویا.
class DateTimeApp extends StatefulWidget {
  const DateTimeApp({super.key});

  @override
  State<DateTimeApp> createState() => _DateTimeAppState();
}

class _DateTimeAppState extends State<DateTimeApp> {
  late final _router = buildRouter(
    database: context.read<AppDatabase?>(),
    authRepository: context.read<SupabaseAuthRepository?>(),
    // Widget tests and embedded previews may intentionally omit cloud auth.
    // Production injects this notifier from main.dart.
    authStateNotifier: context.read<SupabaseAuthStateNotifier?>(),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<SettingsProvider>().palette;
    return MaterialApp.router(
      title: 'DateTime — مدیریت نوبت‌دهی',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: AppTheme.build(palette, formAccentColor: context.watch<SettingsProvider>().formAccentColor),
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1,
            maxScaleFactor: 1.2,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
