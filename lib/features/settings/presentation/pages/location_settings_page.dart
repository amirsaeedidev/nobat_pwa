import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_inputs.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/feedback.dart';
import '../providers/settings_provider.dart';

class LocationSettingsPage extends StatefulWidget {
  const LocationSettingsPage({super.key});

  @override
  State<LocationSettingsPage> createState() => _LocationSettingsPageState();
}

class _LocationSettingsPageState extends State<LocationSettingsPage> {
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final Set<String> _selectedApps = {'google_maps'};
  bool _prefilled = false;
  bool _saving = false;

  static const _mapApps = <(String, String, IconData)>[
    ('waze', 'ویز', Icons.navigation_rounded),
    ('google_maps', 'گوگل مپ', Icons.map_rounded),
    ('neshan', 'نشان', Icons.place_rounded),
    ('balad', 'بلد', Icons.explore_rounded),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final settings = context.read<SettingsProvider>().settings;
    if (settings == null) return;
    _address.text = settings.address;
    _latitude.text = settings.latitude.toStringAsFixed(6);
    _longitude.text = settings.longitude.toStringAsFixed(6);
    _selectedApps
      ..clear()
      ..addAll(settings.mapApps);
  }

  @override
  void dispose() {
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final lat = double.tryParse(_latitude.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_longitude.text.trim().replaceAll(',', '.'));
    if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      AppToast.show(context, 'مختصات جغرافیایی معتبر وارد کنید.', success: false);
      return;
    }
    final current = context.read<SettingsProvider>().settings;
    if (current == null) return;
    setState(() => _saving = true);
    try {
      await context.read<SettingsProvider>().saveBusiness(
        current.copyWith(
          address: _address.text.trim(),
          latitude: lat,
          longitude: lng,
          mapApps: _selectedApps.toList(growable: false),
          postalCode: '',
          province: '',
          city: '',
        ),
        logTitle: 'تغییر موقعیت مکانی',
        logDescription: 'آدرس، مختصات و برنامه‌های نقشه به‌روزرسانی شد.',
      );
      if (mounted) AppToast.show(context, 'موقعیت مکانی ذخیره شد.');
    } catch (error) {
      if (mounted) AppToast.show(context, error.toString(), success: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return PageScaffold(
      title: 'موقعیت مکانی',
      subtitle: 'نشانی و مختصات جغرافیایی سالن زیبایی',
      icon: Icons.location_on_rounded,
      showBackButton: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(Icons.storefront_rounded, color: pal.primaryBright, size: 22),
                  const SizedBox(width: 8),
                  Text('موقعیت سالن زیبایی', style: TextStyle(fontWeight: FontWeight.w800, color: pal.textPrimary)),
                ]),
                const SizedBox(height: 14),
                AppTextField(controller: _address, label: 'آدرس', icon: Icons.location_on_outlined, maxLines: 2),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: AppTextField(controller: _latitude, label: 'عرض جغرافیایی', icon: Icons.swap_vert_rounded, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
                  const SizedBox(width: 10),
                  Expanded(child: AppTextField(controller: _longitude, label: 'طول جغرافیایی', icon: Icons.swap_horiz_rounded, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true))),
                ]),
                const SizedBox(height: 8),
                Text('مختصات را می‌توانید به‌صورت دستی وارد کنید.', style: TextStyle(fontSize: 10, color: pal.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: 'برنامه‌های مسیریابی'),
                const SizedBox(height: 6),
                Text('برنامه‌هایی را که مشتری برای مسیریابی استفاده می‌کند انتخاب کنید. جای تصویر هر برنامه برای بارگذاری لوگوی اصلی آماده است.', style: TextStyle(fontSize: 10, height: 1.7, color: pal.textMuted)),
                const SizedBox(height: 12),
                for (final app in _mapApps)
                  Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      value: _selectedApps.contains(app.$1),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selectedApps.add(app.$1);
                        } else {
                          _selectedApps.remove(app.$1);
                        }
                      }),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Row(children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: pal.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.border)),
                          child: Icon(app.$3, color: pal.primaryBright, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Text(app.$2, style: TextStyle(fontWeight: FontWeight.w700, color: pal.textPrimary)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SolidButton(label: 'ذخیره موقعیت', icon: Icons.save_rounded, loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
