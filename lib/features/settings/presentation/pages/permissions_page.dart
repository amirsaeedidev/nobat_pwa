import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/sensitive_operation_dialog.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/access_control.dart';
import '../../../../data/repositories/operations_repository.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});
  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  String? _selectedRoleId;
  String? _selectedEmployeeId;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<AppDatabase>();
    final pal = context.pal;
    final roles = db.accessRoles;
    final selectedRole = roles.firstWhere((role) => role.id == _selectedRoleId, orElse: () => roles.first);
    final employees = db.employees;
    final selectedEmployee = employees.firstWhere((employee) => employee.id == _selectedEmployeeId, orElse: () => employees.first);
    final assignment = db.accessAssignmentFor(selectedEmployee.id);
    final assignedRoleId = assignment?.roleId ?? 'staff';
    final assignedRole = db.accessRoleById(assignedRoleId) ?? roles.first;

    return PageScaffold(
      title: 'مدیریت نقش‌ها و دسترسی‌ها',
      subtitle: 'کنترل مجوزها در رابط کاربری و لایه داده — حالت آزمایشی آفلاین',
      icon: Icons.admin_panel_settings_rounded,
      showBackButton: true,
      actions: [
        FilledButton.icon(onPressed: _createRole, icon: const Icon(Icons.add_rounded), label: const Text('نقش جدید')),
      ],
      mobileActions: [
        IconButton(tooltip: 'ساخت نقش', onPressed: _createRole, icon: const Icon(Icons.add_rounded)),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionHeader(title: 'حساب آزمایشی فعال'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: db.currentAccessAccount.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'تغییر حساب برای بررسی نقش‌ها'),
              items: db.accessAccounts.map((account) => DropdownMenuItem(value: account.id, child: Text(account.name))).toList(),
              onChanged: (id) {
                if (id == null) return;
                try {
                  db.switchMockAccount(id);
                  AppToast.show(context, 'حساب آزمایشی تغییر کرد.');
                } catch (error) { AppToast.show(context, '$error', success: false); }
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              StatusBadge(label: db.currentAccessRoleName, color: pal.primaryBright),
              const SizedBox(width: 8),
              Expanded(child: Text('این انتخاب فقط برای تست دسترسی است و هیچ ورود یا سرویس آنلاین ندارد.', style: TextStyle(fontSize: 10, color: pal.textMuted))),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'نقش‌های پیش‌فرض و سفارشی'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final role in roles)
              ChoiceChip(
                selected: selectedRole.id == role.id,
                label: Text('${role.name} · ${FaNum.ofInt(db.accessAccounts.where((account) => account.roleId == role.id).length)}'),
                onSelected: (_) => setState(() => _selectedRoleId = role.id),
              ),
          ]),
          const Divider(height: 24),
          Row(children: [
            Expanded(child: Text(selectedRole.name, style: TextStyle(fontWeight: FontWeight.w800, color: pal.textPrimary))),
            if (!selectedRole.isSystem)
              IconButton(tooltip: 'ویرایش نام نقش', onPressed: () => _renameRole(selectedRole), icon: const Icon(Icons.edit_rounded)),
            if (selectedRole.isSystem)
              TextButton.icon(onPressed: () => _resetRole(db, selectedRole), icon: const Icon(Icons.restart_alt_rounded), label: const Text('بازنشانی')),
          ]),
          for (final group in AccessPermission.grouped.entries) ...[
            const SizedBox(height: 8),
            Text(group.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: pal.primaryBright)),
            const SizedBox(height: 4),
            for (final permission in group.value)
              Material(color: Colors.transparent, child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(permission.label, style: TextStyle(fontSize: 11, color: pal.textPrimary)),
                value: selectedRole.permissionIds.contains(permission.id),
                onChanged: selectedRole.isSystem ? null : (checked) => _toggleRolePermission(db, selectedRole, permission.id, checked == true),
              )),
          ],
          if (selectedRole.isSystem)
            Text('نقش‌های سیستمی محافظت شده‌اند؛ برای ساخت ترکیب اختصاصی از «نقش جدید» استفاده کنید.', style: TextStyle(fontSize: 10, color: pal.textMuted)),
        ])),
        const SizedBox(height: 12),
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: 'اختصاص نقش و استثناهای هر پرسنل'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: selectedEmployee.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'انتخاب پرسنل'),
            items: employees.map((employee) => DropdownMenuItem(value: employee.id, child: Text(employee.fullName))).toList(),
            onChanged: (id) => setState(() => _selectedEmployeeId = id),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: roles.any((role) => role.id == assignedRoleId) ? assignedRoleId : roles.first.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'نقش پرسنل'),
            items: roles.map((role) => DropdownMenuItem(value: role.id, child: Text(role.name))).toList(),
            onChanged: (roleId) {
              if (roleId == null) return;
              _saveAssignment(db, selectedEmployee.id, roleId, assignment?.overrides ?? const {},
                assignment?.canViewOtherEmployees ?? false, assignment?.canViewPersonalIncome ?? true);
            },
          ),
          const SizedBox(height: 8),
          Material(color: Colors.transparent, child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('مشاهده اطلاعات سایر کارکنان', style: TextStyle(fontSize: 11)),
            value: assignment?.canViewOtherEmployees ?? false,
            onChanged: (value) => _saveAssignment(db, selectedEmployee.id, assignedRole.id, assignment?.overrides ?? const {}, value, assignment?.canViewPersonalIncome ?? true),
          )),
          Material(color: Colors.transparent, child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('مشاهده درآمد شخصی', style: TextStyle(fontSize: 11)),
            value: assignment?.canViewPersonalIncome ?? true,
            onChanged: (value) => _saveAssignment(db, selectedEmployee.id, assignedRole.id, assignment?.overrides ?? const {}, assignment?.canViewOtherEmployees ?? false, value),
          )),
          const Divider(),
          Text('استثناهای دسترسی (فعال‌سازی یا منع صریح)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pal.textPrimary)),
          for (final permission in AccessPermission.all)
            Material(color: Colors.transparent, child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(permission.label, style: TextStyle(fontSize: 10, color: pal.textSecondary)),
              tristate: true,
              value: assignment?.overrides.containsKey(permission.id) == true ? assignment!.overrides[permission.id] : null,
              onChanged: (value) {
                final overrides = Map<String, bool>.from(assignment?.overrides ?? const {});
                if (value == null) { overrides.remove(permission.id); } else { overrides[permission.id] = value; }
                _saveAssignment(db, selectedEmployee.id, assignedRole.id, overrides,
                  assignment?.canViewOtherEmployees ?? false, assignment?.canViewPersonalIncome ?? true);
              },
            )),
          Text('سه حالت: خالی = پیروی از نقش، تیک = اجازه، خط = منع.', style: TextStyle(fontSize: 10, color: pal.textMuted)),
        ])),
      ]),
    );
  }

  Future<void> _saveAssignment(AppDatabase db, String employeeId, String roleId, Map<String, bool> overrides, bool other, bool income) async {
    final employee = db.employeeById(employeeId);
    final previous = db.accessAssignmentFor(employeeId);
    final oldRole = db.accessRoleById(previous?.roleId ?? 'staff')?.name ?? 'پرسنل';
    final newRole = db.accessRoleById(roleId)?.name ?? roleId;
    final confirmed = await showSensitiveOperationDialog(
      context,
      title: 'تغییر نقش و سطح دسترسی',
      description: 'این تغییر بلافاصله روی دسترسی صفحه‌ها، اطلاعات پرسنل و داده‌های مالی اثر می‌گذارد.',
      recordDetails: {
        'پرسنل': employee?.fullName ?? employeeId,
        'نقش قبلی': oldRole,
        'نقش جدید': newRole,
        'مشاهده سایر پرسنل': other ? 'مجاز' : 'ممنوع',
        'مشاهده درآمد شخصی': income ? 'مجاز' : 'ممنوع',
        'استثناهای دسترسی': overrides.length.toString(),
      },
      isReversible: true,
      confirmLabel: 'ثبت تغییر دسترسی',
    );
    if (!confirmed || !mounted) return;
    try {
      await OperationsRepository(db).assignEmployeeRole(
        employeeId: employeeId,
        roleId: roleId,
        overrides: overrides,
        canViewOtherEmployees: other,
        canViewPersonalIncome: income,
      );
      if (mounted) {
        showUndoableOperationSnackBar(
          context,
          message: 'سطح دسترسی پرسنل به‌روزرسانی شد.',
          onUndo: () {
            OperationsRepository(db).undoLatestForEntity(employeeId);
            if (mounted) setState(() {});
          },
        );
      }
    } catch (error) {
      if (mounted) AppToast.show(context, '$error', success: false);
    }
  }

  Future<void> _toggleRolePermission(AppDatabase db, AccessRole role, String id, bool enabled) async {
    final permissionMatches = AccessPermission.all.where((item) => item.id == id).toList();
    final permission = permissionMatches.isEmpty ? null : permissionMatches.first;
    final ids = role.permissionIds.toSet();
    enabled ? ids.add(id) : ids.remove(id);
    final confirmed = await showSensitiveOperationDialog(
      context,
      title: 'تغییر مجوز نقش',
      description: 'با این تغییر، دسترسی تمام حساب‌هایی که از این نقش استفاده می‌کنند به‌روزرسانی می‌شود.',
      recordDetails: {
        'نقش': role.name,
        'مجوز': permission?.label ?? id,
        'وضعیت جدید': enabled ? 'فعال' : 'غیرفعال',
      },
      isReversible: true,
      confirmLabel: 'ثبت مجوز',
    );
    if (!confirmed || !mounted) return;
    try {
      await OperationsRepository(db).updateAccessRole(role.id, name: role.name, permissionIds: ids.toList());
      if (mounted) {
        showUndoableOperationSnackBar(
          context,
          message: 'مجوز نقش تغییر کرد.',
          onUndo: () {
            OperationsRepository(db).undoLatestForEntity(role.id);
            if (mounted) setState(() {});
          },
        );
      }
    } catch (error) {
      if (mounted) AppToast.show(context, '$error', success: false);
    }
  }

  Future<void> _createRole() async {
    final name = TextEditingController();
    final created = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('ساخت نقش سفارشی'),
      content: TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'نام نقش')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ایجاد')),
      ],
    ));
    if (created == true && mounted) {
      try {
        context.read<AppDatabase>().createAccessRole(name: name.text, permissionIds: const []);
        AppToast.show(context, 'نقش جدید ساخته شد.');
      } catch (error) { AppToast.show(context, '$error', success: false); }
    }
    name.dispose();
  }

  Future<void> _renameRole(AccessRole role) async {
    final name = TextEditingController(text: role.name);
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('ویرایش نقش سفارشی'),
      content: TextField(controller: name, decoration: const InputDecoration(labelText: 'نام نقش')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ذخیره')),
      ],
    ));
    if (saved == true && mounted) {
      final db = context.read<AppDatabase>();
      try { await OperationsRepository(db).updateAccessRole(role.id, name: name.text, permissionIds: role.permissionIds); }
      catch (error) { AppToast.show(context, '$error', success: false); }
    }
    name.dispose();
  }

  Future<void> _resetRole(AppDatabase db, AccessRole role) async {
    final confirmed = await showSensitiveOperationDialog(
      context,
      title: 'بازنشانی نقش',
      description: 'تمام مجوزهای سفارشی این نقش با مقادیر پیش‌فرض جایگزین می‌شوند.',
      recordDetails: {'نقش': role.name, 'تعداد مجوز فعلی': role.permissionIds.length.toString()},
      isReversible: true,
      confirmLabel: 'بازنشانی نقش',
    );
    if (!confirmed || !mounted) return;
    try {
      await OperationsRepository(db).resetAccessRole(role.id);
      if (mounted) {
        showUndoableOperationSnackBar(
          context,
          message: 'مجوزهای نقش بازنشانی شد.',
          onUndo: () {
            OperationsRepository(db).undoLatestForEntity(role.id);
            if (mounted) setState(() {});
          },
        );
      }
    } catch (error) {
      if (mounted) AppToast.show(context, '$error', success: false);
    }
  }
}
