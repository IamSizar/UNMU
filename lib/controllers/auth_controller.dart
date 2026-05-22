import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart' show Color;
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../config/api_config.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/dev_service.dart';
import '../services/locale_sync_service.dart';

/// Authentication + per-user profile state. Replaces the old `AuthProvider`.
///
/// Keeps the same public surface (field names + methods) as the old provider
/// so call sites only have to swap `context.watch<AuthProvider>()` for
/// `Get.find<AuthController>()` and wrap reactive parts in `Obx(...)`.
class AuthController extends GetxController {
  // ── reactive state ──
  final Rxn<User> _user = Rxn<User>();
  final RxnString _token = RxnString();
  final RxBool _isLoading = false.obs;
  final RxnString _error = RxnString();
  // True right after a Google/Apple sign-in for a user who has never set a
  // local password. _AppEntry (main.dart) shows the OnboardingScreen
  // instead of the main app until completeOnboarding() flips it back.
  final RxBool _needsOnboarding = false.obs;

  // Profile extras (test mode; not part of the User model from the backend).
  final RxnString _avatarPath = RxnString();
  final Rxn<int> _avatarAccentArgb = Rxn<int>();

  // Per-user expert subscriptions: which experts the current user follows.
  final RxSet<String> _subscribedExpertIds = <String>{}.obs;

  static const _kAvatarPathKey = 'profile_avatar_path';
  static const _kAvatarAccentKey = 'profile_avatar_accent_argb';

  // ── public getters (mirror old AuthProvider API) ──
  User? get user => _user.value;
  String? get token => _token.value;
  bool get isAuthenticated => _token.value != null;

  /// Reactive handle to the user — `RealtimeController` uses this to fire on
  /// login/logout. Read it inside `Obx` if you want to rebuild on user changes.
  Rxn<User> get userObservable => _user;
  /// Reflects the real subscription tier on the user row. Was previously
  /// hardcoded to `true` for dev convenience, which made every account —
  /// including freshly-registered FREE ones — look premium in the UI
  /// (paywalls bypassed, gold crown shown, etc.). Now it tells the truth:
  /// only users whose `subscription_tier` is exactly 'PREMIUM' get the
  /// premium surface. Admins still see everything via separate role checks.
  bool get isPremium => _user.value?.subscriptionTier == 'PREMIUM';
  bool get isLoading => _isLoading.value;
  bool get authChecked => !_isLoading.value;
  String? get error => _error.value;
  bool get needsOnboarding => _needsOnboarding.value;

  String? get avatarPath => _avatarPath.value;
  Color? get avatarAccent =>
      _avatarAccentArgb.value == null ? null : Color(_avatarAccentArgb.value!);

  Set<String> get subscribedExpertIds =>
      Set.unmodifiable(_subscribedExpertIds);

  @override
  void onInit() {
    super.onInit();
    _loadSession();
  }

  // ── session bootstrap ──
  Future<void> _loadSession() async {
    _isLoading.value = true;
    try {
      final token = await AuthService.getToken();
      final user = await AuthService.getUser();
      if (token != null && user != null) {
        _token.value = token;
        _user.value = user;
      }
      final prefs = await SharedPreferences.getInstance();
      _avatarPath.value = prefs.getString(_kAvatarPathKey);
      _avatarAccentArgb.value = prefs.getInt(_kAvatarAccentKey);
      await _loadSubs();
    } catch (_) {
      _token.value = null;
      _user.value = null;
    } finally {
      _isLoading.value = false;
    }
  }

  // ── real auth via backend ──
  //
  // Both login() and register() now return [AuthFlowResult] so callers can
  // tell the difference between "logged in" and "needs to verify email"
  // (the latter is normal for fresh accounts since migration 0026 — the
  // backend issues a 6-digit code that must be POSTed back via
  // [verifyEmail] before a JWT is granted).
  Future<AuthFlowResult> login(String email, String password) async {
    _isLoading.value = true;
    _error.value = null;

    final result = await AuthService.login(email, password);
    if (result['success'] == true) {
      _user.value = result['user'] as User;
      _token.value = result['token'] as String;
      _isLoading.value = false;
      // Push the device's chosen language so notification pushes are
      // localized to it. Fire-and-forget.
      LocaleSyncService.syncSaved();
      return const AuthFlowResult.authenticated();
    }

    // 403 EMAIL_NOT_VERIFIED — the backend has already issued a fresh code
    // we can hand to the verify screen so the tester doesn't have to ask
    // for a Resend.
    if (result['requiresVerification'] == true) {
      _isLoading.value = false;
      // Don't surface an error banner — we're routing to the verify screen,
      // not failing.
      return AuthFlowResult.needsVerification(
        email: (result['email'] ?? email).toString(),
        devCode: result['devCode']?.toString(),
      );
    }

    _error.value = result['error']?.toString();
    _isLoading.value = false;
    return AuthFlowResult.failed(_error.value ?? 'Login failed');
  }

