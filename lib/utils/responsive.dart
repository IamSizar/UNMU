import 'package:flutter/widgets.dart';

/// =============================================================================
/// Responsive foundation (iPad phase P1)
///
/// Single source of truth for "how wide is the screen and what should we do
/// about it". Everything in the iPad-responsive work (adaptive nav, content
/// max-width, multi-column grids, split-view) reads from HERE so breakpoints
/// never drift between screens.
///
/// IMPORTANT: decisions are made on **width**, never on the device model.
/// That's what makes the app behave correctly in iPad Split View / Slide Over
/// and on a resized desktop window — a narrow pane on an iPad should look like
/// a phone, a wide one like a tablet. Always pass a BuildContext (or a width
/// from LayoutBuilder), not `Platform.isIOS`.
///
/// Phone layouts are completely unchanged: at phone widths every helper here
/// returns the same values the screens already use (phone size class, 1
/// column, no max-width clamp, existing padding).
/// =============================================================================

/// Width-based size classes. Thresholds chosen to match Material's common
/// "compact / medium / expanded" cutoffs and Apple's iPad size classes:
///
///   * phone   < 600   — all current phones (portrait + landscape), and any
///                       narrow multitasking pane on iPad.
///   * tablet  600–1023 — iPad portrait, small split panes, foldables.
///   * large   ≥ 1024  — iPad landscape, desktop windows.
enum ScreenSize { phone, tablet, large }

class Breakpoints {
  Breakpoints._();

  /// Below this width we treat the layout as a phone.
  static const double tablet = 600;

  /// At/above this width we treat the layout as a large tablet / desktop.
  static const double large = 1024;

  /// Comfortable reading measure for a single-column content area. Beyond
  /// this, lines get too long, so reading screens clamp to it and center.
  static const double readingMaxWidth = 720;

  /// A roomier clamp for form/composer-style screens that can use a bit more
  /// horizontal space than pure reading content.
  static const double formMaxWidth = 900;

  static ScreenSize sizeOf(double width) {
    if (width >= large) return ScreenSize.large;
    if (width >= tablet) return ScreenSize.tablet;
    return ScreenSize.phone;
  }
}

/// Width-aware helpers on BuildContext. Prefer these over raw MediaQuery so
/// the intent reads clearly at the call site (`context.isTablet`).
extension ResponsiveContext on BuildContext {
  /// The logical width of the current view.
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// The logical height of the current view.
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Width-based size class (see [ScreenSize]).
  ScreenSize get screenSize => Breakpoints.sizeOf(screenWidth);

  // NOTE: GetX already defines isPhone / isTablet / isLandscape on
  // BuildContext, but those are computed from the device's *shortest side*
  // (device-based) — so a narrow iPad Split View pane would still report
  // isTablet. We deliberately use DIFFERENT names (isCompact / isWide /
  // isWideLandscape) that are purely WIDTH-based, so the layout reacts to
  // the actual pane width and Split View / Slide Over behave correctly.

  /// True for phone-class widths (also true for a narrow iPad split pane).
  bool get isCompact => screenSize == ScreenSize.phone;

  /// True for tablet-class widths and up (tablet OR large). The main
  /// "should I show the tablet layout?" check.
  bool get isWide => screenSize != ScreenSize.phone;

  /// True only for the widest class (iPad landscape / desktop). Use for
  /// things like side-by-side master/detail that need real width.
  bool get isLarge => screenSize == ScreenSize.large;

  /// True when the view is wider than it is tall AND large enough to use
  /// landscape-only affordances (split view, extended rail).
  bool get isWideLandscape => isLarge && screenWidth > screenHeight;

  /// Pick a value by size class without a chain of if/else at the call site.
  /// `large` falls back to `tablet` when omitted.
  T responsive<T>({required T phone, required T tablet, T? large}) {
    switch (screenSize) {
      case ScreenSize.large:
        return large ?? tablet;
      case ScreenSize.tablet:
        return tablet;
      case ScreenSize.phone:
        return phone;
    }
  }

  /// Symmetric horizontal page padding that grows with width. Phone keeps the
  /// app's existing 16; wider screens get more breathing room.
  double get pagePadding => responsive<double>(phone: 16, tablet: 24, large: 32);

  /// Horizontal inset that visually centers a column of [contentWidth] on
  /// wide screens — WITHOUT adding any wrapper widget. Drop it in as a
  /// scroll view's horizontal padding and the content centers itself,
  /// leaving the screen's internal layout (Spacers, IntrinsicHeight fills,
  /// etc.) completely untouched. On phone it returns [phonePadding]
  /// unchanged, so phones render exactly as before.
  double centeringHPad({double contentWidth = 460, double phonePadding = 20}) {
    if (!isWide) return phonePadding;
    final pad = (screenWidth - contentWidth) / 2;
    return pad > phonePadding ? pad : phonePadding;
  }
}

