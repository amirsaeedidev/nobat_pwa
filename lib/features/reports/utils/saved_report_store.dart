import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedReportView {
  const SavedReportView({
    required this.id, required this.name, required this.start,
    required this.endExclusive, required this.columns, required this.createdAt,
    this.serviceId, this.employeeId, this.customerId, this.statusName,
  });

  final String id, name, start, endExclusive;
  final List<String> columns;
  final DateTime createdAt;
  final String? serviceId, employeeId, customerId, statusName;

  Map<String, Object?> toJson() => {
    'id': id, 'name': name, 'start': start, 'endExclusive': endExclusive,
    'columns': columns, 'createdAt': createdAt.toIso8601String(),
    'serviceId': serviceId, 'employeeId': employeeId,
    'customerId': customerId, 'statusName': statusName,
  };

  factory SavedReportView.fromJson(Map<String, dynamic> json) => SavedReportView(
    id: json['id'] as String, name: json['name'] as String,
    start: json['start'] as String, endExclusive: json['endExclusive'] as String,
    columns: (json['columns'] as List? ?? const []).cast<String>(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    serviceId: json['serviceId'] as String?, employeeId: json['employeeId'] as String?,
    customerId: json['customerId'] as String?, statusName: json['statusName'] as String?,
  );
}

class ReportHistorySnapshot {
  const ReportHistorySnapshot({
    required this.id, required this.title, required this.range,
    required this.createdAt, required this.revenue, required this.cost,
    required this.appointments,
    required this.accountId,
    this.includesSalary = false,
    this.includesCommission = false,
  });

  final String id, title, range;
  final DateTime createdAt;
  final num revenue, cost;
  final int appointments;
  final String accountId;
  final bool includesSalary, includesCommission;
  num get profit => revenue - cost;

  Map<String, Object?> toJson() => {
    'id': id, 'title': title, 'range': range,
    'createdAt': createdAt.toIso8601String(),
    'revenue': revenue, 'cost': cost, 'appointments': appointments,
    'accountId': accountId, 'includesSalary': includesSalary,
    'includesCommission': includesCommission,
  };

  factory ReportHistorySnapshot.fromJson(Map<String, dynamic> json) => ReportHistorySnapshot(
    id: json['id'] as String, title: json['title'] as String,
    range: json['range'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    revenue: json['revenue'] as num, cost: json['cost'] as num,
    appointments: json['appointments'] as int,
    accountId: json['accountId'] as String? ?? '',
    includesSalary: json['includesSalary'] as bool? ?? false,
    includesCommission: json['includesCommission'] as bool? ?? false,
  );
}

/// ذخیره محلی تنظیمات و نسخه‌های گزارش؛ بدون حساب کاربری یا API.
class SavedReportStore {
  static const _viewsKey = 'datetime.saved_report_views.v1';
  static const _historyKey = 'datetime.report_history.v1';

  Future<List<SavedReportView>> loadViews() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_viewsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => SavedReportView.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveView(SavedReportView view) async {
    final items = await loadViews();
    items.removeWhere((item) => item.id == view.id);
    items.insert(0, view);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewsKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<void> deleteView(String id) async {
    final items = await loadViews();
    items.removeWhere((item) => item.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_viewsKey, jsonEncode(items.map((item) => item.toJson()).toList()));
  }

  Future<List<ReportHistorySnapshot>> loadHistory({
    String accountId = '',
    bool canViewSalary = true,
    bool canViewCommission = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => ReportHistorySnapshot.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((item) =>
            (item.accountId == accountId || (canViewSalary && canViewCommission)) &&
            (!item.includesSalary || canViewSalary) &&
            (!item.includesCommission || canViewCommission))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addHistory(ReportHistorySnapshot snapshot) async {
    final items = await loadHistory();
    items.insert(0, snapshot);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey, jsonEncode(items.take(20).map((item) => item.toJson()).toList()));
  }
}
