import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee_hr.dart';
import '../../../../core/utils/fa_num.dart';

class EmployeeAttendancePage extends StatelessWidget {
 const EmployeeAttendancePage({super.key,required this.employeeId});
 final String employeeId;
 @override Widget build(BuildContext context){
  final db=context.watch<AppDatabase>(); final e=db.employeeById(employeeId);
  if(e==null)return PageScaffold(title:'حضور و غیاب',showBackButton:true,child:EmptyState(title:'پرسنل یافت نشد'));
  final now=DateTime.now(),from=DateTime(now.year,now.month,1),to=DateTime(now.year,now.month+1,0,23,59);
  final rows=db.attendanceFor(employeeId,from:from,to:to); final sum=db.attendanceSummary(employeeId,from:from,to:to);
  final today=DateTime(now.year,now.month,now.day);
  final hasIn=rows.any((r)=>r.type==AttendanceEventType.checkIn&&r.date.year==now.year&&r.date.month==now.month&&r.date.day==now.day);
  final hasOut=rows.any((r)=>r.type==AttendanceEventType.checkOut&&r.date.year==now.year&&r.date.month==now.month&&r.date.day==now.day);
  return PageScaffold(title:'حضور و غیاب',subtitle:e.fullName,showBackButton:true,actions:[
   SoftButton(label:'ثبت ورود',icon:Icons.login,onTap:()=>_record(context,db,e.id,AttendanceEventType.checkIn)),
   SolidButton(label:'ثبت خروج',icon:Icons.logout,onPressed:hasIn&&!hasOut?()=>_record(context,db,e.id,AttendanceEventType.checkOut):null),
  ],child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   Wrap(spacing:8,runSpacing:8,children:[
    _metric('روز حضور',sum.presentDays.toString()),_metric('غیبت',sum.absentDays.toString()),
    _metric('ساعت کار',(sum.workedMinutes/60).toStringAsFixed(1)),_metric('اضافه‌کاری',FaNum.ofInt(sum.overtimeMinutes)+' دقیقه'),
    _metric('تأخیر',FaNum.ofInt(sum.lateMinutes)+' دقیقه'),
   ]),
   const SizedBox(height:12),
   AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const SectionHeader(title:'سوابق ماه جاری'),
    if(rows.isEmpty) EmptyState(title:'سابقه‌ای ثبت نشده'),
    for(final row in rows) ListTile(contentPadding:EdgeInsets.zero,
     leading:Icon(_icon(row.type)),title:Text(_label(row.type)),
     subtitle:Text('${row.at.hour.toString().padLeft(2,'0')}:${row.at.minute.toString().padLeft(2,'0')} · ${row.note}'),
     trailing:Text(row.lateMinutes>0?'تأخیر ${row.lateMinutes}د':row.overtimeMinutes>0?'اضافه‌کاری ${row.overtimeMinutes}د':''),
    ),
   ])),
   const SizedBox(height:8),Text('گزارش بازه ماهانه؛ تمام اطلاعات در Datamonck و آفلاین نگهداری می‌شوند.',style:Theme.of(context).textTheme.bodySmall),
  ]));
 }
 static Widget _metric(String label,String value)=>Container(width:145,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.black.withValues(alpha:.035),borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(fontSize:11)),const SizedBox(height:4),Text(value,style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold))]));
 static String _label(AttendanceEventType t)=>switch(t){AttendanceEventType.checkIn=>'ورود',AttendanceEventType.checkOut=>'خروج',AttendanceEventType.absence=>'غیبت',AttendanceEventType.mission=>'مأموریت',AttendanceEventType.manualCorrection=>'اصلاح دستی'};
 static IconData _icon(AttendanceEventType t)=>switch(t){AttendanceEventType.checkIn=>Icons.login,AttendanceEventType.checkOut=>Icons.logout,AttendanceEventType.absence=>Icons.event_busy,AttendanceEventType.mission=>Icons.directions_walk,AttendanceEventType.manualCorrection=>Icons.edit_note};
 static Future<void> _record(BuildContext context,AppDatabase db,String id,AttendanceEventType type)async{
  final now=DateTime.now();final note=TextEditingController();
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(type==AttendanceEventType.checkIn?'ثبت ورود':'ثبت خروج'),content:TextField(controller:note,decoration:const InputDecoration(labelText:'توضیحات (اختیاری)')),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ثبت'))]));
  if(ok!=true||!context.mounted)return;
  try{db.recordAttendance(AttendanceRecord(id:db.nextId('attendance'),employeeId:id,date:DateTime(now.year,now.month,now.day),at:now,type:type,note:note.text,createdBy:db.currentAccessAccount.name));AppToast.show(context,'ثبت حضور انجام شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}
  note.dispose();
 }
}