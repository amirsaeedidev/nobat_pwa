import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_inputs.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/models/service.dart';
import '../../../../data/models/employee_service_config.dart';
import '../../../employees/presentation/providers/employees_provider.dart';
import '../providers/services_provider.dart';

/// فرم افزودن/ویرایش خدمت با تنظیمات اختصاصی زمان‌بندی و قواعد رزرو.
class ServiceFormPage extends StatefulWidget {
  const ServiceFormPage({super.key, this.serviceId});

  final String? serviceId;

  @override
  State<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends State<ServiceFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _directCost = TextEditingController();
  final _imageUrl = TextEditingController();
  final _discountPrice = TextEditingController();
  final _discountStartsAt = TextEditingController();
  final _discountEndsAt = TextEditingController();
  final _duration = TextEditingController(text: '45');
  final _prep = TextEditingController(text: '0');
  final _buffer = TextEditingController(text: '5');
  final _maxPerDay = TextEditingController();
  final _advanceDays = TextEditingController(text: '30');

  String _category = '';
  bool _isActive = true;
  bool _requiresConfirmation = false;
  List<String> _employeeIds = [];
  final Map<String, _EmployeeServiceFields> _employeeFields = {};
  bool _saving = false;



  bool _loadingExisting = false;
  String? _loadError;
  Service? _existing;

  @override
  void initState() {
    super.initState();
    if (widget.serviceId != null) {
      _loadingExisting = true;
      unawaited(_loadExisting());
    }
  }

