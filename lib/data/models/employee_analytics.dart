import '../models/appointment.dart';
import '../models/employee.dart';
import '../models/employee_finance.dart';
import '../models/employee_schedule.dart';
import '../models/enums.dart';
import '../models/service.dart';
import '../mock/app_database.dart';

class EmployeeAnalyticsFilter {
  const EmployeeAnalyticsFilter({required this.from, required this.to, this.employeeId, this.serviceId, this.status});
  final DateTime from;
  final DateTime to;
  final String? employeeId;
  final String? serviceId;
  final AppointmentStatus? status;
  EmployeeAnalyticsFilter copyWith({DateTime? from, DateTime? to, String? employeeId, String? serviceId, AppointmentStatus? status, bool clearEmployee = false, bool clearService = false, bool clearStatus = false}) => EmployeeAnalyticsFilter(
    from: from ?? this.from, to: to ?? this.to,
    employeeId: clearEmployee ? null : employeeId ?? this.employeeId,
    serviceId: clearService ? null : serviceId ?? this.serviceId,
    status: clearStatus ? null : status ?? this.status,
  );
}

class AnalyticsPoint {
  const AnalyticsPoint(this.label, this.value);
  final String label;
  final num value;
}

class ServiceAnalytics {
  const ServiceAnalytics({required this.serviceId, required this.name, required this.bookings, required this.revenue});
  final String serviceId;
  final String name;
  final int bookings;
  final int revenue;
}

class EmployeeAnalytics {
  const EmployeeAnalytics({required this.totalAppointments, required this.completed, required this.cancelled, required this.noShow, required this.grossRevenue, required this.netRevenue, required this.commission, required this.companyShare, required this.averageTicket, required this.uniqueCustomers, required this.workingMinutes, required this.bookedMinutes, required this.dailyRevenue, required this.monthlyRevenue, required this.dailyAppointments, required this.dailyCommission, required this.services, required this.previousRevenue, required this.previousCompleted});
  final int totalAppointments, completed, cancelled, noShow;
  final int grossRevenue, netRevenue, commission, companyShare, averageTicket, uniqueCustomers;
  final int workingMinutes, bookedMinutes;
  final List<AnalyticsPoint> dailyRevenue, monthlyRevenue, dailyAppointments, dailyCommission;
  final List<ServiceAnalytics> services;
  final int previousRevenue, previousCompleted;
  double get completionRate => totalAppointments == 0 ? 0 : completed * 100 / totalAppointments;
  double get cancellationRate => totalAppointments == 0 ? 0 : cancelled * 100 / totalAppointments;
  double get utilizationRate => workingMinutes == 0 ? 0 : (bookedMinutes * 100 / workingMinutes).clamp(0, 100).toDouble();
  double get revenuePerCustomer => uniqueCustomers == 0 ? 0 : netRevenue / uniqueCustomers;
  double get revenueChange => previousRevenue == 0 ? (netRevenue == 0 ? 0 : 100) : (netRevenue - previousRevenue) * 100 / previousRevenue;
}

class EmployeeAnalyticsCalculator {
  const EmployeeAnalyticsCalculator._();

