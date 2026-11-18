import '../models/employee.dart';
import '../models/employee_finance.dart';
import '../models/employee_schedule.dart';
import '../models/employee_hr.dart';
import '../models/employee_wallet.dart';
import '../models/enums.dart';
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
  const ServiceAnalytics({required this.serviceId, required this.name, required this.bookings, required this.revenue, this.commission = 0});
  final String serviceId;
  final String name;
  final int bookings;
  final int revenue;
  final int commission;
}

class EmployeeAnalytics {
  const EmployeeAnalytics({required this.totalAppointments, required this.completed, required this.cancelled, required this.noShow, required this.grossRevenue, required this.netRevenue, required this.commission, required this.companyShare, required this.averageTicket, required this.uniqueCustomers, required this.workingMinutes, required this.bookedMinutes, required this.dailyRevenue, required this.monthlyRevenue, required this.dailyAppointments, required this.dailyCommission, required this.services, required this.previousRevenue, required this.previousCompleted,
    this.actualWorkedMinutes = 0, this.attendanceDays = 0, this.absentDays = 0,
    this.lateMinutes = 0, this.overtimeMinutes = 0, this.leaveCount = 0,
    this.fixedSalary = 0, this.bonusAmount = 0, this.deductionAmount = 0,
    this.advanceAmount = 0, this.salaryPaid = 0, this.salaryBalance = 0,
    this.attendanceDataAvailable = false, this.salaryDataAvailable = false,
    this.attendanceRecords = const [], this.leaves = const [], this.busyHours = const [],
    this.customerSatisfactionScore,
  });
  final int totalAppointments, completed, cancelled, noShow;
  final int grossRevenue, netRevenue, commission, companyShare, averageTicket, uniqueCustomers;
  final int workingMinutes, bookedMinutes;
  final List<AnalyticsPoint> dailyRevenue, monthlyRevenue, dailyAppointments, dailyCommission;
  final List<ServiceAnalytics> services;
  final int previousRevenue, previousCompleted;
  final int actualWorkedMinutes, attendanceDays, absentDays, lateMinutes, overtimeMinutes, leaveCount;
  final int fixedSalary, bonusAmount, deductionAmount, advanceAmount, salaryPaid, salaryBalance;
  final bool attendanceDataAvailable, salaryDataAvailable;
  final List<AttendanceRecord> attendanceRecords;
  final List<EmployeeLeave> leaves;
  final List<AnalyticsPoint> busyHours;
  /// null یعنی هنوز امتیاز رضایت مشتری در داده‌ها ثبت نشده است.
  final double? customerSatisfactionScore;
  double get completionRate => totalAppointments == 0 ? 0 : completed * 100 / totalAppointments;
  double get cancellationRate => totalAppointments == 0 ? 0 : cancelled * 100 / totalAppointments;
  double get utilizationRate => workingMinutes == 0 ? 0 : (bookedMinutes * 100 / workingMinutes).clamp(0, 100).toDouble();
  double get revenuePerCustomer => uniqueCustomers == 0 ? 0 : netRevenue / uniqueCustomers;
  double get revenueChange => previousRevenue == 0 ? (netRevenue == 0 ? 0 : 100) : (netRevenue - previousRevenue) * 100 / previousRevenue;
}

