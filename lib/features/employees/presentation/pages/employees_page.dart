import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/enums.dart';
import '../../../services/presentation/providers/services_provider.dart';
import '../providers/employees_provider.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});
  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  final _search = TextEditingController();
  EmployeeStatus? _status;
  String? _specialty;
  String _sort = 'name';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmployeesProvider>();
    final services = context.watch<ServicesProvider>();
    final pal = context.pal;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final specialties = provider.items.expand((employee) => employee.specialties).toSet().toList()..sort();
    final query = _search.text.trim().toLowerCase();
    final filtered = provider.items.where((employee) {
      final matchesQuery = query.isEmpty || employee.fullName.toLowerCase().contains(query) ||
          employee.phone.replaceAll(' ', '').contains(query.replaceAll(' ', ''));
      final matchesStatus = _status == null || employee.employmentStatus == _status;
      final matchesSpecialty = _specialty == null || employee.specialties.contains(_specialty);
      return matchesQuery && matchesStatus && matchesSpecialty;
    }).toList();
    switch (_sort) {
      case 'start':
        filtered.sort((a, b) => (b.startedAt ?? DateTime(1900)).compareTo(a.startedAt ?? DateTime(1900)));
        break;
      case 'performance':
        filtered.sort((a, b) => b.bookedCount.compareTo(a.bookedCount));
        break;
      default:
        filtered.sort((a, b) => a.fullName.compareTo(b.fullName));
    }

    return PageScaffold(
      title: 'مدیریت پرسنل',
      subtitle: '${FaNum.ofInt(provider.activeCount)} پرسنل فعال از ${FaNum.ofInt(provider.totalCount)} نفر',
      icon: Icons.badge_rounded,
      actions: [
        SoftButton(label: 'ساعات کاری', icon: Icons.schedule_rounded, onTap: () => context.push('/settings/hours')),
        SolidButton(label: 'پرسنل جدید', icon: Icons.person_add_alt_1_rounded, height: 42,
            onPressed: () => context.push('/employees/new')),
      ],
      mobileActions: [
        CircleIconButton(icon: Icons.person_add_alt_1_rounded, size: 38, onTap: () => context.push('/employees/new')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: isDesktop ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: isDesktop ? 2.7 : 2.2,
            children: [
              _CountCard(title: 'کل پرسنل', value: provider.totalCount, icon: Icons.groups_rounded, color: pal.primaryBright),
              _CountCard(title: 'فعال', value: provider.activeCount, icon: Icons.check_circle_outline, color: pal.success),
              _CountCard(title: 'در مرخصی', value: provider.onLeaveCount, icon: Icons.event_busy_outlined, color: pal.warning),
              _CountCard(title: 'غیرفعال / تعلیق', value: provider.inactiveCount + provider.suspendedCount, icon: Icons.pause_circle_outline, color: pal.textMuted),
            ],
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'جستجوی نام یا شماره موبایل...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty ? null : IconButton(
                      onPressed: () { _search.clear(); setState(() {}); },
                      icon: const Icon(Icons.close_rounded),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(label: 'همه وضعیت‌ها', selected: _status == null, onTap: () => setState(() => _status = null)),
                    for (final status in EmployeeStatus.values)
                      _FilterChip(label: status.label, selected: _status == status, onTap: () => setState(() => _status = status)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _specialty,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'فیلتر تخصص', isDense: true),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('همه تخصص‌ها')),
                          for (final item in specialties) DropdownMenuItem(value: item, child: Text(item)),
                        ],
                        onChanged: (value) => setState(() => _specialty = value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sort,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'مرتب‌سازی', isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'name', child: Text('نام')),
                          DropdownMenuItem(value: 'start', child: Text('تاریخ همکاری')),
                          DropdownMenuItem(value: 'performance', child: Text('تعداد نوبت')),
                        ],
                        onChanged: (value) => setState(() => _sort = value ?? 'name'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (provider.loading)
            const LoadingState()
          else if (provider.items.isEmpty)
            const EmptyState(title: 'پرسنلی ثبت نشده', description: 'اولین عضو تیم را اضافه کنید.')
          else if (filtered.isEmpty)
            const EmptyState(title: 'نتیجه‌ای پیدا نشد', description: 'فیلترها یا عبارت جستجو را تغییر دهید.')
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final employee in filtered)
                  SizedBox(
                    width: isDesktop ? 420 : double.infinity,
                    child: EmployeeCard(
                      employee: employee,
                      serviceTitles: services.items.where((service) => employee.serviceIds.contains(service.id)).map((service) => service.title).toList(),
                      onTap: () => context.push('/employees/${employee.id}'),
                      onEdit: () => context.push('/employees/${employee.id}/edit'),
                      onDelete: () async {
                        final confirmed = await showConfirmDialog(
                          context,
                          title: 'حذف یا بایگانی پرسنل',
                          message: 'در صورت وجود نوبت یا سابقه، پروفایل به‌جای حذف کامل بایگانی می‌شود. ادامه می‌دهید؟',
                          confirmLabel: 'ادامه',
                          destructive: true,
                        );
                        if (confirmed && context.mounted) {
                          await provider.remove(employee.id);
                          if (context.mounted) AppToast.show(context, 'عملیات حذف یا بایگانی انجام شد.');
                        }
                      },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          AppCard(
            color: pal.surfaceAlt.withValues(alpha: 0.4),
            child: Row(
              children: [
                Icon(Icons.security_rounded, size: 15, color: pal.primaryBright),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'سوابق نوبت پرسنل حفظ می‌شود؛ در صورت وجود سابقه، حذف به‌صورت بایگانی انجام خواهد شد.',
                  style: TextStyle(fontSize: 10.5, color: pal.textMuted, height: 1.7),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final int value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Row(children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(title, style: TextStyle(fontSize: 10, color: context.pal.textMuted)),
        Text(FaNum.ofInt(value), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: context.pal.textPrimary)),
      ])),
    ]),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
}

