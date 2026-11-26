import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee_schedule.dart';

class EmployeeLeaveRequestsPage extends StatelessWidget {
 const EmployeeLeaveRequestsPage({super.key,required this.employeeId});
 final String employeeId;
 @override Widget build(BuildContext context) {
  final db=context.watch<AppDatabase>(); final employee=db.employeeById(employeeId);
  if(employee==null) return PageScaffold(title:'درخواست‌های مرخصی',showBackButton:true,child:EmptyState(title:'پرسنل یافت نشد'));
  final leaves=db.leavesForEmployee(employeeId);
  final canApprove=db.hasPermission('employees.edit',employeeId:employeeId);
  return PageScaffold(title:'درخواست‌های مرخصی',subtitle:employee.fullName,showBackButton:true,
   actions:[SolidButton(label:'ثبت درخواست',icon:Icons.add,onPressed:()=>_request(context,db,employeeId))],
   mobileHeader:Wrap(spacing:8,children:[SoftButton(label:'ثبت درخواست مرخصی',icon:Icons.add,onTap:()=>_request(context,db,employeeId))]),
   child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     const SectionHeader(title:'تاریخچه درخواست‌ها'),
     if(leaves.isEmpty)const EmptyState(title:'درخواستی وجود ندارد',description:'درخواست‌های مرخصی این پرسنل در این قسمت نمایش داده می‌شود.'),
     for(final leave in leaves)Padding(padding:const EdgeInsets.only(top:10),child:Container(
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(border:Border.all(color:Theme.of(context).dividerColor),borderRadius:BorderRadius.circular(14)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Wrap(alignment:WrapAlignment.spaceBetween,crossAxisAlignment:WrapCrossAlignment.center,spacing:8,runSpacing:6,children:[
        Text(leave.type.label,style:Theme.of(context).textTheme.titleSmall),
        _status(context,leave.status),
       ]),
       const SizedBox(height:6),
       Text('از '+_date(leave.startAt)+' تا '+_date(leave.endAt),style:Theme.of(context).textTheme.bodySmall),
       if(leave.description.isNotEmpty)Padding(padding:const EdgeInsets.only(top:4),child:Text(leave.description)),
       if(leave.approvedBy!=null)Padding(padding:const EdgeInsets.only(top:4),child:Text('بررسی توسط: '+leave.approvedBy!,style:Theme.of(context).textTheme.bodySmall)),
       if(canApprove&&leave.status==EmployeeLeaveStatus.pending) ...[
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
         SoftButton(label:'تأیید',icon:Icons.check_circle_outline,color:Colors.green,onTap:()=>_decide(context,db,leave,EmployeeLeaveStatus.approved)),
         SoftButton(label:'رد',icon:Icons.cancel_outlined,color:Theme.of(context).colorScheme.error,onTap:()=>_decide(context,db,leave,EmployeeLeaveStatus.rejected)),
        ]),
       ],
      ]),
     )),
    ])),
    const SizedBox(height:8),
    Text('فقط مرخصی تأییدشده برنامه کاری و امکان رزرو را مسدود می‌کند.',style:Theme.of(context).textTheme.bodySmall),
   ]));
 }
 static Widget _status(BuildContext context,EmployeeLeaveStatus status) {
  final color=switch(status){EmployeeLeaveStatus.pending=>Colors.orange,EmployeeLeaveStatus.approved=>Colors.green,EmployeeLeaveStatus.rejected=>Theme.of(context).colorScheme.error,EmployeeLeaveStatus.cancelled=>Colors.grey};
  return Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),decoration:BoxDecoration(color:color.withValues(alpha:.1),borderRadius:BorderRadius.circular(20)),child:Text(status.label,style:TextStyle(color:color,fontSize:11,fontWeight:FontWeight.w700)));
 }
 static String _date(DateTime d)=>d.year.toString()+'/'+d.month.toString().padLeft(2,'0')+'/'+d.day.toString().padLeft(2,'0');
 static Future<void> _request(BuildContext context,AppDatabase db,String id) async {
  final now=DateTime.now();final note=TextEditingController();EmployeeLeaveType type=EmployeeLeaveType.daily;
  final start=await showDatePicker(context:context,initialDate:now,firstDate:now,lastDate:now.add(const Duration(days:365)));
  if(start==null||!context.mounted){note.dispose();return;}
  final end=await showDatePicker(context:context,initialDate:start,firstDate:start,lastDate:now.add(const Duration(days:365)));
  if(end==null||!context.mounted){note.dispose();return;}
  final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setState)=>AlertDialog(
   title:const Text('ثبت درخواست مرخصی'),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    DropdownButtonFormField<EmployeeLeaveType>(value:type,decoration:const InputDecoration(labelText:'نوع مرخصی'),items:EmployeeLeaveType.values.map((v)=>DropdownMenuItem(value:v,child:Text(v.label))).toList(),onChanged:(v){if(v!=null)setState(()=>type=v);}),
    TextField(controller:note,minLines:2,maxLines:4,decoration:const InputDecoration(labelText:'توضیحات و دلیل درخواست *')),
   ])),
   actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ثبت درخواست'))],
  )));
  if(ok==true&&context.mounted) {
   try {
    if(note.text.trim().isEmpty)throw ArgumentError('توضیحات درخواست الزامی است.');
    var leaveStart=DateTime(start.year,start.month,start.day);
    var leaveEnd=DateTime(end.year,end.month,end.day,23,59);
    if(type==EmployeeLeaveType.hourly){
     final fromTime=await showTimePicker(context:context,initialTime:const TimeOfDay(hour:9,minute:0));
     if(fromTime==null||!context.mounted){note.dispose();return;}
     final toTime=await showTimePicker(context:context,initialTime:const TimeOfDay(hour:10,minute:0));
     if(toTime==null||!context.mounted){note.dispose();return;}
     leaveStart=DateTime(start.year,start.month,start.day,fromTime.hour,fromTime.minute);
     leaveEnd=DateTime(end.year,end.month,end.day,toTime.hour,toTime.minute);
    }
    db.addEmployeeLeave(EmployeeLeave(id:db.nextId('leave'),employeeId:id,startAt:leaveStart,endAt:leaveEnd,type:type,status:EmployeeLeaveStatus.pending,description:note.text.trim(),createdAt:now));
    AppToast.show(context,'درخواست مرخصی ثبت شد.');
   } catch(e){AppToast.show(context,e.toString(),success:false);}
  }
  note.dispose();
 }
 static void _decide(BuildContext context,AppDatabase db,EmployeeLeave leave,EmployeeLeaveStatus status) {
  try {
   db.updateEmployeeLeave(leave.copyWith(status:status,approvedBy:db.currentAccessAccount.name));
   AppToast.show(context,status==EmployeeLeaveStatus.approved?'مرخصی تأیید شد.':'مرخصی رد شد.');
  } catch(e){AppToast.show(context,e.toString(),success:false);}
 }
}
