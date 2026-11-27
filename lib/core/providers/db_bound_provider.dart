import 'package:flutter/foundation.dart';

import '../services/supabase_auth_state_notifier.dart';

/// Base for data providers. The authenticated tenant context is supplied by
/// Supabase and is never inferred from a local/demo account.
abstract class DbBoundProvider extends ChangeNotifier {
  DbBoundProvider({
    this.authStateNotifier,
    Listenable? testOnlyLocalChanges,
  }) : _testOnlyLocalChanges = testOnlyLocalChanges {
    _testOnlyLocalChanges?.addListener(_handleTestOnlyLocalChange);
    authStateNotifier?.addListener(_handleAuthContextChange);
  }

  final Listenable? _testOnlyLocalChanges;
  final SupabaseAuthStateNotifier? authStateNotifier;

  String? get authUserId => authStateNotifier?.userId;
  String? get businessId => authStateNotifier?.businessId;
  String? get membershipRole => authStateNotifier?.role;
  Map<String, dynamic> get membershipPermissions =>
      authStateNotifier?.permissions ?? const {};
  bool get hasVerifiedBusinessMembership =>
      authStateNotifier?.hasActiveBusiness ?? false;

  bool _disposed = false;
  String? _lastAuthContext;

  void _handleTestOnlyLocalChange() {
    if (_disposed) return;
    onDatabaseChanged();
  }

  void _handleAuthContextChange() {
    if (_disposed) return;
    final next = [
      authStateNotifier?.userId,
      authStateNotifier?.businessId,
      authStateNotifier?.role,
      authStateNotifier?.permissions.toString(),
      authStateNotifier?.status.name,
    ].join('|');
    if (_lastAuthContext == next) return;
    _lastAuthContext = next;
    onAuthContextChanged();
  }

  /// Called whenever the authenticated user, tenant, role, or verification
  /// state changes. Feature providers can invalidate tenant-scoped caches.
  @protected
  void onAuthContextChanged() {
    if (hasVerifiedBusinessMembership) {
      onAuthenticatedTenantChanged();
    } else {
      onTenantContextCleared();
    }
    notifyListeners();
  }

  /// Reload tenant-owned records after a new user/business/role is verified.
  @protected
  void onAuthenticatedTenantChanged() {}

  /// Drop all previously visible tenant data as soon as auth is lost or
  /// membership verification becomes uncertain.
  @protected
  void onTenantContextCleared() {}

  @protected
  void onDatabaseChanged() {}

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _testOnlyLocalChanges?.removeListener(_handleTestOnlyLocalChange);
    authStateNotifier?.removeListener(_handleAuthContextChange);
    super.dispose();
  }
}
