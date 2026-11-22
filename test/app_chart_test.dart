import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:datetime/app/theme/app_palette.dart';
import 'package:datetime/core/widgets/app_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const points = [
    AppChartPoint(label: 'شنبه', value: 120, secondary: 35,
      segments: {'پرسنل اول': 70, 'پرسنل دوم': 50}),
    AppChartPoint(label: 'یکشنبه', value: 180, secondary: 55,
      segments: {'پرسنل اول': 100, 'پرسنل دوم': 80}),
    AppChartPoint(label: 'دوشنبه', value: 90, secondary: 20,
      segments: {'پرسنل اول': 40, 'پرسنل دوم': 50}),
  ];

  Widget host(Widget child, {AppPalette palette = AppPalette.creamBrown}) => MaterialApp(
    theme: ThemeData(extensions: [palette]),
    home: Directionality(textDirection: TextDirection.rtl,
      child: Scaffold(body: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(8), child: child,
      )))),
  );

  testWidgets('all shared chart types render without layout exceptions at 320px', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    for (final palette in [AppPalette.pastelPink, AppPalette.creamBrown, AppPalette.white, AppPalette.purpleDark]) {
    for (final type in AppChartType.values) {
      await tester.pumpWidget(host(SizedBox(width: 304, child: AppChart(
        type: type,
        height: 190,
        points: points,
        series: type == AppChartType.line || type == AppChartType.area ||
                type == AppChartType.bar || type == AppChartType.horizontalBar
          ? const [
              AppChartSeries(name: 'درآمد', values: [120, 180, 90]),
              AppChartSeries(name: 'هزینه', values: [35, 55, 20]),
            ]
          : const [],
      )), palette: palette));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'chart type $type overflowed at 320px in ' + palette.id);
    }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('shared charts adapt to desktop and tablet widths', (tester) async {
    for (final width in [360.0, 768.0, 1024.0, 1366.0, 1920.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(host(SizedBox(width: width - 16, child: const AppChart(
        type: AppChartType.line,
        points: points,
        series: [
          AppChartSeries(name: 'درآمد', values: [120, 180, 90]),
          AppChartSeries(name: 'هزینه', values: [35, 55, 20]),
        ],
      ))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'chart overflow at width $width');
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('empty and error states do not fabricate chart values', (tester) async {
    await tester.pumpWidget(host(const AppChart(type: AppChartType.line, points: [])));
    expect(find.text('برای این بازه داده‌ای ثبت نشده است'), findsOneWidget);
    await tester.pumpWidget(host(const AppChart(
      type: AppChartType.line, points: [], error: 'خطا در دریافت اطلاعات',
    )));
    expect(find.text('خطا در دریافت اطلاعات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart type menu reports the selected display mode', (tester) async {
    AppChartType? selected;
    await tester.pumpWidget(host(AppChart(
      type: AppChartType.line,
      points: points,
      onTypeChanged: (value) => selected = value,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ناحیه‌ای').last);
    await tester.pumpAndSettle();
    expect(selected, AppChartType.area);
  });
}