  Future<AuthFlowResult> register(
    String name,
    String email,
    String password,
  ) async {
    _isLoading.value = true;
    _error.value = null;

    final result = await AuthService.register(name, email, password);

    // New behavior (post-migration 0026): the server returns 201 with
    // requiresVerification=true and (in dev mode) the 6-digit code. No
    // JWT is issued yet — the caller pushes VerifyEmailScreen.
    if (result['success'] == true && result['requiresVerification'] == true) {
      _isLoading.value = false;
      return AuthFlowResult.needsVerification(
        email: (result['email'] ?? email).toString(),
        devCode: result['devCode']?.toString(),
      );
    }

    // Legacy path — kept for safety in case the server ever returns a
    // user+token directly (e.g. a future "skip verification for trusted
    // partners" flag). Not currently exercised.
    if (result['success'] == true && result['user'] != null) {
      _user.value = result['user'] as User;
      _token.value = result['token'] as String;
      _isLoading.value = false;
      return const AuthFlowResult.authenticated();
    }

    _error.value = result['error']?.toString();
    _isLoading.value = false;
    return AuthFlowResult.failed(_error.value ?? 'Registration failed');
  }

  // ── email-first onboarding (no verification) ──────────────────────────
  //
  // checkEmail() drives the two-step login: the login screen asks for an
  // email, we report whether an account exists, and the screen branches to
  // the password step (existing) or the onboarding screen (new). signup()
  // creates a brand-new account and logs straight in.

  /// Returns true (account exists → ask for password), false (new → push
  /// onboarding), or null when the check itself failed — in which case
  /// [error] is set for the inline banner.
  Future<bool?> checkEmail(String email) async {
    _isLoading.value = true;
    _error.value = null;
    final result = await AuthService.checkEmail(email);
    _isLoading.value = false;
    if (result['success'] == true) {
      return result['exists'] == true;
    }
    _error.value = result['error']?.toString();
    return null;
  }

  /// Create a brand-new account (email-first, no email-verification step)
  /// and log the user straight in. Mirrors [login]'s success handling.
  Future<AuthFlowResult> signup(
    String name,
    String email,
    String password,
  ) async {
    _isLoading.value = true;
    _error.value = null;
    final result = await AuthService.signup(email, name, password);
    if (result['success'] == true && result['user'] != null) {
      _user.value = result['user'] as User;
      _token.value = result['token'] as String;
      await _loadSubs();
      _isLoading.value = false;
      return const AuthFlowResult.authenticated();
    }
    _error.value = result['error']?.toString();
    _isLoading.value = false;
    return AuthFlowResult.failed(_error.value ?? 'Sign up failed');
  }

  /// Finish first-time OAuth setup — set name + password on the current
  /// (already-authenticated) account. On success clears [needsOnboarding]
  /// so _AppEntry swaps from the onboarding screen to the main app.
  Future<AuthFlowResult> completeOnboarding(String name, String password) async {
    _isLoading.value = true;
    _error.value = null;
    final result = await AuthService.completeOnboarding(name, password);
    if (result['success'] == true) {
      if (result['user'] != null) _user.value = result['user'] as User;
      _needsOnboarding.value = false;
      _isLoading.value = false;
      return const AuthFlowResult.authenticated();
    }
    _error.value = result['error']?.toString();
    _isLoading.value = false;
    return AuthFlowResult.failed(_error.value ?? 'Could not finish setup');
  }

  // ── OAuth via Firebase (Google + Apple) ──────────────────────────────
  //
  // Each method:
  //   1. Runs the native picker (Google Sign-In SDK / ASAuthorizationController).
  //   2. Wraps the picker's credential as a Firebase OAuthCredential.
  //   3. Signs into Firebase to obtain a Firebase idToken.
  //   4. POSTs the idToken to our backend's POST /api/auth/oauth/firebase,
  //      which verifies it with the Admin SDK and returns OUR JWT.
  //   5. Saves the session — same end-state as login() above.
  //
  // Errors are reported via _error.value + an `AuthFlowResult.failed`. We
  // also catch the special "user cancelled the picker" case and return
  // success=false with a sentinel error so the UI can suppress the snackbar
  // (cancellation is not a real error, just a user changing their mind).

  /// Cancellation sentinel — set as `error` when the user closes the OAuth
  /// picker without choosing an account. The login screen checks for this
  /// and suppresses any error UI.
  static const String oauthCancelledSentinel = '__oauth_cancelled__';

