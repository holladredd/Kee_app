import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Central API service for all HTTP communication with Kee backend.
/// Handles base URL resolution, JWT token injection, and response parsing.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const String _tokenKey = 'kee_auth_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Resolves the correct base URL depending on platform.
  /// - Android emulator: 10.0.2.2 (loopback alias)
  /// - iOS simulator: localhost
  /// - Web / Desktop: localhost
  /// - Physical device: use the machine's local IP
  String get baseUrl {
    const port = '3000';
    const basePath = '/api/v1';

    if (kIsWeb) {
      return 'http://localhost:$port$basePath';
    }

    // On Android devices, 127.0.0.1 works seamlessly when port reverse is active:
    // `adb reverse tcp:3000 tcp:3000`
    if (Platform.isAndroid) {
      return 'http://127.0.0.1:$port$basePath';
    }

    // iOS simulator, macOS, Linux, Windows
    return 'http://localhost:$port$basePath';
  }

  // ─── Token Management ─────────────────────────────────

  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
  }

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ─── HTTP Methods ──────────────────────────────────────

  /// Build headers with optional JWT Bearer token.
  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (auth) {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  /// Perform a GET request.
  Future<ApiResponse> get(
    String path, {
    bool auth = true,
    Map<String, String>? queryParams,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
      final headers = await _headers(auth: auth);
      final response = await http.get(uri, headers: headers);
      return _parseResponse(response);
    } catch (e) {
      return ApiResponse.error(_connectionError(e));
    }
  }

  /// Perform a POST request.
  Future<ApiResponse> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = await _headers(auth: auth);
      final response = await http.post(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      return _parseResponse(response);
    } catch (e) {
      return ApiResponse.error(_connectionError(e));
    }
  }

  /// Perform a PUT request.
  Future<ApiResponse> put(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = await _headers(auth: auth);
      final response = await http.put(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      return _parseResponse(response);
    } catch (e) {
      return ApiResponse.error(_connectionError(e));
    }
  }

  /// Perform a DELETE request.
  Future<ApiResponse> delete(
    String path, {
    bool auth = true,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = await _headers(auth: auth);
      final response = await http.delete(uri, headers: headers);
      return _parseResponse(response);
    } catch (e) {
      return ApiResponse.error(_connectionError(e));
    }
  }

  // ─── Response Parsing ──────────────────────────────────

  ApiResponse _parseResponse(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final success = body['success'] == true;

      if (success) {
        return ApiResponse(
          success: true,
          data: body['data'],
          statusCode: response.statusCode,
        );
      }

      // Backend returns { success: false, error: "...", details: [...] }
      String errorMessage = body['error'] ?? 'Something went wrong';

      // Validation errors may include field-level details
      if (body['details'] != null && body['details'] is List) {
        final details = body['details'] as List;
        if (details.isNotEmpty) {
          errorMessage = details
              .map((d) => d['message'] ?? '')
              .where((m) => m.toString().isNotEmpty)
              .join('. ');
        }
      }

      return ApiResponse(
        success: false,
        errorMessage: errorMessage,
        statusCode: response.statusCode,
      );
    } catch (_) {
      return ApiResponse(
        success: false,
        errorMessage: 'Unexpected server response',
        statusCode: response.statusCode,
      );
    }
  }

  String _connectionError(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('connection refused') ||
        msg.contains('no route to host') ||
        msg.contains('network is unreachable')) {
      return 'Unable to connect to Kee. Please check that the server is running and try again.';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'Connection timed out. Please check your network and try again.';
    }
    return 'Network error. Please check your connection and try again.';
  }
}

/// Standardised API response wrapper.
class ApiResponse {
  final bool success;
  final dynamic data;
  final String? errorMessage;
  final int? statusCode;

  const ApiResponse({
    required this.success,
    this.data,
    this.errorMessage,
    this.statusCode,
  });

  factory ApiResponse.error(String message) {
    return ApiResponse(success: false, errorMessage: message);
  }
}
