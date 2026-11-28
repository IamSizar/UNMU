// The loading spinner must look native on iOS and keep its colour there.
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/widgets/platform_adaptive/platform_spinner.dart';

Widget _host(Widget child, {double box = 40}) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: box, height: box, child: child)),
      ),
    );

void main() {
  testWidgets('iOS: native activity indicator in the given colour',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(_host(const PlatformSpinner(color: Colors.white)));
    final ind = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator));
    expect(ind.color, Colors.white);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS: shrinks to fit a small box', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(_host(const PlatformSpinner(), box: 14));
    final ind = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator));
    expect(ind.radius, 7);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android: Material indicator with colour and stroke',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
        _host(const PlatformSpinner(color: Colors.red, strokeWidth: 2)));
    final ind = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ind.color, Colors.red);
    expect(ind.strokeWidth, 2);
    debugDefaultTargetPlatformOverride = null;
  });
}
