import '../../../../core/providers/db_bound_provider.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/repositories/dashboard_repository.dart';
import '../../../../data/repositories/appointment_repository.dart';

/// وضعیت صفحه پیشخوان.
class DashboardProvider extends DbBoundProvider {
  DashboardProvider(this._repository, AppDatabase db, {AppointmentRepository? appointmentRepository, this.isAdminView = true}) : _appointmentRepository = appointmentRepository, super(db) {
    load();
  }

  final DashboardRepository _repository;
  final AppointmentRepository? _appointmentRepository;
  DateTime _selectedDay = DateTime.now();
  List<Appointment> _dayAppointments = const [];
  final bool isAdminView;

  DashboardStats? _stats;
  List<Appointment> _upcoming = const [];
  List<RevenuePoint> _revenueSeries = const [];
  bool _loading = true;
  bool _error = false;
  StatsPeriod _period = StatsPeriod.weekly;
  ReportAnalytics? _analytics;
  ReportAnalyticsFilter _analyticsFilter = const ReportAnalyticsFilter();
  bool _analyticsError = false;

  DashboardStats? get stats => _stats;
  List<Appointment> get upcoming => _upcoming;
  List<RevenuePoint> get revenueSeries => _revenueSeries;
  bool get loading => _loading;
  bool get error => _error;
  StatsPeriod get period => _period;
  ReportAnalytics? get analytics => _analytics;
  ReportAnalyticsFilter get analyticsFilter => _analyticsFilter;
  bool get analyticsError => _analyticsError;
  DateTime get selectedDay => _selectedDay;
  List<Appointment> get dayAppointments => _dayAppointments;

  Future<void> load() async {
    _loading = true;
    _error = false;
    notifyListeners();
    try {
      _stats = await _repository.fetchStats(period: _period);
      _upcoming = await _repository.fetchUpcoming(limit: 4);
      _dayAppointments = await _appointmentRepository?.fetchForDay(_selectedDay) ?? _upcoming.where((item) => _sameDay(item.startAt, _selectedDay)).toList();
      _revenueSeries = await _repository.fetchRevenueSeries(months: 6);
      await _loadAnalytics();
    } catch (_) {
      _error = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadAnalytics() async {
    _analyticsError = false;
    try {
      final reportPeriod = switch (_period) {
        StatsPeriod.daily => ReportPeriod.today,
        StatsPeriod.weekly => ReportPeriod.thisWeek,
        StatsPeriod.monthly => ReportPeriod.thisMonth,
      };
      _analytics = await _repository.fetchReportAnalytics(
        range: ReportDateRange.preset(reportPeriod), filter: _analyticsFilter);
    } catch (_) {
      _analyticsError = true;
      _analytics = null;
    }
  }

  Future<void> setAnalyticsFilter(ReportAnalyticsFilter filter) async {
    _analyticsFilter = filter;
    notifyListeners();
    await _loadAnalytics();
    notifyListeners();
  }

  Future<void> selectDay(DateTime day) async {
    _selectedDay = DateTime(day.year, day.month, day.day);
    try {
      _dayAppointments = await _appointmentRepository?.fetchForDay(_selectedDay) ?? _upcoming.where((item) => _sameDay(item.startAt, _selectedDay)).toList();
      _error = false;
    } catch (_) {
      _error = true;
      _dayAppointments = const [];
    }
    notifyListeners();
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> setPeriod(StatsPeriod period) async {
    if (_period == period) return;
    _period = period;
    _stats = await _repository.fetchStats(period: period);
    await _loadAnalytics();
    notifyListeners();
  }

  @override
  void onDatabaseChanged() {
    _refresh();
  }

  Future<void> _refresh() async {
    _stats = await _repository.fetchStats(period: _period);
    _upcoming = await _repository.fetchUpcoming(limit: 4);
    _revenueSeries = await _repository.fetchRevenueSeries(months: 6);
    await _loadAnalytics();
    _dayAppointments = await _appointmentRepository?.fetchForDay(_selectedDay) ?? _upcoming.where((item) => _sameDay(item.startAt, _selectedDay)).toList();
    notifyListeners();
  }
}
