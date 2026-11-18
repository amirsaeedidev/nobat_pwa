import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/fa_num.dart';
import '../../../../data/models/dashboard_stats.dart';

/// نمودار میله‌ای + خطی عملکرد هفته (بازسازی دقیق نمودار تصویر مرجع).
class PerformanceChart extends StatelessWidget {
  const PerformanceChart({super.key, required this.data, this.height = 216, this.onPointTap});

  final List<WeekdayPerformance> data;
  final double height;
  final ValueChanged<WeekdayPerformance>? onPointTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          if (data.isEmpty || onPointTap == null) return;
          final visualIndex = ((details.localPosition.dx / constraints.maxWidth) * data.length).floor().clamp(0, data.length - 1);
          // محور نمودار در رابط RTL از راست (قدیمی‌تر) به چپ (جدیدتر) خوانده می‌شود.
          final index = data.length - 1 - visualIndex;
          onPointTap!(data[index]);
        },
        child: CustomPaint(
        painter: _PerformancePainter(
          data: data,
          barColor: pal.primary.withValues(alpha: 0.42),
          barPeakColor: pal.accentGlow,
          lineColor: pal.accentGlow,
          labelColor: pal.textSecondary,
          gridColor: pal.textPrimary.withValues(alpha: 0.05),
          dotFill: pal.isDark ? Colors.white : pal.surface,
          revealProgress: progress,
        ),
      ))),
    ));
  }
}

class _PerformancePainter extends CustomPainter {
  _PerformancePainter({
    required this.data,
    required this.barColor,
    required this.barPeakColor,
    required this.lineColor,
    required this.labelColor,
    required this.gridColor,
    required this.dotFill,
    required this.revealProgress,
  });

  final List<WeekdayPerformance> data;
  final Color barColor;
  final Color barPeakColor;
  final Color lineColor;
  final Color labelColor;
  final Color gridColor;
  final Color dotFill;
  final double revealProgress;

  static const double _topPad = 30;
  static const double _bottomPad = 24;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final chartTop = _topPad;
    final chartBottom = size.height - _bottomPad;
    final chartHeight = chartBottom - chartTop;
    final columnWidth = (size.width - 8) / data.length;
    final maxCount = data.map((e) => e.count).fold<int>(0, (a, b) => a > b ? a : b).clamp(1, 999999);
    final maxRevenue = data.map((e) => e.revenue.toDouble()).fold<double>(0, (a, b) => a > b ? a : b);
    const leftInset = 4.0;
    final barWidth = math.min(34.0, columnWidth * 0.58);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(size.width * (1 - revealProgress.clamp(0.0, 1.0)), 0, size.width * revealProgress.clamp(0.0, 1.0), size.height));

    // خطوط راهنمای افقی
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chartTop + chartHeight * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // میله‌ها
    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      final cx = size.width - (leftInset + columnWidth * i + columnWidth / 2);
      final ratio = item.count / maxCount;
      final barHeight = chartHeight * (item.count == 0 ? 0.0 : 0.08 + 0.72 * ratio) * revealProgress.clamp(0.0, 1.0);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barWidth / 2, chartBottom - barHeight, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      if (item.isPeak) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = barPeakColor.withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
        canvas.drawRRect(rect, Paint()..color = barPeakColor);
      } else {
        canvas.drawRRect(rect, Paint()..color = barColor);
      }
    }

    // نقاط خط
    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      final cx = size.width - (leftInset + columnWidth * i + columnWidth / 2);
      final ratio = maxRevenue == 0 ? 0.0 : (item.revenue.toDouble() / maxRevenue).clamp(0.0, 1.0);
      final y = chartBottom - chartHeight * (0.18 + 0.68 * ratio);
      points.add(Offset(cx, y));
    }

    // منحنی نرم
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }
    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // نقاط و درصدها
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      canvas.drawCircle(p, 6.5, Paint()..color = lineColor.withValues(alpha: 0.22));
      canvas.drawCircle(p, 4.6, Paint()..color = dotFill);
      canvas.drawCircle(
        p,
        4.6,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _paintText(
        canvas,
        FaNum.ofInt((data[i].count * revealProgress).round()),
        Offset(p.dx, p.dy - 20),
        color: labelColor,
        fontSize: 10,
        weight: FontWeight.w600,
      );
    }

    // نام روزها
    for (var i = 0; i < data.length; i++) {
      final cx = size.width - (leftInset + columnWidth * i + columnWidth / 2);
      _paintText(
        canvas,
        _shortLabel(data[i].label),
        Offset(cx, size.height - 8),
        color: data[i].isPeak ? lineColor : labelColor,
        fontSize: 9,
        weight: data[i].isPeak ? FontWeight.w700 : FontWeight.w500,
      );
    }
    canvas.restore();
  }

  String _shortLabel(String label) {
    const map = {
      'شنبه': 'شنبه',
      'یک‌شنبه': 'یک',
      'دوشنبه': 'دو',
      'سه‌شنبه': 'سه',
      'چهارشنبه': 'چهار',
      'پنج‌شنبه': 'پنج',
      'جمعه': 'جمعه',
    };
    return map[label] ?? label;
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset center, {
    required Color color,
    required double fontSize,
    FontWeight weight = FontWeight.w500,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Lalezar',
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    )..layout();
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PerformancePainter oldDelegate) => oldDelegate.data != data || oldDelegate.revealProgress != revealProgress;
}
