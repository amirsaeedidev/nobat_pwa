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
  final todayStart=DateTime(now.year,now.month,now.day),weekStart=DateTime(now.year,now.month,now.day).subtract(Duration(days:now.weekday-1));
  final daily=db.attendanceSummary(employeeId,from:todayStart,to:todayStart.add(const Duration(days:1)));
  final weekly=db.attendanceSummary(employeeId,from:weekStart,to:todayStart.add(const Duration(days:1)));
  final rows=db.attendanceFor(employeeId,from:from,to:to); final sum=db.attendanceSummary(employeeId,from:from,to:to);
  final hasIn=rows.any((r)=>r.type==AttendanceEventType.checkIn&&r.date.year==now.year&&r.date.month==now.month&&r.date.day==now.day);
  final hasOut=rows.any((r)=>r.type==AttendanceEventType.checkOut&&r.date.year==now.year&&r.date.month==now.month&&r.date.day==now.day);
  return PageScaffold(title:'حضور و غیاب',subtitle:e.fullName,showBackButton:true,actions:[
   SoftButton(label:'ثبت ورود',icon:Icons.login,onTap:()=>_record(context,db,e.id,AttendanceEventType.checkIn)),
   SolidButton(label:'ثبت خروج',icon:Icons.logout,onPressed:hasIn&&!hasOut?()=>_record(context,db,e.id,AttendanceEventType.checkOut):null),
  ],mobileHeader:Wrap(spacing:8,runSpacing:8,children:[
   SoftButton(label:'ورود',icon:Icons.login,onTap:()=>_record(context,db,e.id,AttendanceEventType.checkIn)),
   SoftButton(label:'خروج',icon:Icons.logout,onTap:hasIn&&!hasOut?()=>_record(context,db,e.id,AttendanceEventType.checkOut):null),
   SoftButton(label:'غیبت',icon:Icons.event_busy,onTap:()=>_special(context,db,e.id,AttendanceEventType.absence)),
   SoftButton(label:'مأموریت',icon:Icons.directions_walk,onTap:()=>_special(context,db,e.id,AttendanceEventType.mission)),
  ]),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   Wrap(spacing:8,runSpacing:8,children:[
    _metric('حضور امروز',daily.presentDays.toString()),_metric('حضور این هفته',weekly.presentDays.toString()),_metric('حضور ماه',sum.presentDays.toString()),_metric('غیبت ماه',sum.absentDays.toString()),
    _metric('ساعت کار',(sum.workedMinutes/60).toStringAsFixed(1)),_metric('اضافه‌کاری',FaNum.ofInt(sum.overtimeMinutes)+' دقیقه'),
    _metric('تأخیر',FaNum.ofInt(sum.lateMinutes)+' دقیقه'),_metric('خروج زودهنگام',FaNum.ofInt(sum.earlyLeaveMinutes)+' دقیقه'),
   ]),
   const SizedBox(height:12),
   Wrap(spacing:8,runSpacing:8,children:[
    SoftButton(label:'ثبت غیبت',icon:Icons.event_busy,onTap:()=>_special(context,db,e.id,AttendanceEventType.absence)),
    SoftButton(label:'ثبت مأموریت',icon:Icons.directions_walk,onTap:()=>_special(context,db,e.id,AttendanceEventType.mission)),
    SoftButton(label:'اصلاح دستی',icon:Icons.edit_note,onTap:()=>_manualCorrection(context,db,e.id)),
   ]),
   const SizedBox(height:12),
   AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const SectionHeader(title:'پیش‌نمایش اثر مالی حضور و غیاب'),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('فعال‌سازی قانون مالی حضور و غیاب'),value:db.attendancePayrollPolicy.enabled,onChanged:(v){
      final p=db.attendancePayrollPolicy;db.saveAttendancePayrollPolicy(AttendancePayrollPolicy(enabled:v,lateDeductionPerMinute:p.lateDeductionPerMinute,absenceDeductionPerDay:p.absenceDeductionPerDay,overtimePaymentPerMinute:p.overtimePaymentPerMinute,earlyLeaveDeductionPerMinute:p.earlyLeaveDeductionPerMinute));
    }),
    SoftButton(label:'تنظیم نرخ‌ها',icon:Icons.tune,onTap:()=>_configurePolicy(context,db)),
    Builder(builder:(context){
      final p=db.attendancePayrollPreview(employeeId,from:from,to:to);
      return Column(children:[
       _metric('کسر تأخیر',p.lateDeduction.toString()),
       _metric('کسر غیبت',p.absenceDeduction.toString()),
       _metric('اضافه‌کاری',p.overtimePayment.toString()),
       _metric('کسر خروج زودهنگام',p.earlyLeaveDeduction.toString()),
       _metric('خالص پیش‌نمایش',p.netAdjustment.toString()),
       const Text('این ارقام فقط پیش‌نمایش هستند و هیچ جریمه یا کسری خودکار در دفتر مالی ثبت نمی‌شود.',style:TextStyle(fontSize:10)),
      ]);
    }),
   ])),
   const SizedBox(height:12),
   AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const SectionHeader(title:'سوابق ماه جاری'),
    if(rows.isEmpty) EmptyState(title:'سابقه‌ای ثبت نشده'),
    for(final row in rows) ListTile(contentPadding:EdgeInsets.zero,
     leading:Icon(_icon(row.type)),title:Text(_label(row.type)),
     subtitle:Text('${row.at.hour.toString().padLeft(2,'0')}:${row.at.minute.toString().padLeft(2,'0')} · ${row.note}'),
     trailing:Wrap(mainAxisSize:MainAxisSize.min,children:[if(row.isManualCorrection)const Icon(Icons.edit_note,size:16),if(row.lateMinutes>0)Text('تأخیر ${row.lateMinutes}د'),if(row.overtimeMinutes>0)Text('اضافه‌کاری ${row.overtimeMinutes}د'),if(row.earlyLeaveMinutes>0)Text('خروج زودهنگام ${row.earlyLeaveMinutes}د'),IconButton(tooltip:'اصلاح رکورد',onPressed:()=>_editRecord(context,db,row),icon:const Icon(Icons.edit_outlined,size:18))]),
    ),
   ])),
   const SizedBox(height:8),Text('گزارش بازه ماهانه؛ تمام اطلاعات در Datamonck و آفلاین نگهداری می‌شوند.',style:Theme.of(context).textTheme.bodySmall),
  ]));
 }
 static Widget _metric(String label,String value)=>Container(width:145,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.black.withValues(alpha:.035),borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(fontSize:11)),const SizedBox(height:4),Text(value,style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold))]));
 static String _label(AttendanceEventType t)=>switch(t){AttendanceEventType.checkIn=>'ورود',AttendanceEventType.checkOut=>'خروج',AttendanceEventType.absence=>'غیبت',AttendanceEventType.mission=>'مأموریت',AttendanceEventType.manualCorrection=>'اصلاح دستی'};
 static IconData _icon(AttendanceEventType t)=>switch(t){AttendanceEventType.checkIn=>Icons.login,AttendanceEventType.checkOut=>Icons.logout,AttendanceEventType.absence=>Icons.event_busy,AttendanceEventType.mission=>Icons.directions_walk,AttendanceEventType.manualCorrection=>Icons.edit_note};
 static Future<void> _record(BuildContext context,AppDatabase db,String id,AttendanceEventType type)async{
  final now=DateTime.now();final note=TextEditingController(),minutes=TextEditingController(),early=TextEditingController();
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(type==AttendanceEventType.checkIn?'ثبت ورود':'ثبت خروج'),content:Column(mainAxisSize:MainAxisSize.min,children:[
   TextField(controller:note,decoration:const InputDecoration(labelText:'توضیحات (اختیاری)')),
   if(type==AttendanceEventType.checkIn)TextField(controller:minutes,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'دقایق تأخیر')),
   if(type==AttendanceEventType.checkOut)...[TextField(controller:minutes,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'دقایق اضافه‌کاری')),TextField(controller:early,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'دقایق خروج زودهنگام'))],
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ثبت'))]));
  if(ok!=true||!context.mounted){note.dispose();minutes.dispose();early.dispose();return;}
  final mins=int.tryParse(FaNum.toLatin(minutes.text))??0,earlyMins=int.tryParse(FaNum.toLatin(early.text))??0;
  try{db.recordAttendance(AttendanceRecord(id:db.nextId('attendance'),employeeId:id,date:DateTime(now.year,now.month,now.day),at:now,type:type,note:note.text,createdBy:db.currentAccessAccount.name,lateMinutes:type==AttendanceEventType.checkIn?mins:0,overtimeMinutes:type==AttendanceEventType.checkOut?mins:0,earlyLeaveMinutes:earlyMins));AppToast.show(context,'ثبت حضور انجام شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}
  note.dispose();minutes.dispose();early.dispose();
 }
 static Future<void> _special(BuildContext context,AppDatabase db,String id,AttendanceEventType type)async{
  final note=TextEditingController();
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(type==AttendanceEventType.absence?'ثبت غیبت':type==AttendanceEventType.mission?'ثبت مأموریت':'اصلاح دستی'),content:TextField(controller:note,decoration:const InputDecoration(labelText:'دلیل / توضیحات',hintText:'ثبت دلیل الزامی است')),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ثبت'))]));
  if(ok==true&&context.mounted){try{if(note.text.trim().isEmpty)throw ArgumentError('ثبت دلیل الزامی است.');final now=DateTime.now();db.recordAttendance(AttendanceRecord(id:db.nextId('attendance'),employeeId:id,date:DateTime(now.year,now.month,now.day),at:now,type:type,note:note.text,createdBy:db.currentAccessAccount.name));AppToast.show(context,'رویداد ثبت شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
  note.dispose();
 }
 static Future<void> _configurePolicy(BuildContext context,AppDatabase db)async{
  final p=db.attendancePayrollPolicy;
  final late=TextEditingController(text:p.lateDeductionPerMinute.toString()),absence=TextEditingController(text:p.absenceDeductionPerDay.toString()),overtime=TextEditingController(text:p.overtimePaymentPerMinute.toString()),early=TextEditingController(text:p.earlyLeaveDeductionPerMinute.toString());
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('قانون مالی حضور و غیاب'),content:Column(mainAxisSize:MainAxisSize.min,children:[
   TextField(controller:late,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'کسر هر دقیقه تأخیر (تومان)')),
   TextField(controller:absence,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'کسر هر روز غیبت (تومان)')),
   TextField(controller:overtime,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'پرداخت هر دقیقه اضافه‌کاری (تومان)')),
   TextField(controller:early,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'کسر هر دقیقه خروج زودهنگام (تومان)')),
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ذخیره نرخ‌ها'))]));
  if(ok==true&&context.mounted){try{db.saveAttendancePayrollPolicy(AttendancePayrollPolicy(enabled:p.enabled,lateDeductionPerMinute:int.parse(FaNum.toLatin(late.text)),absenceDeductionPerDay:int.parse(FaNum.toLatin(absence.text)),overtimePaymentPerMinute:int.parse(FaNum.toLatin(overtime.text)),earlyLeaveDeductionPerMinute:int.parse(FaNum.toLatin(early.text))));AppToast.show(context,'قانون مالی ذخیره شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
  late.dispose();absence.dispose();overtime.dispose();early.dispose();
 }
 static Future<void> _manualCorrection(BuildContext context,AppDatabase db,String id) async {
  var date=DateTime.now();var time=TimeOfDay.now();var type=AttendanceEventType.checkIn;
  final note=TextEditingController();
  final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setState)=>AlertDialog(
   title:const Text('ثبت اصلاح دستی حضور'),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    DropdownButtonFormField<AttendanceEventType>(value:type,decoration:const InputDecoration(labelText:'نوع رکورد'),items:const [AttendanceEventType.checkIn,AttendanceEventType.checkOut].map((v)=>DropdownMenuItem(value:v,child:Text(v==AttendanceEventType.checkIn?'اصلاح ساعت ورود':'اصلاح ساعت خروج'))).toList(),onChanged:(v){if(v!=null)setState(()=>type=v);}),
    ListTile(contentPadding:EdgeInsets.zero,title:const Text('تاریخ'),subtitle:Text(date.toString().split(' ').first),trailing:const Icon(Icons.calendar_month),onTap:()async{final v=await showDatePicker(context:c,initialDate:date,firstDate:DateTime(2020),lastDate:DateTime.now().add(const Duration(days:365)));if(v!=null)setState(()=>date=v);}),
    ListTile(contentPadding:EdgeInsets.zero,title:const Text('ساعت'),subtitle:Text(time.format(c)),trailing:const Icon(Icons.schedule),onTap:()async{final v=await showTimePicker(context:c,initialTime:time);if(v!=null)setState(()=>time=v);}),
    TextField(controller:note,decoration:const InputDecoration(labelText:'دلیل اصلاح (الزامی)')),
   ])),
   actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ثبت اصلاح'))],
  )));
  if(ok==true&&context.mounted){try{if(note.text.trim().isEmpty)throw ArgumentError('دلیل اصلاح الزامی است.');final at=DateTime(date.year,date.month,date.day,time.hour,time.minute);db.recordAttendance(AttendanceRecord(id:db.nextId('attendance'),employeeId:id,date:DateTime(date.year,date.month,date.day),at:at,type:type,note:note.text,createdBy:db.currentAccessAccount.name,isManualCorrection:true));AppToast.show(context,'اصلاح دستی ثبت شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
  note.dispose();
 }
 static Future<void> _editRecord(BuildContext context,AppDatabase db,AttendanceRecord record) async {
  var date=record.date;var time=TimeOfDay.fromDateTime(record.at);final note=TextEditingController(text:record.note);
  final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setState)=>AlertDialog(
   title:const Text('اصلاح رکورد حضور'),
   content:Column(mainAxisSize:MainAxisSize.min,children:[
    ListTile(title:const Text('تاریخ'),subtitle:Text(date.toString().split(' ').first),onTap:()async{final v=await showDatePicker(context:c,initialDate:date,firstDate:DateTime(2020),lastDate:DateTime.now().add(const Duration(days:365)));if(v!=null)setState(()=>date=v);}),
    ListTile(title:const Text('ساعت'),subtitle:Text(time.format(c)),onTap:()async{final v=await showTimePicker(context:c,initialTime:time);if(v!=null)setState(()=>time=v);}),
    TextField(controller:note,decoration:const InputDecoration(labelText:'دلیل اصلاح (الزامی)')),
   ]),
   actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ذخیره اصلاح'))],
  )));
  if(ok==true&&context.mounted){try{if(note.text.trim().isEmpty)throw ArgumentError('دلیل اصلاح الزامی است.');db.updateAttendanceRecord(record.copyWith(date:DateTime(date.year,date.month,date.day),at:DateTime(date.year,date.month,date.day,time.hour,time.minute),note:note.text));AppToast.show(context,'رکورد اصلاح شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
  note.dispose();
 }


}