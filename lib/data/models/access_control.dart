/// مدل مستقل نقش‌ها و دسترسی‌ها برای محیط Mock/آفلاین.
class AccessPermission {
  const AccessPermission(this.id, this.group, this.label);
  final String id;
  final String group;
  final String label;

  static const all = <AccessPermission>[
    AccessPermission('employees.view_list', 'پرسنل', 'مشاهده فهرست پرسنل'),
    AccessPermission('employees.create', 'پرسنل', 'افزودن پرسنل'),
    AccessPermission('employees.edit', 'پرسنل', 'ویرایش اطلاعات پرسنل'),
    AccessPermission('employees.deactivate', 'پرسنل', 'غیرفعال‌سازی پرسنل'),
    AccessPermission('employees.view_profile', 'پرسنل', 'مشاهده پروفایل پرسنل'),
    AccessPermission('appointments.view_all', 'نوبت‌ها', 'مشاهده تمام نوبت‌ها'),
    AccessPermission('appointments.view_self', 'نوبت‌ها', 'مشاهده نوبت‌های خود'),
    AccessPermission('appointments.create', 'نوبت‌ها', 'ثبت نوبت'),
    AccessPermission('appointments.edit', 'نوبت‌ها', 'ویرایش نوبت'),
    AccessPermission('appointments.cancel', 'نوبت‌ها', 'لغو نوبت'),
    AccessPermission('appointments.complete', 'نوبت‌ها', 'تکمیل نوبت'),
    AccessPermission('customers.view', 'مشتریان', 'مشاهده مشتریان'),
    AccessPermission('customers.create', 'مشتریان', 'ثبت مشتری'),
    AccessPermission('customers.edit', 'مشتریان', 'ویرایش اطلاعات مشتری'),
    AccessPermission('customers.history', 'مشتریان', 'مشاهده سوابق مشتریان'),
    AccessPermission('finance.income.view', 'مالی', 'مشاهده درآمد'),
    AccessPermission('finance.commission.view', 'مالی', 'مشاهده پورسانت'),
    AccessPermission('finance.salary.view', 'مالی', 'مشاهده حقوق'),
    AccessPermission('finance.payment.create', 'مالی', 'ثبت پرداخت'),
    AccessPermission('finance.advance.create', 'مالی', 'ثبت مساعده'),
    AccessPermission('finance.settlement.view', 'مالی', 'مشاهده تسویه‌ها'),
    AccessPermission('settings.view', 'تنظیمات', 'مشاهده تنظیمات'),
    AccessPermission('settings.hours.edit', 'تنظیمات', 'ویرایش ساعت کاری'),
    AccessPermission('services.manage', 'تنظیمات', 'مدیریت خدمات'),
    AccessPermission('users.manage', 'تنظیمات', 'مدیریت کاربران'),
    AccessPermission('permissions.manage', 'تنظیمات', 'مدیریت دسترسی‌ها'),
  ];

  static List<String> get ids => all.map((permission) => permission.id).toList(growable: false);
  static Map<String, List<AccessPermission>> get grouped {
    final result = <String, List<AccessPermission>>{};
    for (final permission in all) { result.putIfAbsent(permission.group, () => []).add(permission); }
    return result;
  }
}

class AccessRole {
  const AccessRole({required this.id, required this.name, required this.permissionIds, this.isSystem = false, this.description = ''});
  final String id;
  final String name;
  final List<String> permissionIds;
  final bool isSystem;
  final String description;
  AccessRole copyWith({String? name, List<String>? permissionIds, String? description}) => AccessRole(
    id: id, name: name ?? this.name, permissionIds: List.unmodifiable(permissionIds ?? this.permissionIds),
    isSystem: isSystem, description: description ?? this.description,
  );

  static List<AccessRole> defaults() {
    final all = AccessPermission.ids;
    const manager = [
      'employees.view_list', 'employees.create', 'employees.edit', 'employees.deactivate', 'employees.view_profile',
      'appointments.view_all', 'appointments.create', 'appointments.edit', 'appointments.cancel', 'appointments.complete',
      'customers.view', 'customers.create', 'customers.edit', 'customers.history',
      'finance.income.view', 'finance.commission.view', 'finance.salary.view', 'finance.payment.create',
      'finance.advance.create', 'finance.settlement.view', 'settings.view', 'settings.hours.edit', 'services.manage', 'users.manage', 'permissions.manage',
    ];
    const operator = [
      'employees.view_list', 'employees.view_profile', 'appointments.view_all', 'appointments.create',
      'appointments.edit', 'appointments.cancel', 'appointments.complete', 'customers.view',
      'customers.create', 'customers.edit', 'customers.history', 'settings.view',
    ];
    const staff = ['employees.view_profile', 'appointments.view_self', 'appointments.complete', 'customers.view', 'customers.history', 'finance.commission.view'];
    const accountant = [
      'employees.view_list', 'employees.view_profile', 'finance.income.view', 'finance.commission.view',
      'finance.salary.view', 'finance.payment.create', 'finance.advance.create', 'finance.settlement.view',
    ];
    return [
      AccessRole(id: 'global_admin', name: 'مدیر کل', permissionIds: all, isSystem: true, description: 'دسترسی کامل به همه بخش‌ها'),
      AccessRole(id: 'manager', name: 'مدیر مجموعه', permissionIds: manager, isSystem: true),
      AccessRole(id: 'operator', name: 'اپراتور', permissionIds: operator, isSystem: true),
      AccessRole(id: 'staff', name: 'پرسنل', permissionIds: staff, isSystem: true),
      AccessRole(id: 'accountant', name: 'حسابدار', permissionIds: accountant, isSystem: true),
    ];
  }
}

class AccessAccount {
  const AccessAccount({required this.id, required this.name, required this.roleId, this.employeeId, this.isEnabled = true, this.isDemo = true});
  final String id;
  final String name;
  final String roleId;
  final String? employeeId;
  final bool isEnabled;
  final bool isDemo;
  AccessAccount copyWith({String? roleId, bool? isEnabled}) => AccessAccount(
    id: id, name: name, roleId: roleId ?? this.roleId, employeeId: employeeId,
    isEnabled: isEnabled ?? this.isEnabled, isDemo: isDemo,
  );
}

class AccessAssignment {
  const AccessAssignment({
    required this.employeeId, required this.roleId, this.overrides = const {},
    this.canViewOtherEmployees = false, this.canViewPersonalIncome = true,
  });
  final String employeeId;
  final String roleId;
  final Map<String, bool> overrides;
  final bool canViewOtherEmployees;
  final bool canViewPersonalIncome;
  AccessAssignment copyWith({String? roleId, Map<String, bool>? overrides, bool? canViewOtherEmployees, bool? canViewPersonalIncome}) => AccessAssignment(
    employeeId: employeeId, roleId: roleId ?? this.roleId, overrides: Map.unmodifiable(overrides ?? this.overrides),
    canViewOtherEmployees: canViewOtherEmployees ?? this.canViewOtherEmployees,
    canViewPersonalIncome: canViewPersonalIncome ?? this.canViewPersonalIncome,
  );
}
