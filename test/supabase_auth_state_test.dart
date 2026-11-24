import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:datetime/core/services/supabase_auth_state_notifier.dart';
import 'package:datetime/data/repositories/supabase_auth_repository.dart';
import 'package:datetime/data/repositories/supabase_repository.dart';

User _user(String id) => User.fromJson({
      'id': id,
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    })!;

class _FakeAuthRepository extends SupabaseAuthRepository {
  _FakeAuthRepository(this.user)
      : super(SupabaseClient('https://example.supabase.co', 'test-key'));

  User? user;
  final _events = StreamController<AuthState>.broadcast();

  @override
  User? get currentUser => user;

  @override
  Stream<AuthState> get onAuthStateChange => _events.stream;

  @override
  Future<void> signOut() async {
    user = null;
  }

  Future<void> dispose() => _events.close();
}

class _FakeSupabaseRepository extends SupabaseRepository {
  _FakeSupabaseRepository()
      : super(SupabaseClient('https://example.supabase.co', 'test-key'));

  Future<List<Map<String, dynamic>>> Function()? load;
  @override
  Future<List<Map<String, dynamic>>> fetchMyBusinesses() async =>
      load?.call() ?? <Map<String, dynamic>>[];
}

Map<String, dynamic> _membership({
  required String businessId,
  String role = 'owner',
  bool active = true,
}) =>
    {
      'business_id': businessId,
      'user_id': 'authenticated-user',
      'role': role,
      'permissions': <String, dynamic>{},
      'is_active': active,
      'businesses': {'id': businessId, 'name': 'DateTime'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthRepository auth;
  late _FakeSupabaseRepository data;
  late SupabaseAuthStateNotifier notifier;

  tearDown(() async {
    notifier.dispose();
    await auth.dispose();
  });

  test('loads active tenant and role only from Supabase membership', () async {
    auth = _FakeAuthRepository(_user('authenticated-user'));
    data = _FakeSupabaseRepository()
      ..load = () async => [_membership(businessId: 'datetime-business')];
    notifier = SupabaseAuthStateNotifier(auth, data);

    expect(await notifier.verifyMembership(), isTrue);
    expect(notifier.userId, 'authenticated-user');
    expect(notifier.businessId, 'datetime-business');
    expect(notifier.businessName, 'DateTime');
    expect(notifier.role, 'owner');
    expect(notifier.roleLabel, 'مدیر کل');
    expect(notifier.hasActiveBusiness, isTrue);
  });

  test('denies account without active membership', () async {
    auth = _FakeAuthRepository(_user('authenticated-user'));
    data = _FakeSupabaseRepository()
      ..load = () async => [_membership(businessId: 'disabled', active: false)];
    notifier = SupabaseAuthStateNotifier(auth, data);

    expect(await notifier.verifyMembership(), isFalse);
    expect(notifier.status, SupabaseAuthStatus.membershipRequired);
    expect(notifier.businessId, isNull);
    expect(notifier.role, isNull);
  });

  test('clears previously verified tenant on membership network failure', () async {
    auth = _FakeAuthRepository(_user('authenticated-user'));
    var shouldFail = false;
    data = _FakeSupabaseRepository()
      ..load = () async {
        if (shouldFail) throw const SocketException('offline');
        return [_membership(businessId: 'datetime-business')];
      };
    notifier = SupabaseAuthStateNotifier(auth, data);

    expect(await notifier.verifyMembership(), isTrue);
    shouldFail = true;
    expect(await notifier.retryVerification(), isFalse);
    expect(notifier.status, SupabaseAuthStatus.networkError);
    expect(notifier.businessId, isNull);
    expect(notifier.role, isNull);
  });

  test('late response from previous account cannot replace new account tenant', () async {
    auth = _FakeAuthRepository(_user('first-user'));
    final firstRequest = Completer<List<Map<String, dynamic>>>();
    var calls = 0;
    data = _FakeSupabaseRepository()
      ..load = () {
        calls++;
        if (calls == 1) return firstRequest.future;
        return Future.value([_membership(businessId: 'second-business', role: 'staff')]);
      };
    notifier = SupabaseAuthStateNotifier(auth, data);

    auth.user = _user('second-user');
    expect(await notifier.verifyMembership(), isTrue);
    firstRequest.complete([_membership(businessId: 'first-business')]);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.userId, 'second-user');
    expect(notifier.businessId, 'second-business');
    expect(notifier.role, 'staff');
  });

  test('logout clears authenticated tenant context', () async {
    auth = _FakeAuthRepository(_user('authenticated-user'));
    data = _FakeSupabaseRepository()
      ..load = () async => [_membership(businessId: 'datetime-business')];
    notifier = SupabaseAuthStateNotifier(auth, data);

    expect(await notifier.verifyMembership(), isTrue);
    await notifier.signOut();

    expect(auth.currentUser, isNull);
    expect(notifier.status, SupabaseAuthStatus.signedOut);
    expect(notifier.userId, isNull);
    expect(notifier.businessId, isNull);
    expect(notifier.role, isNull);
  });
}