  static EmployeeAnalytics calculate({required AppDatabase db, required Employee employee, required EmployeeAnalyticsFilter filter}) {
    final appointments = db.appointments.where((a) {
      if (a.employeeId != employee.id || a.startAt.isBefore(filter.from) || !a.startAt.isBefore(filter.to)) return false;
      if (filter.serviceId != null && !a.serviceIds.contains(filter.serviceId)) return false;
      if (filter.status != null && a.status != filter.status) return false;
      return true;
    }).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
    final completed = appointments.where((a) => a.status == AppointmentStatus.completed).toList();
    final cancelled = appointments.where((a) => a.status == AppointmentStatus.cancelled).length;
    final noShow = appointments.where((a) => a.status == AppointmentStatus.noShow).length;
    final completedIds = completed.map((a) => a.id).toSet();
    final ledger = db.employeeFinanceEntries.where((e) => e.employeeId == employee.id && completedIds.contains(e.appointmentId) && e.type != FinanceEntryType.salary).toList();
    final byAppointment = <String, List<EmployeeFinanceEntry>>{};
    for (final entry in ledger) { byAppointment.putIfAbsent(entry.appointmentId, () => []).add(entry); }

    var gross = 0, net = 0, commission = 0, company = 0;
    for (final a in completed) {
      final entries = byAppointment[a.id] ?? const <EmployeeFinanceEntry>[];
      if (entries.isEmpty) { gross += a.price.round(); net += a.price.round(); company += a.price.round(); }
      else {
        gross += entries.fold<int>(0, (s, e) => s + e.grossAmount);
        net += entries.fold<int>(0, (s, e) => s + e.receivedAmount);
        commission += entries.fold<int>(0, (s, e) => s + e.commissionAmount);
        company += entries.fold<int>(0, (s, e) => s + e.companyShare);
      }
    }

    final serviceMap = <String, ServiceAnalytics>{};
    for (final a in completed) {
      final entries = byAppointment[a.id] ?? const <EmployeeFinanceEntry>[];
      if (entries.isNotEmpty) {
        for (final e in entries) {
          final service = db.services.where((s) => s.id == e.serviceId).firstOrNull;
          final key = e.serviceId.isEmpty ? a.serviceName : e.serviceId;
          final old = serviceMap[key];
          serviceMap[key] = ServiceAnalytics(serviceId: key, name: service?.title ?? a.serviceName, bookings: (old?.bookings ?? 0) + 1, revenue: (old?.revenue ?? 0) + e.receivedAmount);
        }
      } else {
        final ids = a.serviceIds.isEmpty ? <String>[''] : a.serviceIds;
        final part = a.price.round() ~/ ids.length;
        for (final id in ids) {
          final service = db.services.where((s) => s.id == id).firstOrNull;
          final key = id.isEmpty ? a.serviceName : id;
          final old = serviceMap[key];
          serviceMap[key] = ServiceAnalytics(serviceId: key, name: service?.title ?? a.serviceName, bookings: (old?.bookings ?? 0) + 1, revenue: (old?.revenue ?? 0) + part);
        }
      }
    }

    final days = filter.to.difference(filter.from).inDays.clamp(1, 366);
    final dailyRevenue = <AnalyticsPoint>[], dailyAppointments = <AnalyticsPoint>[], dailyCommission = <AnalyticsPoint>[];
    for (var i = 0; i < days; i++) {
      final day = DateTime(filter.from.year, filter.from.month, filter.from.day + i);
      final next = day.add(const Duration(days: 1));
      final dayCompleted = completed.where((a) => !a.startAt.isBefore(day) && a.startAt.isBefore(next)).toList();
      final amount = dayCompleted.fold<int>(0, (s, a) {
        final entries = byAppointment[a.id] ?? const <EmployeeFinanceEntry>[];
        return s + (entries.isEmpty ? a.price.round() : entries.fold<int>(0, (v, e) => v + e.receivedAmount));
      });
      final dayCommission = ledger.where((e) {
        final a = completed.where((item) => item.id == e.appointmentId).firstOrNull;
        return a != null && !a.startAt.isBefore(day) && a.startAt.isBefore(next);
      }).fold<int>(0, (s, e) => s + e.commissionAmount);
      final label = '${day.month}/${day.day}';
      dailyRevenue.add(AnalyticsPoint(label, amount));
      dailyAppointments.add(AnalyticsPoint(label, appointments.where((a) => !a.startAt.isBefore(day) && a.startAt.isBefore(next)).length));
      dailyCommission.add(AnalyticsPoint(label, dayCommission));
    }

    final monthlyRevenue = <AnalyticsPoint>[];
    var cursor = DateTime(filter.from.year, filter.from.month);
    while (cursor.isBefore(filter.to) && monthlyRevenue.length < 24) {
      final next = DateTime(cursor.year, cursor.month + 1);
      final amount = completed.where((a) => !a.startAt.isBefore(cursor) && a.startAt.isBefore(next)).fold<int>(0, (s, a) {
        final entries = byAppointment[a.id] ?? const <EmployeeFinanceEntry>[];
        return s + (entries.isEmpty ? a.price.round() : entries.fold<int>(0, (v, e) => v + e.receivedAmount));
      });
      monthlyRevenue.add(AnalyticsPoint('${cursor.month}/${cursor.year % 100}', amount));
      cursor = next;
    }

    var workingMinutes = 0, bookedMinutes = 0;
    final leaves = db.leavesForEmployee(employee.id).where((l) => l.status == EmployeeLeaveStatus.approved).toList();
    for (var i = 0; i < days; i++) {
      final day = DateTime(filter.from.year, filter.from.month, filter.from.day + i);
      var available = db.employeeShiftsForDate(employee.id, day).fold<int>(0, (s, shift) => s + shift.endMinutes - shift.startMinutes);
      final dayEnd = day.add(const Duration(days: 1));
      for (final leave in leaves) {
        if (leave.startAt.isBefore(dayEnd) && leave.endAt.isAfter(day)) {
          final start = leave.startAt.isAfter(day) ? leave.startAt : day;
          final end = leave.endAt.isBefore(dayEnd) ? leave.endAt : dayEnd;
          available -= end.difference(start).inMinutes;
        }
      }
      workingMinutes += available.clamp(0, 1440).toInt();
      for (final a in appointments.where((a) => a.status != AppointmentStatus.cancelled && a.startAt.isBefore(dayEnd) && a.endAt.isAfter(day))) {
        bookedMinutes += a.endAt.difference(a.startAt).inMinutes;
      }
    }
    bookedMinutes = bookedMinutes.clamp(0, workingMinutes).toInt();

    final duration = filter.to.difference(filter.from);
    final previousFrom = filter.from.subtract(duration);
    final previous = db.appointments.where((a) => a.employeeId == employee.id && !a.startAt.isBefore(previousFrom) && a.startAt.isBefore(filter.from) && a.status == AppointmentStatus.completed && (filter.serviceId == null || a.serviceIds.contains(filter.serviceId))).toList();
    final previousIds = previous.map((a) => a.id).toSet();
    final previousRevenue = previous.fold<int>(0, (s, a) {
      final entries = db.employeeFinanceEntries.where((e) => e.employeeId == employee.id && e.appointmentId == a.id && e.type != FinanceEntryType.salary).toList();
      return s + (entries.isEmpty ? a.price.round() : entries.fold<int>(0, (v, e) => v + e.receivedAmount));
    });

    return EmployeeAnalytics(
      totalAppointments: appointments.length, completed: completed.length, cancelled: cancelled, noShow: noShow,
      grossRevenue: gross, netRevenue: net, commission: commission, companyShare: company,
      averageTicket: completed.isEmpty ? 0 : net ~/ completed.length,
      uniqueCustomers: completed.map((a) => a.customerId).where((id) => id.isNotEmpty).toSet().length,
      workingMinutes: workingMinutes, bookedMinutes: bookedMinutes,
      dailyRevenue: dailyRevenue, monthlyRevenue: monthlyRevenue, dailyAppointments: dailyAppointments,
      dailyCommission: dailyCommission, services: serviceMap.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue)),
      previousRevenue: previousRevenue, previousCompleted: previous.length,
    );
  }
}
