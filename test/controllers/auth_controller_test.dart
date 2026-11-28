// =============================================================================
// auth_controller_test.dart — a request in flight must not bring back the
// splash screen.
//
// Found in the 2026-11-28 simulator run: `authChecked` was `!isLoading`, so
// the email check behind "Log in" flipped the app root back to the splash,
// which destroyed the login screen; the login request was never sent.
// =============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:halalstocks/controllers/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
  });

  test('authChecked stays true while a later request is loading', () async {
    final auth = Get.put(AuthController());
    // Let the persisted-session check finish.
    for (var i = 0; i < 20 && !auth.authChecked; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(auth.authChecked, isTrue);

    final pending = auth.checkEmail('someone@example.test');
    expect(auth.isLoading, isTrue); // the request is in flight
    expect(auth.authChecked, isTrue); // ...but the app must not show splash
    await pending;
    expect(auth.authChecked, isTrue);
  });
}
