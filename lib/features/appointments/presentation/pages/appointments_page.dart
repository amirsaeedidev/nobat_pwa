import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_inputs.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/pagination_bar.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/appointment.dart';
import '../../../../data/models/enums.dart';
import '../../../employees/presentation/providers/employees_provider.dart';
import '../../../services/presentation/providers/services_provider.dart';
import '../providers/appointments_provider.dart';
import '../widgets/appointment_tile.dart';
import 'appointment_actions.dart';

/// مدیریت نوبت‌ها با جست‌وجو، فیلتر، صفحه‌بندی و نمای جدول در دسکتاپ.
class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppointmentsProvider>();
    final services = context.watch<ServicesProvider>();
    final employees = context.watch<EmployeesProvider>();
    final db = context.watch<AppDatabase>();
    final pal = context.pal;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    final filters = AppCard(
      padding: const EdgeInsets.all(12),
      child: provider.loading
          ? const LoadingState(kind: SkeletonKind.appointments)
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchField(
            controller: _searchController,
            hint: 'جست‌وجوی نام مشتری، شماره یا کد پیگیری...',
            onChanged: provider.setQuery,
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('وضعیت نوبت', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: pal.textPrimary)),
              Text('انتخاب وضعیت برای محدودکردن فهرست', style: TextStyle(fontSize: 9.5, color: pal.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _AppointmentStatusChip(label: 'همه', count: db.appointments.length, selected: provider.filter.status == null, color: pal.primaryBright, onTap: () => provider.setStatus(null)),
              const SizedBox(width: 7),
              for (final status in AppointmentStatus.values) ...[
                _AppointmentStatusChip(
                  label: status.label,
                  count: db.appointments.where((a) => a.status == status).length,
                  selected: provider.filter.status == status,
                  color: status.color,
                  onTap: () => provider.setStatus(status),
                ),
                const SizedBox(width: 7),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('فیلترهای تکمیلی', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: pal.textPrimary)),
              const Spacer(),
              if (provider.filter.activeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: pal.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text('${FaNum.ofInt(provider.filter.activeCount)} فیلتر فعال', style: TextStyle(fontSize: 9.5, color: pal.primaryBright, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterDropdown<String?>(
                icon: Icons.content_cut_rounded,
                value: provider.filter.serviceId,
                hint: 'همه خدمات',
                items: [null, ...services.items.map((s) => s.id)],
                labelOf: (id) => id == null ? 'همه خدمات' : services.items.firstWhere((s) => s.id == id).title,
                onChanged: provider.setService,
              ),
              _FilterDropdown<String?>(
                icon: Icons.badge_outlined,
                value: provider.filter.employeeId,
                hint: 'همه متخصصان',
                items: [null, ...employees.items.map((e) => e.id)],
                labelOf: (id) => id == null ? 'همه متخصصان' : employees.items.firstWhere((e) => e.id == id).fullName,
                onChanged: provider.setEmployee,
              ),
              SoftButton(
                label: provider.filter.activeCount == 0 ? 'پاک‌کردن فیلترها' : 'پاک‌کردن (${FaNum.ofInt(provider.filter.activeCount)})',
                icon: Icons.close_rounded,
                onTap: () {
                  _searchController.clear();
                  provider.clearFilters();
                },
              ),
              SoftButton(
                label: 'ترتیب زمان',
                icon: Icons.swap_vert_rounded,
                onTap: provider.toggleSort,
              ),
            ],
          ),
        ],
      ),
    );

    return PageScaffold(
      title: 'نوبت‌ها',
      subtitle: 'مدیریت و پیگیری همه نوبت‌ها',
      icon: Icons.event_note_rounded,
      actions: [
        SoftButton(label: 'تقویم', icon: Icons.calendar_month_rounded, onTap: () => context.go('/calendar')),
        SolidButton(
          label: 'نوبت جدید',
          icon: Icons.add_rounded,
          height: 42,
          onPressed: () => context.push('/appointments/new'),
        ),
      ],
      showBackButton: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filters,
          const SizedBox(height: 12),
          if (!isDesktop) ...[
            GradientCta(
              title: 'ثبت نوبت جدید',
              subtitle: 'رزرو سریع در چند ثانیه',
              height: 66,
              compact: false,
              onPressed: () => context.push('/appointments/new'),
            ),
            const SizedBox(height: 12),
          ],
          AppCard(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: SectionHeader(title: 'فهرست نوبت‌ها')),
                    CountPill(value: provider.page.total, icon: Icons.event_available_rounded),
                  ],
                ),
                const SizedBox(height: 10),
                if (provider.loadNotice != null)
            OfflineDataNotice(message: provider.loadNotice!)
          if (provider.loading)
                  const LoadingState(compact: true, kind: SkeletonKind.appointments)
                else if (provider.items.isEmpty && provider.loadNotice != null)
                  ErrorStateView(description: provider.loadNotice, onRetry: provider.load)
                else if (provider.items.isEmpty)
                  const EmptyState(
                    title: 'نوبتی یافت نشد',
                    description: 'فیلترها را تغییر دهید یا نوبت جدیدی ثبت کنید.',
                  )
                else if (isDesktop)
                  _AppointmentsTable(items: provider.items)
                else
                  for (final appointment in provider.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Dismissible(
                        key: ValueKey('appointment-${appointment.id}'),
                        direction: DismissDirection.horizontal,
                        confirmDismiss: (direction) async {
                          // در رابط راست‌به‌چپ، startToEnd یعنی کشیدن کارت به سمت چپ: تأیید.
                          if (direction == DismissDirection.startToEnd) return true;
                          final action = await showModalBottomSheet<String>(
                            context: context,
                            backgroundColor: pal.surface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                            ),
                            builder: (sheetContext) => SafeArea(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                const SizedBox(height: 12),
                                ListTile(
                                  leading: Icon(Icons.event_busy_rounded, color: pal.danger),
                                  title: const Text('لغو نوبت'),
                                  onTap: () => Navigator.pop(sheetContext, 'cancel'),
                                ),
                                ListTile(
                                  leading: Icon(Icons.edit_calendar_rounded, color: pal.primaryBright),
                                  title: const Text('جابه‌جایی نوبت'),
                                  onTap: () => Navigator.pop(sheetContext, 'move'),
                                ),
                                const SizedBox(height: 8),
                              ]),
                            ),
                          );
                          if (action == 'cancel') {
                            final previousStatus = appointment.status;
                            await provider.changeStatus(
                              appointment,
                              AppointmentStatus.cancelled,
                              reason: 'لغو با کشیدن کارت',
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: const Text('نوبت لغو شد'),
                                behavior: SnackBarBehavior.floating,
                                action: SnackBarAction(label: 'برگشت', onPressed: () => provider.changeStatus(appointment, previousStatus, reason: 'بازگردانی لغو نوبت')),
                              ));
                            }
                          } else if (action == 'move' && context.mounted) {
                            context.push('/appointments/${appointment.id}/edit');
                          }
                          return false;
                        },
                        onDismissed: (_) async {
                          final previousStatus = appointment.status;
                          await provider.changeStatus(appointment, AppointmentStatus.confirmed);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                content: const Text('نوبت تأیید شد'),
                                behavior: SnackBarBehavior.floating,
                                action: SnackBarAction(
                                  label: 'برگشت',
                                  onPressed: () => provider.changeStatus(appointment, previousStatus, reason: 'بازگردانی وضعیت نوبت'),
                                ),
                              ));
                          }
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: pal.success,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white),
                            SizedBox(width: 8),
                            Text('تأیید', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        secondaryBackground: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: pal.danger,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                            Icon(Icons.more_horiz_rounded, color: Colors.white),
                            SizedBox(width: 8),
                            Text('لغو / جابه‌جایی', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        child: AppointmentTile(
                          appointment: appointment,
                          onTap: () => context.push('/appointments/${appointment.id}'),
                          onMore: () => showAppointmentActions(context, appointment),
                        ),
                      ),
                    ),
                const SizedBox(height: 10),
                PaginationBar(
                  page: provider.pageNumber,
                  totalPages: provider.page.totalPages,
                  totalItems: provider.page.total,
                  pageSize: provider.page.pageSize,
                  onPageChanged: provider.goToPage,
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentStatusChip extends StatelessWidget {
  const _AppointmentStatusChip({required this.label, required this.count, required this.selected, required this.color, required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Material(
      color: selected ? color.withValues(alpha: 0.16) : pal.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: selected ? color : pal.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected) Icon(Icons.check_circle_rounded, size: 14, color: color)
            else Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? color : pal.textSecondary)),
            const SizedBox(width: 5),
            Text(FaNum.ofInt(count), style: TextStyle(fontSize: 10, color: selected ? color : pal.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    required this.hint,
  });

  final IconData icon;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final maxWidth = MediaQuery.sizeOf(context).width < 600 ? 220.0 : 280.0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: pal.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: pal.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: pal.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  dropdownColor: pal.surfaceAlt,
                  borderRadius: AppRadius.brSm,
                  isDense: true,
                  style: TextStyle(fontSize: 11.5, color: pal.textPrimary, fontFamily: 'Lalezar'),
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: pal.textMuted),
                  items: [
                    for (final item in items)
                      DropdownMenuItem<T>(
                        value: item,
                        child: Text(labelOf(item), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: pal.textPrimary)),
                      ),
                  ],
                  onChanged: (v) => onChanged(v as T),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentsTable extends StatelessWidget {
  const _AppointmentsTable({required this.items});

  final List<Appointment> items;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    const flex = [3, 3, 3, 2, 2, 2];
    return Column(
      children: [
        const TableHeaderRow(
          cells: ['مشتری', 'خدمت', 'متخصص', 'تاریخ', 'ساعت', 'وضعیت'],
          flex: flex,
        ),
        for (final appointment in items)
          InkWell(
            onTap: () => context.push('/appointments/${appointment.id}'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: pal.border.withValues(alpha: 0.6))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: flex[0],
                    child: Row(
                      children: [
                        AvatarBadge(name: appointment.customerName, size: 30, color: pal.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appointment.customerName,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                Fmt.phone(appointment.customerPhone),
                                style: TextStyle(fontSize: 9.5, color: pal.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: flex[1],
                    child: Text(
                      appointment.serviceName,
                      style: TextStyle(fontSize: 11.5, color: pal.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: flex[2],
                    child: Text(
                      appointment.employeeName,
                      style: TextStyle(fontSize: 11.5, color: pal.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: flex[3],
                    child: Text(
                      appointment.jalali.short,
                      style: TextStyle(fontSize: 11, color: pal.textSecondary),
                    ),
                  ),
                  Expanded(
                    flex: flex[4],
                    child: Text(
                      Fmt.time(appointment.startAt.hour, appointment.startAt.minute),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: pal.textPrimary),
                    ),
                  ),
                  Expanded(
                    flex: flex[5],
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: StatusBadge.appointment(appointment.status, dense: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
