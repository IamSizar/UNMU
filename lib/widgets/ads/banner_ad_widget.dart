import 'package:flutter/material.dart';
import '../directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../screens/social/social_tokens.dart';
import '../../services/api_service.dart';
import '../common/app_network_image.dart';

/// =============================================================================
/// Banner / Sponsored card.
///
/// Fetches the active ad for [regionCode] from `GET /api/ads` and renders it
/// (company image, title, description, tap-through to the target URL). When no
/// ad is live for this region, it falls back to the built-in premium-promo
/// placeholder so the slot is never empty.
///
/// Cyan-accented insight card — reads cleanly in both light + dark themes.
/// =============================================================================
class BannerAdWidget extends StatefulWidget {
  /// Which region's ads to request. Defaults to GLOBAL (the backend also
  /// returns GLOBAL / region-less ads for any region, so a GLOBAL ad shows
  /// everywhere).
  final String regionCode;
  const BannerAdWidget({super.key, this.regionCode = 'GLOBAL'});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  // Single accent used throughout this card.
  static const Color _accent = SocialTokens.cyan;

  /// The live ad to show, or null while loading / when none is available
  /// (in which case the built-in placeholder renders).
  Map<String, dynamic>? _ad;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  // Re-fetch when the region changes (e.g. user switches GLOBAL → US → GCC on
  // Discover) so each region shows its own ad.
  @override
  void didUpdateWidget(BannerAdWidget old) {
    super.didUpdateWidget(old);
    if (old.regionCode != widget.regionCode) {
      setState(() => _ad = null);
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    final region = widget.regionCode;
    final ads = await ApiService.getAds(region);
    // Guard against a region switch mid-fetch landing stale data.
    if (!mounted || region != widget.regionCode || ads.isEmpty) return;
    setState(() => _ad = ads.first);
  }

  // Tap → open the ad's target URL in the browser. No-op for the placeholder
  // (no URL to open).
  Future<void> _onTap() async {
    HapticFeedback.lightImpact();
    final raw = (_ad?['targetUrl'] as String?)?.trim() ?? '';
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Bad / unlaunchable URL — fail silently rather than crash the card.
    }
  }

  String get _imageUrl => (_ad?['imageUrl'] as String?)?.trim() ?? '';

  // Headline / subtitle straight from the live ad (only ever built when
  // _ad != null). No promo-placeholder fallback — the bad default is gone.
  String _headline() => (_ad?['title'] as String?)?.trim() ?? '';

  String _subtitle() {
    final d = (_ad?['description'] as String?)?.trim() ?? '';
    if (d.isNotEmpty) return d;
    return (_ad?['companyName'] as String?)?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    // Only render when there's a real, live admin ad. No ad (or still
    // loading / fetch failed) → render nothing, so the slot collapses
    // instead of showing a fake placeholder promo.
    if (_ad == null) return const SizedBox.shrink();

    final palette = SocialTheme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: palette.cardShadow(accent: _accent),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _ad == null ? null : _onTap,
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                gradient: palette.cardGradient(),
                borderRadius: BorderRadius.circular(20),
                border: palette.highlightedBorder(accent: _accent),
              ),
              child: Stack(
                children: [
                  // Decorative cyan orb in the corner — fades into the card
                  Positioned(
                    right: -32,
                    top: -32,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _accent.withValues(
                              alpha: palette.isDark ? 0.20 : 0.12,
                            ),
                            _accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // SPONSORED pill row
                      Row(
                        children: [
                          _SponsoredPill(
                            palette: palette,
                            accent: _accent,
                            label: 'ad.sponsored'.tr,
                          ),
                          const Spacer(),
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: palette.surfaceElevated,
                              shape: BoxShape.circle,
                              border: Border.all(color: palette.border),
                            ),
                            child: Icon(
                              Icons.arrow_outward_rounded,
                              size: 14,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ad image when present (falls back to the cyan
                          // insights icon on a missing / broken URL), so a bad
                          // image link never blanks the card.
                          _LeadingVisual(
                            imageUrl: _imageUrl,
                            accent: _accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _headline(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: -0.3,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _subtitle(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          // Solid cyan-gradient CTA — strong contrast in both modes
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  SocialTokens.cyan,
                                  SocialTokens.cyanSoft,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'ad.learnMore'.tr,
                                  style: const TextStyle(
                                    color: Color(0xFF0A1628),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const DirectionalIcon(
                                  Icons.arrow_forward_rounded,
                                  color: Color(0xFF0A1628),
                                  size: 13,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Trust badge — neutral chip, distinct from the CTA
                          _trustBadge(
                            palette,
                            icon: Icons.shield_outlined,
                            label: 'ad.trusted'.tr,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trustBadge(
    SocialPalette palette, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.subtleDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: palette.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: palette.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Leading 44×44 visual — the ad's image (rounded, cover) when a usable URL
/// is supplied, else the cyan-gradient insights icon. Image errors fall back
/// to the icon so a broken link never leaves a blank box.
class _LeadingVisual extends StatelessWidget {
  final String imageUrl;
  final Color accent;
  const _LeadingVisual({required this.imageUrl, required this.accent});

  Widget _iconTile() {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.40),
            blurRadius: 14,
            spreadRadius: -2,
          ),
        ],
      ),
      child: const Icon(
        Icons.insights_rounded,
        color: Color(0xFF0A1628),
        size: 22,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final looksLikeImage = imageUrl.startsWith('http');
    if (!looksLikeImage) return _iconTile();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AppNetworkImage(
        imageUrl,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        // Broken / non-image URL → show the branded icon instead of an error box.
        errorWidget: _iconTile(),
      ),
    );
  }
}

/// SPONSORED pill — outlined cyan capsule with sparkle icon.
class _SponsoredPill extends StatelessWidget {
  final SocialPalette palette;
  final Color accent;
  final String label;
  const _SponsoredPill({
    required this.palette,
    required this.accent,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: palette.isDark ? 0.20 : 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accent.withValues(alpha: palette.isDark ? 0.55 : 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 11, color: accent),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 9.5,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
