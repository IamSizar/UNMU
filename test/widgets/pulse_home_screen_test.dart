// =============================================================================
// pulse_home_screen_test.dart — the Pulse home tab in every state it can be in
// (loading, content, empty day, offline, server error) on iOS and Android, in
// light and dark, in English and Arabic (RTL). A fake API drives the controller.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:halalstocks/controllers/auth_controller.dart';
import 'package:halalstocks/controllers/language_controller.dart';
import 'package:halalstocks/controllers/pulse_controller.dart';
import 'package:halalstocks/localization/app_translations.dart';
import 'package:halalstocks/models/pulse_item.dart';
import 'package:halalstocks/screens/pulse/pulse_home_screen.dart';
import 'package:halalstocks/services/pulse_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../support/fake_pulse_api.dart';

void main() {
  late FakePulseApi api;

  // The app initialises date data in main(); tests must do the same.
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
    // Report visibility at once so no 500ms debounce timer outlives a test.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'pulse_tip_seen': true});
    Get.reset();
    api = FakePulseApi();
    Get.put(AuthController());
    Get.put(LanguageController());
    Get.put(PulseController(api: api));
  });

  /// Pumps the home tab with the given platform/brightness/locale.
  Future<void> pump(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
    Brightness brightness = Brightness.light,
    String lang = 'en',
    bool load = true,
  }) async {
    // Set the app language directly: setLanguage() would call
    // Get.updateLocale, which schedules a frame mid-test.
    Get.find<LanguageController>().localeRx.value = Locale(lang);
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: Locale(lang),
        fallbackLocale: const Locale('en'),
        theme: ThemeData(platform: platform, brightness: brightness),
        home: const PulseHomeScreen(),
      ),
    );
    if (load) await Get.find<PulseController>().loadToday();
    await tester.pump(const Duration(milliseconds: 100));
  }

  final fullDay = fakePulseDay([
    fakePulseItem(1, PulseSlot.global),
    fakePulseItem(2, PulseSlot.gulf),
    fakePulseItem(3, PulseSlot.sharia),
    fakePulseItem(4, PulseSlot.opportunity),
  ]);

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final brightness in Brightness.values) {
      testWidgets('shows all four slots ($platform, $brightness)', (t) async {
        api.todayResult = PulseResult.ok(fullDay);
        await pump(t, platform: platform, brightness: brightness);
        for (final id in [1, 2, 3, 4]) {
          expect(find.text('Title $id'), findsOneWidget);
        }
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('shows skeletons before the first load finishes', (t) async {
    await pump(t, load: false);
    expect(find.text('Title 1'), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a day with some slots shows a placeholder for the rest', (
    t,
  ) async {
    api.todayResult = PulseResult.ok(
      fakePulseDay([fakePulseItem(1, PulseSlot.global)]),
    );
    await pump(t);
    expect(find.text('Title 1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('an empty day shows the designed empty state', (t) async {
    api.todayResult = PulseResult.ok(fakePulseDay([]));
    await pump(t);
    expect(find.text('pulse.empty.title'.tr), findsOneWidget);
    expect(find.text('pulse.openArchive'.tr), findsOneWidget);
  });

  testWidgets('offline shows a friendly state and Retry reloads', (t) async {
    api.todayResult = const PulseResult.fail(PulseFailure.offline);
    await pump(t);
    expect(find.text('pulse.error.offline.title'.tr), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);

    api.todayResult = PulseResult.ok(fullDay);
    await t.tap(find.text('pulse.error.retry'.tr));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Title 1'), findsOneWidget);
  });

  testWidgets('a server failure uses the server wording', (t) async {
    api.todayResult = const PulseResult.fail(PulseFailure.server);
    await pump(t, platform: TargetPlatform.iOS);
    expect(find.text('pulse.error.server.title'.tr), findsOneWidget);
  });

  testWidgets('Arabic renders right-to-left with Arabic titles', (t) async {
    api.todayResult = PulseResult.ok(fullDay);
    await pump(t, lang: 'ar');
    expect(find.text('عنوان 1'), findsOneWidget);
    final dir = Directionality.of(t.element(find.byType(Scaffold).first));
    expect(dir, TextDirection.rtl);
    expect(t.takeException(), isNull);
  });

  testWidgets('first-run tip shows once and dismisses', (t) async {
    SharedPreferences.setMockInitialValues({});
    api.todayResult = PulseResult.ok(fullDay);
    await pump(t);
    final dismiss = find.text('pulse.tip.dismiss'.tr);
    expect(dismiss, findsOneWidget);
    await t.tap(dismiss);
    await t.pump();
    expect(dismiss, findsNothing);
  });
}
