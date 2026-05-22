import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/social/mock_social_data.dart';
import '../../screens/social/social_tokens.dart';
import 'community_avatar.dart';

/// Editorial bento community card.
///
///   ┌────────────────────────────────────────────────────┐
///   │ ╔═════════╗  US Halal Tech                         │
///   │ ║   US    ║  Shariah-friendly tech megacaps        │
///   │ ╚═════════╝                                        │
///   │             ┌────────────┬───────────┬──────────┐  │
///   │             │  26.1K     │  588      │   ✓      │  │
///   │             │  members   │  active   │  Joined  │  │
///   │             └────────────┴───────────┴──────────┘  │
///   │   AAPL ▲0.84%   MSFT ▲1.10%   NVDA ▲2.43%   ...    │
///   └────────────────────────────────────────────────────┘
///
/// Adapts to dark/light via [SocialTheme.of(context)].
class CommunityCard extends StatefulWidget {
  final Community community;
  final bool isArabic;
  final VoidCallback? onTap;
  /// Step-23 follow-up — viewer's real membership state. Drives the
  /// "✓ Joined" badge in the corner. When null (legacy callers), the
  /// badge falls back to mock state — but every modern caller now
  /// passes the real value from `/me/communities`. Default false so
  /// non-member of paid community doesn't falsely advertise Joined.
  final bool? isJoined;

  /// True when the viewer has a paid subscription for this community
  /// that's currently `status='pending'` (submitted, admin reviewing
  /// payment). Drives the gold "Pending" pill — wins over both Join
  /// and Joined visuals. Null/false → fall back to the join/joined
  /// flow as before.
  final bool? isPending;

  const CommunityCard({
    super.key,
    required this.community,
    required this.isArabic,
    this.onTap,
    this.isJoined,
    this.isPending,
  });

  @override
  State<CommunityCard> createState() => _CommunityCardState();
}

class _CommunityCardState extends State<CommunityCard> {
  bool _pressed = false;
  bool get _joined => widget.isJoined ?? false;
  bool get _pending => widget.isPending ?? false;

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final c = widget.community;
    final accent = SocialTokens.regionColor(c.regionCode);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 130),
        scale: _pressed ? 0.985 : 1.0,
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: region tile + name + join button
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Row(
                    children: [
                      // Was: _RegionTile(code: c.regionCode, accent: accent)
                      // — replaced with the new shared CommunityAvatar so
                      // uploaded community logos show up on the Discover
                      // bento cards too. Falls back to a region-tinted
                      // initials tile when avatarUrl is empty, preserving
                      // the original visual language.
                      CommunityAvatar(
                        size: 50,
                        name: c.name,
                        regionCode: c.regionCode,
                        avatarUrl: c.avatarUrl,
                        borderRadius: 13,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              c.tagline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildJoinButton(accent),
                    ],
                  ),
                ),
                // Stats row — was 3 columns (members · active now · bullish).
                // "Active now" and "Bullish/Bearish" were both synthesized
                // from mock ticker data and have no real backend source,
                // so we render just the member count now. Member count
                // IS real (SELECT COUNT(*) FROM community_members in the
                // backend's communityCols).
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.subtleDivider),
                  ),
                  child: _statCell(
                    palette,
                    label: 'communityCard.members'.tr,
                    value: _compact(c.memberCount),
                    color: palette.textPrimary,
                  ),
                ),
                // (Compact ticker strip removed — `c.liveTickers` is
                // mock data. We'll reintroduce when real per-community
                // ticker tracking exists.)
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCell(
    SocialPalette palette, {
    required String label,
    required String value,
    required Color color,
    Color? dotColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinButton(Color accent) {
    // Three-state chip — pending wins over joined wins over join.
    //   * pending → gold pill, hourglass, "Pending" (still taps through
    //     to the preview screen so the user can see status detail)
    //   * joined  → outlined region-accent pill, checkmark, "Joined"
    //   * join    → solid region-accent pill, plus, "Join"
    //
    // The corner chip is a TAP-THROUGH that opens the community in
    // every state (same as tapping the card body). The actual
    // subscribe / cancel actions live on the preview / detail screen
    // where the price gate + receipt flow runs.
    if (_pending) {
      const gold = SocialTokens.gold;
      final label = 'communityCard.pending'.tr;
      return ElevatedButton(
        onPressed: widget.onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: gold.withValues(alpha: 0.16),
          foregroundColor: gold,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: gold, width: 1.4),
          ),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top_rounded, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final label =
        _joined ? 'communityCard.joined'.tr : 'communityCard.join'.tr;
    return ElevatedButton(
      onPressed: widget.onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _joined ? Colors.transparent : accent,
        foregroundColor: _joined ? accent : Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: accent, width: 1.4),
        ),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _joined ? Icons.check_rounded : Icons.add_rounded,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _compact(int n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

/// Region tile — bold solid block with the region code stamped on it.
///
/// Retired with the CommunityAvatar refactor (May 2026). Kept here in
/// case we want to re-introduce a region-only tile elsewhere; safe to
/// delete in a future cleanup.
// ignore: unused_element
class _RegionTile extends StatelessWidget {
  final String code;
  final Color accent;
  const _RegionTile({required this.code, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha: 0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        code,
        style: const TextStyle(
          color: Color(0xFF0A1628),
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// _CompactTickerStrip removed — was rendering `MockSocialData` ticker
// quotes (AAPL +0.84% etc.) per community. No real backend source for
// per-community live tickers yet; restore here once we have one.
