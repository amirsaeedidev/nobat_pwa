import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live integration test. It intentionally requires a dedicated test employee
/// and an authenticated access token; it never uses AppDatabase or seeded mocks.
/// The test posts a 1 Toman bonus and settles that same 1 Toman so the net
/// wallet balance is unchanged. Ledger/audit rows remain as an audit trail.
void main() {
  const urlKey = 'DATETIME_SUPABASE_URL';
  const anonKeyName = 'DATETIME_SUPABASE_ANON_KEY';
  const tokenName = 'DATETIME_SUPABASE_ACCESS_TOKEN';
  const businessName = 'DATETIME_SUPABASE_BUSINESS_ID';
  const employeeName = 'DATETIME_SUPABASE_TEST_EMPLOYEE_ID';

  final env = Platform.environment;
  final configured = [urlKey, anonKeyName, tokenName, businessName, employeeName]
      .every((key) => (env[key] ?? '').trim().isNotEmpty);

  test('authenticated owner can submit concurrent idempotent wallet and settlement RPCs', () async {
    final client = SupabaseClient(
      env[urlKey]!,
      env[anonKeyName]!,
      headers: {'Authorization': 'Bearer ${env[tokenName]!}'},
    );
    addTearDown(client.dispose);

    final user = await client.auth.getUser(env[tokenName]!);
    final membership = await client.from('business_memberships')
        .select('role,is_active')
        .eq('business_id', env[businessName]!)
        .eq('user_id', user.user!.id)
        .eq('is_active', true)
        .single();
    expect(membership['role'], 'owner');

    final businessId = env[businessName]!;
    final employeeId = env[employeeName]!;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final walletKey = 'ci-wallet-$stamp';
    final settlementKey = 'ci-settlement-$stamp';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final walletResults = await Future.wait([
      client.rpc('record_employee_wallet_transaction', params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
        'p_amount_toman': 1,
        'p_transaction_type': 'bonus',
        'p_direction': 'credit',
        'p_description': 'INTEGRATION_TEST wallet concurrency $stamp',
        'p_idempotency_key': walletKey,
      }),
      client.rpc('record_employee_wallet_transaction', params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
        'p_amount_toman': 1,
        'p_transaction_type': 'bonus',
        'p_direction': 'credit',
        'p_description': 'INTEGRATION_TEST wallet concurrency $stamp',
        'p_idempotency_key': walletKey,
      }),
    ]);
    expect(walletResults[0], walletResults[1]);

    final settlementResults = await Future.wait([
      client.rpc('settle_employee_wallet', params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
        'p_period_type': 'manual',
        'p_period_start': today,
        'p_period_end': today,
        'p_amount_toman': 1,
        'p_method': 'other',
        'p_description': 'INTEGRATION_TEST concurrent settlement $stamp',
        'p_idempotency_key': settlementKey,
      }),
      client.rpc('settle_employee_wallet', params: {
        'p_business_id': businessId,
        'p_employee_id': employeeId,
        'p_period_type': 'manual',
        'p_period_start': today,
        'p_period_end': today,
        'p_amount_toman': 1,
        'p_method': 'other',
        'p_description': 'INTEGRATION_TEST concurrent settlement $stamp',
        'p_idempotency_key': settlementKey,
      }),
    ]);
    expect(settlementResults[0], settlementResults[1]);

    final walletRows = await client.from('employee_wallet_transactions')
        .select('id').eq('business_id', businessId)
        .eq('employee_id', employeeId).eq('idempotency_key', walletKey);
    final settlementRows = await client.from('employee_settlements')
        .select('id').eq('business_id', businessId)
        .eq('employee_id', employeeId).eq('idempotency_key', settlementKey);
    expect(walletRows, hasLength(1));
    expect(settlementRows, hasLength(1));
  }, skip: configured ? false :
      'Set DATETIME_SUPABASE_URL, DATETIME_SUPABASE_ANON_KEY, DATETIME_SUPABASE_ACCESS_TOKEN, DATETIME_SUPABASE_BUSINESS_ID and DATETIME_SUPABASE_TEST_EMPLOYEE_ID for live integration testing.');
}
