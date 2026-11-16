/// مدل‌های مالی پرسنل؛ همه مبالغ به تومان و به‌صورت عدد صحیح ذخیره می‌شوند.
enum EmployeePaymentMethod {
  commissionOnly('فقط پورسانت'),
  fixedMonthly('حقوق ثابت ماهانه'),
  fixedPlusCommission('حقوق ثابت + پورسانت'),
  fixedPerService('مبلغ ثابت هر خدمت'),
  hybrid('مدل ترکیبی');

  const EmployeePaymentMethod(this.label);
  final String label;
}

enum CommissionBasis {
  gross('مبلغ اصلی خدمت'),
  afterDiscount('مبلغ پس از تخفیف'),
  netReceived('مبلغ نهایی دریافتی');

  const CommissionBasis(this.label);
  final String label;
}

enum FinanceEntryType { commission, refund, correction, salary }

class EmployeeCommissionRule {
  const EmployeeCommissionRule({
    required this.id,
    this.serviceId,
    this.category,
    this.rateBps = 0,
    this.fixedAmount = 0,
    this.effectiveFrom,
    this.active = true,
  });

  final String id;
  final String? serviceId;
  final String? category;
  /// نرخ بر حسب basis point؛ 3000 یعنی 30 درصد.
  final int rateBps;
  final int fixedAmount;
  final DateTime? effectiveFrom;
  final bool active;

  bool appliesTo({required String serviceId, required String category, required DateTime date}) {
    if (!active || (effectiveFrom != null && date.isBefore(effectiveFrom!))) return false;
    if (this.serviceId != null) return this.serviceId == serviceId;
    if (this.category != null) return this.category == category;
    return false;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'service_id': serviceId, 'category': category, 'rate_bps': rateBps,
    'fixed_amount': fixedAmount, 'effective_from': effectiveFrom?.toIso8601String(), 'active': active,
  };

  factory EmployeeCommissionRule.fromJson(Map<String, dynamic> json) => EmployeeCommissionRule(
    id: json['id'] as String,
    serviceId: json['service_id'] as String?,
    category: json['category'] as String?,
    rateBps: (json['rate_bps'] as num?)?.toInt() ?? 0,
    fixedAmount: (json['fixed_amount'] as num?)?.toInt() ?? 0,
    effectiveFrom: json['effective_from'] == null ? null : DateTime.tryParse(json['effective_from'] as String),
    active: json['active'] as bool? ?? true,
  );
}

class EmployeePayProfile {
  const EmployeePayProfile({
    required this.employeeId,
    this.method = EmployeePaymentMethod.commissionOnly,
    this.monthlySalary = 0,
    this.generalRateBps = 0,
    this.basis = CommissionBasis.afterDiscount,
    this.rules = const [],
  });

  final String employeeId;
  final EmployeePaymentMethod method;
  final int monthlySalary;
  final int generalRateBps;
  final CommissionBasis basis;
  final List<EmployeeCommissionRule> rules;

  EmployeeCommissionRule? ruleFor({required String serviceId, required String category, required DateTime date}) {
    final matches = rules.where((rule) => rule.appliesTo(serviceId: serviceId, category: category, date: date)).toList()
      ..sort((a, b) {
        final servicePriority = (b.serviceId != null ? 2 : 0).compareTo(a.serviceId != null ? 2 : 0);
        if (servicePriority != 0) return servicePriority;
        return (b.effectiveFrom ?? DateTime(1970)).compareTo(a.effectiveFrom ?? DateTime(1970));
      });
    return matches.isEmpty ? null : matches.first;
  }

  EmployeePayProfile copyWith({
    EmployeePaymentMethod? method,
    int? monthlySalary,
    int? generalRateBps,
    CommissionBasis? basis,
    List<EmployeeCommissionRule>? rules,
  }) => EmployeePayProfile(
    employeeId: employeeId,
    method: method ?? this.method,
    monthlySalary: monthlySalary ?? this.monthlySalary,
    generalRateBps: generalRateBps ?? this.generalRateBps,
    basis: basis ?? this.basis,
    rules: rules ?? this.rules,
  );

  Map<String, dynamic> toJson() => {
    'employee_id': employeeId, 'method': method.name, 'monthly_salary': monthlySalary,
    'general_rate_bps': generalRateBps, 'basis': basis.name, 'rules': rules.map((r) => r.toJson()).toList(),
  };

