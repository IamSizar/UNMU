import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Indeterminate loading spinner that looks native: the iOS activity
/// indicator on iOS/macOS, the Material circular indicator elsewhere.
///
/// Unlike `CircularProgressIndicator.adaptive`, the colour carries over to
/// iOS (adaptive only passes `backgroundColor` there, so a white spinner on
/// a coloured button turned grey). The platform comes from the theme, so
/// tests can pick it with `debugDefaultTargetPlatformOverride`.
class PlatformSpinner extends StatelessWidget {
  const PlatformSpinner({super.key, this.color, this.strokeWidth = 4.0});

  /// Spinner colour; null uses the platform default.
  final Color? color;

  /// Material stroke width (ignored on iOS).
  final double strokeWidth;

  /// Cupertino's default radius; shrunk to fit tighter boxes.
  static const double _defaultRadius = 10;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isApple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    if (!isApple) {
      return CircularProgressIndicator(color: color, strokeWidth: strokeWidth);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortest = math.min(constraints.maxWidth, constraints.maxHeight);
        final radius = shortest.isFinite
            ? math.min(_defaultRadius, shortest / 2)
            : _defaultRadius;
        return Center(
          child: CupertinoActivityIndicator(color: color, radius: radius),
        );
      },
    );
  }
}
