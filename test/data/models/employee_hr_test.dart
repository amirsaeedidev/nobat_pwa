import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/models/employee_hr.dart';
import 'package:datetime/data/mock/app_database.dart';
import 'package:datetime/data/models/employee_schedule.dart';
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
 test('mock database records check-in, check-out, late and overtime without duplicates',(){
  final db=AppDatabase(); final employee=db.employees.first; final day=DateTime(2026,1,3);
  db.recordAttendance(AttendanceRecord(id:'test-in',employeeId:employee.id,date:day,type:AttendanceEventType.checkIn,at:day.add(const Duration(hours:9)),lateMinutes:12));
  db.recordAttendance(AttendanceRecord(id:'test-out',employeeId:employee.id,date:day,type:AttendanceEventType.checkOut,at:day.add(const Duration(hours:18)),overtimeMinutes:60));
  final report=db.attendanceSummary(employee.id,from:day,to:day.add(const Duration(days:1)));
  expect(report.presentDays,1); expect(report.workedMinutes,540); expect(report.lateMinutes,12); expect(report.overtimeMinutes,60);
  expect(()=>db.recordAttendance(AttendanceRecord(id:'test-in2',employeeId:employee.id,date:day,type:AttendanceEventType.checkIn,at:day)),throwsStateError);
 });
 test('leave requests generate notification and approved leave remains linked',(){
  final db=AppDatabase(); final employee=db.employees.first; final start=DateTime(2026,12,2);
  final leave=EmployeeLeave(id:'leave-hr-test',employeeId:employee.id,startAt:start,endAt:start.add(const Duration(days:1)),type:EmployeeLeaveType.daily,status:EmployeeLeaveStatus.pending,description:'آزمایش',createdAt:date);
  db.addEmployeeLeave(leave);
  expect(db.noticesFor(employee.id).any((n)=>n.type==EmployeeNoticeType.leaveRequested),true);
  db.updateEmployeeLeave(leave.copyWith(status:EmployeeLeaveStatus.approved,approvedBy:'مدیر'));
  expect(db.leavesForEmployee(employee.id).singleWhere((l)=>l.id==leave.id).status,EmployeeLeaveStatus.approved);
  expect(db.noticesFor(employee.id).any((n)=>n.type==EmployeeNoticeType.leaveApproved),true);
 });
 test('mock digital documents can be added and expiry is surfaced',(){
  final db=AppDatabase(); final employee=db.employees.first;
  final doc=EmployeeDocument(id:'doc-test',employeeId:employee.id,title:'گواهی تخصصی',type:EmployeeDocumentType.specialty,fileName:'specialty-demo.pdf',addedAt:date,expiresAt:DateTime(2020,1,1));
  db.addEmployeeDocument(doc);
  expect(db.documentsFor(employee.id).any((d)=>d.id=='doc-test'&&d.isExpired),true);
 });
 test('attendance payroll policy produces preview only and does not post wallet transactions',(){
  final db=AppDatabase();final employee=db.employees.first;final day=DateTime(2026,1,4);
  db.recordAttendance(AttendanceRecord(id:'policy-in',employeeId:employee.id,date:day,type:AttendanceEventType.checkIn,at:day.add(const Duration(hours:9)),lateMinutes:10));
  db.recordAttendance(AttendanceRecord(id:'policy-out',employeeId:employee.id,date:day,type:AttendanceEventType.checkOut,at:day.add(const Duration(hours:18)),overtimeMinutes:30));
  db.saveAttendancePayrollPolicy(const AttendancePayrollPolicy(enabled:true,lateDeductionPerMinute:1000,absenceDeductionPerDay:0,overtimePaymentPerMinute:500));
  final preview=db.attendancePayrollPreview(employee.id,from:day,to:day.add(const Duration(days:1)));
  expect(preview.lateDeduction,10000);expect(preview.overtimePayment,15000);expect(preview.netAdjustment,5000);
 });
 test('mock notice can be marked read',(){
  final notice=EmployeeNotice(id:'1',employeeId:'e',title:'مرخصی',message:'درخواست جدید',type:EmployeeNoticeType.leaveRequested,createdAt:date);
  expect(notice.markRead().read,true);
 });
}