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
import '../../../../data/models/service.dart';
import '../../../../data/mock/app_database.dart';
import '../providers/services_provider.dart';

/// مدیریت خدمات — بازسازی صفحه «مدیریت خدمات» تصویر مرجع.
class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServicesProvider>();
    final pal = context.pal;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final services = provider.filtered;

    return PageScaffold(
      title: 'مدیریت خدمات',
      subtitle: '${FaNum.ofInt(provider.activeCount)} خدمت فعال از ${FaNum.ofInt(provider.items.length)}',
      icon: Icons.content_cut_rounded,
      actions: [
        SoftButton(label: 'دسته‌بندی‌ها', icon: Icons.category_outlined, onTap: () => _manageCategories(context)),
        SoftButton(label: 'بازآوری', icon: Icons.refresh_rounded, onTap: provider.load),
        SolidButton(
          label: 'خدمت جدید',
          icon: Icons.add_rounded,
          height: 42,
          onPressed: () => context.push('/services/new'),
        ),
        CircleIconButton(icon: Icons.settings_rounded, size: 38, onTap: () => context.push('/settings')),
      ],
      mobileActions: [
        CircleIconButton(icon: Icons.category_outlined, size: 38, onTap: () => _manageCategories(context)),
        CircleIconButton(icon: Icons.refresh_rounded, size: 38, onTap: provider.load),
        CircleIconButton(icon: Icons.add_rounded, size: 38, onTap: () => context.push('/services/new')),
      ],
      leading: CircleIconButton(icon: Icons.settings_rounded, size: 40, onTap: () => context.push('/settings')),
      child: provider.loading
          ? const LoadingState(kind: SkeletonKind.services)
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchField(
            controller: TextEditingController(text: provider.query),
            hint: 'جست‌وجوی خدمت...',
            onChanged: provider.search,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  value: provider.categoryFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'دسته‌بندی', isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('همه دسته‌ها')),
                    ...provider.categories.map((name) => DropdownMenuItem<String?>(value: name, child: Text(name))),
                  ],
                  onChanged: provider.setCategoryFilter,
                ),
              ),
              SizedBox(width: 120, child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'حداقل قیمت', isDense: true),
                onChanged: (value) => provider.setPriceRange(
                  minimum: value.trim().isEmpty ? null : num.tryParse(FaNum.toLatin(value)),
                  maximum: provider.maximumPrice,
                ),
              )),
              SizedBox(width: 120, child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'حداکثر قیمت', isDense: true),
                onChanged: (value) => provider.setPriceRange(
                  minimum: provider.minimumPrice,
                  maximum: value.trim().isEmpty ? null : num.tryParse(FaNum.toLatin(value)),
                ),
              )),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              PillToggle(
                options: const ['همه خدمات', 'فقط فعال', 'فقط غیرفعال'],
                selectedIndex: provider.inactiveOnly ? 2 : (provider.activeOnly ? 1 : 0),
                onChanged: (i) {
                  if (i == 2) {
                    provider.setInactiveOnly(true);
                  } else {
                    provider.setActiveOnly(i == 1);
                  }
                },
                dense: true,
              ),
              Text(
                '${FaNum.ofInt(services.length)} خدمت',
                style: TextStyle(fontSize: 11, color: pal.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (provider.loadNotice != null)
            OfflineDataNotice(message: provider.loadNotice!),
          if (services.isEmpty && provider.loadNotice != null)
            ErrorStateView(description: provider.loadNotice, onRetry: provider.load)
          else if (services.isEmpty)
            const EmptyState(
              title: 'خدمتی یافت نشد',
              description: 'خدمت جدیدی اضافه کنید یا فیلتر را تغییر دهید.',
              icon: Icons.content_cut_rounded,
            )
          else if (isDesktop)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final service in services)
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 246 - 56 - 12) / 2 > 460
                        ? 460
                        : (MediaQuery.sizeOf(context).width - 246 - 56 - 12) / 2,
                    child: ServiceCard(
                      service: service,
                      onEdit: () => context.push('/services/${service.id}/edit'),
                      onDetails: () => context.push('/services/${service.id}'),
                      onDelete: () => _delete(context, service),
                      onToggle: () => provider.toggle(service.id, !service.isActive),
                    ),
                  ),
              ],
            )
          else
            for (final service in services) ...[
              ServiceCard(
                service: service,
                onEdit: () => context.push('/services/${service.id}/edit'),
                onDetails: () => context.push('/services/${service.id}'),
                onDelete: () => _delete(context, service),
                onToggle: () => provider.toggle(service.id, !service.isActive),
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 6),
          AppCard(
            color: pal.surfaceAlt.withValues(alpha: 0.4),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: pal.primaryBright),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'هر خدمت زمان آماده‌سازی و استراحت اختصاصی دارد و در محاسبه خانه‌های زمانی لحاظ می‌شود.',
                    style: TextStyle(fontSize: 10.5, color: pal.textMuted, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manageCategories(BuildContext context) async {
    final provider = context.read<ServicesProvider>();
    final controller = TextEditingController();
    String? selected = provider.categories.isEmpty ? null : provider.categories.first;
    String? moveTo;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('مدیریت دسته‌بندی خدمات'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: controller, decoration: const InputDecoration(labelText: 'نام دسته‌بندی جدید / نام جدید')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'دسته‌بندی برای ویرایش یا حذف'),
            items: provider.categories.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
            onChanged: (value) => setDialogState(() { selected = value; moveTo = null; }),
          ),
          if (selected != null) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: moveTo,
              decoration: const InputDecoration(labelText: 'انتقال خدمات وابسته هنگام حذف'),
              items: provider.categories.where((item) => item != selected).map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
              onChanged: (value) => setDialogState(() => moveTo = value),
            ),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بستن')),
          TextButton(onPressed: () {
            try { provider.addCategory(controller.text); Navigator.pop(dialogContext); }
            catch (error) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
          }, child: const Text('افزودن')),
          TextButton(onPressed: selected == null ? null : () {
            try { provider.renameCategory(selected!, controller.text); Navigator.pop(dialogContext); }
            catch (error) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
          }, child: const Text('تغییر نام')),
          TextButton(onPressed: selected == null ? null : () {
            try { provider.deleteCategory(selected!, moveServicesTo: moveTo); Navigator.pop(dialogContext); }
            catch (error) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString()))); }
          }, child: const Text('حذف')),
        ],
      ),
    ));
    controller.dispose();
  }

  Future<void> _delete(BuildContext context, Service service) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف خدمت',
      message: 'آیا از حذف «${service.title}» مطمئن هستید؟ این اقدام قابل بازگشت نیست.',
      confirmLabel: 'حذف',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed && context.mounted) {
      await context.read<ServicesProvider>().remove(service.id);
      if (context.mounted) AppToast.show(context, 'خدمت حذف شد', success: false);
    }
  }
}