  /// Google sign-in.
  ///
  /// Uses `google_sign_in` to invoke the system account picker, then hands
  /// the resulting Google idToken/accessToken pair to firebase_auth.
  Future<AuthFlowResult> signInWithGoogle() async {
    _isLoading.value = true;
    _error.value = null;
    try {
      // Force a fresh picker every time — without signOut(), the second
      // call silently reuses the previous account, which makes the
      // "logout → login as a different user" flow impossible.
      final google = GoogleSignIn();
      await google.signOut();

      final account = await google.signIn();
      if (account == null) {
        _isLoading.value = false;
        _error.value = oauthCancelledSentinel;
        return AuthFlowResult.failed(oauthCancelledSentinel);
      }
      final googleAuth = await account.authentication;

      final credential = fb_auth.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );

      return _completeFirebaseSignIn(credential);
    } catch (e) {
      debugPrint('signInWithGoogle failed: $e');
      _error.value = 'Google sign-in failed: $e';
      _isLoading.value = false;
      return AuthFlowResult.failed(_error.value!);
    }
  }

  /// Apple sign-in.
  ///
  /// Only runs on iOS/macOS — calling this from Android will throw
  /// `SignInWithAppleException` because the Apple flow requires
  /// ASAuthorizationController. The login screen should hide the button
  /// on Android (or wire it to Apple's web auth flow separately).
  Future<AuthFlowResult> signInWithApple() async {
    _isLoading.value = true;
    _error.value = null;
    try {
      if (!Platform.isIOS && !Platform.isMacOS) {
        _error.value = 'Apple sign-in is only available on iOS.';
        _isLoading.value = false;
        return AuthFlowResult.failed(_error.value!);
      }

      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Apple gives us an `identityToken` (their JWT) which Firebase
      // accepts directly as an OAuthCredential. Provider id = apple.com.
      final credential = fb_auth.OAuthProvider('apple.com').credential(
        idToken: apple.identityToken,
        accessToken: apple.authorizationCode,
      );

      // Apple's quirk: it only returns givenName + familyName on the
      // *very first* sign-in. Subsequent times these are null. The
      // Firebase ID token also doesn't auto-include the Apple display
      // name. So we stitch them together here, hand them to
      // _completeFirebaseSignIn, which will call updateDisplayName()
      // on the FirebaseUser — the next idToken refresh will then carry
      // the `name` claim that our backend reads.
      String? displayName;
      if (apple.givenName != null || apple.familyName != null) {
        displayName = [apple.givenName, apple.familyName]
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .join(' ')
            .trim();
        if (displayName.isEmpty) displayName = null;
      }

      return _completeFirebaseSignIn(credential, displayName: displayName);
    } on SignInWithAppleAuthorizationException catch (e) {
      // 1000 = canceled (user closed the sheet). Anything else is a real
      // failure worth surfacing.
      if (e.code == AuthorizationErrorCode.canceled) {
        _isLoading.value = false;
        _error.value = oauthCancelledSentinel;
        return AuthFlowResult.failed(oauthCancelledSentinel);
      }
      debugPrint('signInWithApple failed: ${e.code} ${e.message}');
      _error.value = 'Apple sign-in failed: ${e.message}';
      _isLoading.value = false;
      return AuthFlowResult.failed(_error.value!);
    } catch (e) {
      debugPrint('signInWithApple unexpected: $e');
      _error.value = 'Apple sign-in failed: $e';
      _isLoading.value = false;
      return AuthFlowResult.failed(_error.value!);
    }
  }

  // Common tail: convert any Firebase OAuthCredential into a backend
  // session. Sign into Firebase → grab idToken → exchange with backend.
  //
  // `displayName` is only set by the Apple flow on the very first
  // sign-in (Apple omits the name after that). When non-null we stamp
  // it onto the FirebaseUser so the next force-refresh of the idToken
  // includes the `name` claim — which our backend reads to populate
  // users.name.
  Future<AuthFlowResult> _completeFirebaseSignIn(
    fb_auth.AuthCredential credential, {
    String? displayName,
  }) async {
    try {
      final cred = await fb_auth.FirebaseAuth.instance
          .signInWithCredential(credential);
      final fbUser = cred.user;
      if (fbUser == null) {
        _error.value = 'Firebase sign-in returned no user.';
        _isLoading.value = false;
        return AuthFlowResult.failed(_error.value!);
      }

      // Apple-first-time path: persist the name on the Firebase user
      // record so subsequent idTokens carry it as a claim. Wrapped in
      // try/catch because a transient network error here shouldn't
      // block sign-in — worst case the user's name lands as null in
      // our DB and they can edit it from their profile.
      if (displayName != null &&
          displayName.isNotEmpty &&
          (fbUser.displayName == null || fbUser.displayName!.isEmpty)) {
        try {
          await fbUser.updateDisplayName(displayName);
          await fbUser.reload();
        } catch (e) {
          debugPrint('updateDisplayName failed: $e');
        }
      }

      // Force-refresh true so the idToken is freshly minted with the
      // name claim we just stamped above. Also keeps our 5s server-
      // side verification cap honest.
      final idToken = await fbUser.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        _error.value = 'No Firebase idToken issued.';
        _isLoading.value = false;
        return AuthFlowResult.failed(_error.value!);
      }

      final result = await AuthService.signInWithFirebase(idToken);
      if (result['success'] == true) {
        _user.value = result['user'] as User;
        _token.value = result['token'] as String;
        // First-time OAuth user with no local password → route to
        // onboarding (set name + password) via _AppEntry.
        _needsOnboarding.value = result['needsOnboarding'] == true;
        await _loadSubs();
        _isLoading.value = false;
        return const AuthFlowResult.authenticated();
      }

      _error.value = result['error']?.toString() ?? 'Backend rejected token';
      _isLoading.value = false;
      return AuthFlowResult.failed(_error.value!);
    } catch (e) {
      debugPrint('_completeFirebaseSignIn failed: $e');
      _error.value = 'Sign-in failed: $e';
      _isLoading.value = false;
      return AuthFlowResult.failed(_error.value!);
    }
  }

  /// Submit the 6-digit code the user typed in. On success the server
  /// returns a JWT — we save the session and the next build of `_AppEntry`
  /// will swap to the main app via its AnimatedSwitcher.
  Future<AuthFlowResult> verifyEmail(String email, String code) async {
    _isLoading.value = true;
    _error.value = null;
    final result = await AuthService.verifyEmail(email, code);
    if (result['success'] == true) {
      _user.value = result['user'] as User;
      _token.value = result['token'] as String;
      await _loadSubs();
      _isLoading.value = false;
      return const AuthFlowResult.authenticated();
    }
    _error.value = result['error']?.toString();
    _isLoading.value = false;
    return AuthFlowResult.failed(_error.value ?? 'Verification failed');
  }

  /// Ask the server to issue a fresh code. Returns the new dev-mode code
  /// when available so the verify screen can re-render its "Tap to fill"
  /// chip without an extra round-trip.
  Future<({bool success, String? devCode, String? error, int? retryAfter})>
      resendVerificationCode(String email) async {
    final result = await AuthService.resendCode(email);
    if (result['success'] == true) {
      return (
        success: true,
        devCode: result['devCode']?.toString(),
        error: null,
        retryAfter: null,
      );
    }
    return (
      success: false,
      devCode: null,
      error: result['error']?.toString(),
      retryAfter: result['retryAfter'] is int
          ? result['retryAfter'] as int
          : null,
    );
  }

  // ── test / dev login (no backend) ──
  /// Shared password for every preset test account. Must match the bcrypt
  /// hash installed by the seed migrations (currently 0012). When changing
  /// the password, regenerate the hash with `bcrypt.GenerateFromPassword`
  /// at cost 10 and update both the migration and this constant in lockstep.
  static const String testPassword = 'test1234';

  /// Preset test accounts. Public so the "switch test account" sheet can
  /// list them. Three groups:
  ///
  ///   1. Originals (Sizar / Sarah / Ahmad / You / Admin) — created by
  ///      the early seed migrations.
  ///   2. New experts (Sheikh Abdullah, Fatima, Dr. Yusuf, Aisha, Mufti
  ///      Bilal) — seeded in 0012 with matching expert_id values.
  ///   3. Demo subscribers (Khaled, Layla, Omar) — seeded in 0012 with
  ///      active 1y subscriptions.
  static final Map<String, TestAccount> testAccounts = {
    // ── Originals ────────────────────────────────────────────────────
    'admin@test.com': TestAccount(
      id: 1000,
      name: 'Platform Admin',
      role: UserRole.admin,
      expertId: null,
      tier: 'PREMIUM',
    ),
    'user@test.com': TestAccount(
      id: 1001,
      name: 'Sizar',
      role: UserRole.user,
      expertId: null,
      tier: 'FREE',
    ),
    'expert@test.com': TestAccount(
      id: 1002,
      name: 'Sarah Chen',
      role: UserRole.expert,
      expertId: 'e2',
      tier: 'PREMIUM',
    ),
    'scholar@test.com': TestAccount(
      id: 1003,
      name: 'Ahmad Al-Rashid',
      role: UserRole.expert,
      expertId: 'e1',
      tier: 'PREMIUM',
    ),
    'you@test.com': TestAccount(
      id: 1004,
      name: 'You',
      role: UserRole.expert,
      expertId: 'ex_admin_1004',
      tier: 'FREE',
    ),
    // ── New experts seeded in migration 0012 ─────────────────────────
    'sheikh.abdullah@test.com': TestAccount(
      id: 2029,
      name: 'Sheikh Abdullah Al-Mansoori',
      role: UserRole.expert,
      expertId: 'e3',
      tier: 'PREMIUM',
    ),
    'fatima@test.com': TestAccount(
      id: 2027,
      name: 'Fatima Al-Zahrani',
      role: UserRole.expert,
      expertId: 'e4',
      tier: 'PREMIUM',
    ),
    'dr.yusuf@test.com': TestAccount(
      id: 2028,
      name: 'Dr. Yusuf Rahman',
      role: UserRole.expert,
      expertId: 'e5',
      tier: 'PREMIUM',
    ),
    'aisha@test.com': TestAccount(
      id: 2025,
      name: 'Aisha Khalil',
      role: UserRole.expert,
      expertId: 'e6',
      tier: 'PREMIUM',
    ),
    'mufti.bilal@test.com': TestAccount(
      id: 2026,
      name: 'Mufti Bilal Khan',
      role: UserRole.expert,
      expertId: 'e7',
      tier: 'PREMIUM',
    ),
    // ── Demo subscribers seeded in migration 0012 ────────────────────
    'khaled@test.com': TestAccount(
      id: 2030,
      name: 'Khaled Mansour',
      role: UserRole.user,
      expertId: null,
      tier: 'PREMIUM',
    ),
    'layla@test.com': TestAccount(
      id: 2031,
      name: 'Layla Hassan',
      role: UserRole.user,
      expertId: null,
      tier: 'PREMIUM',
    ),
    'omar@test.com': TestAccount(
      id: 2032,
      name: 'Omar Khalil',
      role: UserRole.user,
      expertId: null,
      tier: 'PREMIUM',
    ),
    // ── Fresh-state tester ──────────────────────────────────────────
    // hiwa intentionally has NO community memberships. Use this
    // account to exercise non-member flows: 403 on private community
    // post lists, the Discover screen, the Join button, joining for
    // the first time, etc.
    'hiwa@test.com': TestAccount(
      id: 9001,
      name: 'hiwa',
      role: UserRole.user,
      expertId: null,
      tier: 'FREE',
    ),
  };

  Future<bool> loginTest(String email, String password) async {
    _isLoading.value = true;
    _error.value = null;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    final user = _userFromTestEmail(email);
    final token = 'test-token-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await AuthService.saveSession(token, user);
    } catch (_) {/* persistence is best-effort */}
    _user.value = user;
    _token.value = token;
    await _loadSubs();
    _isLoading.value = false;
    return true;
  }

  Future<bool> registerTest(String name, String email, String password) async {
    _isLoading.value = true;
    _error.value = null;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    final user = User(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      email: email,
      name: name,
      subscriptionTier: 'FREE',
      subscriptionStatus: 'ACTIVE',
      role: UserRole.user,
    );
    final token = 'test-token-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await AuthService.saveSession(token, user);
    } catch (_) {/* ignore */}
    _user.value = user;
    _token.value = token;
    await _loadSubs();
    _isLoading.value = false;
    return true;
  }

  /// Replace the current session with the given (token, user) pair —
  /// persists to SharedPreferences and refreshes any per-user state like
  /// the expert-subscription list.
  ///
  /// Used by the dev-only "Switch account" sheet so we can swap to any
  /// account in the DB without a password (the backend's
  /// `/api/dev/impersonate` route hands us a JWT directly).
  ///
  /// IMPORTANT — persistence ORDER matters here. The HTTP services
  /// (community_service.dart, notifications_service.dart, etc.) all
  /// pull the token via `AuthService.getToken()`, which reads from
  /// SharedPreferences. Mutating `_token.value` fires Get's reactive
  /// observers synchronously — RealtimeController.ever / FeedController
  /// re-fetch immediately. If we mutate reactive state BEFORE saving,
  /// those in-flight requests read the OLD (or null) token from disk
  /// and the backend 401s them → handleAuthFailure() kicks in → user
  /// sees "session expired" right after logging in. Write first, flip
  /// reactive state second.
  Future<void> applySession(String token, User user) async {
    try {
      await AuthService.saveSession(token, user);
    } catch (_) {/* persistence best-effort */}
    _user.value = user;
    _token.value = token;
    await _loadSubs();
  }

  /// Swap the cached User record in place (keeps the same JWT). Used
  /// by screens that mutate fields on the user row server-side — e.g.
  /// /me/change-email/confirm returns the refreshed User and we want
  /// the rest of the app to see the new email immediately, without
  /// re-issuing the token.
  ///
  /// Subscription tier/status are preserved from the existing session
  /// because /me/change-email/confirm doesn't carry those fields back.
  Future<void> replaceSessionUser(User updated) async {
    final current = _user.value;
    final merged = current == null
        ? updated
        : updated.copyWith(
            subscriptionTier: current.subscriptionTier,
            subscriptionStatus: current.subscriptionStatus,
          );
    _user.value = merged;
    final t = _token.value;
    if (t != null && t.isNotEmpty) {
      try {
        await AuthService.saveSession(t, merged);
      } catch (_) {/* best-effort */}
    }
  }

  /// Switch to any account in the DB via the dev impersonate endpoint.
  /// Returns true on success, false if the backend wasn't reachable or
  /// the route is gated (production).
  Future<bool> switchToAnyAccount(String email) async {
    // Lazy import to avoid a controller→service cycle at parse time.
    final result = await _devImpersonate(email);
    if (result == null) return false;
    await applySession(result.$1, result.$2);
    return true;
  }

  /// Tiny indirection so we don't import DevService at the top of this
  /// file (which would force every consumer of AuthController to pull in
  /// the dev surface). Defined as a top-level function below.
  static Future<(String, User)?> Function(String email) _devImpersonate =
      _defaultDevImpersonate;

  /// Hookable for tests — flips the impersonation strategy.
  // ignore: use_setters_to_change_properties
  static void overrideDevImpersonate(
    Future<(String, User)?> Function(String email) fn,
  ) {
    _devImpersonate = fn;
  }

  /// Switch to one of the seeded test accounts in-place. Tries a REAL
  /// backend login first (using [testPassword] — the seed migration
  /// installs the matching bcrypt hash) so the user gets a real JWT and
  /// the WebSocket can connect to receive realtime events.
  ///
  /// Falls back to a synthetic local-only user when the backend is
  /// unreachable, so dev still works without a server running.
  Future<void> switchTestAccount(String email) async {
    final result = await AuthService.login(email, testPassword);
    if (result['success'] == true) {
      _user.value = result['user'] as User;
      _token.value = result['token'] as String;
      await _loadSubs();
      return;
    }

    // Backend isn't reachable — fall back to local-only fake session so
    // the dev experience doesn't fully break.
    final user = _userFromTestEmail(email);
    final token = 'test-token-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await AuthService.saveSession(token, user);
    } catch (_) {/* ignore */}
    _user.value = user;
    _token.value = token;
    await _loadSubs();
  }

  User _userFromTestEmail(String email) {
    final preset = testAccounts[email.toLowerCase()];
    if (preset != null) {
      return User(
        id: preset.id,
        email: email,
        name: preset.name,
        subscriptionTier: preset.tier,
        subscriptionStatus: 'ACTIVE',
        role: preset.role,
        expertId: preset.expertId,
      );
    }
    return User(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      email: email,
      name: email.split('@').first,
      subscriptionTier: 'FREE',
      subscriptionStatus: 'ACTIVE',
      role: UserRole.user,
    );
  }

  Future<void> logout() async {
    await AuthService.logout();
    // Also sign the user out of Firebase + Google so the next sign-in
    // shows the account picker instead of silently reusing the cached
    // account. Wrapped in try/catch because the user may have signed in
    // via email/password and never touched Firebase — in that case
    // signOut() is a no-op but still returns cleanly.
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
    } catch (_) {/* not signed into Firebase — fine */}
    try {
      await GoogleSignIn().signOut();
    } catch (_) {/* not signed into Google — fine */}
    _user.value = null;
    _token.value = null;
    _needsOnboarding.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAvatarPathKey);
    await prefs.remove(_kAvatarAccentKey);
    _avatarPath.value = null;
    _avatarAccentArgb.value = null;
  }

  /// Called by services when the backend returns 401 — typically because the
  /// stored JWT is stale (test-token from a previous fake-login flow, or a
  /// real token that's past its expiry). Clears the session and shows a
  /// snackbar so the user knows to log in again. The next build of
  /// `_AppEntry` swaps to the LoginScreen automatically.
  bool _handlingAuthFailure = false;
  Future<void> handleAuthFailure() async {
    if (_handlingAuthFailure) return;
    _handlingAuthFailure = true;
    try {
      await logout();
      Get.snackbar(
        'Session expired',
        'Please sign in again.',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
    } finally {
      _handlingAuthFailure = false;
    }
  }

  /// Updates the backend profile (mig 0038) + the local SharedPreferences
  /// extras (the picked image path + accent color, which the UI uses
  /// for offline rendering).
  ///
  ///   * `name` — when non-null, written to the backend.
  ///   * `avatarUrl` — when non-null, written to the backend's
  ///     users.avatar_url column. Phase 2.4: produced by uploading the
  ///     picked image via /me/uploads/image before calling here.
  ///   * `avatarPath`, `avatarAccent`, `clearAvatar*` — local-only
  ///     SharedPreferences state; the path is what the gallery picker
  ///     returned (already uploaded into avatarUrl when present).
  ///
  /// Returns `null` on success, or an error message string suitable for
  /// a SnackBar.
  Future<String?> updateProfile({
    String? name,
    String? avatarUrl,
    String? avatarPath,
    Color? avatarAccent,
    bool clearAvatarPath = false,
    bool clearAvatarAccent = false,
    bool clearAvatarUrl = false,
  }) async {
    final token = _token.value;
    final current = _user.value;

    // Compose the backend PATCH body. We only call the endpoint when
    // there's something to send (otherwise it's a wasted round-trip).
    final patchBody = <String, dynamic>{};
    if (name != null) patchBody['name'] = name;
    if (avatarUrl != null) patchBody['avatarUrl'] = avatarUrl;
    if (clearAvatarUrl) patchBody['avatarUrl'] = '';

    if (token != null && current != null && patchBody.isNotEmpty) {
      try {
        final response = await http
            .patch(
              Uri.parse('${ApiConfig.baseUrl}/me/profile'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: json.encode(patchBody),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final body = json.decode(response.body) as Map<String, dynamic>;
          _user.value = User.fromJson(body).copyWith(
            // Preserve subscription tier/status from the existing session
            // since PATCH /me/profile doesn't return those.
            subscriptionTier: current.subscriptionTier,
            subscriptionStatus: current.subscriptionStatus,
          );
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
              AuthService.keyUser,
              json.encode(_user.value!.toJson()),
            );
          } catch (_) {/* best-effort */}
        } else if (response.statusCode == 401) {
          await handleAuthFailure();
          return 'Session expired — please sign in again.';
        } else {
          final body = _safeDecodeProfile(response.body);
          return body['error']?.toString() ?? 'Could not save profile.';
        }
      } catch (e) {
        return 'Network error: $e';
      }
    }

    // Local-only extras — the picked file path (used to render the
    // image without re-downloading) + the gradient accent color.
    await _persistLocalAvatarExtras(
      avatarPath: avatarPath,
      avatarAccent: avatarAccent,
      clearAvatarPath: clearAvatarPath,
      clearAvatarAccent: clearAvatarAccent,
    );
    return null;
  }

  // Internal helper — same body as the legacy updateProfileTest minus
  // the name-write path (that now goes through the backend).
  Future<void> _persistLocalAvatarExtras({
    String? avatarPath,
    Color? avatarAccent,
    bool clearAvatarPath = false,
    bool clearAvatarAccent = false,
  }) async {
    if (clearAvatarPath) {
      _avatarPath.value = null;
    } else if (avatarPath != null) {
      _avatarPath.value = avatarPath;
    }
    if (clearAvatarAccent) {
      _avatarAccentArgb.value = null;
    } else if (avatarAccent != null) {
      _avatarAccentArgb.value = avatarAccent.toARGB32();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_avatarPath.value == null) {
        await prefs.remove(_kAvatarPathKey);
      } else {
        await prefs.setString(_kAvatarPathKey, _avatarPath.value!);
      }
      if (_avatarAccentArgb.value == null) {
        await prefs.remove(_kAvatarAccentKey);
      } else {
        await prefs.setInt(_kAvatarAccentKey, _avatarAccentArgb.value!);
      }
    } catch (_) {/* persistence is best-effort */}
  }

  static Map<String, dynamic> _safeDecodeProfile(String s) {
    try {
      final v = json.decode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return {};
  }

  /// Updates the locally-stored profile (test mode).
  Future<void> updateProfileTest({
    String? name,
    String? avatarPath,
    Color? avatarAccent,
    bool clearAvatarPath = false,
    bool clearAvatarAccent = false,
  }) async {
    final current = _user.value;
    if (name != null && name.isNotEmpty && current != null) {
      _user.value = current.copyWith(name: name);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          AuthService.keyUser,
          json.encode(_user.value!.toJson()),
        );
      } catch (_) {/* persistence is best-effort */}
    }

    if (clearAvatarPath) {
      _avatarPath.value = null;
    } else if (avatarPath != null) {
      _avatarPath.value = avatarPath;
    }

    if (clearAvatarAccent) {
      _avatarAccentArgb.value = null;
    } else if (avatarAccent != null) {
      _avatarAccentArgb.value = avatarAccent.toARGB32();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_avatarPath.value == null) {
        await prefs.remove(_kAvatarPathKey);
      } else {
        await prefs.setString(_kAvatarPathKey, _avatarPath.value!);
      }
      if (_avatarAccentArgb.value == null) {
        await prefs.remove(_kAvatarAccentKey);
      } else {
        await prefs.setInt(_kAvatarAccentKey, _avatarAccentArgb.value!);
      }
    } catch (_) {/* persistence is best-effort */}
  }

  void clearError() => _error.value = null;

  /// Re-fetches the current user from `/api/me` and updates local state.
  ///
  /// Called by the realtime layer when a `user_role_changed` event arrives —
  /// e.g. after the admin approves an expert application, the user's role
  /// flips to EXPERT and we want the UI to react without a re-login.
  Future<void> refreshFromBackend() async {
    final t = _token.value;
    if (t == null) return;
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/me'),
        headers: {'Authorization': 'Bearer $t'},
      );
      if (response.statusCode != 200) return;
      final body = json.decode(response.body) as Map<String, dynamic>;
      final updated = User(
        id: (body['id'] as num).toInt(),
        email: body['email'] as String? ?? _user.value?.email ?? '',
        name: body['name'] as String?,
        subscriptionTier: body['tier'] as String? ?? _user.value?.subscriptionTier ?? 'FREE',
        subscriptionStatus: body['status'] as String? ?? 'ACTIVE',
        role: UserRoleX.fromWire(body['role'] as String?),
        expertId: body['expertId'] as String?,
      );
      _user.value = updated;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AuthService.keyUser, json.encode(updated.toJson()));
      } catch (_) {/* persistence is best-effort */}
    } catch (_) {/* network errors swallowed; next event will retry */}
  }

  // ── per-user expert subscriptions ──
  bool isSubscribedTo(String expertId) {
    final u = _user.value;
    if (u == null) return false;
    if (u.expertId == expertId) return true;
    return _subscribedExpertIds.contains(expertId);
  }

  Future<void> toggleSubscription(String expertId) async {
    if (_user.value == null) return;
    if (_subscribedExpertIds.contains(expertId)) {
      _subscribedExpertIds.remove(expertId);
    } else {
      _subscribedExpertIds.add(expertId);
    }
    await _persistSubs();
  }

  Future<void> _loadSubs() async {
    final u = _user.value;
    if (u == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('subs_${u.id}') ?? const [];
      _subscribedExpertIds
        ..clear()
        ..addAll(raw);
    } catch (_) {/* ignore */}
  }

  Future<void> _persistSubs() async {
    final u = _user.value;
    if (u == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('subs_${u.id}', _subscribedExpertIds.toList());
    } catch (_) {/* ignore */}
  }
}

