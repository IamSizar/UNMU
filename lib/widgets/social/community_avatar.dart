import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../screens/social/social_tokens.dart';

/// Square avatar tile for a community. Renders the uploaded `avatarUrl`
/// when one is set, otherwise a region-tinted initials tile.
///
/// Designed as a drop-in replacement for the inline `Container` +
/// initials block previously duplicated across the social hub cards,
/// community detail header, and discover results. Centralising the
/// rendering here also fixes the old contrast bug where the initials
/// text color (full cyan) matched the very-light cyan-tinted background
/// closely enough to look like a solid teal block.
///
/// The fallback now uses a stronger contrast pairing:
///   * Background — region color at 18% alpha (unchanged)
///   * Border    — region color at 60% alpha
///   * Initials  — region color at full strength on top of a layered
///                 white-90% glyph stroke so the letters read on any tint
///
/// Layout:
///   * Outer rounded square ([size] × [size], radius = [size] * 0.25)
///   * If `avatarUrl` non-empty → `Image.network` clipped to the square
///   * Else                      → centred initials text
///
/// The widget is intentionally `const`-friendly so the social hub list
/// doesn't pay a rebuild cost when scrolling.
class CommunityAvatar extends StatelessWidget {
  /// Display size in logical pixels (width = height).
  final double size;

  /// Community name used to derive the 1–2 letter fallback initials.
  final String name;

  /// Region code (`'US'`, `'GCC'`, `''`, …) used to tint the fallback
  /// tile. Empty string → cyan tint via [SocialTokens.regionColor].
  final String regionCode;

  /// Remote URL or `/uploads/...` path. Empty string renders the
  /// initials fallback.
  final String avatarUrl;

  /// Optional override for the corner radius. Defaults to ~25% of size,
  /// which lands somewhere between iOS-launcher-icon rounding and a
  /// classic rounded rectangle.
  final double? borderRadius;

  /// When true, draws a 1px ring around the tile. Cards that already
  /// supply their own border (the owned-community gold ring) pass
  /// `showRing: false`.
  final bool showRing;

  const CommunityAvatar({
    super.key,
    required this.size,
    required this.name,
    required this.regionCode,
    required this.avatarUrl,
    this.borderRadius,
    this.showRing = true,
  });

  /// Resolves a possibly-relative avatar URL into something `Image.network`
  /// can actually load.
  ///
  /// The upload service hands back relative paths (`/uploads/images/abc.png`)
  /// because the upload endpoint lives on the same host but at a different
  /// path than the `/api` prefix. Passing those raw to `Image.network`
  /// would fail (Flutter requires absolute http/https URIs), Flutter's
  /// `errorBuilder` would fire, and the user would see the initials
  /// fallback even though they DID upload an avatar.
  ///
  /// Strips the trailing `/api` off the API base URL so we point at the
  /// raw host (e.g. `http://192.168.1.75:8080/uploads/...`).
  static String _resolve(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    if (url.startsWith('/')) return '$base$url';
    return '$base/$url';
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? size * 0.25;
    final raw = avatarUrl.trim();
    final hasImage = raw.isNotEmpty;
    final resolved = hasImage ? _resolve(raw) : '';
    final accent = SocialTokens.regionColor(regionCode);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: hasImage ? null : accent.withValues(alpha: 0.18),
          border: showRing
              ? Border.all(
                  color: accent.withValues(alpha: hasImage ? 0.45 : 0.55),
                  width: 1,
                )
              : null,
        ),
        alignment: Alignment.center,
        child: hasImage
            ? Image.network(
                resolved,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // If the URL 404s, fall back to the initials tile so
                // the card never shows a broken-image icon.
                errorBuilder: (_, __, ___) => _Initials(
                  name: name,
                  size: size,
                  accent: accent,
                ),
                // Subtle skeleton while loading — avoids a flash.
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: size,
                    height: size,
                    color: accent.withValues(alpha: 0.12),
                  );
                },
              )
            : _Initials(name: name, size: size, accent: accent),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  final double size;
  final Color accent;
  const _Initials({
    required this.name,
    required this.size,
    required this.accent,
  });

  // Compute the 1-2 letter initials with sensible fallbacks for empty
  // names ("?") and single-token names ("E" from "EasyTech").
  static String _of(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final letters = _of(name);
    // Pick a contrasting text color depending on how light the region
    // tint is. We darken the accent (50% lerp toward black) so the
    // letters always read against the 18%-alpha background. This fixes
    // the bug where solid cyan letters disappeared into a cyan-tinted
    // tile on light themes.
    final letterColor = Color.lerp(accent, Colors.black, 0.45) ?? accent;
    return Text(
      letters,
      style: TextStyle(
        color: letterColor,
        fontWeight: FontWeight.w900,
        // ~38% of the tile width → nice "logo letter" weight.
        fontSize: size * 0.38,
        letterSpacing: -0.5,
        height: 1,
      ),
    );
  }
}
