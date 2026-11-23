
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/supabase_auth_repository.dart';
import '../../data/repositories/supabase_repository.dart';

/// Auth session and active business verification for cloud mode.
class SupabaseAuthStateNotifier extends ChangeNotifier {
  SupabaseAuthStateNotifier(this._authRepository, this._dataRepository) {
    if (_authRepository == null || _dataRepository == null) return;

    _subscription = _authRepository!.onAuthStateChange.listen(
      (state) {
        if (state.session == null) {
          _clearMembership();
        } else {
          unawaited(verifyMembership());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[DateTime][SupabaseAuth] Auth stream error: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );

    if (_authRepository!.currentUser != null) {
      unawaited(verifyMembership());
    }
  }

  final SupabaseAuthRepository? _authRepository;
  final SupabaseRepository? _dataRepository;

  StreamSubscription<dynamic>? _subscription;
  Future<bool>? _verification;

  bool _isCheckingMembership = false;
  bool _hasActiveBusiness = false;
  String? _businessId;
  String? _businessName;
  String? _role;
  String? _verificationError;

  bool get isCheckingMembership => _isCheckingMembership;
  bool get hasActiveBusiness => _hasActiveBusiness;
  String? get businessId => _businessId;
  String? get businessName => _businessName;
  String? get role => _role;
  String? get verificationError => _verificationError;
  String get roleLabel => _role == 'owner' ? 'مدیر کل' : 'نقش محدود';

  Future<bool> verifyMembership() async {
    final pending = _verification;
    if (pending != null) return pending;

    final request = _loadMembership();
    _verification = request;
    try {
      return await request;
    } finally {
      if (identical(_verification, request)) {
        _verification = null;
      }
    }
  }

  Future<bool> _loadMembership() async {
    final auth = _authRepository;
    final data = _dataRepository;

    if (auth?.currentUser == null || data == null) {
      _clearMembership();
      _verificationError = 'ابتدا وارد حساب Supabase شوید.';
      notifyListeners();
      return false;
    }

    _isCheckingMembership = true;
    _hasActiveBusiness = false;
    _businessId = null;
    _businessName = null;
    _role = null;
    _verificationError = null;
    notifyListeners();

    try {
      final memberships = await data.fetchMyBusinesses();
      for (final rawMembership in memberships) {
        final membership = Map<String, dynamic>.from(rawMembership);
        final role = membership['role'] as String? ?? '';
        if (role != 'owner') continue;

        final rawBusiness = membership['businesses'];
        final business = rawBusiness is Map
            ? Map<String, dynamic>.from(rawBusiness)
            : <String, dynamic>{};

        _businessId = membership['business_id'] as String? ??
            business['id'] as String?;
        _businessName = business['name'] as String?;
        _role = role;
        _hasActiveBusiness = _businessId != null;
        if (_hasActiveBusiness) break;
      }

      if (!_hasActiveBusiness) {
        _verificationError = memberships.isEmpty
            ? 'این حساب به هیچ مجموعه فعالی متصل نیست.'
            : 'عضویت این حساب وجود دارد، اما نقش آن هنوز در این مرحله پشتیبانی نمی‌شود.';
      }
      return _hasActiveBusiness;
    } catch (error, stackTrace) {
      debugPrint('[DateTime][SupabaseAuth] Membership check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _verificationError =
          'ارتباط با سرور برای بررسی دسترسی برقرار نشد. اتصال اینترنت را بررسی و دوباره تلاش کنید.';
      return false;
    } finally {
      _isCheckingMembership = false;
      notifyListeners();
    }
  }

  void _clearMembership() {
    _isCheckingMembership = false;
    _hasActiveBusiness = false;
    _businessId = null;
    _businessName = null;
    _role = null;
    _verificationError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    final subscription = _subscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
