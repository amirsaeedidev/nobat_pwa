import 'package:flutter_test/flutter_test.dart';
import 'package:datetime/data/models/employee_payroll.dart';
import 'package:datetime/data/mock/app_database.dart';
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
 test('Datamonck seeds payroll records for at least five employees', () {
  final db=AppDatabase();
  expect(db.employees.length, greaterThanOrEqualTo(5));
  for (final employee in db.employees.take(5)) {
   expect(db.salaryContractsFor(employee.id), isNotEmpty);
   expect(db.performanceTargets.any((target)=>target.employeeId==employee.id), isTrue);
  }
 });
 test('salary changes append history and payroll reads the active contract', () {
  final db=AppDatabase(); final employee=db.employees.first;
  final first=db.salaryContractsFor(employee.id).first;
  db.saveSalaryContract(SalaryContract(id:'salary-next',employeeId:employee.id,monthlyBase:25000000,effectiveFrom:date));
  expect(db.salaryContractsFor(employee.id),hasLength(2));
  expect(db.payrollFor(employee.id,at:date).baseSalary,25000000);
  expect(first.monthlyBase,isNot(25000000));
 });
 test('rejects duplicate payroll adjustment identifiers', () {
  final db=AppDatabase(); final employee=db.employees.first;
  final item=PayrollAdjustment(id:'unique-adjustment',employeeId:employee.id,amount:100,date:date,
    description:'پاداش',createdBy:'مدیر',status:PayrollRecordStatus.approved,bonusType:PayrollBonusType.manual);
  db.addPayrollAdjustment(item);
  expect(()=>db.addPayrollAdjustment(item),throwsStateError);
 });
 test('rejects negative commission', () => expect(() => EmployeePayrollCalculator.calculate(contract:null,at:date,approvedCommission:-1,adjustments:const[],advances:const[],previousPayments:0),throwsArgumentError));
}