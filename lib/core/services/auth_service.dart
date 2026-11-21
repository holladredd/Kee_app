import 'package:kee/core/services/api_service.dart';
import 'package:kee/features/auth/data/user_model.dart';

/// Auth service layer — all auth API calls go through here.
/// Endpoints:
///   POST /auth/register  → { user, token }
///   POST /auth/login     → { user, token }
///   GET  /auth/profile   → user (with counts)
class AuthApiService {
  AuthApiService._();
  static final AuthApiService instance = AuthApiService._();

  final ApiService _api = ApiService.instance;

  /// Register a new account. Stores token on success.
  /// Returns the [UserModel] on success, throws on failure.
  Future<AuthResult> register({
    required String email,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/register',
      body: {'email': email, 'password': password},
      auth: false,
    );

    if (!response.success || response.data == null) {
      return AuthResult.failure(
        response.errorMessage ?? 'Registration failed. Please try again.',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final token = data['token'] as String;
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

    // Persist token for future authenticated requests
    await _api.saveToken(token);

    return AuthResult.success(user: user, token: token);
  }

  /// Login with existing credentials. Stores token on success.
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/login',
      body: {'email': email, 'password': password},
      auth: false,
    );

    if (!response.success || response.data == null) {
      return AuthResult.failure(
        response.errorMessage ?? 'Login failed. Please check your credentials.',
      );
    }

    final data = response.data as Map<String, dynamic>;
    final token = data['token'] as String;
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

    await _api.saveToken(token);

    return AuthResult.success(user: user, token: token);
  }

  /// Fetch the current user's profile using stored token.
  Future<AuthResult> getProfile() async {
    final response = await _api.get('/auth/profile');

    if (!response.success || response.data == null) {
      // If 401, token is expired/invalid
      if (response.statusCode == 401) {
        await _api.clearToken();
        return AuthResult.failure('Session expired. Please sign in again.');
      }
      return AuthResult.failure(
        response.errorMessage ?? 'Could not load profile.',
      );
    }

    final user = UserModel.fromJson(response.data as Map<String, dynamic>);
    return AuthResult.success(user: user);
  }

  /// Logout — clears stored token.
  Future<void> logout() async {
    await _api.clearToken();
  }

  /// Check whether a token exists (quick startup check).
  Future<bool> hasStoredToken() async {
    return await _api.hasToken();
  }
}

/// Result wrapper for auth operations.
class AuthResult {
  final bool isSuccess;
  final UserModel? user;
  final String? token;
  final String? errorMessage;

  const AuthResult._({
    required this.isSuccess,
    this.user,
    this.token,
    this.errorMessage,
  });

  factory AuthResult.success({required UserModel user, String? token}) {
    return AuthResult._(isSuccess: true, user: user, token: token);
  }

  factory AuthResult.failure(String message) {
    return AuthResult._(isSuccess: false, errorMessage: message);
  }
}
