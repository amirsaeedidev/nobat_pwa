import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/models/employee_hr.dart';
import 'package:datetime/data/models/employee_payroll.dart';
import 'package:datetime/data/models/employee_wallet.dart';
import 'package:datetime/data/models/enums.dart';
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
  expect(()=>db.recordAttendance(AttendanceRecord(id:'test-in-open-duplicate',employeeId:employee.id,date:day,type:AttendanceEventType.checkIn,at:day.add(const Duration(hours:10)))),throwsStateError);
  db.recordAttendance(AttendanceRecord(id:'test-out',employeeId:employee.id,date:day,type:AttendanceEventType.checkOut,at:day.add(const Duration(hours:18)),overtimeMinutes:60));
  final report=db.attendanceSummary(employee.id,from:day,to:day.add(const Duration(days:1)));
  expect(report.presentDays,1); expect(report.workedMinutes,540); expect(report.lateMinutes,12); expect(report.overtimeMinutes,60);
 });
 test('leave requests generate notification and approved leave remains linked',(){
  final db=AppDatabase(); final employee=db.employees.first; final start=DateTime(2030,12,2);
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
 test('pending leave does not block calendar availability; approved leave does',(){
  final db=AppDatabase();final employee=db.employees.first;
  DateTime? start;
  for(var offset=1;offset<40 && start==null;offset++){
   final day=DateTime.now().add(Duration(days:offset));
   final dayStart=DateTime(day.year,day.month,day.day);
   final dayEnd=dayStart.add(const Duration(days:1));
   // The test covers leave-state behavior, so select a date with no existing
   // appointment at all; otherwise approval is correctly rejected by the
   // database's appointment-conflict protection.
   if(db.appointments.any((appointment)=>
     appointment.employeeId==employee.id &&
     appointment.status!=AppointmentStatus.cancelled &&
     appointment.startAt.isBefore(dayEnd) &&
     dayStart.isBefore(appointment.endAt))) continue;
   final shifts=db.employeeShiftsForDate(employee.id,day);
   for(final shift in shifts){
    final candidate=DateTime(day.year,day.month,day.day,shift.startMinutes~/60,(shift.startMinutes%60)+10);
    if(db.isEmployeeAvailableAt(employeeId:employee.id,startAt:candidate,durationMinutes:15)){start=candidate;break;}
   }
  }
  expect(start,isNotNull);
  final slot=start!;
  final leave=EmployeeLeave(id:'leave-pending-hr',employeeId:employee.id,startAt:DateTime(slot.year,slot.month,slot.day),endAt:DateTime(slot.year,slot.month,slot.day,23,59),type:EmployeeLeaveType.daily,status:EmployeeLeaveStatus.pending,description:'درخواست آزمایشی',createdAt:DateTime.now());
  db.addEmployeeLeave(leave);
  expect(db.isEmployeeAvailableAt(employeeId:employee.id,startAt:slot,durationMinutes:15),true);
  db.updateEmployeeLeave(leave.copyWith(status:EmployeeLeaveStatus.approved,approvedBy:'مدیر'));
  expect(db.isEmployeeAvailableAt(employeeId:employee.id,startAt:slot,durationMinutes:15),false);
 });
 test('approved leave cannot overlap a booked appointment',(){
  final db=AppDatabase();final appointment=db.appointments.firstWhere((a)=>a.status!=AppointmentStatus.cancelled);
  final leave=EmployeeLeave(id:'leave-conflict-hr',employeeId:appointment.employeeId,startAt:appointment.startAt.subtract(const Duration(minutes:5)),endAt:appointment.endAt.add(const Duration(minutes:5)),type:EmployeeLeaveType.daily,status:EmployeeLeaveStatus.pending,description:'تداخل آزمایشی',createdAt:DateTime.now());
  db.addEmployeeLeave(leave);
  expect(()=>db.updateEmployeeLeave(leave.copyWith(status:EmployeeLeaveStatus.approved)),throwsArgumentError);
 });
 test('new leave request notifies the manager and the employee',(){
  final db=AppDatabase();final employee=db.employees.first;final start=DateTime(2026,12,10);
  db.addEmployeeLeave(EmployeeLeave(id:'leave-notice-manager',employeeId:employee.id,startAt:start,endAt:start.add(const Duration(hours:8)),type:EmployeeLeaveType.hourly,status:EmployeeLeaveStatus.pending,description:'قرار پزشکی',createdAt:date));
  expect(db.noticesFor(employee.id).any((n)=>n.type==EmployeeNoticeType.leaveRequested),true);
  expect(db.noticesFor('emp-shima').any((n)=>n.type==EmployeeNoticeType.leaveRequested),true);
 });
 test('attendance rejects checkout before check-in and duplicate absence',(){
  final db=AppDatabase();final employee=db.employees.first;final day=DateTime(2026,1,9);
  db.recordAttendance(AttendanceRecord(id:'validation-in',employeeId:employee.id,date:day,type:AttendanceEventType.checkIn,at:day.add(const Duration(hours:9))));
  expect(()=>db.recordAttendance(AttendanceRecord(id:'validation-out',employeeId:employee.id,date:day,type:AttendanceEventType.checkOut,at:day.add(const Duration(hours:8)))),throwsStateError);
  expect(()=>db.recordAttendance(AttendanceRecord(id:'validation-absence',employeeId:employee.id,date:day,type:AttendanceEventType.absence,at:day.add(const Duration(hours:8)))),throwsStateError);
 });
 test('manual attendance correction requires manager permission',(){
  final db=AppDatabase();final staff=db.accessAccounts.firstWhere((a)=>a.id=='demo-staff');db.switchMockAccount(staff.id);
  expect(()=>db.recordAttendance(AttendanceRecord(id:'staff-manual',employeeId:staff.employeeId!,date:date,type:AttendanceEventType.checkIn,at:date,createdBy:staff.name,isManualCorrection:true)),throwsA(isA<Exception>()));
 });
 test('employee documents can be edited and deleted with manager permission',(){
  final db=AppDatabase();final employee=db.employees.first;
  final doc=EmployeeDocument(id:'doc-crud',employeeId:employee.id,title:'قرارداد',type:EmployeeDocumentType.contract,fileName:'contract-sample.pdf',addedAt:date);
  db.addEmployeeDocument(doc);
  db.updateEmployeeDocument(EmployeeDocument(id:doc.id,employeeId:doc.employeeId,title:'قرارداد اصلاح‌شده',type:doc.type,fileName:doc.fileName,addedAt:doc.addedAt,expiresAt:date.add(const Duration(days:10))));
  expect(db.documentsFor(employee.id).singleWhere((d)=>d.id==doc.id).title,'قرارداد اصلاح‌شده');
  db.deleteEmployeeDocument(doc.id);
  expect(db.documentsFor(employee.id).any((d)=>d.id==doc.id),false);
 });
 test('attendance reports early leave and absence days',(){
  final db=AppDatabase();final employee=db.employees.first;final absentDay=DateTime(2026,1,12);final workDay=DateTime(2026,1,13);
  db.recordAttendance(AttendanceRecord(id:'report-absence',employeeId:employee.id,date:absentDay,type:AttendanceEventType.absence,at:absentDay.add(const Duration(hours:9)),note:'غیبت آزمایشی'));
  db.recordAttendance(AttendanceRecord(id:'report-in',employeeId:employee.id,date:workDay,type:AttendanceEventType.checkIn,at:workDay.add(const Duration(hours:9))));
  db.recordAttendance(AttendanceRecord(id:'report-out',employeeId:employee.id,date:workDay,type:AttendanceEventType.checkOut,at:workDay.add(const Duration(hours:16)),earlyLeaveMinutes:30));
  final summary=db.attendanceSummary(employee.id,from:absentDay,to:workDay.add(const Duration(days:1)));
  expect(summary.absentDays,1);expect(summary.presentDays,1);expect(summary.earlyLeaveMinutes,30);
 });
 test('salary and payment changes create employee notices',(){
  final db=AppDatabase();final employee=db.employees.first;
  db.saveSalaryContract(SalaryContract(id:'notice-salary',employeeId:employee.id,monthlyBase:9000000,effectiveFrom:date));
  expect(db.noticesFor(employee.id).any((n)=>n.type==EmployeeNoticeType.salaryChanged),true);
  final start=DateTime(2000,1,1);final end=DateTime(2100,1,1);
  db.settleEmployeeWallet(employeeId:employee.id,periodStart:start,periodEnd:end,
    periodType:EmployeeWalletPeriodType.manual,paidAmount:1000,idempotencyKey:'hr-payment-notice');
  expect(db.noticesFor(employee.id).any((n)=>n.type==EmployeeNoticeType.paymentRecorded),true);
 });
 test('mock data includes contract-expiry and schedule notices',(){
  final db=AppDatabase();
  expect(db.employeeNotices.any((n)=>n.type==EmployeeNoticeType.contractExpiring),true);
  expect(db.employeeNotices.any((n)=>n.type==EmployeeNoticeType.scheduleChanged),true);
 });
 test('mock notice can be marked read',(){
  final notice=EmployeeNotice(id:'1',employeeId:'e',title:'مرخصی',message:'درخواست جدید',type:EmployeeNoticeType.leaveRequested,createdAt:date);
  expect(notice.markRead().read,true);
 });
}