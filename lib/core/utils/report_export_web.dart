import 'dart:convert';
import 'dart:html' as html;

Future<bool> printReport(String reportHtml) async {
  final blob = html.Blob([reportHtml], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  return true;
}
