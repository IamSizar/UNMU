import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/user.dart';

class AuthService {
  static String get baseUrl => '${ApiConfig.baseUrl}/auth';

  static const String keyToken = 'auth_token';
  static const String keyUser = 'auth_user';

  // Login.
  //
  // Returns shapes:
  //   { success: true, user, token }
  //   { success: false, error, requiresVerification?, email?, devCode? }
  //
  // The `requiresVerification` branch fires when the backend returns 403
  // EMAIL_NOT_VERIFIED — the caller should push the VerifyEmailScreen.
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      debugPrint('Attempting login to $baseUrl/login with email: $email');
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      );

      debugPrint('Login response status: ${response.statusCode}');
      debugPrint('Login response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'];
        final user = User.fromJson(data['user']);

        await _saveSession(token, user);
        return {'success': true, 'user': user, 'token': token};
      }

      final body = _safeDecode(response.body);

      // Special-case: 403 EMAIL_NOT_VERIFIED. The backend has already
      // issued a fresh code — the caller can jump straight to VerifyEmail.
      if (response.statusCode == 403 && body['code'] == 'EMAIL_NOT_VERIFIED') {
        return {
          'success': false,
          'requiresVerification': true,
          'email': body['email'] ?? email,
          'devCode': body['verificationCode'],
          'error': body['error'] ?? 'Please verify your email first.',
        };
      }

      return {
        'success': false,
        'error': body['error'] ?? 'Login failed',
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Check whether an account exists for [email] — POST /auth/check-email.
  //
  // Drives the email-first login flow: the client branches to the
  // password step (exists) or the create-account/onboarding step (new).
  //
  // Returns:
  //   { success: true,  exists: bool }
  //   { success: false, error }
  static Future<Map<String, dynamic>> checkEmail(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/check-email'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      final body = _safeDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'exists': body['exists'] == true};
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Could not check that email.',
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Create a brand-new account — POST /auth/signup.
  //
  // The replacement for register + verify-email: the backend creates an
  // immediately-verified user and returns a JWT, so we save the session
  // and the caller drops straight into the app.
  //
  // Returns:
  //   { success: true,  user, token }
  //   { success: false, error, code? }   (code='EMAIL_TAKEN' on 409)
  static Future<Map<String, dynamic>> signup(
    String email,
    String name,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email.trim(),
          'name': name.trim(),
          'password': password,
        }),
      );
      final body = _safeDecode(response.body);
      if (response.statusCode == 201) {
        final token = body['token'] as String;
        final user = User.fromJson(body['user']);
        await _saveSession(token, user);
        return {'success': true, 'user': user, 'token': token};
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Could not create your account.',
        'code': body['code'],
      };
    } catch (e) {
      debugPrint('Signup error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Register.
  //
  // The new flow does NOT issue a JWT on /register. Instead the backend
  // returns `requiresVerification: true` plus (in dev mode) the 6-digit
  // code. Callers should push the VerifyEmailScreen and pass that code
  // along so the testing UI can prefill it.
  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'name': name, 'email': email, 'password': password}),
      );

      if (response.statusCode == 201) {
        final data = _safeDecode(response.body);
        return {
          'success': true,
          'requiresVerification': data['requiresVerification'] == true,
          'email': data['email'] ?? email,
          'userId': data['userId'],
          'devCode': data['verificationCode'], // null outside dev mode
          'devMode': data['devMode'] == true,
        };
      }

      final body = _safeDecode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Registration failed',
      };
    } catch (e) {
      debugPrint('Register error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Verify the 6-digit code emailed to (well, returned alongside) Register.
  // Server marks the user verified and issues a JWT — we save the session
  // on success so the caller can navigate straight into the app.
  static Future<Map<String, dynamic>> verifyEmail(
    String email,
    String code,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'code': code.trim()}),
      );

      if (response.statusCode == 200) {
        final data = _safeDecode(response.body);
        final token = data['token'];
        final user = User.fromJson(data['user']);
        await _saveSession(token, user);
        return {'success': true, 'user': user, 'token': token};
      }

      final body = _safeDecode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Verification failed',
        'code': body['code'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Sign in via Firebase OAuth (Google / Apple).
  //
  // The mobile auth flow:
  //   1. firebase_auth opens the Google / Apple native picker
  //   2. Picker returns a FirebaseUser whose `getIdToken()` is a JWT
  //   3. We POST that JWT here to the backend
  //   4. Backend's POST /auth/oauth/firebase verifies the token with the
  //      Firebase Admin SDK and returns our own AuthResponse (same shape
  //      as /auth/login)
  //
  // On success: session saved, returns { success: true, user, token }.
  // On failure: { success: false, error }.
  static Future<Map<String, dynamic>> signInWithFirebase(
    String firebaseIdToken,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/oauth/firebase'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'idToken': firebaseIdToken}),
      );

      if (response.statusCode == 200) {
        final data = _safeDecode(response.body);
        final token = data['token'] as String;
        final user = User.fromJson(data['user']);
        await _saveSession(token, user);
        return {
          'success': true,
          'user': user,
          'token': token,
          // true when this OAuth user has never set a local password —
          // the app routes them to the onboarding screen.
          'needsOnboarding': data['needsOnboarding'] == true,
        };
      }

      final body = _safeDecode(response.body);
      return {
        'success': false,
        'error': body['error'] ?? 'Firebase sign-in failed',
        'code': body['code'],
      };
    } catch (e) {
      debugPrint('signInWithFirebase error: $e');
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // POST /api/me/complete-onboarding — finish first-time OAuth setup by
  // setting a display name + local password. Authenticated via the stored
  // JWT (minted at OAuth sign-in). On success the refreshed user is saved
  // back to the session so the cached record carries the new name.
  static Future<Map<String, dynamic>> completeOnboarding(
    String name,
    String password,
  ) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {'success': false, 'error': 'Not signed in.'};
      }
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/me/complete-onboarding'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'name': name.trim(), 'password': password}),
      );
      final body = _safeDecode(response.body);
      if (response.statusCode == 200) {
        final user = User.fromJson(body);
        await _saveSession(token, user); // keep same token, refresh user
        return {'success': true, 'user': user};
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Could not finish setup.',
        'code': body['code'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  // Resend a fresh code. Backend rate-limits to once per 30s and returns
  // 429 with `retryAfter` seconds when called too soon.
  static Future<Map<String, dynamic>> resendCode(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/resend-code'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      final body = _safeDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'devCode': body['verificationCode'],
          'devMode': body['devMode'] == true,
        };
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Failed to resend code',
        'code': body['code'],
        'retryAfter': body['retryAfter'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  /// POST /api/auth/password-reset/request
  ///
  /// Always returns success=true (the backend deliberately returns a
  /// generic 200 regardless of whether the email exists, to prevent
  /// account-enumeration). In dev mode the response also includes
  /// `resetToken` so testers can skip the email round-trip.
  static Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/password-reset/request'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));
      final body = _safeDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'devCode': body['resetToken'],
          'devMode': body['devMode'] == true,
        };
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Could not send reset link.',
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  /// POST /api/auth/password-reset/confirm
  ///
  /// Consumes the token from the emailed link (or pasted manually) and
  /// writes the new bcrypt hash. On success the user can log in with
  /// the new password — no auto-login here, so the UX flow is:
  /// confirm → snackbar → back to login screen.
  static Future<Map<String, dynamic>> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/password-reset/confirm'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'token': token,
              'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final body = _safeDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {
        'success': false,
        'error': body['error'] ?? 'Reset failed.',
        'code': body['code'],
      };
    } catch (e) {
      return {'success': false, 'error': 'Connection error: $e'};
    }
  }

  static Map<String, dynamic> _safeDecode(String body) {
    try {
      final v = json.decode(body);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return <String, dynamic>{};
  }

  // Logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyToken);
    await prefs.remove(keyUser);
  }

  // Get current token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyToken);
  }

  // Get current user
  static Future<User?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(keyUser);
    if (userJson != null) {
      return User.fromJson(json.decode(userJson));
    }
    return null;
  }

  // Helper: Save session
  static Future<void> _saveSession(String token, User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyToken, token);
    await prefs.setString(keyUser, json.encode(user.toJson()));
  }

  /// Public wrapper around [_saveSession] used by test/dev login flows that
  /// bypass the backend (e.g. so the user can sign in with any non-empty
  /// credentials while the API isn't wired up yet).
  static Future<void> saveSession(String token, User user) =>
      _saveSession(token, user);
}
