import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/models/employee.dart';

void main() {
  group('Employee profile model', () {
    test('reads legacy employee JSON without new profile fields', () {
      final employee = Employee.fromJson({
        'id': 'emp-legacy',
        'full_name': 'کاربر آزمایشی',
        'phone': '09120000000',
        'is_active': true,
      });

      expect(employee.fullName, 'کاربر آزمایشی');
      expect(employee.employmentStatus, EmployeeStatus.active);
      expect(employee.specialties, isEmpty);
      expect(employee.notes, isEmpty);
    });

    test('round-trips extended profile fields and employment status', () {
      final employee = Employee(
        id: 'emp-test',
        fullName: 'پرسنل آزمایشی',
        phone: '09120000001',
        status: EmployeeStatus.onLeave,
        isActive: false,
        specialties: const ['رنگ مو', 'کراتین'],
        notes: 'یادداشت آزمایشی',
        emergencyContactName: 'تماس اضطراری',
        emergencyContactPhone: '09120000002',
        avatarAsset: 'assets/image/personnel/demo.png',
      );

      final restored = Employee.fromJson(employee.toJson());
      expect(restored.employmentStatus, EmployeeStatus.onLeave);
      expect(restored.isAvailableForBooking, isFalse);
      expect(restored.specialties, employee.specialties);
      expect(restored.notes, employee.notes);
      expect(restored.emergencyContactPhone, employee.emergencyContactPhone);
      expect(restored.avatarAsset, employee.avatarAsset);
    });

    test('copyWith keeps legacy fields and updates status consistently', () {
      final employee = Employee(id: 'emp-copy', fullName: 'آزمایشی', phone: '09120000003');
      final inactive = employee.copyWith(status: EmployeeStatus.suspended);
      expect(inactive.employmentStatus, EmployeeStatus.suspended);
      expect(inactive.isActive, isFalse);
      expect(inactive.copyWith(status: EmployeeStatus.active).isAvailableForBooking, isTrue);
    });
  });
}
