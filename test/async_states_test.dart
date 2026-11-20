import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app/theme/app_palette.dart';
import '../lib/core/models/app_failure.dart';
import '../lib/core/widgets/async_states.dart';
import '../lib/core/widgets/feedback.dart';

void main() {
  group('AppFailure', () {
    test('maps known failures to clear Persian messages', () {
      expect(AppFailure(AppErrorKind.connection).persianMessage, contains('ارتباط'));
      expect(AppFailure(AppErrorKind.save).persianMessage, contains('ذخیره'));
      expect(AppFailure(AppErrorKind.validation).persianMessage, contains('معتبر'));
      expect(AppFailure(AppErrorKind.access).canRetry, isFalse);
      expect(AppFailure(AppErrorKind.connection).canRetry, isTrue);
    });

    test('classifies common network and permission exceptions', () {
      expect(AppFailure.from(Exception('SocketException')).kind, AppErrorKind.connection);
      expect(AppFailure.from(Exception('permission denied')).kind, AppErrorKind.access);
    });
  });

  group('shared async UI', () {
    testWidgets('renders every page skeleton within mobile, tablet and desktop viewports', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 360.0, 375.0, 390.0, 414.0, 768.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 640);
        for (final kind in SkeletonKind.values) {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(extensions: const [AppPalette.creamBrown]),
            home: Scaffold(body: SingleChildScrollView(child: PageSkeleton(kind: kind))),
          ));
          await tester.pump(const Duration(milliseconds: 30));
          expect(find.bySemanticsLabel('در حال بارگذاری اطلاعات'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '${kind.name} skeleton overflow at width $width');
        }
      }
    });

    testWidgets('does not show retry action for access errors', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.creamBrown]),
        home: Scaffold(body: ErrorStateView(kind: AppErrorKind.access, onRetry: () {})),
      ));
      expect(find.text('تلاش مجدد'), findsNothing);
      expect(find.text('دسترسی مجاز نیست'), findsOneWidget);
    });

    testWidgets('shows retry action for recoverable fetch errors', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.creamBrown]),
        home: Scaffold(body: ErrorStateView(kind: AppErrorKind.fetch, onRetry: () {})),
      ));
      expect(find.text('تلاش مجدد'), findsOneWidget);
    });
  });
}
