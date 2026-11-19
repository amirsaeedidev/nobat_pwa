import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/utils/jalali.dart';
import '../../../../data/models/report_analytics.dart';

class ReportExecutivePdfExport {
  const ReportExecutivePdfExport._();

  static Future<Uint8List> buildBytes({
    required ReportAnalytics analytics,
    required ReportAnalytics comparison,
    required String title,
    required List<String> columns,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    final generatedAt = DateTime.now();
    final values = <String, String>{
      'درآمد': analytics.revenue.round().toString(),
      'هزینه': analytics.cost.round().toString(),
      'سود خالص': analytics.profitIsComplete ? analytics.netProfit.round().toString() : 'نامشخص',
      'نوبت': analytics.totalAppointments.toString(),
      'تکمیل‌شده': analytics.completedAppointments.toString(),
      'مشتری یکتا': analytics.uniqueCustomers.toString(),
      'نرخ بازگشت': '${analytics.repeatCustomerRate.toStringAsFixed(1)}٪',
    };

    pw.Widget cell(String value, {bool header = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(value, textAlign: pw.TextAlign.right,
        style: pw.TextStyle(font: font, fontSize: header ? 9 : 8,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

    final rows = <pw.TableRow>[
      pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.brown100),
        children: [cell('شاخص', header: true), cell('مقدار', header: true)]),
      for (final column in columns)
        if (values.containsKey(column))
          pw.TableRow(children: [cell(column), cell(values[column]!)]),
    ];

    // برای بازه‌های طولانی، نقاط نمودار را یکنواخت نمونه‌برداری می‌کنیم تا PDF صدها صفحه نشود.
    final trendPoints = analytics.trend.length <= 24
      ? analytics.trend
      : List.generate(24, (index) => analytics.trend[
          (index * (analytics.trend.length - 1) / 23).round()]);
    final maxRevenue = trendPoints.fold<double>(0,
      (max, item) => item.revenue > max ? item.revenue.toDouble() : max);

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            pw.Text(title, style: pw.TextStyle(font: font, fontSize: 19, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text('بازه گزارش: ${analytics.range.label}',
              style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
            pw.Text('تاریخ تولید: ${JalaliDate.fromDateTime(generatedAt).long}',
              style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 14),
            pw.Text('خلاصه مدیریتی', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300, width: .5), children: rows),
            pw.SizedBox(height: 14),
            pw.Text('وضعیت سود: ${analytics.profitStatusNote}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
            pw.Text('مقایسه با بازه انتخاب‌شده', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text('درآمد مقایسه: ${comparison.revenue.round()} · هزینه مقایسه: ${comparison.cost.round()} · سود مقایسه: ${comparison.profitIsComplete ? comparison.netProfit.round() : 'نامشخص'} · نوبت مقایسه: ${comparison.totalAppointments}',
              style: pw.TextStyle(font: font, fontSize: 8)),
            pw.SizedBox(height: 14),
            pw.Text('نمودار روند درآمد', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            for (final point in trendPoints)
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Row(children: [
                pw.SizedBox(width: 45, child: pw.Text(point.label, style: pw.TextStyle(font: font, fontSize: 7))),
                pw.Expanded(child: pw.Container(height: 8,
                  alignment: pw.Alignment.centerRight,
                  decoration: const pw.BoxDecoration(color: PdfColors.brown100),
                  child: pw.Align(alignment: pw.Alignment.centerRight,
                    child: pw.Container(height: 8, width: maxRevenue <= 0 ? 0.0 : (260 * point.revenue / maxRevenue).toDouble(),
                      color: PdfColors.brown)),
                )),
                pw.SizedBox(width: 8),
                pw.Text(point.revenue.round().toString(), style: pw.TextStyle(font: font, fontSize: 7)),
              ])),
            pw.SizedBox(height: 14),
            pw.Text('خدمات پرفروش', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300, width: .5), children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.brown100),
                children: [cell('خدمت', header: true), cell('تعداد', header: true), cell('درآمد', header: true)]),
              for (final item in analytics.services.take(10))
                pw.TableRow(children: [cell(item.name), cell(item.count.toString()), cell(item.revenue.round().toString())]),
            ]),
            pw.SizedBox(height: 14),
            pw.Text('عملکرد پرسنل', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300, width: .5), children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.brown100),
                children: [cell('پرسنل', header: true), cell('درآمد', header: true), cell('پورسانت', header: true)]),
              for (final item in analytics.employees.take(10))
                pw.TableRow(children: [cell(item.name), cell(item.revenue.round().toString()), cell(item.commission.round().toString())]),
            ]),
            pw.SizedBox(height: 14),
            pw.Text('مشتریان برتر', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300, width: .5), children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.brown100),
                children: [cell('مشتری', header: true), cell('مراجعه', header: true), cell('مجموع خرید', header: true)]),
              for (final item in analytics.customerMetrics.take(10))
                pw.TableRow(children: [cell(item.name), cell(item.lifetimeVisits.toString()), cell(item.totalSpent.round().toString())]),
            ]),
            pw.SizedBox(height: 10),
            pw.Text('این گزارش به‌صورت محلی از داده‌های Datamonck تولید شده است.',
              style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey700)),
          ]),
        ),
      ],
    ));
    return Uint8List.fromList(await document.save());
  }

  static Future<void> save({
    required ReportAnalytics analytics,
    required ReportAnalytics comparison,
    required String title,
    required List<String> columns,
  }) async {
    final bytes = await buildBytes(
      analytics: analytics, comparison: comparison, title: title, columns: columns,
    );
    await FileSaver.instance.saveFile(
      name: 'گزارش-مدیریتی',
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.custom,
      customMimeType: 'application/pdf',
    );
  }
}
