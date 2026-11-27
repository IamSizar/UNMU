// The forgot-password flow existed but nothing linked to it, so a user who
// forgot their password had no way back in. The login screen must open it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:halalstocks/controllers/app_config_controller.dart';
import 'package:halalstocks/controllers/auth_controller.dart';
import 'package:halalstocks/screens/auth/forgot_password_screen.dart';
import 'package:halalstocks/screens/auth/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    Get.put(AuthController());
    Get.put(AppConfigController(allowTestTools: false));
  });

  testWidgets('login links to forgot password', (t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const GetMaterialApp(home: LoginScreen()));
    await t.pump();
    final link = find.text('auth.forgotPassword');
    expect(link, findsOneWidget);
    await t.ensureVisible(link);
    await t.tap(link);
    await t.pumpAndSettle();
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });
}
