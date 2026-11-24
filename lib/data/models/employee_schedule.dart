import 'employee.dart';

enum EmployeeLeaveType {
  daily('مرخصی روزانه'),
  hourly('مرخصی ساعتی'),
  multiDay('مرخصی چندروزه'),
  emergency('مرخصی اضطراری'),
  holiday('تعطیلی اختصاصی');

  const EmployeeLeaveType(this.label);
  final String label;
}

enum EmployeeLeaveStatus {
  pending('در انتظار تأیید'),
  approved('تأیید شده'),
  rejected('رد شده'),
  cancelled('لغو شده');

  const EmployeeLeaveStatus(this.label);
  final String label;
}

class EmployeeScheduleException {
  const EmployeeScheduleException({
    required this.employeeId,
    required this.dateKey,
    this.title = 'ساعات ویژه',
    this.isClosed = false,
    this.shifts = const [],
  });

  final String employeeId;
  final String dateKey;
  final String title;
  final bool isClosed;
  final List<Shift> shifts;

  Map<String, dynamic> toJson() => {
    'employee_id': employeeId,
    'date_key': dateKey,
    'title': title,
    'is_closed': isClosed,
    'shifts': shifts.map((shift) => shift.toJson()).toList(),
  };

  factory EmployeeScheduleException.fromJson(Map<String, dynamic> json) => EmployeeScheduleException(
    employeeId: json['employee_id'] as String,
    dateKey: json['date_key'] as String,
    title: json['title'] as String? ?? 'ساعات ویژه',
    isClosed: json['is_closed'] as bool? ?? false,
    shifts: (json['shifts'] as List? ?? []).map((item) => Shift.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
  );
}

class EmployeeLeave {
  const EmployeeLeave({
    required this.id,
    required this.employeeId,
    required this.startAt,
    required this.endAt,
    required this.type,
    this.status = EmployeeLeaveStatus.approved,
    this.description = '',
    required this.createdAt,
    this.approvedBy,
  });

  final String id;
  final String employeeId;
  final DateTime startAt;
  final DateTime endAt;
  final EmployeeLeaveType type;
  final EmployeeLeaveStatus status;
  final String description;
  final DateTime createdAt;
  final String? approvedBy;

  bool overlaps(DateTime start, DateTime end) =>
      status == EmployeeLeaveStatus.approved && startAt.isBefore(end) && start.isBefore(endAt);

  EmployeeLeave copyWith({EmployeeLeaveStatus? status, String? description, String? approvedBy}) => EmployeeLeave(
    id: id, employeeId: employeeId, startAt: startAt, endAt: endAt, type: type,
    status: status ?? this.status, description: description ?? this.description,
    createdAt: createdAt, approvedBy: approvedBy ?? this.approvedBy,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'employee_id': employeeId, 'start_at': startAt.toIso8601String(),
    'end_at': endAt.toIso8601String(), 'type': type.name, 'status': status.name,
    'description': description, 'created_at': createdAt.toIso8601String(), 'approved_by': approvedBy,
  };

  factory EmployeeLeave.fromJson(Map<String, dynamic> json) => EmployeeLeave(
    id: json['id'] as String, employeeId: json['employee_id'] as String,
    startAt: DateTime.parse(json['start_at'] as String), endAt: DateTime.parse(json['end_at'] as String),
    type: EmployeeLeaveType.values.firstWhere((item) => item.name == json['type'], orElse: () => EmployeeLeaveType.daily),
    status: EmployeeLeaveStatus.values.firstWhere((item) => item.name == json['status'], orElse: () => EmployeeLeaveStatus.pending),
    description: json['description'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String), approvedBy: json['approved_by'] as String?,
  );
}

class EmployeeScheduleRules {
  const EmployeeScheduleRules._();

  static void validateShifts(List<Shift> shifts) {
    final sorted = [...shifts]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    for (final shift in sorted) {
      if (shift.startMinutes < 0 || shift.endMinutes > 24 * 60 || shift.startMinutes >= shift.endMinutes) {
        throw ArgumentError('بازه شیفت معتبر نیست.');
      }
    }
    for (var index = 1; index < sorted.length; index++) {
      if (sorted[index].startMinutes < sorted[index - 1].endMinutes) {
        throw ArgumentError('شیفت‌ها نباید با یکدیگر هم‌پوشانی داشته باشند.');
      }
    }
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