  factory EmployeePayProfile.fromJson(Map<String, dynamic> json) => EmployeePayProfile(
    employeeId: json['employee_id'] as String,
    method: EmployeePaymentMethod.values.firstWhere((v) => v.name == json['method'], orElse: () => EmployeePaymentMethod.commissionOnly),
    monthlySalary: (json['monthly_salary'] as num?)?.toInt() ?? 0,
    generalRateBps: (json['general_rate_bps'] as num?)?.toInt() ?? 0,
    basis: CommissionBasis.values.firstWhere((v) => v.name == json['basis'], orElse: () => CommissionBasis.afterDiscount),
    rules: (json['rules'] as List? ?? []).map((v) => EmployeeCommissionRule.fromJson(Map<String, dynamic>.from(v as Map))).toList(),
  );
}

/// snapshot immutable قانون مالی در لحظه قطعی شدن پورسانت.
class EmployeeFinanceEntry {
  const EmployeeFinanceEntry({
    required this.id,
    required this.employeeId,
    required this.appointmentId,
    required this.serviceId,
    required this.createdAt,
    required this.type,
    required this.methodSnapshot,
    required this.basisSnapshot,
    required this.grossAmount,
    required this.discountAmount,
    required this.receivedAmount,
    required this.calculationBase,
    required this.rateBps,
    required this.fixedAmount,
    required this.commissionAmount,
    required this.companyShare,
    this.reversesEntryId,
  });

  final String id;
  final String employeeId;
  final String appointmentId;
  final String serviceId;
  final DateTime createdAt;
  final FinanceEntryType type;
  final String methodSnapshot;
  final String basisSnapshot;
  final int grossAmount;
  final int discountAmount;
  final int receivedAmount;
  final int calculationBase;
  final int rateBps;
  final int fixedAmount;
  final int commissionAmount;
  final int companyShare;
  final String? reversesEntryId;

  Map<String, dynamic> toJson() => {
    'id': id, 'employee_id': employeeId, 'appointment_id': appointmentId, 'service_id': serviceId,
    'created_at': createdAt.toIso8601String(), 'type': type.name, 'method_snapshot': methodSnapshot,
    'basis_snapshot': basisSnapshot, 'gross_amount': grossAmount, 'discount_amount': discountAmount,
    'received_amount': receivedAmount, 'calculation_base': calculationBase, 'rate_bps': rateBps,
    'fixed_amount': fixedAmount, 'commission_amount': commissionAmount, 'company_share': companyShare,
    'reverses_entry_id': reversesEntryId,
  };

  factory EmployeeFinanceEntry.fromJson(Map<String, dynamic> json) => EmployeeFinanceEntry(
    id: json['id'] as String, employeeId: json['employee_id'] as String,
    appointmentId: json['appointment_id'] as String, serviceId: json['service_id'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    type: FinanceEntryType.values.firstWhere((v) => v.name == json['type'], orElse: () => FinanceEntryType.commission),
    methodSnapshot: json['method_snapshot'] as String? ?? '',
    basisSnapshot: json['basis_snapshot'] as String? ?? '',
    grossAmount: (json['gross_amount'] as num?)?.toInt() ?? 0,
    discountAmount: (json['discount_amount'] as num?)?.toInt() ?? 0,
    receivedAmount: (json['received_amount'] as num?)?.toInt() ?? 0,
    calculationBase: (json['calculation_base'] as num?)?.toInt() ?? 0,
    rateBps: (json['rate_bps'] as num?)?.toInt() ?? 0,
    fixedAmount: (json['fixed_amount'] as num?)?.toInt() ?? 0,
    commissionAmount: (json['commission_amount'] as num?)?.toInt() ?? 0,
    companyShare: (json['company_share'] as num?)?.toInt() ?? 0,
    reversesEntryId: json['reverses_entry_id'] as String?,
  );
}

/// ماشین‌حساب بدون اعشار شناور؛ تمام خروجی‌ها عدد صحیح تومان هستند.
class CommissionCalculator {
  const CommissionCalculator._();

  static int commission({required int baseAmount, required int rateBps, int fixedAmount = 0}) {
    if (baseAmount < 0 || rateBps < 0 || fixedAmount < 0) {
      throw ArgumentError('مقادیر محاسبه مالی نمی‌توانند منفی باشند.');
    }
    return (baseAmount * rateBps + 5000) ~/ 10000 + fixedAmount;
  }

  static int base({
    required CommissionBasis basis,
    required int grossAmount,
    required int discountAmount,
    required int receivedAmount,
  }) {
    if (grossAmount < 0 || discountAmount < 0 || receivedAmount < 0 || discountAmount > grossAmount) {
      throw ArgumentError('مبالغ خدمت یا تخفیف معتبر نیستند.');
    }
    return switch (basis) {
      CommissionBasis.gross => grossAmount,
      CommissionBasis.afterDiscount => grossAmount - discountAmount,
      CommissionBasis.netReceived => receivedAmount,
    };
  }
}
