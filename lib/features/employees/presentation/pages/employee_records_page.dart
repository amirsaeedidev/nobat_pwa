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
   mobileHeader:Wrap(children:[SoftButton(label:'افزودن سند نمونه',icon:Icons.add,onTap:()=>_add(context,db,employeeId))]),
   child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     const SectionHeader(title:'مدارک و اسناد'),
     if(docs.isEmpty)EmptyState(title:'سندی ثبت نشده'),
     for(final d in docs)ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.description_outlined),title:Text(d.title),subtitle:Text('${d.fileName} · ${d.type.name}'),trailing:Wrap(mainAxisSize:MainAxisSize.min,children:[Icon(d.isExpired?Icons.error_outline:d.isExpiringSoon?Icons.warning_amber:Icons.verified_outlined,color:d.isExpired?Colors.red:d.isExpiringSoon?Colors.orange:Colors.green),PopupMenuButton<String>(onSelected:(v){if(v=='edit')_edit(context,db,d);if(v=='delete'){try{db.deleteEmployeeDocument(d.id);AppToast.show(context,'سند حذف شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}},itemBuilder:(c)=>const [PopupMenuItem(value:'edit',child:Text('ویرایش')),PopupMenuItem(value:'delete',child:Text('حذف'))])]),onTap:()=>showDialog<void>(context:context,builder:(c)=>AlertDialog(title:Text(d.title),content:Text('پیش‌نمایش فایل آزمایشی\n${d.mockPreview}\n\nنام فایل: ${d.fileName}\nتوضیحات: ${d.note}\nاعتبار: ${d.expiresAt?.toString().split(' ').first??'بدون تاریخ پایان'}'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('بستن'))]))),
    ])),
    const SizedBox(height:8),const Text('فایل‌ها نمونه نمایشی هستند؛ هیچ آپلود یا سرویس آنلاین لازم نیست.',style:TextStyle(fontSize:11)),
   ]));
 }
 static Future<void> _add(BuildContext context,AppDatabase db,String id)async{
  final title=TextEditingController(),note=TextEditingController();String file='contract-sample.pdf';EmployeeDocumentType type=EmployeeDocumentType.certificate;DateTime? expiresAt;
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('ثبت سند آزمایشی'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:title,decoration:const InputDecoration(labelText:'عنوان سند')),DropdownButtonFormField<String>(value:file,decoration:const InputDecoration(labelText:'انتخاب فایل آزمایشی'),items:const ['contract-sample.pdf','identity-card-demo.png','certificate-demo.pdf','specialty-license-demo.pdf','employee-attachment-demo.pdf'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)file=v;}),DropdownButtonFormField(value:type,items:EmployeeDocumentType.values.map((v)=>DropdownMenuItem(value:v,child:Text(switch(v){EmployeeDocumentType.contract=>'قرارداد',EmployeeDocumentType.identity=>'مدرک شناسایی',EmployeeDocumentType.certificate=>'گواهی',EmployeeDocumentType.specialty=>'مدرک تخصصی',EmployeeDocumentType.attachment=>'فایل مرتبط'}))).toList(),onChanged:(v){if(v!=null)type=v;}),TextField(controller:note,decoration:const InputDecoration(labelText:'توضیحات')),StatefulBuilder(builder:(c,setState)=>ListTile(title:const Text('تاریخ اعتبار سند'),subtitle:Text(expiresAt?.toString().split(' ').first??'بدون تاریخ انقضا'),trailing:Wrap(children:[IconButton(icon:const Icon(Icons.calendar_month),onPressed:()async{final v=await showDatePicker(context:c,initialDate:DateTime.now().add(const Duration(days:30)),firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:3650)));if(v!=null)setState(()=>expiresAt=v);}),if(expiresAt!=null)IconButton(icon:const Icon(Icons.clear),onPressed:()=>setState(()=>expiresAt=null))]))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ثبت'))]));
  if(ok==true&&context.mounted){try{db.addEmployeeDocument(EmployeeDocument(id:db.nextId('document'),employeeId:id,title:title.text,type:type,fileName:file,addedAt:DateTime.now(),expiresAt:expiresAt,note:note.text));AppToast.show(context,'سند نمونه ثبت شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
  title.dispose();note.dispose();
 }
  static Future<void> _edit(BuildContext context,AppDatabase db,EmployeeDocument document)async{
  final title=TextEditingController(text:document.title),note=TextEditingController(text:document.note);DateTime? expiry=document.expiresAt;
  final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setState)=>AlertDialog(title:const Text('ویرایش سند'),content:Column(mainAxisSize:MainAxisSize.min,children:[
   TextField(controller:title,decoration:const InputDecoration(labelText:'عنوان سند')),
   TextField(controller:note,decoration:const InputDecoration(labelText:'توضیحات')),
   ListTile(title:const Text('اعتبار تا'),subtitle:Text(expiry?.toString().split(' ').first??'بدون تاریخ پایان'),onTap:()async{final v=await showDatePicker(context:c,initialDate:expiry??DateTime.now().add(const Duration(days:30)),firstDate:DateTime(2020),lastDate:DateTime.now().add(const Duration(days:3650)));if(v!=null)setState(()=>expiry=v);}),
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('ذخیره'))])));
  if(ok==true&&context.mounted){try{db.updateEmployeeDocument(EmployeeDocument(id:document.id,employeeId:document.employeeId,title:title.text,type:document.type,fileName:document.fileName,addedAt:document.addedAt,expiresAt:expiry,note:note.text));AppToast.show(context,'سند ویرایش شد.');}catch(e){AppToast.show(context,e.toString(),success:false);}}
  title.dispose();note.dispose();
 }

}