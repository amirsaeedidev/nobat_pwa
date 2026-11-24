import 'enums.dart';

/// وضعیت همکاری پرسنل؛ با isActive قدیمی سازگار نگه داشته شده است.
enum EmployeeStatus {
  active('فعال'),
  inactive('غیرفعال'),
  onLeave('در مرخصی'),
  suspended('تعلیق‌شده');

  const EmployeeStatus(this.label);
  final String label;

  static EmployeeStatus fromKey(String? key, {bool isActive = true}) =>
      EmployeeStatus.values.firstWhere(
        (status) => status.name == key,
        orElse: () => isActive ? EmployeeStatus.active : EmployeeStatus.inactive,
      );
}

/// یک شیفت کاری در طول روز.
class Shift {
  const Shift({required this.start, required this.end});
  final String start;
  final String end;

  int get startMinutes => _toMinutes(start);
  int get endMinutes => _toMinutes(end);

  static int _toMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  String get label => '${_fa(start)} تا ${_fa(end)}';

  static String _fa(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return value;
    return '${_digits(parts[0])}:${_digits(parts[1])}';
  }

  static String _digits(String value) {
    const fa = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    return value.split('').map((c) => int.tryParse(c) != null ? fa[int.parse(c)] : c).join();
  }

  Shift copyWith({String? start, String? end}) => Shift(start: start ?? this.start, end: end ?? this.end);
  Map<String, dynamic> toJson() => {'start': start, 'end': end};
  factory Shift.fromJson(Map<String, dynamic> json) =>
      Shift(start: json['start'] as String? ?? '09:00', end: json['end'] as String? ?? '17:00');
}

/// پرسنل / متخصص — مدل سازگار با ساختار فعلی و قابل توسعه برای فازهای بعدی.
class Employee {
  const Employee({
    required this.id,
    required this.fullName,
    required this.phone,
    this.title = '',
    this.role = StaffRole.specialist,
    this.isActive = true,
    this.status,
    this.serviceIds = const [],
    this.schedule = const {},
    this.daysOff = const [],
    this.permissions = const [],
    this.colorValue = 0xFF642CA9,
    this.email = '',
    this.startedAt,
    this.bookedCount = 0,
    this.rating = 0,
    this.avatarAsset = '',
    this.specialties = const [],
    this.notes = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.scheduleEnabled = true,
    this.bufferMinutes = 0,
  });

  final String id;
  final String fullName;
  final String phone;
  final String title;
  final StaffRole role;
  final bool isActive;
  final EmployeeStatus? status;
  final List<String> serviceIds;
  final Map<int, List<Shift>> schedule;
  final List<String> daysOff;
  final List<String> permissions;
  final int colorValue;
  final String email;
  final DateTime? startedAt;
  final int bookedCount;
  final double rating;
  /// مسیر محلی تصویر؛ برای حالت آفلاین URL شبکه‌ای استفاده نمی‌شود.
  final String avatarAsset;
  final List<String> specialties;
  final String notes;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final bool scheduleEnabled;
  final int bufferMinutes;

  EmployeeStatus get employmentStatus => status ?? (isActive ? EmployeeStatus.active : EmployeeStatus.inactive);
  bool get isAvailableForBooking => isActive && employmentStatus == EmployeeStatus.active;

  List<Shift> shiftsFor(int weekday) => schedule[weekday] ?? const [];
  bool worksOn(int weekday) => shiftsFor(weekday).isNotEmpty;
  String get initials => fullName.trim().isEmpty ? '؟' : fullName.trim().split(RegExp(r'\\s+')).first.characters.first;

  Employee copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? title,
    StaffRole? role,
    bool? isActive,
    EmployeeStatus? status,
    List<String>? serviceIds,
    Map<int, List<Shift>>? schedule,
    List<String>? daysOff,
    List<String>? permissions,
    int? colorValue,
    String? email,
    DateTime? startedAt,
    int? bookedCount,
    double? rating,
    String? avatarAsset,
    List<String>? specialties,
    String? notes,
    String? emergencyContactName,
    String? emergencyContactPhone,
    bool? scheduleEnabled,
    int? bufferMinutes,
  }) {
    final nextStatus = status ?? (isActive == null ? this.status : (isActive ? EmployeeStatus.active : EmployeeStatus.inactive));
    final nextActive = isActive ?? (status == null ? this.isActive : status == EmployeeStatus.active);
    return Employee(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      title: title ?? this.title,
      role: role ?? this.role,
      isActive: nextActive,
      status: nextStatus,
      serviceIds: serviceIds ?? this.serviceIds,
      schedule: schedule ?? this.schedule,
      daysOff: daysOff ?? this.daysOff,
      permissions: permissions ?? this.permissions,
      colorValue: colorValue ?? this.colorValue,
      email: email ?? this.email,
      startedAt: startedAt ?? this.startedAt,
      bookedCount: bookedCount ?? this.bookedCount,
      rating: rating ?? this.rating,
      avatarAsset: avatarAsset ?? this.avatarAsset,
      specialties: specialties ?? this.specialties,
      notes: notes ?? this.notes,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'phone': phone,
    'title': title,
    'role': role.key,
    'is_active': isActive,
    'status': employmentStatus.name,
    'service_ids': serviceIds,
    'schedule': schedule.map((k, v) => MapEntry(k.toString(), v.map((s) => s.toJson()).toList())),
    'days_off': daysOff,
    'permissions': permissions,
    'color_value': colorValue,
    'email': email,
    'started_at': startedAt?.toIso8601String(),
    'booked_count': bookedCount,
    'rating': rating,
    'avatar_asset': avatarAsset,
    'specialties': specialties,
    'notes': notes,
    'emergency_contact_name': emergencyContactName,
    'emergency_contact_phone': emergencyContactPhone,
    'schedule_enabled': scheduleEnabled,
    'buffer_minutes': bufferMinutes,
  };

  factory Employee.fromJson(Map<String, dynamic> json) {
    final active = json['is_active'] as bool? ?? true;
    return Employee(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      title: json['title'] as String? ?? '',
      role: StaffRole.fromKey(json['role'] as String? ?? 'specialist'),
      isActive: active,
      status: EmployeeStatus.fromKey(json['status'] as String?, isActive: active),
      serviceIds: (json['service_ids'] as List?)?.cast<String>() ?? const [],
      schedule: ((json['schedule'] as Map?) ?? {}).map((k, v) => MapEntry(
        int.parse(k.toString()),
        (v as List).map((e) => Shift.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      )),
      daysOff: (json['days_off'] as List?)?.cast<String>() ?? const [],
      permissions: (json['permissions'] as List?)?.cast<String>() ?? const [],
      colorValue: (json['color_value'] as num?)?.toInt() ?? 0xFF642CA9,
      email: json['email'] as String? ?? '',
      startedAt: json['started_at'] == null ? null : DateTime.tryParse(json['started_at'] as String),
      bookedCount: (json['booked_count'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      avatarAsset: json['avatar_asset'] as String? ?? '',
      specialties: (json['specialties'] as List?)?.cast<String>() ?? const [],
      notes: json['notes'] as String? ?? '',
      emergencyContactName: json['emergency_contact_name'] as String? ?? '',
      emergencyContactPhone: json['emergency_contact_phone'] as String? ?? '',
      scheduleEnabled: json['schedule_enabled'] as bool? ?? true,
      bufferMinutes: (json['buffer_minutes'] as num?)?.toInt() ?? 0,
    );
  }
}

extension _Chars on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
