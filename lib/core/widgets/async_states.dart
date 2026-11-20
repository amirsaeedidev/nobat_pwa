import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_tokens.dart';

enum SkeletonKind {
  dashboard,
  appointments,
  personnel,
  customers,
  services,
  reports,
  finance,
  wallet,
  generic,
}

/// اسکلتون‌های هم‌اندازه با اجزای اصلی صفحات؛ فقط یک انیمیشن سبک برای کل سطح اجرا می‌شود.
class PageSkeleton extends StatefulWidget {
  const PageSkeleton({super.key, this.kind = SkeletonKind.generic, this.compact = false});

  final SkeletonKind kind;
  final bool compact;

  @override
  State<PageSkeleton> createState() => _PageSkeletonState();
}

class _PageSkeletonState extends State<PageSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final content = _layout(pal);
    return Semantics(
      label: 'در حال بارگذاری اطلاعات',
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: widget.compact ? 8 : 14),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final position = reduceMotion ? 0.5 : _controller.value;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(-1.2 + position * 2.4, 0),
                end: Alignment(-0.2 + position * 2.4, 0),
                colors: [pal.surfaceAlt, pal.surfaceHigh.withValues(alpha: 0.92), pal.surfaceAlt],
                stops: const [0.1, 0.5, 0.9],
              ).createShader(bounds),
              child: child,
            );
          },
          child: content,
        ),
      ),
    );
  }

  Widget _block(double height, {double? width, double radius = 12}) => Container(
    height: height,
    width: width,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
  );

  Widget _line(double width, {double height = 10}) => _block(height, width: width, radius: 8);

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: context.pal.border),
    ),
    child: child,
  );

  Widget _metricGrid(int count) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth > 760 ? 4 : 2;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(count, (_) => SizedBox(
        width: (constraints.maxWidth - 10 * (columns - 1)) / columns,
        child: _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _line(62, height: 9), const SizedBox(height: 14), _line(100, height: 20),
        ])),
      )),
    );
  });

  Widget _rows({int count = 4, double height = 72}) => Column(
    children: List.generate(count, (_) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _card(child: Row(children: [
        _block(42, width: 42, radius: 22), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _line(116), const SizedBox(height: 9), _line(178, height: 8),
        ])),
        const SizedBox(width: 12), _block(24, width: 52, radius: 8),
      ])),
    )),
  );

  Widget _layout(AppPalette pal) {
    switch (widget.kind) {
      case SkeletonKind.dashboard:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _metricGrid(4), const SizedBox(height: 14),
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _line(130), const SizedBox(height: 14), _block(176, radius: 14),
          ])),
          const SizedBox(height: 12), _rows(count: 3),
        ]);
      case SkeletonKind.appointments:
        return Column(children: [
          _card(child: Column(children: [_block(42), const SizedBox(height: 12), _block(36), const SizedBox(height: 12), _block(36)])),
          const SizedBox(height: 12), _rows(count: 5, height: 78),
        ]);
      case SkeletonKind.personnel:
        return Column(children: [_metricGrid(4), const SizedBox(height: 12), _card(child: _block(42)), const SizedBox(height: 12), _rows(count: 4)]);
      case SkeletonKind.customers:
        return Column(children: [_card(child: _block(44)), const SizedBox(height: 12), _rows(count: 5)]);
      case SkeletonKind.services:
        return Column(children: [_card(child: Column(children: [_block(42), const SizedBox(height: 10), _block(36)])), const SizedBox(height: 12), _metricGrid(2), const SizedBox(height: 12), _rows(count: 4, height: 92)]);
      case SkeletonKind.reports:
        return Column(children: [_card(child: _block(42)), const SizedBox(height: 12), _metricGrid(4), const SizedBox(height: 12), _card(child: _block(210)), const SizedBox(height: 12), _card(child: _block(170))]);
      case SkeletonKind.finance:
        return Column(children: [_metricGrid(3), const SizedBox(height: 12), _card(child: _block(48)), const SizedBox(height: 12), _rows(count: 4)]);
      case SkeletonKind.wallet:
        return Column(children: [_card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_line(112), const SizedBox(height: 16), _line(180, height: 28), const SizedBox(height: 18), _metricGrid(2)])), const SizedBox(height: 12), _card(child: _block(54)), const SizedBox(height: 12), _rows(count: 4)]);
      case SkeletonKind.generic:
        return _rows(count: widget.compact ? 2 : 3);
    }
  }
}
