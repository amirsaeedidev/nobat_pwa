class EmployeePerformanceDay {
  const EmployeePerformanceDay({
    required this.date,
    this.appointments = 0,
    this.completed = 0,
    this.cancelled = 0,
    this.noShow = 0,
    this.uniqueCustomers = 0,
    this.grossRevenue = 0,
    this.netRevenue = 0,
    this.commission = 0,
    this.companyShare = 0,
    this.bookedMinutes = 0,
    this.attendanceAvailable = false,
    this.absentDays = 0,
    this.workedMinutes = 0,
    this.lateMinutes = 0,
    this.overtimeMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.leaveCount = 0,
    this.earned = 0,
    this.bonus = 0,
    this.deduction = 0,
    this.advance = 0,
    this.salaryPaid = 0,
    this.walletDelta = 0,
  });

  final DateTime date;
  final int appointments, completed, cancelled, noShow, uniqueCustomers;
  final int grossRevenue, netRevenue, commission, companyShare, bookedMinutes;
  final bool attendanceAvailable;
  final int absentDays, workedMinutes, lateMinutes, overtimeMinutes, earlyLeaveMinutes, leaveCount;
  final int earned, bonus, deduction, advance, salaryPaid, walletDelta;

  factory EmployeePerformanceDay.fromJson(Map<String, dynamic> row) {
    int number(String key) => (row[key] as num?)?.toInt() ?? 0;
    return EmployeePerformanceDay(
      date: DateTime.parse(row['work_date'].toString()),
      appointments: number('appointment_count'),
      completed: number('completed_count'),
      cancelled: number('cancelled_count'),
      noShow: number('no_show_count'),
      uniqueCustomers: number('unique_customers'),
      grossRevenue: number('gross_revenue_toman'),
      netRevenue: number('net_revenue_toman'),
      commission: number('commission_toman'),
      companyShare: number('company_share_toman'),
      bookedMinutes: number('booked_minutes'),
      attendanceAvailable: row['attendance_data_available'] == true,
      absentDays: number('absence_count'),
      workedMinutes: number('worked_minutes'),
      lateMinutes: number('late_minutes'),
      overtimeMinutes: number('overtime_minutes'),
      earlyLeaveMinutes: number('early_leave_minutes'),
      leaveCount: number('approved_leave_count'),
      earned: number('earned_toman'),
      bonus: number('bonus_toman'),
      deduction: number('deduction_toman'),
      advance: number('advance_toman'),
      salaryPaid: number('salary_paid_toman'),
      walletDelta: number('wallet_delta_toman'),
    );
  }
}

class EmployeePerformanceReport {
  const EmployeePerformanceReport({
    required this.days,
    required this.totalAppointments,
    required this.completed,
    required this.cancelled,
    required this.noShow,
    required this.uniqueCustomers,
    required this.grossRevenue,
    required this.netRevenue,
    required this.commission,
    required this.companyShare,
    required this.bookedMinutes,
    required this.scheduledMinutes,
    required this.attendanceAvailable,
    required this.presentDays,
    required this.absentDays,
    required this.workedMinutes,
    required this.lateMinutes,
    required this.overtimeMinutes,
    required this.earlyLeaveMinutes,
    required this.leaveCount,
    required this.earned,
    required this.bonus,
    required this.deduction,
    required this.advance,
    required this.salaryPaid,
    required this.walletBalanceDelta,
  });

  final List<EmployeePerformanceDay> days;
  final int totalAppointments, completed, cancelled, noShow, uniqueCustomers;
  final int grossRevenue, netRevenue, commission, companyShare;
  final int bookedMinutes, scheduledMinutes;
  final bool attendanceAvailable;
  final int presentDays, absentDays, workedMinutes, lateMinutes, overtimeMinutes, earlyLeaveMinutes, leaveCount;
  final int earned, bonus, deduction, advance, salaryPaid, walletBalanceDelta;

  double get completionRate => totalAppointments == 0 ? 0 : completed * 100 / totalAppointments;
  double get utilizationRate => scheduledMinutes == 0 ? 0 : (bookedMinutes * 100 / scheduledMinutes).clamp(0, 100).toDouble();
  int get averageTicket => completed == 0 ? 0 : netRevenue ~/ completed;
}
