import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kee/core/services/auth_service.dart';
import 'package:kee/features/auth/data/user_model.dart';

// ─── Auth State ──────────────────────────────────────────

enum AuthStatus {
  /// App just launched, checking for stored token
  loading,

  /// User is authenticated
  authenticated,

  /// No valid session
  unauthenticated,
}

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;
  final bool isSubmitting;

  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
    this.isSubmitting = false,
  });

  const AuthState.initial()
      : status = AuthStatus.loading,
        user = null,
        errorMessage = null,
        isSubmitting = false;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? errorMessage,
    bool? isSubmitting,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

// ─── Auth Notifier ───────────────────────────────────────

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Kick off the initial auth check on creation
    _checkStoredSession();
    return const AuthState.initial();
  }

  final AuthApiService _authService = AuthApiService.instance;

  /// Called on app startup — checks for stored token and validates it.
  Future<void> _checkStoredSession() async {
    final hasToken = await _authService.hasStoredToken();

    if (!hasToken) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
      );
      return;
    }

    // Token exists — validate by fetching profile
    final result = await _authService.getProfile();

    if (result.isSuccess && result.user != null) {
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        clearError: true,
      );
    } else {
      // Token invalid or expired
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
        clearError: true,
      );
    }
  }

  /// Register a new account.
  Future<bool> register({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);

    final result = await _authService.register(
      email: email,
      password: password,
    );

    if (result.isSuccess && result.user != null) {
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isSubmitting: false,
        clearError: true,
      );
      return true;
    }

    state = state.copyWith(
      isSubmitting: false,
      errorMessage: result.errorMessage,
    );
    return false;
  }

  /// Login with existing credentials.
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);

    final result = await _authService.login(
      email: email,
      password: password,
    );

    if (result.isSuccess && result.user != null) {
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isSubmitting: false,
        clearError: true,
      );
      return true;
    }

    state = state.copyWith(
      isSubmitting: false,
      errorMessage: result.errorMessage,
    );
    return false;
  }

  /// Logout — clears token and resets state.
  Future<void> logout() async {
    await _authService.logout();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
    );
  }

  /// Refresh profile data (e.g. after creating a memory).
  Future<void> refreshProfile() async {
    final result = await _authService.getProfile();
    if (result.isSuccess && result.user != null) {
      state = state.copyWith(user: result.user);
    }
  }

  /// Clear any displayed error.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ─── Providers ───────────────────────────────────────────

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

/// Convenience provider — just the auth status for redirect guards.
final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authProvider).status;
});

/// Convenience provider — the current user (nullable).
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});