/// Builds a [SliverList] that lays the given items into responsive columns —
/// 1 on phone, [tablet] on tablet, [large] on large screens.
///
/// GLITCH-PROOF BY DESIGN:
///   * At 1 column it returns a plain `SliverList.builder` with the SAME
///     itemCount + builder, so phone rendering is byte-for-byte unchanged.
///   * At 2+ columns it groups items into Rows of equal-width [Expanded]
///     cells with `CrossAxisAlignment.start`, so each row is exactly as
///     tall as its tallest card — content never clips even if heights vary,
///     and a short final row keeps its cards at column width (not stretched).
///
/// [itemBuilder] is the exact same builder you'd pass to a normal
/// SliverList — the card's own margins become the gutter between columns.
Widget sliverResponsiveCards({
  required BuildContext context,
  required int itemCount,
  required IndexedWidgetBuilder itemBuilder,
  int tablet = 2,
  int large = 3,
}) {
  final cols = context.responsive<int>(phone: 1, tablet: tablet, large: large);
  if (cols <= 1) {
    return SliverList.builder(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
  final rowCount = (itemCount + cols - 1) ~/ cols;
  return SliverList.builder(
    itemCount: rowCount,
    itemBuilder: (ctx, row) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var c = 0; c < cols; c++)
            Expanded(
              child: () {
                final i = row * cols + c;
                return i < itemCount
                    ? itemBuilder(ctx, i)
                    : const SizedBox.shrink();
              }(),
            ),
        ],
      );
    },
  );
}

/// Box (non-sliver) sibling of [sliverResponsiveCards] — a plain ListView.
///
/// At 1 column it's a `ListView.separated` with a [rowSpacing] gap, so a
/// screen that used `ListView.separated(separatorBuilder: SizedBox(height:
/// 12))` renders identically on phone. At 2+ columns it chunks items into
/// Rows of equal-width [Expanded] cells (gap [columnSpacing]) separated by
/// [rowSpacing]; rows size to their tallest card so nothing clips.
Widget responsiveCardList({
  required BuildContext context,
  required int itemCount,
  required IndexedWidgetBuilder itemBuilder,
  EdgeInsetsGeometry? padding,
  ScrollPhysics? physics,
  double rowSpacing = 12,
  double columnSpacing = 12,
  int tablet = 2,
  int large = 3,
}) {
  final cols = context.responsive<int>(phone: 1, tablet: tablet, large: large);
  if (cols <= 1) {
    return ListView.separated(
      padding: padding,
      physics: physics,
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: rowSpacing),
      itemBuilder: itemBuilder,
    );
  }
  final rowCount = (itemCount + cols - 1) ~/ cols;
  return ListView.builder(
    padding: padding,
    physics: physics,
    itemCount: rowCount,
    itemBuilder: (ctx, row) {
      return Padding(
        padding: EdgeInsets.only(bottom: row == rowCount - 1 ? 0 : rowSpacing),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) SizedBox(width: columnSpacing),
              Expanded(
                child: () {
                  final i = row * cols + c;
                  return i < itemCount
                      ? itemBuilder(ctx, i)
                      : const SizedBox.shrink();
                }(),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Centers its [child] in a column no wider than [maxWidth] on tablet+ widths.
///
/// On PHONE widths this is a hard pass-through — it returns [child]
/// untouched (no clamp, no added padding), so existing phone layouts render
/// byte-for-byte the same. On iPad it caps the content to a comfortable
/// measure and centers it instead of stretching edge-to-edge; the side
/// margin comes from the clamp itself, and each screen keeps its own inner
/// padding, so we never double-pad.
///
/// Used heavily in P3 (reading screens). Lives here so the clamp width is
/// defined in one place.
class MaxWidthBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  /// Extra horizontal padding applied OUTSIDE the clamp on wide screens
  /// only. Defaults to 0 — the clamp gap usually provides enough margin and
  /// the wrapped screen keeps its own padding.
  final double horizontalPadding;

  /// Vertical alignment of the clamped column within the available space.
  final Alignment alignment;

  const MaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.readingMaxWidth,
    this.horizontalPadding = 0,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    // Phone: untouched.
    if (context.isCompact) return child;
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    );
    if (horizontalPadding > 0) {
      content = Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: content,
      );
    }
    return Align(alignment: alignment, child: content);
  }
}
