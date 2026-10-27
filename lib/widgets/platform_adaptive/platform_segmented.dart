import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// A two-or-more option segmented control in the platform's native style:
/// `CupertinoSlidingSegmentedControl` on iOS, Material `SegmentedButton` on
/// Android. Picks the style from `Theme.of(context).platform` (not
/// `dart:io`), so tests can flip the platform.
///
/// Used where a screen switches between a few peer views (e.g. the Pulse
/// archive's "All | Saved").
class PlatformSegmented<T extends Object> extends StatelessWidget {
  /// Value → visible label, in display order.
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  const PlatformSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        children: {
          for (final e in options.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(e.value, style: const TextStyle(fontSize: 13)),
            ),
        },
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    }
    return SegmentedButton<T>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      segments: [
        for (final e in options.entries)
          ButtonSegment<T>(value: e.key, label: Text(e.value)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