T? _firstOrNull<T>(Iterable<T> items) {
  final iterator = items.iterator;
  return iterator.moveNext() ? iterator.current : null;
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
    final ledger = db.employeeFinanceEntries.where((e) => e.employeeId == employee.id && completedIds.contains(e.appointmentId) && e.type != FinanceEntryType.salary && (filter.serviceId == null || e.serviceId == filter.serviceId)).toList();
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
          final service = _firstOrNull(db.services.where((s) => s.id == e.serviceId));
          final key = e.serviceId.isEmpty ? a.serviceName : e.serviceId;
          final old = serviceMap[key];
          serviceMap[key] = ServiceAnalytics(serviceId: key, name: service?.title ?? a.serviceName, bookings: (old?.bookings ?? 0) + 1, revenue: (old?.revenue ?? 0) + e.receivedAmount, commission: (old?.commission ?? 0) + e.commissionAmount);
        }
      } else {
        final ids = a.serviceIds.isEmpty ? <String>[''] : a.serviceIds;
        final part = a.price.round() ~/ ids.length;
        for (final id in ids) {
          final service = _firstOrNull(db.services.where((s) => s.id == id));
          final key = id.isEmpty ? a.serviceName : id;
          final old = serviceMap[key];
          serviceMap[key] = ServiceAnalytics(serviceId: key, name: service?.title ?? a.serviceName, bookings: (old?.bookings ?? 0) + 1, revenue: (old?.revenue ?? 0) + part, commission: old?.commission ?? 0);
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
        final a = _firstOrNull(completed.where((item) => item.id == e.appointmentId));
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

    // حضور واقعی از رویدادهای ورود/خروج؛ نبود رکورد به معنی صفر ساعت حضور نیست.
    final inclusiveEnd = filter.to.subtract(const Duration(microseconds: 1));
    final attendanceRecords = db.attendanceFor(employee.id, from: filter.from, to: inclusiveEnd);
    final attendance = db.attendanceSummary(employee.id, from: filter.from, to: inclusiveEnd);
    final attendanceAvailable = attendanceRecords.isNotEmpty;
    final leaves = db.leavesForEmployee(employee.id).where((leave) =>
      leave.startAt.isBefore(filter.to) && leave.endAt.isAfter(filter.from)).toList();
    final leaveCount = leaves.where((leave) => leave.status == EmployeeLeaveStatus.approved).length;

    // اطلاعات مالی فقط در صورت مجوز؛ منبع واحد همان دفتر کیف پول پرسنل است.
    final canViewSalary = db.hasPermission('finance.salary.view', employeeId: employee.id);
    final wallet = canViewSalary
      ? db.walletTransactionsFor(employee.id, from: filter.from, to: inclusiveEnd)
          .where((entry) => entry.status == EmployeeWalletTransactionStatus.posted).toList()
      : <EmployeeWalletTransaction>[];
    var fixedSalary = 0, bonusAmount = 0, deductionAmount = 0;
    var advanceAmount = 0, salaryPaid = 0, salaryBalance = 0;
    for (final entry in wallet) {
      salaryBalance += entry.amount;
      switch (entry.type) {
        case EmployeeWalletTransactionType.fixedSalary:
          fixedSalary += entry.amount;
          break;
        case EmployeeWalletTransactionType.bonus:
          bonusAmount += entry.amount;
          break;
        case EmployeeWalletTransactionType.penalty:
        case EmployeeWalletTransactionType.deduction:
          deductionAmount += entry.amount.abs();
          break;
        case EmployeeWalletTransactionType.advance:
          advanceAmount += entry.amount.abs();
          break;
        case EmployeeWalletTransactionType.salaryPayment:
          salaryPaid += entry.amount.abs();
          break;
        case EmployeeWalletTransactionType.commission:
        case EmployeeWalletTransactionType.refund:
          break;
      }
    }

    // توزیع تعداد نوبت‌ها بر ساعت شروع؛ فقط ساعت‌هایی که داده دارند نمایش داده می‌شوند.
    final hourlyBookings = <int, int>{};
    for (final appointment in appointments.where((item) =>
      item.status != AppointmentStatus.cancelled && item.status != AppointmentStatus.noShow)) {
      hourlyBookings[appointment.startAt.hour] = (hourlyBookings[appointment.startAt.hour] ?? 0) + 1;
    }
    final busyHours = hourlyBookings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final duration = filter.to.difference(filter.from);
    final previousFrom = filter.from.subtract(duration);
    final previous = db.appointments.where((a) => a.employeeId == employee.id && !a.startAt.isBefore(previousFrom) && a.startAt.isBefore(filter.from) && a.status == AppointmentStatus.completed && (filter.serviceId == null || a.serviceIds.contains(filter.serviceId))).toList();
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
      actualWorkedMinutes: attendance.workedMinutes,
      attendanceDays: attendance.presentDays, absentDays: attendance.absentDays,
      lateMinutes: attendance.lateMinutes, overtimeMinutes: attendance.overtimeMinutes,
      leaveCount: leaveCount, fixedSalary: fixedSalary, bonusAmount: bonusAmount,
      deductionAmount: deductionAmount, advanceAmount: advanceAmount, salaryPaid: salaryPaid,
      salaryBalance: salaryBalance, attendanceDataAvailable: attendanceAvailable,
      salaryDataAvailable: canViewSalary, attendanceRecords: attendanceRecords,
      leaves: leaves, busyHours: [for (final item in busyHours)
        AnalyticsPoint('${item.key.toString().padLeft(2, '0')}:00', item.value)],
    );
  }
}
