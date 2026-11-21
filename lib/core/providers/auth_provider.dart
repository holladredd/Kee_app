import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kee/core/services/auth_service.dart';
import 'package:kee/features/auth/data/user_model.dart';

// ─── Auth State ──────────────────────────────────────────

enum AuthStatus {
  /// App just launched, checking local storage (very fast)
  initializing,

  /// User is authenticated — either optimistically (token found locally)
  /// or confirmed (profile loaded from server)
  authenticated,

  /// No valid session — no stored token or token was invalidated
  unauthenticated,
}

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;
  final bool isSubmitting;

  /// True when we've optimistically set authenticated but haven't
  /// confirmed with the server yet. If validation fails, we roll back.
  final bool isValidating;

  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
    this.isSubmitting = false,
    this.isValidating = false,
  });

  const AuthState.initial()
      : status = AuthStatus.initializing,
        user = null,
        errorMessage = null,
        isSubmitting = false,
        isValidating = false;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? errorMessage,
    bool? isSubmitting,
    bool? isValidating,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isValidating: isValidating ?? this.isValidating,
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

  /// OPTIMISTIC: Check local storage. If token exists, immediately
  /// set authenticated and let the UI render home. Validate with
  /// the server in the background — roll back only if it fails.
  Future<void> _checkStoredSession() async {
    final hasToken = await _authService.hasStoredToken();

    if (!hasToken) {
      // No token — unauthenticated immediately
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
      );
      return;
    }

    // OPTIMISTIC: Token found → authenticated NOW, validate later
    state = state.copyWith(
      status: AuthStatus.authenticated,
      isValidating: true,
      clearError: true,
    );

    // Background validation — user is already seeing the home screen
    final result = await _authService.getProfile();

    if (result.isSuccess && result.user != null) {
      // Confirmed — populate user data
      state = state.copyWith(
        user: result.user,
        isValidating: false,
        clearError: true,
      );
    } else {
      // Token invalid/expired — roll back to unauthenticated
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isValidating: false,
        clearUser: true,
        errorMessage: 'Session expired. Please sign in again.',
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
      // Immediate transition — navigate to home right away
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isSubmitting: false,
        isValidating: false,
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
      // Immediate transition — navigate to home right away
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isSubmitting: false,
        isValidating: false,
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

  /// OPTIMISTIC LOGOUT: Clear UI immediately, clean up storage
  /// in background. User sees login screen instantly.
  Future<void> logout() async {
    // Instant UI reset — don't wait for storage
    state = const AuthState(
      status: AuthStatus.unauthenticated,
    );

    // Fire-and-forget storage cleanup
    _authService.logout();
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

/// True while the token is being validated with the server
/// (user is already seeing home optimistically).
final isValidatingProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isValidating;
});