  Future<void> _loadExisting() async {
    try {
      final provider = context.read<ServicesProvider>();
      await provider.load();
      final service = await provider.byId(widget.serviceId!);
      if (!mounted) return;
      if (service == null) throw StateError('خدمت در Supabase پیدا نشد یا دسترسی مشاهده آن وجود ندارد.');
      _existing = service;
      _title.text = service.title;
      _description.text = service.description;
      _price.text = service.price.toString();
      _directCost.text = service.directCost?.toString() ?? '';
      _imageUrl.text = service.imageUrl ?? '';
      _discountPrice.text = service.discountPrice?.toString() ?? '';
      _discountStartsAt.text = service.discountStartsAt == null ? '' : _dateOnly(service.discountStartsAt!);
      _discountEndsAt.text = service.discountEndsAt == null ? '' : _dateOnly(service.discountEndsAt!);
      _duration.text = service.durationMinutes.toString();
      _prep.text = service.prepMinutes.toString();
      _buffer.text = service.bufferMinutes.toString();
      _maxPerDay.text = service.maxPerDay?.toString() ?? '';
      _advanceDays.text = service.advanceDays.toString();
      _category = service.category;
      _isActive = service.isActive;
      _requiresConfirmation = service.requiresConfirmation;
      _employeeIds = [...service.employeeIds];
      if (mounted) setState(() { _loadingExisting = false; _loadError = null; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loadingExisting = false; _loadError = error.toString(); });
    }
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _directCost.dispose();
    _imageUrl.dispose();
    _discountPrice.dispose();
    _discountStartsAt.dispose();
    _discountEndsAt.dispose();
    _duration.dispose();
    _prep.dispose();
    _buffer.dispose();
    _maxPerDay.dispose();
    _advanceDays.dispose();
    for (final fields in _employeeFields.values) {
      fields.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category.trim().isEmpty) {
      AppToast.show(context, 'ابتدا یک دسته‌بندی واقعی ایجاد یا انتخاب کنید.', success: false);
      return;
    }
    final discountStart = _discountStartsAt.text.trim().isEmpty ? null : DateTime.tryParse(_discountStartsAt.text.trim());
    final discountEnd = _discountEndsAt.text.trim().isEmpty ? null : DateTime.tryParse(_discountEndsAt.text.trim());
    final discountValue = _discountPrice.text.trim().isEmpty ? null : num.tryParse(FaNum.toLatin(_discountPrice.text));
    final basePrice = num.tryParse(FaNum.toLatin(_price.text)) ?? 0;
    if (discountValue != null && (discountValue < 0 || discountValue >= basePrice)) {
      AppToast.show(context, 'قیمت تخفیفی باید از صفر تا کمتر از قیمت اصلی باشد.', success: false);
      return;
    }
    if (discountStart != null && discountEnd != null && discountEnd.isBefore(discountStart)) {
      AppToast.show(context, 'پایان تخفیف نمی‌تواند قبل از شروع آن باشد', success: false);
      return;
    }
    try {
      for (final employeeId in _employeeIds) {
        final fields = _fieldsFor(employeeId);
        _optionalInteger(fields.price.text, 'قیمت اختصاصی');
        _optionalInteger(fields.duration.text, 'مدت اختصاصی');
        _optionalInteger(fields.fixedCommission.text, 'پورسانت ثابت');
        final rawPercent = fields.commissionPercent.text.trim();
        final percent = rawPercent.isEmpty ? null : num.tryParse(FaNum.toLatin(rawPercent));
        if (rawPercent.isNotEmpty && percent == null) throw ArgumentError('درصد پورسانت باید عددی باشد.');
        if (percent != null && (percent < 0 || percent > 100)) throw ArgumentError('درصد پورسانت باید بین صفر تا صد باشد.');
      }
    } catch (error) {
      AppToast.show(context, error.toString(), success: false);
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<ServicesProvider>();
    final serviceId = _existing?.id ?? provider.nextId();
    final service = (_existing ?? Service(id: serviceId, title: '', price: 0, durationMinutes: 45)).copyWith(
      title: _title.text.trim(),
      description: _description.text.trim(),
      price: num.tryParse(FaNum.toLatin(_price.text)) ?? 0,
      directCost: _directCost.text.trim().isEmpty ? null : num.tryParse(FaNum.toLatin(_directCost.text)),
      clearDirectCost: _directCost.text.trim().isEmpty,
      imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
      clearImageUrl: _imageUrl.text.trim().isEmpty,
      discountPrice: _discountPrice.text.trim().isEmpty ? null : num.tryParse(FaNum.toLatin(_discountPrice.text)),
      clearDiscountPrice: _discountPrice.text.trim().isEmpty,
      discountStartsAt: _discountStartsAt.text.trim().isEmpty ? null : DateTime.tryParse(_discountStartsAt.text.trim()),
      clearDiscountStartsAt: _discountStartsAt.text.trim().isEmpty,
      discountEndsAt: _discountEndsAt.text.trim().isEmpty ? null : DateTime.tryParse(_discountEndsAt.text.trim()),
      clearDiscountEndsAt: _discountEndsAt.text.trim().isEmpty,
      durationMinutes: int.tryParse(FaNum.toLatin(_duration.text)) ?? 45,
      prepMinutes: int.tryParse(FaNum.toLatin(_prep.text)) ?? 0,
      bufferMinutes: int.tryParse(FaNum.toLatin(_buffer.text)) ?? 5,
      maxPerDay: int.tryParse(FaNum.toLatin(_maxPerDay.text)),
      advanceDays: int.tryParse(FaNum.toLatin(_advanceDays.text)) ?? 30,
      category: _category,
      isActive: _isActive,
      requiresConfirmation: _requiresConfirmation,
      employeeIds: _employeeIds,
    );
    try {
      final configs = <EmployeeServiceConfig>[];
      for (final employeeId in _employeeIds) {
        final fields = _fieldsFor(employeeId);
        final rawPercent = fields.commissionPercent.text.trim();
        final percent = rawPercent.isEmpty ? null : num.parse(FaNum.toLatin(rawPercent));
        final previous = provider.employeeServiceConfig(employeeId, serviceId);
        configs.add(EmployeeServiceConfig(
          employeeId: employeeId,
          serviceId: serviceId,
          active: previous?.active ?? true,
          customPrice: _optionalInteger(fields.price.text, 'قیمت اختصاصی'),
          customDurationMinutes: _optionalInteger(fields.duration.text, 'مدت اختصاصی'),
          commissionRateBps: percent == null ? null : (percent * 100).round(),
          fixedCommissionAmount: _optionalInteger(fields.fixedCommission.text, 'پورسانت ثابت'),
          specialtyNote: previous?.specialtyNote ?? '',
        ));
      }
      await provider.saveCatalogItem(service, configs);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.show(context, 'ذخیره تنظیمات خدمت ناموفق بود: $error', success: false);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    AppToast.show(context, _existing != null ? 'خدمت به‌روزرسانی شد' : 'خدمت جدید ثبت شد');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/services');
    }
  }

  _EmployeeServiceFields _fieldsFor(String employeeId) {
    return _employeeFields.putIfAbsent(employeeId, () {
      final config = widget.serviceId == null
          ? null
          : context.read<ServicesProvider>().employeeServiceConfig(employeeId, widget.serviceId!);
      return _EmployeeServiceFields(config);
    });
  }


  int? _optionalInteger(String raw, String label) {
    if (raw.trim().isEmpty) return null;
    final value = int.tryParse(FaNum.toLatin(raw).replaceAll(',', '').trim());
    if (value == null || value < 0) throw ArgumentError('$label باید عددی و صفر یا بیشتر باشد.');
    if (label == 'مدت اختصاصی' && value == 0) throw ArgumentError('$label باید بیشتر از صفر باشد.');
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final employees = context.watch<EmployeesProvider>().items;
    final categories = context.watch<ServicesProvider>().categories;

    if (_loadingExisting) {
      return PageScaffold(title: 'ویرایش خدمت', showBackButton: true,
        child: const LoadingState(kind: SkeletonKind.services));
    }
    if (_loadError != null) {
      return PageScaffold(title: 'ویرایش خدمت', showBackButton: true,
        child: ErrorStateView(description: _loadError, onRetry: () {
          setState(() { _loadingExisting = true; _loadError = null; });
          unawaited(_loadExisting());
        }));
    }

    return PageScaffold(
      title: widget.serviceId == null ? 'خدمت جدید' : 'ویرایش خدمت',
      subtitle: 'تنظیمات قیمت، زمان و قواعد رزرو',
      icon: Icons.content_cut_rounded,
      showBackButton: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final basic = AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(title: 'اطلاعات خدمت'),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _title,
                        label: 'عنوان خدمت',
                        hint: 'مثلاً کراتینه و ویتامینه',
                        icon: Icons.content_cut_rounded,
                        validator: (v) => Validators.required(v, label: 'عنوان خدمت'),
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _description,
                        label: 'توضیحات',
                        hint: 'توضیح کوتاه درباره خدمت...',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _price,
                              label: 'قیمت (تومان)',
                              hint: '۵۵۰۰۰۰',
                              icon: Icons.sell_outlined,
                              keyboardType: TextInputType.number,
                              numericFa: true,
                              validator: Validators.price,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppDropdown<String>(
                              label: 'دسته‌بندی',
                              items: categories,
                              value: categories.contains(_category) ? _category : (categories.isEmpty ? null : categories.first),
                              onChanged: categories.isEmpty ? null : (v) => setState(() => _category = v ?? _category),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _imageUrl,
                        label: 'تصویر خدمت (مسیر فایل یا نشانی تصویر)',
                        hint: 'assets/image/service.png',
                        icon: Icons.image_outlined,
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _discountPrice,
                        label: 'قیمت تخفیفی (تومان)',
                        hint: 'اختیاری',
                        icon: Icons.local_offer_outlined,
                        keyboardType: TextInputType.number,
                        numericFa: true,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final discount = num.tryParse(FaNum.toLatin(value));
                          final price = num.tryParse(FaNum.toLatin(_price.text));
                          if (discount == null || discount < 0 || price == null || discount >= price) {
                            return 'قیمت تخفیفی باید کمتر از قیمت اصلی باشد.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: AppTextField(
                          controller: _discountStartsAt,
                          label: 'شروع تخفیف',
                          hint: 'YYYY-MM-DD',
                          icon: Icons.event_available_outlined,
                          validator: (value) => value != null && value.trim().isNotEmpty && DateTime.tryParse(value.trim()) == null ? 'تاریخ معتبر وارد کنید.' : null,
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: AppTextField(
                          controller: _discountEndsAt,
                          label: 'پایان تخفیف',
                          hint: 'YYYY-MM-DD',
                          icon: Icons.event_busy_outlined,
                          validator: (value) => value != null && value.trim().isNotEmpty && DateTime.tryParse(value.trim()) == null ? 'تاریخ معتبر وارد کنید.' : null,
                        )),
                      ]),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _directCost,
                        label: 'هزینه مستقیم هر بار ارائه (تومان)',
                        hint: 'اختیاری؛ مواد مصرفی و هزینه مستقیم',
                        icon: Icons.sell_outlined,
                        keyboardType: TextInputType.number,
                        numericFa: true,
                        helper: 'خالی بماند یعنی هزینه مستقیم این خدمت ثبت نشده است؛ در گزارش سود تخمینی نمایش داده نمی‌شود.',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return null;
                          final amount = num.tryParse(FaNum.toLatin(value));
                          if (amount == null || amount < 0) return 'هزینه باید عددی و صفر یا بیشتر باشد.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _duration,
                              label: 'مدت (دقیقه)',
                              icon: Icons.timelapse_rounded,
                              keyboardType: TextInputType.number,
                              numericFa: true,
                              validator: (v) => Validators.positiveInt(v, label: 'مدت', min: 5, max: 480),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppTextField(
                              controller: _prep,
                              label: 'آماده‌سازی (دقیقه)',
                              icon: Icons.hourglass_top_rounded,
                              keyboardType: TextInputType.number,
                              numericFa: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppTextField(
                              controller: _buffer,
                              label: 'استراحت (دقیقه)',
                              icon: Icons.pause_circle_outline_rounded,
                              keyboardType: TextInputType.number,
                              numericFa: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );

                final rules = AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(title: 'زمان‌بندی و قواعد رزرو'),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _advanceDays,
                              label: 'حداکثر روز رزرو جلوتر',
                              icon: Icons.date_range_rounded,
                              keyboardType: TextInputType.number,
                              numericFa: true,
                              helper: 'مشتری تا چند روز آینده می‌تواند رزرو کند',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppTextField(
                              controller: _maxPerDay,
                              label: 'حداکثر رزرو روزانه',
                              icon: Icons.filter_9_plus_rounded,
                              keyboardType: TextInputType.number,
                              numericFa: true,
                              helper: 'خالی = بدون محدودیت',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'متخصصان این خدمت',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final employee in employees)
                            GestureDetector(
                              onTap: () => setState(() {
                                _employeeIds = _employeeIds.contains(employee.id)
                                    ? _employeeIds.where((id) => id != employee.id).toList()
                                    : [..._employeeIds, employee.id];
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: _employeeIds.contains(employee.id)
                                      ? pal.primary.withValues(alpha: 0.18)
                                      : pal.surfaceAlt,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(
                                    color: _employeeIds.contains(employee.id) ? pal.primary : pal.border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AvatarBadge(name: employee.fullName, size: 22, color: pal.primaryBright),
                                    const SizedBox(width: 6),
                                    Text(
                                      employee.fullName,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: pal.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_employeeIds.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const SectionHeader(title: 'قیمت، زمان و پورسانت اختصاصی پرسنل'),
                        const SizedBox(height: 8),
                        Text(
                          'مقادیر خالی از تنظیمات عمومی خدمت و قانون پرداخت پرسنل استفاده می‌کنند.',
                          style: TextStyle(fontSize: 11, color: pal.textSecondary, height: 1.6),
                        ),
                        const SizedBox(height: 10),
                        for (final employee in employees.where((item) => _employeeIds.contains(item.id))) ...[
                          AppCard(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  AvatarBadge(name: employee.fullName, size: 26, color: pal.primaryBright),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(employee.fullName, style: TextStyle(fontWeight: FontWeight.w700, color: pal.textPrimary))),
                                ]),
                                const SizedBox(height: 10),
                                LayoutBuilder(builder: (context, constraints) {
                                  final fieldWidth = (constraints.maxWidth - 12) / 2;
                                  final fields = _fieldsFor(employee.id);
                                  Widget entry(String label, TextEditingController controller, String hint) => SizedBox(
                                    width: fieldWidth,
                                    child: TextField(
                                      controller: controller,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
                                    ),
                                  );
                                  return Wrap(
                                    spacing: 12,
                                    runSpacing: 10,
                                    children: [
                                      entry('قیمت اختصاصی (تومان)', fields.price, 'قیمت عمومی'),
                                      entry('مدت اختصاصی (دقیقه)', fields.duration, 'مدت عمومی'),
                                      entry('پورسانت درصدی', fields.commissionPercent, 'مثلاً ۱۵'),
                                      entry('پورسانت ثابت (تومان)', fields.fixedCommission, 'اختیاری'),
                                    ],
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                      const SizedBox(height: 16),
                      AppSwitchRow(
                        title: 'خدمت فعال است',
                        description: 'خدمات غیرفعال در صفحه رزرو نمایش داده نمی‌شوند.',
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        icon: Icons.toggle_on_outlined,
                      ),
                      AppSwitchRow(
                        title: 'نیاز به تأیید دستی',
                        description: 'نوبت‌های این خدمت در وضعیت «در انتظار» ثبت می‌شوند.',
                        value: _requiresConfirmation,
                        onChanged: (v) => setState(() => _requiresConfirmation = v),
                        icon: Icons.verified_outlined,
                      ),
                    ],
                  ),
                );

                if (!wide) {
                  return Column(children: [basic, const SizedBox(height: 12), rules]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: basic),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: rules),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SolidButton(label: 'ذخیره خدمت', icon: Icons.check_rounded, loading: _saving, onPressed: _save),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SolidButton(
                    label: 'انصراف',
                    outlined: true,
                    onPressed: () => context.canPop() ? context.pop() : context.go('/services'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

 
class _EmployeeServiceFields {
  _EmployeeServiceFields(EmployeeServiceConfig? config)
      : price = TextEditingController(text: config?.customPrice?.toString() ?? ''),
        duration = TextEditingController(text: config?.customDurationMinutes?.toString() ?? ''),
        commissionPercent = TextEditingController(
          text: config?.commissionRateBps == null ? '' : (config!.commissionRateBps! / 100).toString(),
        ),
        fixedCommission = TextEditingController(text: config?.fixedCommissionAmount?.toString() ?? '');

  final TextEditingController price;
  final TextEditingController duration;
  final TextEditingController commissionPercent;
  final TextEditingController fixedCommission;

  void dispose() {
    price.dispose();
    duration.dispose();
    commissionPercent.dispose();
    fixedCommission.dispose();
  }
}
