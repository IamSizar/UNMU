import 'package:flutter/material.dart';

/// An [Icon] whose glyph mirrors horizontally in RTL so directional
/// arrows/chevrons point the correct way in Arabic. Same bounding box
/// as a plain Icon (Transform.flip is visual-only), so it never affects
/// layout. Use for back/forward/chevron icons ONLY.
class DirectionalIcon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? color;
  const DirectionalIcon(this.icon, {super.key, this.size, this.color});
  @override
  Widget build(BuildContext context) {
    final ic = Icon(icon, size: size, color: color);
    return Directionality.of(context) == TextDirection.rtl
        ? Transform.flip(flipX: true, child: ic)
        : ic;
  }
}
