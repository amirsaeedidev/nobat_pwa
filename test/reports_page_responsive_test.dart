import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:datetime/app/theme/app_palette.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';
import 'package:datetime/features/reports/presentation/pages/reports_page.dart';
import 'package:datetime/features/reports/presentation/providers/reports_provider.dart';

void main() {
  testWidgets('reports dashboard stays within mobile, tablet and desktop widths', (tester) async {
    tester.view.devicePixelRatio = 1;
    final db = AppDatabase();
    final reports = ReportsProvider(MockDashboardRepository(db), db);
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const ReportsPage())],
    );
    addTearDown(router.dispose);

    for (final width in [320.0, 390.0, 768.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<ReportsProvider>.value(value: reports),
          ],
          child: MaterialApp.router(
            theme: ThemeData(extensions: const [AppPalette.creamBrown]),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'reports dashboard overflow at width $width');
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
