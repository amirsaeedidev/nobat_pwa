import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/customer.dart';
import 'package:datetime/data/models/service.dart';
import 'package:datetime/data/models/employee_service_config.dart';
import 'package:datetime/data/repositories/customer_repository.dart';
import 'package:datetime/data/repositories/service_repository.dart';
import 'package:datetime/features/customers/presentation/providers/customers_provider.dart';
import 'package:datetime/features/services/presentation/providers/services_provider.dart';

void main() {
  group('مشتریان', () {
    late AppDatabase db;
    late CustomersProvider provider;

    setUp(() async {
      db = AppDatabase();
      provider = CustomersProvider(MockCustomerRepository(db));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });

    test('جست‌وجو بر اساس نام و شماره', () async {
      provider.search('مریم');
      await provider.load();
      expect(provider.items.every((c) => c.fullName.contains('مریم')), isTrue);
      expect(provider.items, isNotEmpty);

      provider.search('09121234501');
      await provider.load();
      expect(provider.items.any((c) => c.phone == '09121234501'), isTrue);
    });

    test('افزودن و ویرایش مشتری', () async {
      final before = db.customers.length;
      await provider.create(
        const Customer(id: 'cus-test', fullName: 'نگار سلیمی', phone: '09011112233'),
      );
      expect(db.customers.length, before + 1);

      final created = db.customers.firstWhere((c) => c.id == 'cus-test');
      await provider.update(created.copyWith(fullName: 'نگار س.'));
      expect(db.customers.firstWhere((c) => c.id == 'cus-test').fullName, 'نگار س.');
    });

    test('حذف مشتری از لیست', () async {
      final target = db.customers.first;
      await provider.delete(target.id);
      await provider.load();
      expect(db.customers.any((c) => c.id == target.id), isFalse);
      expect(provider.items.any((c) => c.id == target.id), isFalse);
    });
  });

  group('خدمات', () {
    late AppDatabase db;
    late ServicesProvider provider;

    setUp(() async {
      db = AppDatabase();
      provider = ServicesProvider(MockServiceRepository(db));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });

    test('فیلتر فعال و غیرفعال', () async {
      provider.setActiveOnly(true);
      await provider.load();
      expect(provider.items.every((s) => s.isActive), isTrue);

      await provider.create(const Service(
        id: 'inactive-filter-test',
        title: 'خدمت غیرفعال آزمایشی',
        price: 100000,
        durationMinutes: 30,
        isActive: false,
      ));
      provider.setInactiveOnly(true);
      await provider.load();
      expect(provider.filtered.any((s) => s.id == 'inactive-filter-test'), isTrue);
      expect(provider.filtered.every((s) => !s.isActive), isTrue);
    });

    test('ایجاد خدمت، ارتباط پرسنل و تنظیم قیمت، مدت و پورسانت اختصاصی', () async {
      final employee = db.employees.first;
      const serviceId = 'service-staff-config-test';
      await provider.create(Service(
        id: serviceId,
        title: 'خدمت اختصاصی پرسنل',
        price: 200000,
        durationMinutes: 40,
        employeeIds: [employee.id],
      ));

      expect(db.employeeById(employee.id)!.serviceIds, contains(serviceId));
      expect(db.serviceById(serviceId)!.employeeIds, contains(employee.id));

      db.saveEmployeeServiceConfig(EmployeeServiceConfig(
        employeeId: employee.id,
        serviceId: serviceId,
        customPrice: 175000,
        customDurationMinutes: 55,
        commissionRateBps: 1500,
        fixedCommissionAmount: 5000,
      ));
      expect(db.effectiveServicePrice(employee.id, serviceId), 175000);
      expect(db.effectiveServiceDuration(employee.id, serviceId), 55);
      expect(db.employeeServiceConfig(employee.id, serviceId)?.commissionRateBps, 1500);
      expect(db.employeeServiceConfig(employee.id, serviceId)?.fixedCommissionAmount, 5000);
    });

    test('مدیریت دسته‌بندی و جلوگیری از حذف دسته دارای خدمت', () {
      final category = db.serviceCategories.first;
      expect(() => db.deleteServiceCategory(category), throwsStateError);
      final target = db.serviceCategories.firstWhere((item) => item != category);
      db.renameServiceCategory(category, 'دسته آزمایشی');
      expect(db.services.where((item) => item.category == 'دسته آزمایشی'), isNotEmpty);
      db.deleteServiceCategory('دسته آزمایشی', moveServicesTo: target);
      expect(db.services.any((item) => item.category == 'دسته آزمایشی'), isFalse);
      expect(db.serviceCategories.contains('دسته آزمایشی'), isFalse);
    });

    test('قیمت تخفیفی فقط در بازه اعتبار اعمال و در JSON حفظ می‌شود', () {
      final start = DateTime(2026, 11, 20);
      final service = Service(
        id: 'discount-test',
        title: 'خدمت تخفیفی',
        price: 200000,
        discountPrice: 150000,
        discountStartsAt: start,
        discountEndsAt: DateTime(2026, 11, 22),
        durationMinutes: 30,
      );
      expect(service.priceAt(DateTime(2026, 11, 20, 23)), 150000);
      expect(service.priceAt(DateTime(2026, 11, 23)), 200000);
      final restored = Service.fromJson(service.toJson());
      expect(restored.discountPrice, 150000);
      expect(restored.discountStartsAt?.year, 2026);
      expect(restored.discountEndsAt?.day, 22);
    });

    test('ساخت خدمت جدید با شناسه یکتا', () async {
      final before = db.services.length;
      final id = provider.nextId();
      expect(db.services.any((s) => s.id == id), isFalse);
      await provider.create(
        Service(
          id: id,
          title: 'خدمت آزمایشی',
          price: 100000,
          durationMinutes: 30,
          isActive: true,
          category: 'ناخن',
        ),
      );
      expect(db.services.length, before + 1);
    });
  });
}
