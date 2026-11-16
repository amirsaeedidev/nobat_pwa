/// تنظیمات رابطه یک پرسنل با یک خدمت؛ مقادیر null از تنظیمات عمومی خدمت ارث می‌برند.
class EmployeeServiceConfig {
  const EmployeeServiceConfig({
    required this.employeeId,
    required this.serviceId,
    this.active = true,
    this.customPrice,
    this.customDurationMinutes,
    this.commissionRateBps,
    this.fixedCommissionAmount,
    this.specialtyNote = '',
  });

  final String employeeId;
  final String serviceId;
  final bool active;
  final int? customPrice;
  final int? customDurationMinutes;
  /// null یعنی استفاده از قانون پورسانت عمومی پرسنل.
  final int? commissionRateBps;
  final int? fixedCommissionAmount;
  final String specialtyNote;

  int get effectivePrice => customPrice ?? 0;
  int get effectiveDurationMinutes => customDurationMinutes ?? 0;

  EmployeeServiceConfig copyWith({
    bool? active,
    int? customPrice,
    int? customDurationMinutes,
    int? commissionRateBps,
    int? fixedCommissionAmount,
    String? specialtyNote,
    bool clearCustomPrice = false,
    bool clearCustomDuration = false,
    bool clearCommissionRate = false,
    bool clearFixedCommission = false,
  }) => EmployeeServiceConfig(
    employeeId: employeeId,
    serviceId: serviceId,
    active: active ?? this.active,
    customPrice: clearCustomPrice ? null : customPrice ?? this.customPrice,
    customDurationMinutes: clearCustomDuration ? null : customDurationMinutes ?? this.customDurationMinutes,
    commissionRateBps: clearCommissionRate ? null : commissionRateBps ?? this.commissionRateBps,
    fixedCommissionAmount: clearFixedCommission ? null : fixedCommissionAmount ?? this.fixedCommissionAmount,
    specialtyNote: specialtyNote ?? this.specialtyNote,
  );

  Map<String, dynamic> toJson() => {
    'employee_id': employeeId,
    'service_id': serviceId,
    'active': active,
    'custom_price': customPrice,
    'custom_duration_minutes': customDurationMinutes,
    'commission_rate_bps': commissionRateBps,
    'fixed_commission_amount': fixedCommissionAmount,
    'specialty_note': specialtyNote,
  };

  factory EmployeeServiceConfig.fromJson(Map<String, dynamic> json) => EmployeeServiceConfig(
    employeeId: json['employee_id'] as String,
    serviceId: json['service_id'] as String,
    active: json['active'] as bool? ?? true,
    customPrice: (json['custom_price'] as num?)?.toInt(),
    customDurationMinutes: (json['custom_duration_minutes'] as num?)?.toInt(),
    commissionRateBps: (json['commission_rate_bps'] as num?)?.toInt(),
    fixedCommissionAmount: (json['fixed_commission_amount'] as num?)?.toInt(),
    specialtyNote: json['specialty_note'] as String? ?? '',
  );
}
