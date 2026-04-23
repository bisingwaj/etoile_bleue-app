import 'dart:async';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ErrorHandler {
  /// Maps a dynamic error (from API or system) to a user-friendly localized string.
  static String getLocalizedError(dynamic error) {
    if (error is SocketException) {
      return 'errors.network_error'.tr();
    }
    
    if (error is TimeoutException) {
      return 'errors.timeout_error'.tr();
    }

    if (error is AuthException) {
      return _handleAuthError(error);
    }

    if (error is PostgrestException) {
      return _handlePostgrestError(error);
    }

    // Default generic error
    return 'errors.generic'.tr();
  }

  static String _handleAuthError(AuthException error) {
    final code = error.message.toLowerCase();
    
    if (code.contains('invalid login credentials') || code.contains('invalid credentials')) {
      return 'errors.invalid_code'.tr(); // Or a specific credentials error if we add one
    }
    
    if (code.contains('email not confirmed')) {
      return 'errors.auth_failed'.tr();
    }

    return 'errors.auth_failed'.tr();
  }

  static String _handlePostgrestError(PostgrestException error) {
    // Supabase / Postgres error codes: https://www.postgresql.org/docs/current/errcodes-appendix.html
    final code = error.code;
    
    if (code == '42P01') { // undefined_table
      return 'errors.technical_error'.tr();
    }
    
    if (code == '42703') { // undefined_column
      return 'errors.technical_error'.tr();
    }

    if (code == '23505') { // unique_violation
      return 'errors.generic'.tr();
    }
    
    if (code == 'PGRST116') { // unexpected result
       return 'errors.generic'.tr();
    }

    // Default for API errors
    return 'errors.invalid_server_response'.tr();
  }
}
