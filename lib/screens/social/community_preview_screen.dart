import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../config/api_config.dart';
import '../../services/community_service.dart';
import '../../services/community_subscription_service.dart';
import '../../widgets/common/app_network_image.dart';
import '../../widgets/social/community_payment_sheet.dart';
import '../../widgets/social/community_pricing_card.dart';
import 'social_tokens.dart';

/// Pre-join "About this community" screen (step-23).
///
/// Tapping a community in Discover or anywhere a non-member encounters
/// it routes here instead of jumping into the chat-style detail. The
/// screen renders:
///
///   * Cover banner + name + region + category + tags
///   * Description + rules
///   * Member count + active now
///   * Experts strip (your "show all experts" requirement)
///   * Sample public posts (up to 3, when available)
///   * Pricing card (paid) OR Join free button (free)
///   * Pending payment banner when the user has a pending
///     subscription for this community
///
/// All sourced from a single `/communities/:id/preview` round-trip
/// plus the user's own /me/community-subscriptions to detect a
/// pending row.
class CommunityPreviewScreen extends StatefulWidget {
  final String communityId;

  const CommunityPreviewScreen({super.key, required this.communityId});

  @override
  State<CommunityPreviewScreen> createState() =>
      _CommunityPreviewScreenState();
}

class _CommunityPreviewScreenState extends State<CommunityPreviewScreen> {
  CommunityMeta? _community;
  List<Map<String, dynamic>> _experts = const [];
  List<Map<String, dynamic>> _samplePosts = const [];
  CommunitySubscriptionRow? _pendingSub;
  CommunitySubscriptionRow? _activeSub;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      CommunityService.preview(widget.communityId),
      CommunitySubscriptionService.mySubs(),
    ]);
    if (!mounted) return;
    final preview = results[0] as ({Map<String, dynamic>? data, String? error});
    final mine = results[1]
        as ({List<CommunitySubscriptionRow>? rows, String? error});
    if (preview.error != null) {
      setState(() {
        _loading = false;
        _error = preview.error;
      });
      return;
    }
    final data = preview.data!;
    final c = data['community'] as Map<String, dynamic>;
    setState(() {
      _community = CommunityMeta.fromJson(c);
      _experts = ((data['experts'] as List<dynamic>?) ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      _samplePosts = ((data['samplePosts'] as List<dynamic>?) ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      _pendingSub = (mine.rows ?? const [])
          .where((s) => s.communityId == widget.communityId && s.isPending)
          .cast<CommunitySubscriptionRow?>()
          .firstWhere(
            (s) => s != null,
            orElse: () => null,
          );
      _activeSub = (mine.rows ?? const [])
          .where((s) => s.communityId == widget.communityId && s.isActive)
          .cast<CommunitySubscriptionRow?>()
          .firstWhere(
            (s) => s != null,
            orElse: () => null,
          );
      _loading = false;
    });
  }

  String _absoluteCover(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    return '$base$url';
  }

  Future<void> _joinFree() async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    final res = await CommunityService.join(widget.communityId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _snack(res.error ?? 'communityPreview.couldNotJoin'.tr);
      return;
    }
    HapticFeedback.lightImpact();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _subscribe(String plan) async {
    if (_community == null) return;
    final priceCents = plan == 'monthly'
        ? _community!.joinPriceMonthlyCents
        : _community!.joinPriceYearlyCents;
    final result = await CommunityPaymentSheet.show(
      context,
      communityId: _community!.id,
      communityName: _community!.name,
      plan: plan,
      priceCents: priceCents,
      currency: _community!.priceCurrency,
    );
    if (result == null || !mounted) return;
    setState(() => _pendingSub = result);
    _snack('communityPreview.paymentSubmitted'.tr);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: _body(palette),
    );
  }

  Widget _body(SocialPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _community == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: SocialTokens.down, size: 56),
              const SizedBox(height: 12),
              Text(
                _error ?? 'communityPreview.couldNotLoad'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _bootstrap,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('common.retry'.tr),
              ),
            ],
          ),
        ),
      );
    }
    final c = _community!;
    final accent = SocialTokens.regionColor(c.regionCode);
    final coverAbs = _absoluteCover(c.coverUrl);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: palette.background,
          foregroundColor: palette.textPrimary,
          expandedHeight: coverAbs.isEmpty ? 60 : 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: coverAbs.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.4),
                          accent.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  )
                : AppNetworkImage(coverAbs, fit: BoxFit.cover),
            collapseMode: CollapseMode.parallax,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heroBlock(palette, c, accent),
                const SizedBox(height: 18),
                if (_pendingSub != null)
                  _pendingBanner(palette),
                if (_pendingSub != null) const SizedBox(height: 14),
                _statsStrip(palette, c, accent),
                const SizedBox(height: 18),
                if (c.description.isNotEmpty) ...[
                  _sectionLabel(palette, 'communityPreview.about'.tr),
                  const SizedBox(height: 6),
                  Text(
                    c.description,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (_experts.isNotEmpty) ...[
                  _sectionLabel(palette, 'communityPreview.experts'.tr),
                  const SizedBox(height: 8),
                  _expertsStrip(palette, accent),
                  const SizedBox(height: 18),
                ],
                if (_samplePosts.isNotEmpty) ...[
                  _sectionLabel(palette, 'communityPreview.recentPosts'.tr),
                  const SizedBox(height: 8),
                  for (final p in _samplePosts)
                    _samplePostTile(palette, p),
                  const SizedBox(height: 18),
                ],
                if (c.rules.isNotEmpty) ...[
                  _sectionLabel(palette, 'communityPreview.rules'.tr),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      c.rules,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                _ctaBlock(palette, c),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroBlock(SocialPalette palette, CommunityMeta c, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.name,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
            if (!c.isPublic)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SocialTokens.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 12, color: SocialTokens.gold),
                    const SizedBox(width: 4),
                    Text('communityPreview.private'.tr,
                        style: const TextStyle(
                          color: SocialTokens.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        )),
                  ],
                ),
              ),
          ],
        ),
        if (c.tagline.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            c.tagline,
            style: TextStyle(color: palette.textMuted, fontSize: 13.5),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (c.regionCode.isNotEmpty)
              _tinyChip(c.regionCode, accent),
            if (c.category.isNotEmpty)
              _tinyChip(_titleCase(c.category), accent),
            if (c.isPaid)
              _tinyChip('communityPreview.paid'.tr, SocialTokens.gold),
          ],
        ),
      ],
    );
  }

  Widget _tinyChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 10.5,
          ),
        ),
      );

  Widget _statsStrip(SocialPalette palette, CommunityMeta c, Color accent) {
    return Row(
      children: [
        _stat(palette, Icons.people_alt_rounded,
            '${c.memberCount}', 'communityPreview.members'.tr),
        const SizedBox(width: 12),
        _stat(palette, Icons.bolt_rounded,
            '${c.activeNow}', 'communityPreview.active'.tr),
        const SizedBox(width: 12),
        _stat(palette, Icons.workspace_premium_rounded,
            '${_experts.length}', 'communityPreview.expertsStat'.tr),
      ],
    );
  }

  Widget _stat(SocialPalette palette, IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: palette.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(SocialPalette palette, String text) => Text(
        text,
        style: TextStyle(
          color: palette.textMuted,
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
          letterSpacing: 0.5,
        ),
      );

  Widget _expertsStrip(SocialPalette palette, Color accent) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _experts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final e = _experts[i];
          final name = (e['name'] as String?) ?? 'communityPreview.defaultExpertName'.tr;
          final isOwner = (e['isOwner'] as bool?) ?? false;
          final subs = (e['subscriberCount'] as num?)?.toInt() ?? 0;
          return Container(
            width: 130,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOwner
                    ? SocialTokens.gold.withValues(alpha: 0.6)
                    : palette.border,
                width: isOwner ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          accent.withValues(alpha: 0.18),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (isOwner) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.star_rounded,
                          size: 14, color: SocialTokens.gold),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subs == 1
                      ? 'communityPreview.oneSubscriber'.tr
                      : 'communityPreview.subsCount'.trParams({'count': '$subs'}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _samplePostTile(SocialPalette palette, Map<String, dynamic> p) {
    final title = (p['title'] as String?) ?? '';
    final body = (p['body'] as String?) ?? '';
    final author = (p['authorName'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          if (body.isNotEmpty) ...[
            if (title.isNotEmpty) const SizedBox(height: 4),
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (author.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '— $author',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pendingBanner(SocialPalette palette) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SocialTokens.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SocialTokens.gold.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded,
              color: SocialTokens.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'communityPreview.pendingBanner'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctaBlock(SocialPalette palette, CommunityMeta c) {
    if (_activeSub != null) {
      return _statusBanner(palette,
          'communityPreview.youreMember'.tr, SocialTokens.up);
    }
    if (_pendingSub != null) {
      // Banner already shown above; CTA collapses into a "Subscription
      // pending" status pill.
      return _statusBanner(palette,
          'communityPreview.subscriptionPending'.tr,
          SocialTokens.gold);
    }
    if (c.isPaid) {
      return CommunityPricingCard(
        currency: c.priceCurrency,
        monthlyCents: c.joinPriceMonthlyCents,
        yearlyCents: c.joinPriceYearlyCents,
        onSubscribe: _subscribe,
        busy: _busy,
      );
    }
    // Free community CTA.
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: SocialTokens.cyan,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _busy ? null : _joinFree,
        icon: const Icon(Icons.person_add_rounded),
        label: Text(
          _busy
              ? 'communityPreview.joining'.tr
              : 'communityPreview.joinCommunity'.tr,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _statusBanner(SocialPalette palette, String label, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
