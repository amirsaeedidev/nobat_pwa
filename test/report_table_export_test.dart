import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:datetime/features/reports/utils/report_table_export.dart';
import 'package:datetime/core/utils/jalali.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/report_analytics.dart';
import 'package:datetime/data/repositories/dashboard_repository.dart';
import 'package:datetime/features/reports/utils/report_executive_pdf_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Report table exports', () {
    test('CSV preserves Persian text, quotes delimiters and protects formula cells', () {
      final csv = ReportTableExport.toCsv(
        ['مشتری', 'مبلغ', 'یادداشت'],
        [['علی، رضایی', 120000, '=1+1'], ['مریم', 50000, 'گفت "سلام"']],
      );
      expect(csv, contains('"علی، رضایی"'));
      expect(csv, contains('"\'=1+1"'));
      expect(csv, contains('"گفت ""سلام"""'));
      expect(ReportTableExport.csvBytes(['نام'], [['امیر']]).take(3).toList(), [0xEF, 0xBB, 0xBF]);
    });

    test('CSV protects formulas preceded by whitespace', () {
      final csv = ReportTableExport.toCsv(
        ['یادداشت'], [['   =HYPERLINK("https://example.invalid")']],
      );
      expect(csv, contains("'   =HYPERLINK"));
    });

    test('PDF export creates a readable PDF and does not claim incomplete profit', () async {
      final db = AppDatabase();
      final range = ReportDateRange.custom(
        JalaliDate.fromDateTime(DateTime(2000, 1, 1)),
        JalaliDate.fromDateTime(DateTime(2100, 1, 1)),
      );
      final analytics = await MockDashboardRepository(db).fetchReportAnalytics(range: range);
      expect(analytics.profitIsComplete, isFalse);
      final bytes = await ReportExecutivePdfExport.buildBytes(
        analytics: analytics,
        comparison: analytics,
        title: 'گزارش مدیریتی',
        columns: const ['درآمد', 'هزینه', 'سود خالص'],
      );
      expect(utf8.decode(bytes.take(4).toList()), '%PDF');
      expect(bytes.length, greaterThan(1000));
    });

    test('XLSX workbook contains headers and data rows', () {
      final bytes = ReportTableExport.excelBytes(
        headers: ['خدمت', 'تعداد', 'درآمد'],
        rows: [['ژلیش', 3, 1650000]],
      );
      final workbook = Excel.decodeBytes(bytes);
      final sheet = workbook.tables['Sheet1']!;
      expect(sheet.maxRows, 2);
      expect(sheet.rows.first.first!.value, isA<TextCellValue>());
      expect((sheet.rows[1][1]!.value as IntCellValue).value, 3);
    });
  });
}
