import 'package:flutter/material.dart';

/// Wraps [child] with a transparent gesture detector that drops focus on
/// any unhandled tap — making the keyboard slide away when the user taps
/// outside the active text field.
///
/// Drop this around the body of any screen that has a [TextField] /
/// [TextFormField] in it. The default Flutter behavior is to keep the
/// keyboard open until the user explicitly taps "done" or hits back —
/// which feels stale on modern apps.
///
///   Scaffold(
///     body: DismissKeyboardOnTap(child: ...form widgets...),
///   )
///
/// `behavior: HitTestBehavior.opaque` ensures the gesture detector
/// catches taps on empty space (like the Scaffold background) without
/// blocking interactions on real widgets — buttons, list tiles, etc.
/// still get their taps because the framework dispatches in z-order.
class DismissKeyboardOnTap extends StatelessWidget {
  final Widget child;
  const DismissKeyboardOnTap({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // unfocus() drops focus from whatever has it, which slides the
        // keyboard away. The disallowScope variant prevents Flutter from
        // re-focusing a parent FocusNode if the screen was inside a
        // FocusScope (rare but harmless to guard against).
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: child,
    );
  }
}
