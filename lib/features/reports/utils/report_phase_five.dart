import '../../../../data/models/appointment.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/report_analytics.dart';
import '../../../../data/models/service.dart';

class ReportDelta {
  const ReportDelta(this.current, this.previous);
  final num current;
  final num previous;
  num? get percent => previous == 0 ? null : (current - previous) * 100 / previous;
  bool get increased => current > previous;
  bool get decreased => current < previous;
}

enum ReportAlertLevel { info, warning, critical }

class ReportInsight {
  const ReportInsight(this.id, this.title, this.reason, this.evidence, this.level);
  final String id, title, reason, evidence;
  final ReportAlertLevel level;
}

class ReportInsightEngine {
  const ReportInsightEngine._();

  static ReportDelta compare(num current, num previous) => ReportDelta(current, previous);

  static List<ReportInsight> build({
    required ReportAnalytics current,
    required ReportAnalytics previous,
    required List<Service> services,
  }) {
    final result = <ReportInsight>[];
    if (previous.revenue > 0 && previous.totalAppointments >= 5 &&
        current.revenue <= previous.revenue * .8) {
      final drop = (previous.revenue - current.revenue) * 100 / previous.revenue;
      result.add(ReportInsight('revenue-drop', 'کاهش درآمد',
        'درآمد جاری حداقل ۲۰٪ کمتر از بازه مقایسه‌ای است.',
        'جاری: ${current.revenue.round()} · مقایسه: ${previous.revenue.round()} · کاهش: ${drop.toStringAsFixed(1)}٪',
        drop >= 40 ? ReportAlertLevel.critical : ReportAlertLevel.warning));
    }
    if (current.filter.isEmpty && current.completedAppointments >= 10 && services.length >= 3) {
      final counts = <String, int>{};
      for (final item in current.operationalAppointments.where((a) => a.status == AppointmentStatus.completed)) {
        for (final id in item.serviceIds) { counts[id] = (counts[id] ?? 0) + 1; }
      }
      final average = services.fold<int>(0, (sum, s) => sum + (counts[s.id] ?? 0)) / services.length;
      for (final service in services) {
        final count = counts[service.id] ?? 0;
        if (average > 0 && count <= average * .25 && count < average) {
          result.add(ReportInsight('service-${service.id}', 'فروش پایین خدمت: ${service.title}',
            'تعداد ارائه خدمت به‌طور محسوسی کمتر از میانگین است.',
            'ارائه: $count · میانگین: ${average.toStringAsFixed(1)}',
            ReportAlertLevel.warning));
        }
      }
    }
    final hours = current.hourlyDemand.where((h) => h.scheduledMinutes >= 60).toList();
    if (current.filter.isEmpty && current.capacityMinutes >= 240 && hours.length >= 3) {
      final low = hours.where((h) => h.appointments == 0 && h.bookedMinutes <= h.scheduledMinutes * .1).toList();
      if (low.isNotEmpty) {
        result.add(ReportInsight('low-hours', 'ساعت‌های کم‌تقاضا',
          'در ساعات دارای برنامه کاری، نوبتی ثبت نشده است.',
          low.map((h) => '${h.hour.toString().padLeft(2, '0')}:00').join('، '),
          ReportAlertLevel.info));
      }
    }
    final currentStaff = current.filter.isEmpty ? _staffCounts(current.operationalAppointments) : <String, int>{};
    final previousStaff = current.filter.isEmpty ? _staffCounts(previous.operationalAppointments) : <String, int>{};
    for (final entry in previousStaff.entries) {
      if (entry.value < 3 || (currentStaff[entry.key] ?? 0) > entry.value * .7) continue;
      final names = previous.operationalAppointments.where((a) => a.employeeId == entry.key);
      final name = names.isEmpty ? 'پرسنل' : names.first.employeeName;
      result.add(ReportInsight('staff-${entry.key}', 'افت عملکرد پرسنل: $name',
        'تعداد نوبت‌های تکمیل‌شده حداقل ۳۰٪ کاهش یافته است.',
        'جاری: ${currentStaff[entry.key] ?? 0} · مقایسه: ${entry.value}',
        ReportAlertLevel.warning));
    }
    if (current.totalAppointments >= 5 && previous.totalAppointments >= 5) {
      final rate = current.cancelledAppointments * 100 / current.totalAppointments;
      final oldRate = previous.cancelledAppointments * 100 / previous.totalAppointments;
      if (rate - oldRate >= 10) {
        result.add(ReportInsight('cancellations', 'افزایش نرخ لغو',
          'نرخ لغو حداقل ۱۰ واحد درصد افزایش یافته است.',
          'جاری: ${rate.toStringAsFixed(1)}٪ · مقایسه: ${oldRate.toStringAsFixed(1)}٪',
          ReportAlertLevel.warning));
      }
    }
    if (current.customerMetrics.length >= 5 && current.inactiveCustomers > 0) {
      result.add(ReportInsight('inactive-customers', 'مشتریان غیرفعال',
        'مشتریانی با حداقل ۹۰ روز فاصله از آخرین مراجعه شناسایی شده‌اند.',
        '${current.inactiveCustomers} از ${current.customerMetrics.length} مشتری قابل تحلیل',
        ReportAlertLevel.info));
    }
    return List.unmodifiable(result);
  }

  static Map<String, int> _staffCounts(List<Appointment> appointments) {
    final result = <String, int>{};
    for (final item in appointments.where((a) => a.status == AppointmentStatus.completed)) {
      result[item.employeeId] = (result[item.employeeId] ?? 0) + 1;
    }
    return result;
  }
}
