import 'package:flutter/foundation.dart';

import '../../data/mock/app_database.dart';
import '../services/supabase_auth_state_notifier.dart';

/// Base for data providers. The authenticated tenant context is supplied by
/// Supabase and is never inferred from a local/demo account.
abstract class DbBoundProvider extends ChangeNotifier {
  DbBoundProvider(
    this.db, {
    this.authStateNotifier,
  }) {
    db.addListener(_handleDbChange);
    authStateNotifier?.addListener(_handleAuthContextChange);
  }

  @protected
  final AppDatabase db;

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

  void _handleDbChange() {
    if (_disposed) return;
    onDatabaseChanged();
  }

  void _handleAuthContextChange() {
    if (_disposed) return;
    final next = [
      authStateNotifier?.userId,
      authStateNotifier?.businessId,
      authStateNotifier?.role,
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
    notifyListeners();
  }

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
    db.removeListener(_handleDbChange);
    authStateNotifier?.removeListener(_handleAuthContextChange);
    super.dispose();
  }
}
