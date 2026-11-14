import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../features/settings/presentation/providers/settings_provider.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// ریشه برنامه با پشتیبانی کامل RTL و تم پویا.
class OnTimeApp extends StatefulWidget {
  const OnTimeApp({super.key});

  @override
  State<OnTimeApp> createState() => _OnTimeAppState();
}

class _OnTimeAppState extends State<OnTimeApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<SettingsProvider>().palette;
    return MaterialApp.router(
      title: 'ONTIME — مدیریت نوبت‌دهی',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: AppTheme.build(palette),
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
