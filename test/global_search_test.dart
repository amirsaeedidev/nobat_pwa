import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/repositories/global_search_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GlobalSearchRepository', () {
    test('normalizes Persian and Arabic digits and common Arabic letter forms', () {
      expect(
        GlobalSearchRepository.normalize('ي ك ۱۲۳۴۵۶۷۸۹۰ ٠١٢'),
        GlobalSearchRepository.normalize('ی ک 1234567890 012'),
      );
      expect(GlobalSearchRepository.normalize('نیم‌فاصله'), 'نیمفاصله');
    });

    test('searches local offline customer, service, category and appointment data', () async {
      final db = AppDatabase();
      final repository = GlobalSearchRepository(db);

      final customer = db.customers.first;
      final customerResults = await repository.search(customer.fullName);
      expect(customerResults.any((item) =>
          item.type == GlobalSearchType.customer && item.id == customer.id), isTrue);

      final service = db.services.first;
      final serviceResults = await repository.search(service.title);
      expect(serviceResults.any((item) =>
          item.type == GlobalSearchType.service && item.id == service.id), isTrue);

      final categoryResults = await repository.search(service.category, type: GlobalSearchType.category);
      expect(categoryResults.any((item) =>
          item.type == GlobalSearchType.category && item.title == service.category), isTrue);

      final appointment = db.appointments.first;
      final appointmentResults = await repository.search(appointment.reference);
      expect(appointmentResults.any((item) =>
          item.type == GlobalSearchType.appointment && item.id == appointment.id), isTrue);
    });

    test('matches phone numbers written with Persian digits', () async {
      final db = AppDatabase();
      final customer = db.customers.first;
      const digits = '۰۱۲۳۴۵۶۷۸۹';
      final persianPhone = customer.phone.replaceAllMapped(
        RegExp(r'\d'),
        (match) => digits[int.parse(match.group(0)!)],
      );
      final results = await GlobalSearchRepository(db).search(persianPhone);
      expect(results.any((item) =>
          item.type == GlobalSearchType.customer && item.id == customer.id), isTrue);
    });

    test('does not expose finance records to a role without finance permission', () async {
      final db = AppDatabase();
      db.switchMockAccount('demo-custom');
      final repository = GlobalSearchRepository(db);

      final results = await repository.search('DOC-DM-RENT-001');
      expect(results.where((item) => item.type == GlobalSearchType.transaction), isEmpty);
      expect(db.canOpenRoute('/search'), isTrue);
    });

    test('staff search is limited to their own appointments and income', () async {
      final db = AppDatabase();
      db.switchMockAccount('demo-staff');
      final repository = GlobalSearchRepository(db);

      final otherAppointment = db.appointments.firstWhere(
        (item) => item.employeeId != 'emp-zahra',
      );
      final hiddenAppointments = await repository.search(otherAppointment.reference);
      expect(hiddenAppointments.where((item) => item.type == GlobalSearchType.appointment), isEmpty);

      final otherIncome = db.employeeFinanceEntries.firstWhere(
        (item) => item.employeeId != 'emp-zahra',
      );
      final hiddenIncome = await repository.search(otherIncome.id);
      expect(hiddenIncome.where((item) => item.type == GlobalSearchType.transaction), isEmpty);
    });

    test('searches finance documents and activity history when permissions allow', () async {
      final db = AppDatabase();
      final repository = GlobalSearchRepository(db);

      final expense = db.businessExpenses.first;
      final expenseResults = await repository.search(expense.sourceDocumentId);
      expect(expenseResults.any((item) =>
          item.type == GlobalSearchType.transaction && item.id == expense.id), isTrue);

      final activity = db.activityLogs.first;
      final activityResults = await repository.search(activity.title);
      expect(activityResults.any((item) =>
          item.type == GlobalSearchType.activity && item.id == activity.id), isTrue);

      if (db.employeeDocuments.isNotEmpty) {
        final document = db.employeeDocuments.first;
        final documentResults = await repository.search(document.title);
        expect(documentResults.any((item) =>
            item.type == GlobalSearchType.document && item.id == document.id), isTrue);
      }
    });

    test('invalidates cached results after changing the active mock account', () async {
      final db = AppDatabase();
      final repository = GlobalSearchRepository(db);
      final customer = db.customers.first;
      final results = await repository.search(customer.fullName);
      final result = results.firstWhere((item) =>
          item.type == GlobalSearchType.customer && item.id == customer.id);
      expect(canOpenGlobalSearchResult(db, result), isTrue);

      db.switchMockAccount('demo-custom');
      expect(canOpenGlobalSearchResult(db, result), isFalse);
    });

    test('local search completes without waiting for any network service', () async {
      final db = AppDatabase();
      final repository = GlobalSearchRepository(db);
      final stopwatch = Stopwatch()..start();
      final results = await repository.search('سارا');
      stopwatch.stop();

      expect(results, isNotEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('persists, deduplicates and clears recent searches per account', () async {
      final db = AppDatabase();
      final repository = GlobalSearchRepository(db);
      await repository.rememberSearch('سارا');
      await repository.rememberSearch('  سارا  ');
      await repository.rememberSearch('۰۹۱۲');

      expect(await repository.recentSearches(), ['۰۹۱۲', 'سارا']);
      await repository.clearHistory();
      expect(await repository.recentSearches(), isEmpty);
    });
  });
}
