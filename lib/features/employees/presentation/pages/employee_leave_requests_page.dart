import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee_schedule.dart';

class EmployeeLeaveRequestsPage extends StatelessWidget{
 const EmployeeLeaveRequestsPage({super.key,required this.employeeId});final String employeeId;
 @override Widget build(BuildContext context){
  final db=context.watch<AppDatabase>();final e=db.employeeById(employeeId);
  if(e==null)return PageScaffold(title:'درخواست‌های مرخصی',showBackButton:true,child:EmptyState(title:'پرسنل یافت نشد'));
  final leaves=db.leavesForEmployee(employeeId);
  return PageScaffold(title:'درخواست‌های مرخصی',subtitle:e.fullName,showBackButton:true,actions:[SolidButton(label:'ثبت درخواست',icon:Icons.add,onPressed:()=>_request(context,db,employeeId))],
   mobileHeader:Wrap(children:[SoftButton(label:'ثبت درخواست مرخصی',icon:Icons.add,onTap:()=>_request(context,db,employeeId))]),
   child:AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const SectionHeader(title:'تاریخچه درخواست‌ها'),
    if(leaves.isEmpty)EmptyState(title:'درخواستی وجود ندارد'),
    for(final l in leaves)ListTile(contentPadding:EdgeInsets.zero,title:Text(l.type.label),subtitle:Text('${l.startAt.toString().split(' ').first} تا ${l.endAt.toString().split(' ').first}\n${l.description}'),trailing:Column(mainAxisSize:MainAxisSize.min,children:[Text(l.status.label,style:const TextStyle(fontSize:10)),if(l.status==EmployeeLeaveStatus.pending)Wrap(children:[IconButton(tooltip:'تأیید',onPressed:()=>_decide(context,db,l,EmployeeLeaveStatus.approved),icon:const Icon(Icons.check_circle_outline,color:Colors.green)),IconButton(tooltip:'رد',onPressed:()=>_decide(context,db,l,EmployeeLeaveStatus.rejected),icon:const Icon(Icons.cancel_outlined,color:Colors.red))])])) ,
   ])));
 }
 static Future<void> _request(BuildContext context,AppDatabase db,String id)async{
  final now=DateTime.now();final note=TextEditingController();EmployeeLeaveType type=EmployeeLeaveType.daily;
  final start=await showDatePicker(context:context,initialDate:now,firstDate:now,lastDate:now.add(const Duration(days:365)));if(start==null||!context.mounted)return;
  final end=await showDatePicker(context:context,initialDate:start,firstDate:start,lastDate:now.add(const Duration(days:365)));if(end==null||!context.mounted)return;
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('نوع مرخصی و توضیحات'),content:Column(mainAxisSize:MainAxisSize.min,children:[DropdownButtonFormField(value:type,items:EmployeeLeaveType.values.map((v)=>DropdownMenuItem(value:v,child:Text(v.label))).toList(),onChanged:(v){if(v!=null)type=v;}),TextField(controller:note,decoration:const InputDecoration(labelText:'دلیل درخواست'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ثبت'))]));
  if(ok==true&&context.mounted){try{db.addEmployeeLeave(EmployeeLeave(id:db.nextId('leave'),employeeId:id,startAt:DateTime(start.year,start.month,start.day),endAt:DateTime(end.year,end.month,end.day,23,59),type:type,status:EmployeeLeaveStatus.pending,description:note.text,createdAt:now));AppToast.show(context,'درخواست مرخصی ثبت شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
  note.dispose();
 }
 static void _decide(BuildContext context,AppDatabase db,EmployeeLeave l,EmployeeLeaveStatus status){try{db.updateEmployeeLeave(l.copyWith(status:status,approvedBy:db.currentAccessAccount.name));AppToast.show(context,status==EmployeeLeaveStatus.approved?'مرخصی تأیید شد.':'مرخصی رد شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
}