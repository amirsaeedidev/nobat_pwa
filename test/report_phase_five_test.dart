import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/report_analytics.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';
import 'package:datetime/features/reports/utils/report_phase_five.dart';
import 'package:datetime/features/reports/utils/report_executive_pdf_export.dart';
import 'package:datetime/features/reports/utils/saved_report_store.dart';

ReportAnalytics sample({
  num revenue = 1000,
  int total = 10,
  int completed = 8,
  int cancelled = 1,
}) {
  final range = ReportDateRange.preset(ReportPeriod.thisMonth);
  return ReportAnalytics(
    range: range, revenue: revenue, cost: 200,
    commissionCost: 100, payrollCost: 100,
    totalAppointments: total, completedAppointments: completed,
    cancelledAppointments: cancelled, noShowAppointments: 0,
    uniqueCustomers: 5, statusCounts: const {}, trend: const [],
    employees: const [], services: const [], recentAppointments: const [],
    recentTransactions: const [], costNote: 'test',
  );
}

void main() {
  group('Phase five local report analysis', () {
    test('comparison returns a percentage only when the baseline is non-zero', () {
      expect(ReportInsightEngine.compare(75, 100).percent, -25);
      expect(ReportInsightEngine.compare(125, 100).percent, 25);
      expect(ReportInsightEngine.compare(10, 0).percent, isNull);
    });

    test('revenue drop alert contains its supporting figures', () {
      final alerts = ReportInsightEngine.build(
        current: sample(revenue: 700),
        previous: sample(revenue: 1000),
        services: const [],
      );
      final alert = alerts.singleWhere((item) => item.id == 'revenue-drop');
      expect(alert.evidence, contains('700'));
      expect(alert.evidence, contains('1000'));
      expect(alert.level, ReportAlertLevel.warning);
    });

    test('does not infer a revenue drop from an insufficient baseline', () {
      final alerts = ReportInsightEngine.build(
        current: sample(revenue: 0, total: 2, completed: 0),
        previous: sample(revenue: 1000, total: 4),
        services: const [],
      );
      expect(alerts.where((item) => item.id == 'revenue-drop'), isEmpty);
    });

    test('generates a valid offline PDF document', () async {
      final bytes = await ReportExecutivePdfExport.buildBytes(
        analytics: sample(), comparison: sample(revenue: 800),
        title: 'گزارش مدیریتی', columns: const ['درآمد', 'هزینه', 'سود خالص'],
      );
      expect(bytes.take(4).toList(), [37, 80, 68, 70]);
      expect(bytes.length, greaterThan(500));
    });
  });

  group('Saved report persistence', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('stores filters, selected columns and history locally', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SavedReportStore();
      final now = DateTime(2026, 11, 19);
      final view = SavedReportView(
        id: 'view-1', name: 'گزارش ماهانه',
        start: now.toIso8601String(),
        endExclusive: now.add(const Duration(days: 30)).toIso8601String(),
        columns: const ['درآمد', 'سود خالص'],
        createdAt: now, serviceId: 'service-1', statusName: 'completed',
      );
      await store.saveView(view);
      final views = await store.loadViews();
      expect(views.single.name, 'گزارش ماهانه');
      expect(views.single.columns, ['درآمد', 'سود خالص']);
      expect(views.single.serviceId, 'service-1');

      await store.addHistory(ReportHistorySnapshot(
        id: 'history-1', title: 'نسخه اول', range: 'آبان',
        createdAt: now, revenue: 500, cost: 200, appointments: 7,
      ));
      expect((await store.loadHistory()).single.profit, 300);
      await store.deleteView('view-1');
      expect(await store.loadViews(), isEmpty);
    });
  });

  test('staff without income permission cannot retrieve management reports', () async {
    final db = AppDatabase();
    db.switchMockAccount('demo-staff');
    expect(db.canOpenRoute('/reports'), isFalse);
    final range = ReportDateRange.custom(
      JalaliDate.fromDateTime(DateTime(2000, 1, 1)),
      JalaliDate.fromDateTime(DateTime(2100, 1, 1)),
    );
    await expectLater(
      MockDashboardRepository(db).fetchReportAnalytics(range: range),
      throwsA(isA<AccessDeniedException>()),
    );
  });
}