/// Outcome of [AuthController.login] / [AuthController.register] /
/// [AuthController.verifyEmail]. Three states:
///
/// * **authenticated** — JWT saved, caller should pop to root.
/// * **needsVerification** — user/server expects a 6-digit code next.
///   `email` is the address to verify; `devCode` is the pre-filled code
///   the dev backend hands back (null in production builds — the user
///   has to read it from their email).
/// * **failed** — show `error` in the inline banner.
class AuthFlowResult {
  final bool authenticated;
  final bool needsVerification;
  final String? email;
  final String? devCode;
  final String? error;

  const AuthFlowResult._({
    required this.authenticated,
    required this.needsVerification,
    this.email,
    this.devCode,
    this.error,
  });

  const AuthFlowResult.authenticated()
      : this._(authenticated: true, needsVerification: false);

  const AuthFlowResult.needsVerification({required String email, String? devCode})
      : this._(
          authenticated: false,
          needsVerification: true,
          email: email,
          devCode: devCode,
        );

  const AuthFlowResult.failed(String message)
      : this._(authenticated: false, needsVerification: false, error: message);

  bool get isFailure => !authenticated && !needsVerification;
}

class TestAccount {
  final int id;
  final String name;
  final UserRole role;
  final String? expertId;
  final String tier;
  const TestAccount({
    required this.id,
    required this.name,
    required this.role,
    required this.expertId,
    required this.tier,
  });
}

/// Public, ordered view of every preset account so UI can list them.
class TestAccountPreset {
  final String email;
  final String name;
  final UserRole role;
  final String? expertId;
  final String tier;
  const TestAccountPreset({
    required this.email,
    required this.name,
    required this.role,
    required this.expertId,
    required this.tier,
  });
}

/// Default impersonation strategy — hits the dev-only backend route.
/// Pulled out as a top-level function so AuthController doesn't need to
/// know about DevService's classes at field-init time.
Future<(String, User)?> _defaultDevImpersonate(String email) async {
  final result = await DevService.impersonate(email);
  if (result == null) return null;
  return (result.token, result.user);
}

List<TestAccountPreset> get testAccountPresets => AuthController.testAccounts
    .entries
    .map(
      (e) => TestAccountPreset(
        email: e.key,
        name: e.value.name,
        role: e.value.role,
        expertId: e.value.expertId,
        tier: e.value.tier,
      ),
    )
    .toList(growable: false);
