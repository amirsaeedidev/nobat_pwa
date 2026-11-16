import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_tokens.dart';
import '../utils/fa_num.dart';

/// فیلد متنی استاندارد با برچسب، آیکون و پشتیبانی از ورودی فارسی.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.icon,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.obscure = false,
    this.onChanged,
    this.suffix,
    this.enabled = true,
    this.numericFa = false,
    this.textInputAction,
    this.onFieldSubmitted,
    this.helper,
    this.dense = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final bool enabled;
  final bool numericFa;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final String? helper;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label!,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.textSecondary),
            ),
          ),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: maxLines,
          enabled: enabled,
          obscureText: obscure,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: dense ? 13 : 13.5,
            fontWeight: FontWeight.w500,
            color: pal.textPrimary,
            height: 1.6,
          ),
          inputFormatters: numericFa
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9۰-۹]')),
                ]
              : null,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: pal.surfaceAlt,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 12 : 15),
            prefixIcon: icon == null
                ? null
                : Padding(
                    padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
                    child: Icon(icon, size: 18, color: pal.textMuted),
                  ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            suffixIcon: suffix == null
                ? null
                : Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: suffix),
            suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            helperText: helper,
            helperStyle: TextStyle(fontSize: 10.5, color: pal.textMuted, fontFamily: 'Vazirmatn'),
          ),
        ),
      ],
    );
  }
}

/// فیلد جست‌وجو با آیکون ذره‌بین (مطابق تصویر مرجع مشتریان).
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.hint = 'جست‌وجو...',
    this.onChanged,
    this.onClear,
    this.accentBorder = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final bool accentBorder;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accentBorder ? pal.primary.withValues(alpha: 0.45) : pal.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textDirection: TextDirection.rtl,
        style: TextStyle(fontSize: 13, color: pal.textPrimary, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: pal.primaryBright),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.close_rounded, size: 16, color: pal.textMuted),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                  onClear?.call();
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// انتخابگر کشویی سفارشی.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint = 'انتخاب کنید',
    this.itemLabel,
    this.icon,
    this.dense = false,
    this.validator,
    this.accent,
  });

  final List<T> items;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String hint;
  final String Function(T item)? itemLabel;
  final IconData? icon;
  final bool dense;
  final String? Function(T?)? validator;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final labelOf = itemLabel ?? (T item) => item.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label!,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.textSecondary),
            ),
          ),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          validator: validator == null ? null : (v) => validator!(v),
          dropdownColor: pal.surfaceAlt,
          borderRadius: AppRadius.brMd,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: pal.textMuted, size: 20),
          style: TextStyle(fontSize: dense ? 12.5 : 13.5, fontWeight: FontWeight.w500, color: pal.textPrimary),
          hint: Text(hint, style: TextStyle(fontSize: 12.5, color: pal.textMuted)),
          decoration: InputDecoration(
            filled: true,
            fillColor: pal.surfaceAlt,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 12 : 15),
            prefixIcon: icon == null ? null : Icon(icon, size: 18, color: accent ?? pal.textMuted),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
          ),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(
                  labelOf(item),
                  style: TextStyle(fontSize: dense ? 12.5 : 13, color: pal.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// ردیف کلید روشن/خاموش با عنوان و توضیح.
class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.icon,
    this.showDivider = false,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: value ? pal.primaryBright : pal.textMuted),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.textPrimary),
                      ),
                    ),
                  ],
                ),
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      description!,
                      style: TextStyle(fontSize: 11, color: pal.textMuted, height: 1.6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: pal.primary,
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

/// انتخابگر چیپ‌ای (روزهای هفته، بازه‌های زمانی و ...).
class ChipSelector extends StatelessWidget {
  const ChipSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.multi = true,
    this.dangerSelected = false,
    this.wrap = true,
  });

  final List<String> options;
  final List<int> selected;
  final ValueChanged<int> onToggle;
  final bool multi;
  final bool dangerSelected;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final selectedColor = dangerSelected ? const Color(0xFF9F1239) : pal.primary;
    final chips = [
      for (var i = 0; i < options.length; i++)
        GestureDetector(
          onTap: () => onToggle(i),
          child: AnimatedContainer(
            duration: AppDurations.fast,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: selected.contains(i) ? selectedColor.withValues(alpha: dangerSelected ? 0.55 : 0.22) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected.contains(i) ? selectedColor : pal.borderStrong,
                width: selected.contains(i) ? 1.4 : 1,
              ),
            ),
            child: Text(
              options[i],
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected.contains(i) ? pal.textPrimary : pal.textSecondary,
              ),
            ),
          ),
        ),
    ];
    if (!wrap) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

