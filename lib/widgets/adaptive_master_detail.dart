import 'package:flutter/material.dart';

import '../utils/responsive.dart';

/// Generic two-pane master/detail layout for the iPad-landscape "real app"
/// feel (P7).
///
/// Behavior by width:
///   * NOT large-landscape (phones, phone-landscape, portrait iPad, narrow
///     split-view panes) → renders ONLY [master], so the screen behaves
///     exactly as it always has (the master's own tap handlers keep doing
///     their normal push navigation). Zero change off the big canvas.
///   * Large landscape (iPad landscape / desktop) → master on the leading
///     side at [masterWidth], a divider, then a detail pane that shows
///     [placeholder] until something is selected, then [detailBuilder].
///
/// This widget is purely presentational: the PARENT owns the selected value
/// and decides, in split mode, to update it instead of pushing a route.
class AdaptiveMasterDetail<T> extends StatelessWidget {
  final Widget master;
  final T? selected;
  final Widget Function(BuildContext context, T value) detailBuilder;
  final Widget placeholder;
  final double masterWidth;

  const AdaptiveMasterDetail({
    super.key,
    required this.master,
    required this.selected,
    required this.detailBuilder,
    required this.placeholder,
    this.masterWidth = 360,
  });

  /// True when this layout will actually show two panes — lets the parent
  /// switch a card's tap from "push route" to "select" only when it matters.
  static bool isSplit(BuildContext context) => context.isWideLandscape;

  @override
  Widget build(BuildContext context) {
    if (!context.isWideLandscape) return master;
    final sel = selected;
    return Row(
      children: [
        SizedBox(width: masterWidth, child: master),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: sel == null ? placeholder : detailBuilder(context, sel),
        ),
      ],
    );
  }
}
