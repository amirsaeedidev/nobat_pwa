import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:datetime/features/reports/utils/report_table_export.dart';

void main() {
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