/// انتخابگر ساعت با دو چرخ اسکرول نرم برای ساعت و دقیقه.
class TimeDropdown extends StatelessWidget {
  const TimeDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.times,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final List<String>? times;

  static List<String> defaultTimes({int fromHour = 7, int toHour = 23}) => [
        for (var h = fromHour; h <= toHour; h++)
          for (var m = 0; m < 60; m++) '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
      ];

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final options = times ?? defaultTimes();
    final normalized = options.contains(value) ? value : options.first;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: pal.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => _TimeWheelSheet(initial: normalized, options: options),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: pal.backgroundAlt,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: pal.border),
        ),
        child: Row(
          children: [
            Expanded(child: Text(FaNum.convert(normalized), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pal.textPrimary))),
            Icon(Icons.unfold_more_rounded, size: 18, color: pal.primaryBright),
          ],
        ),
      ),
    );
  }
}

class _TimeWheelSheet extends StatefulWidget {
  const _TimeWheelSheet({required this.initial, required this.options});

  final String initial;
  final List<String> options;

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  late final List<int> _hours = widget.options.map((v) => int.parse(v.split(':').first)).toSet().toList()..sort();
  late final List<int> _minutes = widget.options.map((v) => int.parse(v.split(':').last)).toSet().toList()..sort();
  late int _hour = int.parse(widget.initial.split(':').first);
  late int _minute = int.parse(widget.initial.split(':').last);
  late final FixedExtentScrollController _hourController = FixedExtentScrollController(initialItem: _hours.indexOf(_hour));
  late final FixedExtentScrollController _minuteController = FixedExtentScrollController(initialItem: _minutes.indexOf(_minute));

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('انتخاب ساعت کاری', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: pal.textPrimary)),
          const SizedBox(height: 16),
          SizedBox(height: 176, child: Row(children: [
            Expanded(child: _wheel(_hourController, _hours, (v) => setState(() => _hour = v))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(':', style: TextStyle(fontSize: 24, color: pal.primaryBright, fontWeight: FontWeight.w800))),
            Expanded(child: _wheel(_minuteController, _minutes, (v) => setState(() => _minute = v))),
          ])),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: () {
              final value = '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';
              if (widget.options.contains(value)) Navigator.pop(context, value);
              else {
                final nearest = widget.options.reduce((a, b) {
                  int distance(String x) => (int.parse(x.substring(0, 2)) * 60 + int.parse(x.substring(3))) - (_hour * 60 + _minute);
                  return distance(a).abs() <= distance(b).abs() ? a : b;
                });
                Navigator.pop(context, nearest);
              }
            },
            child: const Text('ثبت ساعت'),
          )),
        ]),
      ),
    );
  }

  Widget _wheel(FixedExtentScrollController controller, List<int> values, ValueChanged<int> onSelected) {
    final pal = context.pal;
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 44,
      diameterRatio: 1.5,
      physics: const FixedExtentScrollPhysics(),
      overAndUnderCenterOpacity: 0.38,
      onSelectedItemChanged: (index) => onSelected(values[index]),
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: values.length,
        builder: (context, index) => Center(
          child: Text(values[index].toString().padLeft(2, '0'),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.textPrimary)),
        ),
      ),
    );
  }
}
