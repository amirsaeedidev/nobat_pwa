import 'dart:async';
import '../../../../core/providers/db_bound_provider.dart';
import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../core/utils/jalali.dart';
import '../../../../core/models/app_failure.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/dashboard_stats.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/repositories/dashboard_repository.dart';
import '../../../../data/repositories/appointment_repository.dart';

/// وضعیت صفحه پیشخوان.
class DashboardProvider extends DbBoundProvider {
  DashboardProvider(this._repository, AppDatabase db, {AppointmentRepository? appointmentRepository, this.isAdminView = true, SupabaseAuthStateNotifier? authStateNotifier}) : _appointmentRepository = appointmentRepository, super(db, authStateNotifier: authStateNotifier) {
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
  AppFailure? _failure;
  StatsPeriod _period = StatsPeriod.weekly;
  ReportAnalytics? _analytics;
  ReportAnalyticsFilter _analyticsFilter = const ReportAnalyticsFilter();
  bool _analyticsError = false;
  int _loadGeneration = 0;

  DashboardStats? get stats => _stats;
  List<Appointment> get upcoming => _upcoming;
  List<RevenuePoint> get revenueSeries => _revenueSeries;
  bool get loading => _loading;
  bool get error => _error;
  AppFailure? get failure => _failure;
  StatsPeriod get period => _period;
  ReportAnalytics? get analytics => _analytics;
  ReportAnalyticsFilter get analyticsFilter => _analyticsFilter;
  bool get analyticsError => _analyticsError;
  DateTime get selectedDay => _selectedDay;
  List<Appointment> get dayAppointments => _dayAppointments;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    _error = false;
    _failure = null;
    notifyListeners();
    try {
      final stats = await _repository.fetchStats(period: _period);
      final upcoming = await _repository.fetchUpcoming(limit: 4);
      final dayAppointments = await _appointmentRepository?.fetchForDay(_selectedDay) ?? upcoming.where((item) => _sameDay(item.startAt, _selectedDay)).toList();
      final revenueSeries = await _repository.fetchRevenueSeries(months: 6);
      if (generation != _loadGeneration) return;
      _stats = stats;
      _upcoming = upcoming;
      _dayAppointments = dayAppointments;
      _revenueSeries = revenueSeries;
      await _loadAnalytics(generation: generation);
    } catch (error) {
      if (generation != _loadGeneration) return;
      _error = true;
      _failure = AppFailure.from(error, fallback: AppErrorKind.fetch);
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadAnalytics({int? generation}) async {
    _analyticsError = false;
    try {
      final today = JalaliDate.today();
      final analytics = await _repository.fetchReportAnalytics(
        range: ReportDateRange.custom(today.addDays(-29), today),
        filter: _analyticsFilter);
      if (generation != null && generation != _loadGeneration) return;
      _analytics = analytics;
    } catch (_) {
      if (generation != null && generation != _loadGeneration) return;
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
  void onAuthenticatedTenantChanged() => unawaited(load());

  @override
  void onTenantContextCleared() {
    _loadGeneration++;
    _stats = null;
    _upcoming = const [];
    _dayAppointments = const [];
    _revenueSeries = const [];
    _analytics = null;
    _comparisonAnalytics = null;
    _error = false;
    _failure = null;
    _loading = false;
  }

  @override
  void onDatabaseChanged() {
    _refresh();
  }

  Future<void> _refresh() async => load();
}
