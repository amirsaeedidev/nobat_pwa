import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';

void main() {
  group('Dashboard performance periods', () {
    late MockDashboardRepository repository;

    setUp(() {
      repository = MockDashboardRepository(AppDatabase());
    });

    test('daily period returns 24 hourly buckets', () async {
      final stats = await repository.fetchStats(period: StatsPeriod.daily);

      expect(stats.weekdayPerformance, hasLength(24));
      expect(stats.weekdayPerformance.first.label, '00:00');
      expect(stats.weekdayPerformance.last.label, '23:00');
      expect(stats.weekdayPerformance.every((point) => point.dateIso != null), isTrue);
    });

    test('weekly period returns Saturday through Friday', () async {
      final stats = await repository.fetchStats(period: StatsPeriod.weekly);

      expect(stats.weekdayPerformance, hasLength(7));
      expect(stats.weekdayPerformance.first.label, 'شنبه');
      expect(stats.weekdayPerformance.last.label, 'جمعه');
    });

    test('monthly period returns all twelve Persian months', () async {
      final stats = await repository.fetchStats(period: StatsPeriod.monthly);

      expect(stats.weekdayPerformance, hasLength(12));
      expect(stats.weekdayPerformance.first.label, 'فروردین');
      expect(stats.weekdayPerformance.last.label, 'اسفند');
    });
  });
}
