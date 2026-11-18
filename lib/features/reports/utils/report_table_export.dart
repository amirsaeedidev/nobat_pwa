import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';

/// ساخت و ذخیره خروجی گزارش‌ها بدون نیاز به اینترنت یا سرویس سمت سرور.
class ReportTableExport {
  const ReportTableExport._();

  static String toCsv(List<String> headers, List<List<Object?>> rows) {
    String field(Object? value) {
      var text = value?.toString() ?? '';
      if (text.isNotEmpty && RegExp(r'^[=+@-]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }
    return [
      headers.map(field).join(','),
      for (final row in rows) row.map(field).join(','),
    ].join('\r\n');
  }

  static Uint8List csvBytes(List<String> headers, List<List<Object?>> rows) =>
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv(headers, rows))]);

  static Uint8List excelBytes({
    required List<String> headers,
    required List<List<Object?>> rows,
  }) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow(headers.map((value) => TextCellValue(value)).toList());
    for (final row in rows) {
      sheet.appendRow(row.map(_cell).toList());
    }
    final encoded = workbook.encode();
    if (encoded == null || encoded.isEmpty) {
      throw StateError('ساخت فایل Excel ناموفق بود.');
    }
    return Uint8List.fromList(encoded);
  }

  static CellValue _cell(Object? value) => switch (value) {
    null => TextCellValue(''),
    int number => IntCellValue(number),
    double number => DoubleCellValue(number),
    num number => DoubleCellValue(number.toDouble()),
    bool boolean => BoolCellValue(boolean),
    _ => TextCellValue(value.toString()),
  };

  static Future<void> saveCsv({
    required String name,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) async {
    await FileSaver.instance.saveFile(
      name: name,
      bytes: csvBytes(headers, rows),
      fileExtension: 'csv',
      mimeType: MimeType.custom,
      customMimeType: 'text/csv',
    );
  }

  static Future<void> saveExcel({
    required String name,
    required List<String> headers,
    required List<List<Object?>> rows,
  }) async {
    await FileSaver.instance.saveFile(
      name: name,
      bytes: excelBytes(headers: headers, rows: rows),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }
}
