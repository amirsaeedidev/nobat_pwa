import '../../../../core/providers/db_bound_provider.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/repositories/dashboard_repository.dart';

enum ReportServiceSort { revenue, bookings, profit }

class ReportsProvider extends DbBoundProvider {
  ReportsProvider(this._repository, AppDatabase db) : super(db) { load(); }

  final DashboardRepository _repository;
  ReportDateRange _range = ReportDateRange.preset(ReportPeriod.thisMonth);
  ReportAnalyticsFilter _filter = const ReportAnalyticsFilter();
  ReportDateRange? _customComparisonRange;
  ReportAnalytics? _analytics;
  ReportAnalytics? _comparisonAnalytics;
  ReportServiceSort _serviceSort = ReportServiceSort.revenue;
  bool _loading = true;
  String? _error;

  ReportDateRange get range => _range;
  ReportDateRange get comparisonRange => _customComparisonRange ?? _defaultComparisonRange();
  ReportPeriod get period => _range.period;
  ReportAnalyticsFilter get filter => _filter;
  ReportAnalytics? get comparisonAnalytics => _comparisonAnalytics;
  bool get hasCustomComparison => _customComparisonRange != null;
  ReportServiceSort get serviceSort => _serviceSort;
  List<ReportServiceMetric> get rankedServices {
    final items = [...analytics.services];
    items.sort((a, b) => switch (_serviceSort) {
      ReportServiceSort.revenue => b.revenue.compareTo(a.revenue),
      ReportServiceSort.bookings => b.count.compareTo(a.count),
      ReportServiceSort.profit => (b.profit ?? double.negativeInfinity).compareTo(a.profit ?? double.negativeInfinity),
    });
    return items;
  }
  ReportAnalytics get analytics => _analytics ?? ReportAnalytics.empty(_range);
  bool get loading => _loading;
  String? get error => _error;
  num get totalRevenue => analytics.revenue;
  num get totalCost => analytics.cost;
  num get netProfit => analytics.netProfit;
  int get totalAppointments => analytics.totalAppointments;
  int get completedAppointments => analytics.completedAppointments;
  int get cancelledAppointments => analytics.cancelledAppointments;
  int get totalCustomers => analytics.uniqueCustomers;

  List<RevenuePoint> get revenueSeries => [
    for (final item in analytics.trend)
      RevenuePoint(label: item.label, value: item.revenue, secondary: item.cost),
  ];
  List<RevenuePoint> get serviceRevenue => [
    for (final item in analytics.services)
      RevenuePoint(label: item.name, value: item.revenue, secondary: item.count),
  ];
  Map<String, num> get employeeRevenue => {
    for (final item in analytics.employees) item.name: item.revenue,
  };
  Map<String, int> get statusCounts => analytics.statusCounts;

  ReportDateRange _defaultComparisonRange() {
    switch (_range.period) {
      case ReportPeriod.today:
        return ReportDateRange.preset(ReportPeriod.yesterday);
      case ReportPeriod.thisWeek:
        return ReportDateRange.preset(ReportPeriod.lastWeek);
      case ReportPeriod.thisMonth:
        return ReportDateRange.preset(ReportPeriod.lastMonth);
      case ReportPeriod.thisYear:
        final year = _range.jalaliStart.year;
        return ReportDateRange.custom(JalaliDate(year - 1, 1, 1), JalaliDate(year - 1, 12, 29));
      case ReportPeriod.yesterday:
        return _shiftRange(const Duration(days: 1));
      case ReportPeriod.lastWeek:
        return _shiftRange(const Duration(days: 7));
      case ReportPeriod.lastMonth:
        final end = _range.jalaliStart;
        final previousStart = end.addMonths(-1);
        return ReportDateRange.custom(previousStart, end.addDays(-1));
      case ReportPeriod.custom:
        return _shiftRange(_range.endExclusive.difference(_range.start));
    }
  }

  ReportDateRange _shiftRange(Duration amount) {
    final from = JalaliDate.fromDateTime(_range.start.subtract(amount));
    final to = JalaliDate.fromDateTime(_range.endExclusive.subtract(amount).subtract(const Duration(microseconds: 1)));
    return ReportDateRange.custom(from, to);
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _analytics = await _repository.fetchReportAnalytics(range: _range, filter: _filter);
      try {
        _comparisonAnalytics = await _repository.fetchReportAnalytics(
          range: comparisonRange, filter: _filter,
        );
      } catch (_) {
        _comparisonAnalytics = null;
      }
    } catch (error) {
      _analytics = ReportAnalytics.empty(_range);
      _comparisonAnalytics = null;
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onDatabaseChanged() { _refresh(); }

  Future<void> _refresh() async => load();

  Future<void> setFilters({
    String? serviceId, String? employeeId, String? customerId,
    AppointmentStatus? status, bool clearService = false,
    bool clearEmployee = false, bool clearCustomer = false, bool clearStatus = false,
  }) async {
    _filter = _filter.copyWith(
      serviceId: serviceId, employeeId: employeeId, customerId: customerId,
      status: status, clearService: clearService, clearEmployee: clearEmployee,
      clearCustomer: clearCustomer, clearStatus: clearStatus,
    );
    await load();
  }

  Future<void> setServiceSort(ReportServiceSort sort) async {
    _serviceSort = sort;
    notifyListeners();
  }

  Future<void> clearFilters() async {
    _filter = const ReportAnalyticsFilter();
    await load();
  }

  Future<void> setPeriod(ReportPeriod period) async {
    _customComparisonRange = null;
    _range = ReportDateRange.preset(period);
    await load();
  }

  Future<void> setCustomRange(JalaliDate from, JalaliDate to) async {
    _customComparisonRange = null;
    _range = ReportDateRange.custom(from, to);
    await load();
  }

  Future<void> setComparisonRange(JalaliDate from, JalaliDate to) async {
    _customComparisonRange = ReportDateRange.custom(from, to);
    await load();
  }

  Future<void> clearComparisonRange() async {
    _customComparisonRange = null;
    await load();
  }
}
