import '../../../../core/providers/db_bound_provider.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/repositories/dashboard_repository.dart';

class ReportsProvider extends DbBoundProvider {
  ReportsProvider(this._repository, AppDatabase db) : super(db) { load(); }

  final DashboardRepository _repository;
  ReportDateRange _range = ReportDateRange.preset(ReportPeriod.thisMonth);
  ReportAnalytics? _analytics;
  bool _loading = true;
  String? _error;

  ReportDateRange get range => _range;
  ReportPeriod get period => _range.period;
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

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _analytics = await _repository.fetchReportAnalytics(range: _range);
    } catch (error) {
      _analytics = ReportAnalytics.empty(_range);
      _error = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void onDatabaseChanged() { _refresh(); }

  Future<void> _refresh() async {
    try {
      _analytics = await _repository.fetchReportAnalytics(range: _range);
      _error = null;
    } catch (error) {
      _analytics = ReportAnalytics.empty(_range);
      _error = error.toString();
    }
    notifyListeners();
  }

  Future<void> setPeriod(ReportPeriod period) async {
    _range = ReportDateRange.preset(period);
    await load();
  }

  Future<void> setCustomRange(JalaliDate from, JalaliDate to) async {
    _range = ReportDateRange.custom(from, to);
    await load();
  }
}
