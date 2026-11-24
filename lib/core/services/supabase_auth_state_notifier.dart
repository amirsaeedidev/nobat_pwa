import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/supabase_auth_repository.dart';
import '../../data/repositories/supabase_repository.dart';

/// Authentication and tenant membership state derived only from Supabase.
class SupabaseAuthStateNotifier extends ChangeNotifier {
  SupabaseAuthStateNotifier(this._authRepository, this._dataRepository) {
    if (_authRepository == null || _dataRepository == null) {
      _status = SupabaseAuthStatus.unavailable;
      return;
    }

    _subscription = _authRepository.onAuthStateChange.listen(
      _handleAuthState,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[DateTime][SupabaseAuth] Auth stream error: $error');
        debugPrintStack(stackTrace: stackTrace);
        _setNetworkError(error);
      },
    );

    if (_authRepository.currentUser != null) {
      unawaited(verifyMembership());
    } else {
      _status = SupabaseAuthStatus.signedOut;
    }
  }

  final SupabaseAuthRepository? _authRepository;
  final SupabaseRepository? _dataRepository;

  StreamSubscription<dynamic>? _subscription;
  Future<bool>? _verification;
  String? _verificationUserId;
  int _generation = 0;

  SupabaseAuthStatus _status = SupabaseAuthStatus.initializing;
  String? _userId;
  String? _businessId;
  String? _businessName;
  String? _role;
  Map<String, dynamic> _permissions = const {};
  String? _verificationError;

  SupabaseAuthStatus get status => _status;
  bool get isCheckingMembership =>
      _status == SupabaseAuthStatus.initializing ||
      _status == SupabaseAuthStatus.checkingMembership;
  bool get hasActiveBusiness => _status == SupabaseAuthStatus.authenticated;
  bool get isSignedIn => _authRepository?.currentUser != null;
  String? get userId => _userId;
  String? get userEmail => _authRepository?.currentUser?.email;
  String? get businessId => _businessId;
  String? get businessName => _businessName;
  String? get role => _role;
  Map<String, dynamic> get permissions => Map.unmodifiable(_permissions);
  String? get verificationError => _verificationError;

  String get roleLabel => switch (_role) {
        'owner' => 'مدیر کل',
        'staff' || 'personnel' => 'پرسنل',
        null => 'بدون نقش',
        final value => value,
      };

  void _handleAuthState(dynamic state) {
    final session = state.session;
    final nextUserId = session?.user.id as String?;
    if (nextUserId == null) {
      _generation++;
      _verification = null;
      _verificationUserId = null;
      _clearMembership(status: SupabaseAuthStatus.signedOut);
      return;
    }

    // Invalidate every result started under a previous account. This also
    // handles switching accounts without briefly retaining the old tenant.
    if (_userId != nextUserId) {
      _generation++;
      _verification = null;
      _verificationUserId = null;
      _clearMembership(status: SupabaseAuthStatus.checkingMembership);
    }
    unawaited(verifyMembership());
  }

  Future<bool> verifyMembership() async {
    final userId = _authRepository?.currentUser?.id;
    final data = _dataRepository;
    if (userId == null || data == null) {
      _generation++;
      _clearMembership(status: SupabaseAuthStatus.signedOut);
      return false;
    }

    final pending = _verification;
    if (pending != null && _verificationUserId == userId) {
      return pending;
    }

    final generation = ++_generation;
    _verificationUserId = userId;
    final request = _loadMembership(userId, generation);
    _verification = request;
    try {
      return await request;
    } finally {
      if (identical(_verification, request)) {
        _verification = null;
        _verificationUserId = null;
      }
    }
  }

  Future<bool> _loadMembership(String expectedUserId, int generation) async {
    final data = _dataRepository;
    if (data == null) return false;

    _userId = expectedUserId;
    _status = SupabaseAuthStatus.checkingMembership;
    _businessId = null;
    _businessName = null;
    _role = null;
    _permissions = const {};
    _verificationError = null;
    notifyListeners();

    try {
      final memberships = await data.fetchMyBusinesses();
      if (!_isCurrentRequest(expectedUserId, generation)) return false;

      // Membership is authoritative. Never infer a role from email, user
      // metadata, a local account picker, or a hard-coded user identifier.
      if (memberships.isEmpty) {
        _status = SupabaseAuthStatus.membershipRequired;
        _verificationError = 'این حساب عضو فعال هیچ مجموعه‌ای نیست.';
        return false;
      }

      final membership = memberships.firstWhere(
        (row) => row['is_active'] == true,
        orElse: () => <String, dynamic>{},
      );
      if (membership.isEmpty) {
        _status = SupabaseAuthStatus.membershipRequired;
        _verificationError = 'عضویت فعال برای این حساب پیدا نشد.';
        return false;
      }

      final rawBusiness = membership['businesses'];
      final business = rawBusiness is Map
          ? Map<String, dynamic>.from(rawBusiness)
          : <String, dynamic>{};
      final businessId = membership['business_id'] as String? ??
          business['id'] as String?;
      final role = membership['role'] as String?;

      if (businessId == null || businessId.isEmpty || role == null || role.isEmpty) {
        _status = SupabaseAuthStatus.membershipRequired;
        _verificationError = 'اطلاعات عضویت مجموعه ناقص است؛ دسترسی صادر نشد.';
        return false;
      }

      _businessId = businessId;
      _businessName = business['name'] as String?;
      _role = role;
      final rawPermissions = membership['permissions'];
      _permissions = rawPermissions is Map
          ? Map<String, dynamic>.from(rawPermissions)
          : const {};
      _status = SupabaseAuthStatus.authenticated;
      _verificationError = null;
      return true;
    } catch (error, stackTrace) {
      if (!_isCurrentRequest(expectedUserId, generation)) return false;
      debugPrint('[DateTime][SupabaseAuth] Membership check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _status = SupabaseAuthStatus.networkError;
      _verificationError =
          'بررسی عضویت از سرور ممکن نشد. اتصال را بررسی کنید و دوباره تلاش کنید.';
      return false;
    } finally {
      if (_isCurrentRequest(expectedUserId, generation)) {
        notifyListeners();
      }
    }
  }

  bool _isCurrentRequest(String expectedUserId, int generation) =>
      generation == _generation &&
      _authRepository?.currentUser?.id == expectedUserId;

  void _setNetworkError(Object error) {
    debugPrint('[DateTime][SupabaseAuth] Session state became unreliable: $error');
    if (_authRepository?.currentUser == null) {
      _clearMembership(status: SupabaseAuthStatus.signedOut);
      return;
    }

    // Fail closed: never keep a previously verified tenant or role available
    // after the auth stream or membership request becomes unreliable.
    _generation++;
    _verification = null;
    _verificationUserId = null;
    _clearMembership(status: SupabaseAuthStatus.networkError);
    _verificationError =
        'ارتباط با سرویس احراز هویت برقرار نشد. پس از بررسی اینترنت دوباره تلاش کنید.';
    notifyListeners();
  }

  /// Revalidates the current stored session after a network interruption.
  Future<bool> retryVerification() async {
    final auth = _authRepository;
    if (auth?.currentUser == null) {
      _clearMembership(status: SupabaseAuthStatus.signedOut);
      return false;
    }
    try {
      await auth!.refreshSession();
    } catch (error) {
      _setNetworkError(error);
      return false;
    }
    if (auth.currentUser == null) {
      _clearMembership(status: SupabaseAuthStatus.signedOut);
      return false;
    }
    return verifyMembership();
  }

  /// Clears the Supabase session and tenant context together.
  Future<void> signOut() async {
    final auth = _authRepository;
    if (auth == null) {
      _clearMembership(status: SupabaseAuthStatus.unavailable);
      return;
    }
    await auth.signOut();
    _generation++;
    _verification = null;
    _verificationUserId = null;
    _clearMembership(status: SupabaseAuthStatus.signedOut);
  }

  void _clearMembership({required SupabaseAuthStatus status}) {
    _status = status;
    _userId = null;
    _businessId = null;
    _businessName = null;
    _role = null;
    _permissions = const {};
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

enum SupabaseAuthStatus {
  initializing,
  unavailable,
  signedOut,
  checkingMembership,
  authenticated,
  membershipRequired,
  networkError,
}
