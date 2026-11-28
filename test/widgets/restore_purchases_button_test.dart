// Restore purchases: App Review requires it; the button must call the store
// and tell the user what happened. iOS only (Android cannot verify yet).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:halalstocks/widgets/subscriptions/restore_purchases_button.dart';

Widget _host(TargetPlatform platform, Future<bool> Function() onRestore) =>
    GetMaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(body: RestorePurchasesButton(onRestore: onRestore)),
    );

void main() {
  testWidgets('iOS: tapping calls restore and confirms', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(TargetPlatform.iOS, () async {
      calls++;
      return true;
    }));
    await tester.tap(find.text('mySubscriptions.restore'));
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    expect(find.text('mySubscriptions.restoreStarted'), findsOneWidget);
  });

  testWidgets('iOS: store unavailable is reported', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.iOS, () async => false));
    await tester.tap(find.text('mySubscriptions.restore'));
    await tester.pump();
    await tester.pump();
    expect(find.text('mySubscriptions.restoreUnavailable'), findsOneWidget);
  });

  testWidgets('Android: button is hidden', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android, () async => true));
    expect(find.text('mySubscriptions.restore'), findsNothing);
  });
}
