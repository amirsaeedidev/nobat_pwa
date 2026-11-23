import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_inputs.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../providers/settings_provider.dart';

/// اطلاعات پایه مجموعه؛ نشانی و تنها شبکه اجتماعی قابل ثبت در این صفحه.
class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _slogan = TextEditingController();
  final _description = TextEditingController();
  final _mobile = TextEditingController();
  final _address = TextEditingController();
  final _instagram = TextEditingController();
  bool _prefilled = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final settings = context.read<SettingsProvider>().settings;
    if (settings == null) return;
    _name.text = settings.name;
    _slogan.text = settings.slogan;
    _description.text = settings.description;
    _mobile.text = settings.mobile;
    _address.text = settings.address;
    _instagram.text = settings.instagram;
  }

  @override
  void dispose() {
    for (final controller in [_name, _slogan, _description, _mobile, _address, _instagram]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final current = context.read<SettingsProvider>().settings;
    if (current == null) return;
    setState(() => _saving = true);
    try {
      await context.read<SettingsProvider>().saveBusiness(
        current.copyWith(
          name: _name.text.trim(),
          slogan: _slogan.text.trim(),
          description: _description.text.trim(),
          mobile: _mobile.text.trim(),
          address: _address.text.trim(),
          instagram: _instagram.text.trim(),
          // اطلاعات حذف‌شده از فرم نیز پاک می‌شوند تا در داده‌های مجموعه باقی نمانند.
          phone: '',
          email: '',
          province: '',
          city: '',
          postalCode: '',
          telegram: '',
          whatsapp: '',
          website: '',
        ),
        logTitle: 'ویرایش اطلاعات مجموعه',
        logDescription: 'اطلاعات مجموعه و نشانی به‌روزرسانی شد.',
      );
      if (!mounted) return;
      AppToast.show(context, 'اطلاعات مجموعه ذخیره شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'اطلاعات مجموعه',
      subtitle: 'اطلاعات اصلی و راه ارتباطی مجموعه',
      icon: Icons.storefront_rounded,
      showBackButton: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: 'مشخصات مجموعه'),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _name,
                    label: 'نام مجموعه',
                    icon: Icons.storefront_outlined,
                    validator: (value) => Validators.required(value, label: 'نام مجموعه'),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(controller: _slogan, label: 'شعار مجموعه', icon: Icons.campaign_outlined),
                  const SizedBox(height: 12),
                  AppTextField(controller: _description, label: 'توضیحات', maxLines: 3),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: 'نشانی و تماس'),
                  const SizedBox(height: 12),
                  AppTextField(controller: _mobile, label: 'شماره موبایل', icon: Icons.phone_iphone_rounded, numericFa: true),
                  const SizedBox(height: 12),
                  AppTextField(controller: _address, label: 'آدرس', icon: Icons.location_on_outlined, maxLines: 2),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: 'شبکه اجتماعی'),
                  const SizedBox(height: 12),
                  AppTextField(controller: _instagram, label: 'اینستاگرام', icon: Icons.camera_alt_outlined),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SolidButton(label: 'ذخیره تغییرات', icon: Icons.save_rounded, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
