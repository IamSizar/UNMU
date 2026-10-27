// =============================================================================
// pulse_surface_box_test.dart — regression test for the tone cards (teal/ink).
//
// Bug found on a simulator run: the cards set both `color` and `gradient` on
// one BoxDecoration. Flutter paints only the gradient in that case, so the
// solid base was dropped and white text sat on a see-through, pale card.
// The fix nests a gradient box over a box that owns the solid base colour.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/widgets/pulse/pulse_tokens.dart';

void main() {
  for (final surface in [PulseSurface.teal, PulseSurface.ink]) {
    testWidgets('$surface paints a solid base colour under its glow',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PulseSurfaceBox(surface: surface, child: const Text('x')),
        ),
      ));

      final decorations = tester
          .widgetList<DecoratedBox>(find.descendant(
            of: find.byType(PulseSurfaceBox),
            matching: find.byType(DecoratedBox),
          ))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .toList();

      // One box owns an opaque solid colour with no gradient...
      final solid =
          decorations.where((d) => d.gradient == null && d.color != null);
      expect(solid, isNotEmpty);
      expect(solid.first.color!.a, 1.0);
      // ...and no single box mixes colour with gradient (Flutter would drop
      // the colour).
      expect(
        decorations.where((d) => d.gradient != null && d.color != null),
        isEmpty,
      );
    });
  }
}
