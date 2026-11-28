// =============================================================================
// language_controller_test.dart — the saved language must reach GetX on launch.
//
// Bug found on a simulator run: after choosing Arabic and restarting, layout
// direction and Arabic content were right but every `.tr` label was English.
// _loadLanguage() updated the controller's own locale but never told GetX
// (Get.updateLocale), so translations kept the default.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:halalstocks/controllers/language_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    Get.reset();
  });

  /// Starts the controller the way main.dart does (inside a GetMaterialApp,
  /// because Get.updateLocale reassembles the widget tree) and waits for the
  /// async SharedPreferences read in _loadLanguage to finish.
  Future<LanguageController> start(
    WidgetTester tester,
    Map<String, Object> saved,
  ) async {
    SharedPreferences.setMockInitialValues(saved);
    await tester.pumpWidget(const GetMaterialApp(
      locale: Locale('en'),
      home: SizedBox(),
    ));
    final controller = Get.put(LanguageController());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('a saved Arabic choice is applied to GetX on start',
      (tester) async {
    final controller = await start(tester, {'language': 'ar'});

    expect(controller.isArabic, isTrue);
    expect(Get.locale?.languageCode, 'ar');
  });

  testWidgets('with nothing saved the app stays on English', (tester) async {
    final controller = await start(tester, {});

    expect(controller.isArabic, isFalse);
    expect(Get.locale?.languageCode, 'en');
  });
}