/// کارت خدمت مطابق تصویر مرجع.
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.service,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onDetails,
  });

  final Service service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final db = context.watch<AppDatabase>();
    final bookingCount = db.appointments.where((item) => item.serviceIds.contains(service.id)).length;
    final serviceRevenue = db.employeeFinanceEntries.where((item) => item.serviceId == service.id).fold<int>(0, (sum, item) => sum + item.receivedAmount);
    return AppCard(
      radius: AppRadius.xl,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: Icons.content_cut_rounded, color: pal.primary, size: 46, radius: 15),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: pal.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _MetaItem(
                          icon: Icons.sell_outlined,
                          label: Fmt.money(service.priceAt(DateTime.now())),
                          color: pal.primaryBright,
                        ),
                        _MetaItem(
                          icon: Icons.timelapse_rounded,
                          label: Fmt.duration(service.durationMinutes),
                          color: pal.textSecondary,
                        ),
                        _MetaItem(
                          icon: Icons.category_outlined,
                          label: service.category,
                          color: pal.textMuted,
                        ),
                        _MetaItem(icon: Icons.event_available_outlined, label: FaNum.ofInt(bookingCount) + ' نوبت', color: pal.textSecondary),
                        _MetaItem(icon: Icons.account_balance_wallet_outlined, label: Fmt.money(serviceRevenue), color: pal.success),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onToggle,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: pal.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: pal.primary.withValues(alpha: 0.28)),
                  ),
                  child: Icon(
                    service.isActive ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    size: 19,
                    color: pal.primaryBright,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: pal.border.withValues(alpha: 0.8), height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SoftButton(label: 'جزئیات', icon: Icons.visibility_outlined, dense: true, onTap: onDetails),
              SoftButton(label: 'ویرایش', icon: Icons.edit_rounded, dense: true, onTap: onEdit),
              SoftButton(
                label: 'حذف',
                icon: Icons.delete_outline_rounded,
                dense: true,
                color: pal.danger,
                onTap: onDelete,
              ),
              StatusBadge(
                label: service.isActive ? 'فعال' : 'غیرفعال',
                color: service.isActive ? pal.success : pal.textMuted,
                dense: true,
                icon: service.isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
