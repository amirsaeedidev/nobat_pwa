import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';

import '../lib/app/theme/app_palette.dart';
import '../lib/core/widgets/app_buttons.dart';
import '../lib/core/widgets/app_page.dart';

void main() {
  testWidgets('shared headers, grids and icon controls fit target viewports', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 360.0, 375.0, 390.0, 414.0, 768.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.creamBrown]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const DesktopPageHeader(
                        title: 'عنوان بسیار طولانی برای بررسی واکنش‌گرایی سربرگ صفحات',
                        subtitle: 'توضیح فارسی طولانی که نباید روی دکمه‌ها قرار بگیرد یا بریده شود',
                        actions: [
                          HugeIconCircleButton(icon: HugeIcons.strokeRoundedSearch01, size: 30, tooltip: 'جست‌وجو'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ResponsiveGrid(
                        minItemWidth: 180,
                        children: List.generate(
                          6,
                          (index) => Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('کارت آزمایشی شماره ${index + 1}'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'shared layout overflow at width $width');
      expect(tester.getSize(find.byType(HugeIconCircleButton)).width, greaterThanOrEqualTo(44));
    }
  });
}
