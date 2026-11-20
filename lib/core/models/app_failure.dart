import 'package:flutter/foundation.dart';

enum AppErrorKind {
  connection,
  fetch,
  save,
  validation,
  access,
  server,
  unknown,
}

@immutable
class AppFailure implements Exception {
  const AppFailure(this.kind, {this.message, this.cause, this.retryable});

  final AppErrorKind kind;
  final String? message;
  final Object? cause;
  final bool? retryable;

  bool get canRetry => retryable ?? (kind == AppErrorKind.connection || kind == AppErrorKind.fetch || kind == AppErrorKind.server);

  String get persianMessage => message ?? switch (kind) {
    AppErrorKind.connection => 'ارتباط با سرور برقرار نشد. اطلاعات ذخیره‌شده روی دستگاه در دسترس است.',
    AppErrorKind.fetch => 'دریافت اطلاعات با مشکل روبه‌رو شد. دوباره تلاش کنید.',
    AppErrorKind.save => 'ذخیره تغییرات انجام نشد. اطلاعات واردشده را بررسی کنید.',
    AppErrorKind.validation => 'اطلاعات واردشده معتبر نیست. موارد مشخص‌شده را اصلاح کنید.',
    AppErrorKind.access => 'شما اجازه دسترسی به این بخش یا انجام این عملیات را ندارید.',
    AppErrorKind.server => 'سرور موقتاً پاسخ‌گو نیست. کمی بعد دوباره تلاش کنید.',
    AppErrorKind.unknown => 'عملیات با مشکل روبه‌رو شد. دوباره تلاش کنید.',
  };

  static Future<T> guard<T>(
    Future<T> Function() operation, {
    AppErrorKind fallback = AppErrorKind.unknown,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error, fallback: fallback), stackTrace);
    }
  }

  factory AppFailure.from(Object error, {AppErrorKind fallback = AppErrorKind.unknown}) {
    if (error is AppFailure) return error;
    final value = error.toString().toLowerCase();
    if (value.contains('socket') || value.contains('network') || value.contains('connection') || value.contains('offline')) {
      return AppFailure(AppErrorKind.connection, cause: error);
    }
    if (value.contains('permission') || value.contains('unauthorized') || value.contains('forbidden')) {
      return AppFailure(AppErrorKind.access, cause: error, retryable: false);
    }
    if (value.contains('validation') || value.contains('invalid')) {
      return AppFailure(AppErrorKind.validation, cause: error, retryable: false);
    }
    if (value.contains('500') || value.contains('502') || value.contains('503') || value.contains('server')) {
      return AppFailure(AppErrorKind.server, cause: error);
    }
    return AppFailure(fallback, cause: error);
  }

  @override
  String toString() => persianMessage;
}