class EmployeeCard extends StatelessWidget {
  const EmployeeCard({super.key, required this.employee, required this.serviceTitles, this.onTap, this.onEdit, this.onDelete});
  final Employee employee;
  final List<String> serviceTitles;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final color = Color(employee.colorValue);
    final workDays = [for (var i = 0; i < 7; i++) if (employee.worksOn(i)) i];
    final statusColor = switch (employee.employmentStatus) {
      EmployeeStatus.active => pal.success,
      EmployeeStatus.onLeave => pal.warning,
      EmployeeStatus.suspended => pal.danger,
      EmployeeStatus.inactive => pal.textMuted,
    };
    return AppCard(
      onTap: onTap,
      radius: AppRadius.xl,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 48, height: 48, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.6)])),
            child: Text(employee.initials, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(employee.fullName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: pal.textPrimary)),
            Text('${employee.title} • ${employee.role.label}', style: TextStyle(fontSize: 10.5, color: pal.textMuted)),
          ])),
          StatusBadge(label: employee.employmentStatus.label, color: statusColor, dense: true),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 6, children: [
          _Meta(icon: Icons.star_rounded, text: FaNum.convert(employee.rating.toStringAsFixed(1))),
          _Meta(icon: Icons.event_available_rounded, text: '${FaNum.ofInt(employee.bookedCount)} نوبت'),
          _Meta(icon: Icons.call_outlined, text: Fmt.phone(employee.phone)),
        ]),
        if (employee.specialties.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [for (final skill in employee.specialties.take(3)) StatusBadge(label: skill, color: pal.primaryBright, dense: true)]),
        ],
        if (serviceTitles.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [for (final title in serviceTitles.take(4)) StatusBadge(label: title, color: pal.success, dense: true)]),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [for (final day in workDays) Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: pal.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: pal.border)),
          child: Text(WeekDay.shortNames[day], style: TextStyle(fontSize: 9.5, color: pal.textSecondary, fontWeight: FontWeight.w600)),
        )]),
        const SizedBox(height: 12),
        Divider(color: pal.border.withValues(alpha: 0.8), height: 1),
        const SizedBox(height: 10),
        Row(children: [
          SoftButton(label: 'ویرایش', icon: Icons.edit_rounded, dense: true, onTap: onEdit),
          const SizedBox(width: 8),
          SoftButton(label: 'حذف / بایگانی', icon: Icons.archive_outlined, dense: true, color: pal.danger, onTap: onDelete),
          const Spacer(),
          Text('مشاهده پروفایل', style: TextStyle(fontSize: 10, color: pal.primaryBright, fontWeight: FontWeight.w600)),
          Icon(Icons.chevron_left_rounded, size: 14, color: pal.primaryBright),
        ]),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: context.pal.textMuted),
    const SizedBox(width: 3),
    Text(text, style: TextStyle(fontSize: 10.5, color: context.pal.textMuted)),
  ]);
}
