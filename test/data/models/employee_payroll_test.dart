import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/models/employee_payroll.dart';
void main() {
 final date=DateTime(2026,11,18);
 test('approved payroll items only; salary, commission, bonus, deductions, advance and payments', () {
  final c=SalaryContract(id:'s',employeeId:'e',monthlyBase:20000000,effectiveFrom:DateTime(2026,1,1));
  final r=EmployeePayrollCalculator.calculate(contract:c,at:date,approvedCommission:5000000,adjustments:[
   PayrollAdjustment(id:'b',employeeId:'e',amount:1000000,date:date,description:'عملکرد',createdBy:'مدیر',status:PayrollRecordStatus.approved,bonusType:PayrollBonusType.performance),
   PayrollAdjustment(id:'d',employeeId:'e',amount:500000,date:date,description:'تاخیر',createdBy:'مدیر',status:PayrollRecordStatus.approved,deductionType:PayrollDeductionType.lateness),
   PayrollAdjustment(id:'p',employeeId:'e',amount:900000,date:date,description:'در انتظار',createdBy:'مدیر',status:PayrollRecordStatus.pending,bonusType:PayrollBonusType.manual),
  ],advances:[PayrollAdvance(id:'a',employeeId:'e',amount:3000000,requestedAt:date,description:'مساعده',status:AdvanceStatus.deducted,deductedAmount:1000000)],previousPayments:4000000);
  expect(r.gross,26000000); expect(r.totalDeductions,5500000); expect(r.payable,20500000);
 });
 test('salary expires at effective end date', () {
  final c=SalaryContract(id:'s',employeeId:'e',monthlyBase:10000000,effectiveFrom:DateTime(2026,1,1),effectiveTo:DateTime(2026,10,31));
  expect(EmployeePayrollCalculator.calculate(contract:c,at:date,approvedCommission:0,adjustments:const[],advances:const[],previousPayments:0).baseSalary,0);
 });
 test('negative payable is debt', () {
  final r=EmployeePayrollCalculator.calculate(contract:null,at:date,approvedCommission:100,adjustments:const[],advances:const[],previousPayments:250);
  expect(r.payable,-150); expect(r.debt,150); expect(r.remainingPayable,0);
 });
 test('target progress and advance balance', () {
  final t=EmployeePerformanceTarget(id:'t',employeeId:'e',type:PerformanceTargetType.monthlyRevenue,targetValue:1000,periodStart:DateTime(2026,11,1),periodEnd:DateTime(2026,11,30));
  expect(t.progress(750),0.75);
  final a=PayrollAdvance(id:'a',employeeId:'e',amount:500,requestedAt:date,description:'مساعده',status:AdvanceStatus.paid,deductedAmount:200);
  expect(a.outstanding,300);
 });
 test('rejects negative commission', () => expect(() => EmployeePayrollCalculator.calculate(contract:null,at:date,approvedCommission:-1,adjustments:const[],advances:const[],previousPayments:0),throwsArgumentError));
}