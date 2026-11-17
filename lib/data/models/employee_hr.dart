enum AttendanceEventType { checkIn, checkOut, absence, mission, manualCorrection }
class AttendanceRecord {
 const AttendanceRecord({required this.id,required this.employeeId,required this.date,required this.type,required this.at, this.note='',this.createdBy='پرسنل',this.overtimeMinutes=0,this.lateMinutes=0,this.earlyLeaveMinutes=0});
 final String id,employeeId,note,createdBy; final DateTime date,at; final AttendanceEventType type; final int overtimeMinutes,lateMinutes,earlyLeaveMinutes;
 int get signedMinutes => overtimeMinutes-lateMinutes-earlyLeaveMinutes;
}
enum EmployeeDocumentType { contract, identity, certificate, specialty, attachment }
class EmployeeDocument {
 const EmployeeDocument({required this.id,required this.employeeId,required this.title,required this.type,required this.fileName,required this.addedAt,this.expiresAt,this.note='',this.mockPreview='نمونه نمایشی سند'});
 final String id,employeeId,title,fileName,note,mockPreview; final EmployeeDocumentType type; final DateTime addedAt; final DateTime? expiresAt;
 bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
 bool get isExpiringSoon => expiresAt != null && !isExpired && expiresAt!.difference(DateTime.now()).inDays <= 30;
}
enum EmployeeNoticeType { leaveRequested, leaveApproved, leaveRejected, contractExpiring, scheduleChanged, paymentRecorded, salaryChanged }
class EmployeeNotice {
 const EmployeeNotice({required this.id,required this.employeeId,required this.title,required this.message,required this.type,required this.createdAt,this.read=false});
 final String id,employeeId,title,message; final EmployeeNoticeType type; final DateTime createdAt; final bool read;
 EmployeeNotice markRead()=>EmployeeNotice(id:id,employeeId:employeeId,title:title,message:message,type:type,createdAt:createdAt,read:true);
}
class AttendanceSummary {
 const AttendanceSummary({required this.presentDays,required this.absentDays,required this.workedMinutes,required this.overtimeMinutes,required this.lateMinutes});
 final int presentDays,absentDays,workedMinutes,overtimeMinutes,lateMinutes;
}