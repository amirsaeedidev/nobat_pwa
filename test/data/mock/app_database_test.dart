import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';

void main() {
  group('Datamonck employee persistence', () {
    test('keeps employee and service assignments synchronized', () {
      final db = AppDatabase();
      final sara = db.employeeById('emp-sara')!;
      expect(db.services.firstWhere((service) => service.id == 'srv-color').employeeIds, contains(sara.id));
    });

    test('archives employees with appointment history instead of deleting them', () {
      final db = AppDatabase();
      final employeeWithHistory = db.appointments.first.employeeId;
      db.deleteEmployee(employeeWithHistory);
      final archived = db.employeeById(employeeWithHistory);
      expect(archived, isNotNull);
      expect(archived!.isActive, isFalse);
    });

    test('removes employees without appointment history and cleans service links', () {
      final db = AppDatabase();
      const id = 'emp-nima';
      expect(db.employeeById(id), isNotNull);
      db.deleteEmployee(id);
      expect(db.employeeById(id), isNull);
      expect(db.services.every((service) => !service.employeeIds.contains(id)), isTrue);
    });
  });
}
