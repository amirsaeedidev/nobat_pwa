
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/supabase_auth_state_notifier.dart';
import '../../../../data/repositories/supabase_auth_repository.dart';

/// Sign-in entry point for cloud mode. Offline Datamonck mode never routes here.
class SupabaseLoginPage extends StatefulWidget {
  const SupabaseLoginPage({super.key});

  @override
  State<SupabaseLoginPage> createState() => _SupabaseLoginPageState();
}

class _SupabaseLoginPageState extends State<SupabaseLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  bool _isSendingReset = false;
  bool _obscurePassword = true;
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<SupabaseAuthRepository?>();
    if (auth == null) {
      setState(() => _message = 'اتصال Supabase در این نسخه فعال نیست.');
      return;
    }

    final sessionNotifier = context.read<SupabaseAuthStateNotifier>();
    setState(() {
      _isSubmitting = true;
      _message = null;
      _messageIsError = true;
    });

    try {
      await auth.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final allowed = await sessionNotifier.verifyMembership();
      if (!mounted) return;
      if (!allowed) {
        setState(() {
          _message = sessionNotifier.verificationError ??
              'این حساب اجازه ورود به مجموعه را ندارد.';
        });
      } else {
        context.go('/dashboard');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = _friendlyError(error);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _message = 'ابتدا ایمیل معتبر خود را وارد کنید.');
      return;
    }

    final auth = context.read<SupabaseAuthRepository?>();
    if (auth == null) return;

    setState(() {
      _isSendingReset = true;
      _message = null;
      _messageIsError = true;
    });

    try {
      await auth.resetPasswordForEmail(email: email);
      if (mounted) {
        setState(() {
          _message = 'درخواست بازیابی رمز ارسال شد. صندوق ورودی ایمیل را بررسی کنید.';
          _messageIsError = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  String _friendlyError(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('invalid login credentials')) {
      return 'ایمیل یا رمز عبور اشتباه است.';
    }
    if (value.contains('email not confirmed')) {
      return 'ایمیل این حساب هنوز تأیید نشده است.';
    }
    if (value.contains('network') || value.contains('socket')) {
      return 'ارتباط با سرور برقرار نشد. اینترنت را بررسی کنید.';
    }
    return 'ورود انجام نشد. اطلاعات حساب و وضعیت اتصال را بررسی کنید.';
  }

  Future<void> _signOut() async {
    final sessionNotifier = context.read<SupabaseAuthStateNotifier>();
    try {
      await sessionNotifier.signOut();
      if (mounted) {
        setState(() {
          _message = 'از حساب خارج شدید.';
          _messageIsError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'خروج از حساب انجام نشد. دوباره تلاش کنید.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.read<SupabaseAuthRepository?>();
    final session = context.watch<SupabaseAuthStateNotifier>();
    final user = auth?.currentUser;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 54,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'DateTime',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ورود امن به پنل مدیریت مجموعه',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (user != null) ...[
                        _buildExistingSession(context, session, user.email),
                      ] else ...[
                        Form(
                          key: _formKey,
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textDirection: TextDirection.ltr,
                                  autofillHints: const [AutofillHints.username],
                                  decoration: const InputDecoration(
                                    labelText: 'ایمیل',
                                    hintText: 'name@example.com',
                                    prefixIcon: Icon(Icons.alternate_email_rounded),
                                  ),
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    if (email.isEmpty || !email.contains('@')) {
                                      return 'ایمیل معتبر وارد کنید.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  autofillHints: const [AutofillHints.password],
                                  decoration: InputDecoration(
                                    labelText: 'رمز عبور',
                                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword ? 'نمایش رمز' : 'پنهان کردن رمز',
                                      onPressed: () => setState(
                                        () => _obscurePassword = !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      (value ?? '').isEmpty ? 'رمز عبور را وارد کنید.' : null,
                                  onFieldSubmitted: (_) => _signIn(),
                                ),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  onPressed: _isSubmitting ? null : _signIn,
                                  icon: _isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.login_rounded),
                                  label: Text(_isSubmitting ? 'در حال ورود...' : 'ورود به سامانه'),
                                ),
                                Align(
                                  alignment: Alignment.center,
                                  child: TextButton(
                                    onPressed: _isSendingReset ? null : _sendPasswordReset,
                                    child: Text(
                                      _isSendingReset
                                          ? 'در حال ارسال درخواست...'
                                          : 'فراموشی رمز عبور',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        _messageBox(theme, _message!, isError: _messageIsError),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'حالت آفلاین Datamonck مستقل است و برای اجرای آزمایشی به ورود اینترنتی نیاز ندارد.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExistingSession(
    BuildContext context,
    SupabaseAuthStateNotifier session,
    String? email,
  ) {
    final theme = Theme.of(context);
    if (session.isCheckingMembership) {
      return const Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('در حال بررسی عضویت و دسترسی مجموعه...'),
        ],
      );
    }

    if (session.hasActiveBusiness) {
      return Column(
        children: [
          const Icon(Icons.verified_user_rounded, size: 42, color: Colors.green),
          const SizedBox(height: 10),
          Text(email ?? 'کاربر واردشده', textDirection: TextDirection.ltr),
          const SizedBox(height: 6),
          Text('${session.businessName ?? 'مجموعه'} • ${session.roleLabel}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/dashboard'),
            child: const Text('ورود به پنل'),
          ),
        ],
      );
    }

    return Column(
      children: [
        Icon(Icons.lock_outline_rounded, size: 42, color: theme.colorScheme.error),
        const SizedBox(height: 10),
        Text(
          session.verificationError ?? 'دسترسی این حساب تأیید نشده است.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => session.retryVerification(),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('بررسی دوباره دسترسی'),
        ),
        TextButton(
          onPressed: _signOut,
          child: const Text('خروج از حساب'),
        ),
      ],
    );
  }

  Widget _messageBox(ThemeData theme, String message, {required bool isError}) {
    final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}
