import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/access_control.dart';

/// تنها دو سطح دسترسی برنامه: مدیر کل و پرسنل.
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  String? _selectedEmployeeId;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final pal = context.pal;
    final staffRole = db.accessRoleById('staff')!;
    final adminAccounts = db.accessAccounts.where((account) => account.roleId == 'global_admin').toList();
    final adminEmployeeId = adminAccounts.isEmpty ? null : adminAccounts.first.employeeId;
    final employees = db.employees.where((employee) => employee.id != adminEmployeeId).toList();
    final selectedEmployee = employees.firstWhere(
      (employee) => employee.id == _selectedEmployeeId,
      orElse: () => employees.first,
    );
    final assignment = db.accessAssignmentFor(selectedEmployee.id);
    final overrides = assignment?.overrides ?? const <String, bool>{};

    return PageScaffold(
      title: 'مدیریت دسترسی پرسنل',
      subtitle: 'فقط دو نقش فعال در برنامه وجود دارد: مدیر کل و پرسنل',
      icon: Icons.admin_panel_settings_rounded,
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'مدیر کل'),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.verified_user_rounded, color: pal.success, size: 30),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'دسترسی کامل به تمام بخش‌ها، اطلاعات و عملیات برنامه؛ امکان مدیریت دسترسی همه پرسنل.',
                    style: TextStyle(fontSize: 11, height: 1.8, color: pal.textSecondary),
                  )),
                  StatusBadge(label: 'همه دسترسی‌ها فعال', color: pal.success, dense: true),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'پرسنل'),
                const SizedBox(height: 8),
                Text(
                  'دسترسی پایه پرسنل فقط شامل نوبت‌های خودش و امور شخصی اوست. مدیر کل می‌تواند مجوزهای هر پرسنل را جداگانه فعال یا غیرفعال کند.',
                  style: TextStyle(fontSize: 11, height: 1.8, color: pal.textSecondary),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedEmployee.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'انتخاب پرسنل'),
                  items: employees.map((employee) => DropdownMenuItem(
                    value: employee.id,
                    child: Text(employee.fullName),
                  )).toList(),
                  onChanged: (id) => setState(() => _selectedEmployeeId = id),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  StatusBadge(label: 'نقش: پرسنل', color: pal.primaryBright),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'مشاهده سایر پرسنل و درآمد دیگران غیرفعال است.',
                    style: TextStyle(fontSize: 10, color: pal.textMuted),
                  )),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'مجوزهای پرسنل'),
                const SizedBox(height: 6),
                for (final group in AccessPermission.grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Text(group.key, style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: pal.primaryBright,
                    )),
                  ),
                  for (final permission in group.value)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(permission.label, style: TextStyle(fontSize: 11, color: pal.textPrimary)),
                      value: overrides.containsKey(permission.id)
                          ? overrides[permission.id]
                          : staffRole.permissionIds.contains(permission.id),
                      onChanged: (value) => _savePermission(
                        db,
                        selectedEmployee.id,
                        permission.id,
                        value == (staffRole.permissionIds.contains(permission.id)) ? null : value,
                        overrides,
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  'تغییرات برای همان پرسنل ذخیره می‌شود؛ مدیر کل همچنان دسترسی کامل دارد.',
                  style: TextStyle(fontSize: 10, height: 1.7, color: pal.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'حساب‌های آزمایشی'),
                const SizedBox(height: 8),
                Text(
                  'مدیر کل و پرسنل دو حساب نمونه برای بررسی رفتار دسترسی‌ها در حالت آفلاین هستند.',
                  style: TextStyle(fontSize: 10.5, height: 1.7, color: pal.textMuted),
                ),
                const SizedBox(height: 8),
                for (final account in db.accessAccounts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(account.roleId == 'global_admin'
                        ? Icons.admin_panel_settings_rounded
                        : Icons.badge_rounded),
                    title: Text(account.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    subtitle: Text(account.roleId == 'global_admin' ? 'مدیر کل' : 'پرسنل'),
                    trailing: TextButton(
                      onPressed: () {
                        try {
                          db.switchMockAccount(account.id);
                          AppToast.show(context, 'حساب آزمایشی تغییر کرد.');
                        } catch (error) {
                          AppToast.show(context, error.toString(), success: false);
                        }
                      },
                      child: const Text('فعال‌سازی'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _savePermission(
    AppDatabase db,
    String employeeId,
    String permissionId,
    bool? value,
    Map<String, bool> current,
  ) {
    final next = Map<String, bool>.from(current);
    if (value == null) {
      next.remove(permissionId);
    } else {
      next[permissionId] = value;
    }
    try {
      db.assignEmployeeAccess(
        employeeId: employeeId,
        roleId: 'staff',
        overrides: next,
        canViewOtherEmployees: false,
        canViewPersonalIncome: true,
      );
      AppToast.show(context, 'دسترسی پرسنل ذخیره شد.');
    } catch (error) {
      AppToast.show(context, error.toString(), success: false);
    }
  }
}
