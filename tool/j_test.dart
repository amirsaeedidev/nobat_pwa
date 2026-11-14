import '../lib/core/utils/jalali.dart';
void main() {
  final cases = ['2026-11-12', '2024-03-20', '2025-03-21', '2026-03-21', '2025-01-01', '1404-01-01'];
  final g = JalaliDate.fromDateTime(DateTime.parse(cases[0]));
  print('2026-11-12 => ${g.iso}  (expected 1405-08-21)  wd=${g.weekdayName}');
  for (final c in ['2024-03-20','2025-03-21','2026-03-21']) {
    final j = JalaliDate.fromDateTime(DateTime.parse(c));
    print('$c => ${j.iso} ${j.weekdayName}');
  }
  final j2 = JalaliDate(1404, 10, 15);
  print('1404-10-15 => greg ${j2.toDateTime()}  jdn=${j2.toJdn()} back=${JalaliDate.fromJdn(j2.toJdn()).iso} wd=${j2.weekdayName}');
  print('1404 leap=${JalaliDate(1404,1,1).isLeapYear} 1403 leap=${JalaliDate(1403,1,1).isLeapYear}');
  print('esfand 1403 len=${JalaliDate(1403,12,1).monthLength}  1404 len=${JalaliDate(1404,12,1).monthLength}');
  print('today=${JalaliDate.today().iso} ${JalaliDate.today().long}');
  print('numer=${JalaliDate(1404,10,15).numeric}');
}
