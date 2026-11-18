/// مدل‌های تکمیلی حقوق و عملکرد پرسنل؛ تمام مبالغ به تومان صحیح هستند.
enum SalaryPeriod { monthly, weekly, daily }
enum PayrollRecordStatus { pending, approved, rejected, paid }
enum PayrollBonusType { performance, sales, occasion, manager, manual }
enum PayrollDeductionType { absence, lateness, shortHours, agreed, correction }
enum AdvanceStatus { requested, approved, paid, deducted, rejected }
enum PerformanceTargetType { monthlyRevenue, appointmentCount, serviceSales, newCustomers }
class SalaryContract {
  const SalaryContract({required this.id, required this.employeeId, required this.monthlyBase, required this.effectiveFrom, this.effectiveTo, this.period = SalaryPeriod.monthly, this.active = true, this.createdAt});
  final String id, employeeId; final int monthlyBase; final DateTime effectiveFrom; final DateTime? effectiveTo; final SalaryPeriod period; final bool active; final DateTime? createdAt;
  bool appliesAt(DateTime date) => active && !date.isBefore(effectiveFrom) && (effectiveTo == null || !date.isAfter(effectiveTo!));
}
class PayrollAdjustment {
  const PayrollAdjustment({required this.id, required this.employeeId, required this.amount, required this.date, required this.description, required this.createdBy, required this.status, this.bonusType, this.deductionType, this.relatedAdvanceId, this.sourceWalletTransactionId});
  final String id, employeeId, description, createdBy; final int amount; final DateTime date; final PayrollRecordStatus status; final PayrollBonusType? bonusType; final PayrollDeductionType? deductionType; final String? relatedAdvanceId;
  bool get isBonus => bonusType != null;
}
class PayrollAdvance {
  const PayrollAdvance({required this.id, required this.employeeId, required this.amount, required this.requestedAt, required this.description, required this.status, this.paidAt, this.deductedAmount = 0, this.sourceWalletTransactionId});
  final String id, employeeId, description; final int amount, deductedAmount; final DateTime requestedAt; final DateTime? paidAt; final AdvanceStatus status; final String? sourceWalletTransactionId;
  int get outstanding => (amount - deductedAmount).clamp(0, amount);
}
class EmployeePerformanceTarget {
  const EmployeePerformanceTarget({required this.id, required this.employeeId, required this.type, required this.targetValue, required this.periodStart, required this.periodEnd, this.serviceId});
  final String id, employeeId; final String? serviceId; final PerformanceTargetType type; final int targetValue; final DateTime periodStart, periodEnd;
  double progress(int actual) => targetValue <= 0 ? 0 : (actual / targetValue).clamp(0, 1).toDouble();
}
class PayrollCalculation {
  const PayrollCalculation({
    required this.baseSalary,
    required this.approvedCommission,
    required this.approvedBonuses,
    required this.deductions,
    required this.advanceDeducted,
    required this.previousPayments,
    this.commissionRefunds = 0,
    this.attendanceAdjustment = 0,
  });
  final int baseSalary, approvedCommission, approvedBonuses, deductions, advanceDeducted, previousPayments;
  /// برگشت پورسانت، به‌عنوان کسری مستقل از پورسانت مثبت ثبت می‌شود.
  final int commissionRefunds;
  /// خروجی قانون حضور و غیاب؛ مثبت = پرداخت اضافه‌کاری، منفی = کسورات.
  final int attendanceAdjustment;
  int get gross => baseSalary + approvedCommission + approvedBonuses;
  int get totalDeductions => deductions + advanceDeducted + previousPayments + commissionRefunds;
  int get payable => gross - totalDeductions + attendanceAdjustment;
  int get debt => payable < 0 ? -payable : 0;
  int get remainingPayable => payable > 0 ? payable : 0;
}
class EmployeePayrollCalculator {
  const EmployeePayrollCalculator._();
  static PayrollCalculation calculate({
    required SalaryContract? contract,
    required DateTime at,
    required int approvedCommission,
    required Iterable<PayrollAdjustment> adjustments,
    required Iterable<PayrollAdvance> advances,
    required int previousPayments,
    int commissionRefunds = 0,
    int attendanceAdjustment = 0,
  }) {
    if (approvedCommission < 0 || previousPayments < 0 || commissionRefunds < 0) {
      throw ArgumentError('پورسانت، برگشت پورسانت و پرداخت قبلی معتبر نیستند.');
    }
    final salary = contract != null && contract.appliesAt(at) ? contract.monthlyBase : 0;
    var bonuses = 0, deductions = 0;
    for (final item in adjustments) { if (item.status != PayrollRecordStatus.approved) continue; if (item.isBonus) { bonuses += item.amount; } else { deductions += item.amount; } }
    final advanceDeducted = advances.where((item) => item.status == AdvanceStatus.paid || item.status == AdvanceStatus.deducted).fold<int>(0, (sum, item) => sum + item.deductedAmount);
    return PayrollCalculation(
      baseSalary: salary,
      approvedCommission: approvedCommission,
      approvedBonuses: bonuses,
      deductions: deductions,
      advanceDeducted: advanceDeducted,
      previousPayments: previousPayments,
      commissionRefunds: commissionRefunds,
      attendanceAdjustment: attendanceAdjustment,
    );
  }
}