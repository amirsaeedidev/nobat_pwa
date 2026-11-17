import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/models/employee_hr.dart';
void main(){
 final date=DateTime(2026,11,18);
 test('attendance summary records event metadata',(){
  final row=AttendanceRecord(id:'1',employeeId:'e',date:date,type:AttendanceEventType.checkIn,at:date.add(const Duration(minutes:15)),lateMinutes:15);
  expect(row.lateMinutes,15); expect(row.signedMinutes,-15);
 });
 test('document expiry states',(){
  final expired=EmployeeDocument(id:'1',employeeId:'e',title:'قرارداد',type:EmployeeDocumentType.contract,fileName:'contract-demo.pdf',addedAt:date,expiresAt:DateTime(2026,1,1));
  expect(expired.isExpired,true);
 });
 test('mock notice can be marked read',(){
  final notice=EmployeeNotice(id:'1',employeeId:'e',title:'مرخصی',message:'درخواست جدید',type:EmployeeNoticeType.leaveRequested,createdAt:date);
  expect(notice.markRead().read,true);
 });
}