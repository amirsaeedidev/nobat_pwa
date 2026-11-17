import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../data/mock/app_database.dart';
class EmployeeNoticesPage extends StatelessWidget{
 const EmployeeNoticesPage({super.key,required this.employeeId});final String employeeId;
 @override Widget build(BuildContext context){
  final db=context.watch<AppDatabase>();final e=db.employeeById(employeeId);
  if(e==null)return PageScaffold(title:'اعلان‌های پرسنل',showBackButton:true,child:EmptyState(title:'پرسنل یافت نشد'));
  final notices=db.noticesFor(employeeId);
  return PageScaffold(title:'اعلان‌های پرسنل',subtitle:e.fullName,showBackButton:true,child:AppCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   const SectionHeader(title:'اعلان‌های آفلاین'),
   if(notices.isEmpty)EmptyState(title:'اعلانی وجود ندارد'),
   for(final n in notices)ListTile(contentPadding:EdgeInsets.zero,leading:Icon(n.read?Icons.notifications_none:Icons.notifications_active_outlined),title:Text(n.title),subtitle:Text('${n.message}\n${n.createdAt.toString().split('.').first}'),trailing:n.read?const Icon(Icons.done,color:Colors.green):TextButton(onPressed:()=>db.markEmployeeNoticeRead(n.id),child:const Text('خواندم'))),
  ])));
 }
}