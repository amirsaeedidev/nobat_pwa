import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../data/mock/app_database.dart';
import '../../../../data/models/employee_hr.dart';

class EmployeeRecordsPage extends StatelessWidget{
 const EmployeeRecordsPage({super.key,required this.employeeId});final String employeeId;
 @override Widget build(BuildContext context){
  final db=context.watch<AppDatabase>();final e=db.employeeById(employeeId);
  if(e==null)return PageScaffold(title:'پرونده دیجیتال',showBackButton:true,child:EmptyState(title:'پرسنل یافت نشد'));
  final docs=db.documentsFor(employeeId);
  return PageScaffold(title:'پرونده دیجیتال',subtitle:e.fullName,showBackButton:true,
   actions:[SolidButton(label:'افزودن سند نمونه',icon:Icons.add,onPressed:()=>_add(context,db,employeeId))],
   child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     const SectionHeader(title:'مدارک و اسناد'),
     if(docs.isEmpty)EmptyState(title:'سندی ثبت نشده'),
     for(final d in docs)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.description_outlined),title:Text(d.title),subtitle:Text('${d.fileName} · ${d.type.name}'),trailing:Icon(d.isExpired?Icons.error_outline:d.isExpiringSoon?Icons.warning_amber:Icons.verified_outlined,color:d.isExpired?Colors.red:d.isExpiringSoon?Colors.orange:Colors.green),onTap:()=>showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(d.title),content:Text('پیش‌نمایش فایل آزمایشی\n${d.mockPreview}\n\nنام فایل: ${d.fileName}\nتوضیحات: ${d.note}\nاعتبار: ${d.expiresAt?.toString().split(' ').first??'بدون تاریخ پایان'}'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('بستن'))]))),
    ])),
    const SizedBox(height:8),const Text('فایل‌ها نمونه نمایشی هستند؛ هیچ آپلود یا سرویس آنلاین لازم نیست.',style:TextStyle(fontSize:11)),
   ]));
 }
 static Future<void> _add(BuildContext context,AppDatabase db,String id)async{
  final title=TextEditingController();final file=TextEditingController(text:'sample-document.pdf');EmployeeDocumentType type=EmployeeDocumentType.certificate;
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('ثبت سند آزمایشی'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:title,decoration:const InputDecoration(labelText:'عنوان سند')),TextField(controller:file,decoration:const InputDecoration(labelText:'نام فایل نمونه')),DropdownButtonFormField(value:type,items:EmployeeDocumentType.values.map((v)=>DropdownMenuItem(value:v,child:Text(v.name))).toList(),onChanged:(v){if(v!=null)type=v;})]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ثبت'))]));
  if(ok==true&&context.mounted){try{db.addEmployeeDocument(EmployeeDocument(id:db.nextId('document'),employeeId:id,title:title.text,type:type,fileName:file.text,addedAt:DateTime.now()));AppToast.show(context,'سند نمونه ثبت شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
  title.dispose();file.dispose();
 }
}