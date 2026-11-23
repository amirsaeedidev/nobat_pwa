import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:printing/printing.dart';

import '../../../../core/utils/jalali.dart';
import '../../../../core/utils/pdf_table_document_builder.dart';
import '../../../../data/models/report_analytics.dart';

class ReportExecutivePdfExport {
  const ReportExecutivePdfExport._();

  static Future<Uint8List> buildBytes({
    required ReportAnalytics analytics,
    required ReportAnalytics comparison,
    required String title,
    required List<String> columns,
  }) async {
    final values = <String, String>{
      'درآمد ناخالص': analytics.grossRevenue.round().toString(),
      'تخفیف': analytics.discounts.round().toString(),
      'درآمد': analytics.netRevenue.round().toString(),
      'وصول‌شده': analytics.collectedRevenue.round().toString(),
      'هزینه': analytics.cost.round().toString(),
      'هزینه عمومی': analytics.operatingExpense.round().toString(),
      'حقوق و مزایا': analytics.payrollCost.round().toString(),
      'سود خالص': analytics.netProfit.round().toString(),
      'سهم مجموعه': analytics.companyShare.round().toString(),
      'پورسانت پرسنل': analytics.commissionCost.round().toString(),
      'حقوق پرداختی': analytics.staffPaid.round().toString(),
      'مانده پرسنل': analytics.staffPayable.round().toString(),
      'بدهی پرسنل': analytics.staffDebt.round().toString(),
      'مساعده باز': analytics.advancesOutstanding.round().toString(),
      'مطالبات': analytics.receivables.round().toString(),
      'نوبت': analytics.totalAppointments.toString(),
      'تکمیل‌شده': analytics.completedAppointments.toString(),
      'لغوشده': analytics.cancelledAppointments.toString(),
      'عدم مراجعه': analytics.noShowAppointments.toString(),
      'مشتری یکتا': analytics.uniqueCustomers.toString(),
      'نرخ بازگشت': '\${analytics.repeatCustomerRate.toStringAsFixed(1)}٪',
      'میانگین مدت نوبت': '\${analytics.averageAppointmentMinutes.round()} دقیقه',
    };
    final sections = <Map<String, Object>>[
      {
        'title': 'خلاصه مدیریتی',
        'rows': <List<String>>[
          ['شاخص', 'مقدار'],
          for (final column in columns)
            if (values.containsKey(column)) [column, values[column]!],
        ],
      },
      {
        'title': 'مقایسه با بازه انتخاب‌شده',
        'rows': <List<String>>[
          ['شاخص', 'مقدار'],
          ['درآمد مقایسه', comparison.revenue.round().toString()],
          ['هزینه مقایسه', comparison.cost.round().toString()],
          ['نوبت مقایسه', comparison.totalAppointments.toString()],
        ],
      },
      {
        'title': 'روند درآمد',
        'rows': <List<String>>[
          ['بازه', 'درآمد'],
          for (final item in analytics.trend) [item.label, item.revenue.round().toString()],
        ],
      },
      {
        'title': 'خدمات',
        'rows': <List<String>>[
          ['خدمت', 'تعداد', 'درآمد'],
          for (final item in analytics.services)
            [item.name, item.count.toString(), item.revenue.round().toString()],
        ],
      },
      {
        'title': 'عملکرد پرسنل',
        'rows': <List<String>>[
          ['پرسنل', 'درآمد', 'پورسانت'],
          for (final item in analytics.employees)
            [item.name, item.revenue.round().toString(), item.commission.round().toString()],
        ],
      },
      {
        'title': 'مشتریان برتر',
        'rows': <List<String>>[
          ['مشتری', 'مراجعه', 'مجموع خرید'],
          for (final item in analytics.customerMetrics)
            [item.name, item.lifetimeVisits.toString(), item.totalSpent.round().toString()],
        ],
      },
      {
        'title': 'تراکنش‌های دریافت و برگشت وجه',
        'rows': <List<String>>[
          ['شرح', 'روش', 'نوع', 'مبلغ'],
          for (final item in analytics.paymentTransactions)
            [item.description, item.method.label, item.type.name == 'refund' ? 'برگشت وجه' : 'دریافت', item.signedAmount.toString()],
        ],
      },
      {
        'title': 'دفتر کل کیف پول پرسنل',
        'rows': <List<String>>[
          ['نوع', 'شرح', 'تاریخ', 'مبلغ'],
          for (final item in analytics.walletTransactions)
            [item.type.label, item.description, JalaliDate.fromDateTime(item.createdAt).short, item.amount.toString()],
        ],
      },
      {
        'title': 'تسویه‌های پرسنل',
        'rows': <List<String>>[
          ['رسید', 'وضعیت', 'مبلغ پرداختی', 'مانده'],
          for (final item in analytics.settlements)
            [item.receiptNumber, item.status.name == 'completed' ? 'کامل' : 'جزئی', item.paidAmount.toString(), item.remainingAfter.toString()],
        ],
      },
      {
        'title': 'هزینه‌های ثبت‌شده مجموعه',
        'rows': <List<String>>[
          ['دسته', 'شرح', 'سند منبع', 'مبلغ'],
          for (final item in analytics.businessExpenses)
            [item.category.label, item.description, item.sourceDocumentId, item.amount.toString()],
        ],
      },
    ];
    return PdfTableDocumentBuilder.build(
      title: title,
      subtitle: 'بازه گزارش: \${analytics.range.label} — تاریخ تولید: \${JalaliDate.fromDateTime(DateTime.now()).long}',
      sections: sections,
    );
  }

  static Future<void> print({
    required ReportAnalytics analytics,
    required ReportAnalytics comparison,
    required String title,
    required List<String> columns,
  }) async {
    final bytes = await buildBytes(
      analytics: analytics, comparison: comparison, title: title, columns: columns,
    );
    await Printing.layoutPdf(
      name: 'گزارش-مدیریتی',
      onLayout: (_) async => bytes,
    );
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
