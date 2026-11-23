import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfTableDocumentBuilder {
  const PdfTableDocumentBuilder._();

  static Future<Uint8List> build({
    required String title,
    required String subtitle,
    required List<Map<String, Object>> sections,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
    final payload = <String, Object>{
      'title': title,
      'subtitle': subtitle,
      'font': fontData.buffer.asUint8List(fontData.offsetInBytes, fontData.lengthInBytes),
      'sections': sections,
    };
    return Isolate.run(() => _buildPdfInBackground(payload));
  }
}

Future<Uint8List> _buildPdfInBackground(Map<String, Object> payload) async {
  final fontBytes = payload['font'] as Uint8List;
  final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
  final document = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final sections = payload['sections'] as List<Map<String, Object>>;
  pw.Widget cell(String value, {bool header = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(value, textAlign: pw.TextAlign.right,
      style: pw.TextStyle(font: font, fontSize: header ? 9 : 8,
        fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );
  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (context) => [
      pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text(payload['title'] as String,
            style: pw.TextStyle(font: font, fontSize: 19, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Text(payload['subtitle'] as String,
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 16),
          for (final section in sections) ...[
            pw.Text(section['title'] as String,
              style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
              children: [
                for (var index = 0; index < (section['rows'] as List<List<String>>).length; index++)
                  pw.TableRow(
                    decoration: index == 0 ? const pw.BoxDecoration(color: PdfColors.brown100) : null,
                    children: [
                      for (final value in (section['rows'] as List<List<String>>)[index])
                        cell(value, header: index == 0),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          pw.Text('این گزارش به‌صورت محلی از داده‌های Datamonck تهیه شده است.',
            style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey700)),
        ]),
      ),
    ],
  ));
  return Uint8List.fromList(await document.save());
}
