import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/pulse_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/pulse_item.dart';
import '../../services/pulse_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/pulse/pulse_cards.dart';
import '../../widgets/pulse/pulse_states.dart';
import '../../widgets/pulse/pulse_tokens.dart';
import '../../widgets/skeleton_loaders.dart';
import '../social/social_tokens.dart';
import '../stock_detail/stock_detail_screen.dart';

/// =============================================================================
/// PulseItemScreen — one Pulse item in full.
///
/// Shows the type (confirmed information vs analysis — always visibly
/// different), the marker (new / updated / corrected), the full text, the
/// source with its link, the evidence, when it was verified and published, the
/// linked stock with how it relates to the user, and Save / Share.
///
/// [preview] (the card the user tapped) is shown instantly while the full item
/// loads, so opening a card never starts from a blank screen. If the item has
/// been withdrawn the screen says so calmly and offers a way back.
///
/// Analytics: opening is reported once; reaching the end of the text is
/// reported once as "read to the end".
/// =============================================================================
class PulseItemScreen extends StatefulWidget {
  final int itemId;
  final PulseItem? preview;

  const PulseItemScreen({super.key, required this.itemId, this.preview});

  @override
  State<PulseItemScreen> createState() => _PulseItemScreenState();
}

class _PulseItemScreenState extends State<PulseItemScreen> {
  late final PulseController _c = Get.find<PulseController>();
  final ScrollController _scroll = ScrollController();

  PulseItem? _item;
  PulseFailure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _item = widget.preview;
    _scroll.addListener(_checkReadToEnd);
    _c.track(PulseEvent.openItem, itemId: widget.itemId, once: true);
    _load();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_checkReadToEnd)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final res = await _c.loadItem(widget.itemId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _item = res.data;
      } else {
        _failure = res.failure;
      }
    });
    // A short item that fits on screen counts as read once its text is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkReadToEnd());
  }

  /// Reports "read to the end" the first time the bottom is reached.
  void _checkReadToEnd() {
    if (_item == null || _loading || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) {
      _c.track(PulseEvent.readComplete, itemId: widget.itemId, once: true);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleSave(PulseItem item) async {
    HapticUtils.lightTap();
    final before = _c.isSaved(item.id);
    final after = await _c.toggleSave(item);
    if (after == before) {
      HapticUtils.error();
      _snack('pulse.detail.saveFailed'.tr);
    }
  }

  void _share(PulseItem item) {
    HapticUtils.lightTap();
    final arabic = pulseIsArabic();
    final text = 'pulse.share.text'.trParams({
      'title': item.title(arabic),
      'summary': item.summary(arabic),
    });
    _c.track(PulseEvent.share, itemId: item.id);
    Share.share(text);
  }

  Future<void> _openSource(PulseItem item) async {
    final uri = Uri.tryParse(item.sourceUrl);
    // Only web links are ever opened (the server validates too).
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      _snack('pulse.detail.linkFailed'.tr);
      return;
    }
    _c.track(PulseEvent.openSource, itemId: item.id);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) _snack('pulse.detail.linkFailed'.tr);
  }

  void _openStock(PulseItem item) {
    final stock = item.stock;
    if (stock == null) return;
    HapticUtils.lightTap();
    _c.track(PulseEvent.openStock, itemId: item.id);
    Get.to(
      () => StockDetailScreen(ticker: stock.ticker, exchange: stock.exchange),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final item = _item;

    return PulseAuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: p.textPrimary),
          actions: item == null
              ? null
              : [
                  Obx(() {
                    final saved = _c.isSaved(item.id);
                    return IconButton(
                      tooltip:
                          (saved ? 'pulse.detail.saved' : 'pulse.detail.save')
                              .tr,
                      icon: Icon(
                        PulseIcons.bookmark(context, filled: saved),
                        color: saved
                            ? (p.isDark
                                  ? PulseColors.tealBright
                                  : PulseColors.tealDeep)
                            : p.textPrimary,
                      ),
                      onPressed: () => _toggleSave(item),
                    );
                  }),
                  IconButton(
                    tooltip: 'pulse.detail.share'.tr,
                    icon: Icon(Icons.adaptive.share, color: p.textPrimary),
                    onPressed: () => _share(item),
                  ),
                  const SizedBox(width: PulseSpace.xs),
                ],
        ),
        body: _body(item),
      ),
    );
  }

  Widget _body(PulseItem? item) {
    if (item == null) {
      if (_loading) return const _DetailSkeleton();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(PulseSpace.lg),
          child: _failure == PulseFailure.notFound
              ? PulseStatusView(
                  icon: PulseIcons.inbox(context),
                  title: 'pulse.detail.notFoundTitle'.tr,
                  body: 'pulse.detail.notFoundBody'.tr,
                  actionLabel: 'pulse.openArchive'.tr,
                  onAction: () => Get.back(),
                )
              : PulseStatusView.failure(
                  context,
                  failure: _failure ?? PulseFailure.server,
                  onRetry: _load,
                ),
        ),
      );
    }
    return _Content(
      item: item,
      scroll: _scroll,
      loadingDetails: _loading,
      onOpenSource: () => _openSource(item),
      onOpenStock: () => _openStock(item),
    );
  }
}

/// The scrollable body of a loaded item.
class _Content extends StatelessWidget {
  final PulseItem item;
  final ScrollController scroll;
  final bool loadingDetails;
  final VoidCallback onOpenSource;
  final VoidCallback onOpenStock;

  const _Content({
    required this.item,
    required this.scroll,
    required this.loadingDetails,
    required this.onOpenSource,
    required this.onOpenStock,
  });

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final arabic = pulseIsArabic();
    final details = item.details(arabic);
    final changed = item.lastChangedAt;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
            PulseSpace.lg,
            0,
            PulseSpace.lg,
            PulseSpace.xxl,
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _SlotPill(slot: item.slot),
                PulseTypeBadge(isAnalysis: item.isAnalysis),
                PulseMarkerBadge(item: item),
              ],
            ),
            const SizedBox(height: PulseSpace.md),
            Text(
              item.title(arabic),
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 25,
                height: arabic ? 1.5 : 1.22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: PulseSpace.md),
            Text(
              item.summary(arabic),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 16,
                height: 1.55,
              ),
            ),
            if ((item.isCorrected || item.isUpdated) && changed != null) ...[
              const SizedBox(height: PulseSpace.md),
              _Note(
                icon: PulseIcons.alert(context),
                tint: const Color(0xFFF5A623),
                text:
                    (item.isCorrected
                            ? 'pulse.detail.correctedNote'
                            : 'pulse.detail.updatedNote')
                        .trParams({'time': LocaleFormat.dateTime(changed)}),
              ),
            ],
            if (item.isAnalysis) ...[
              const SizedBox(height: PulseSpace.md),
              _Note(
                icon: PulseIcons.chart(context),
                tint: const Color(0xFF8A5BC7),
                title: 'pulse.detail.analysisTitle'.tr,
                text: 'pulse.detail.analysisBody'.tr,
              ),
            ],
            if (loadingDetails && details.isEmpty) ...[
              const SizedBox(height: PulseSpace.lg),
              const _DetailLines(),
            ],
            if (details.isNotEmpty) ...[
              const SizedBox(height: PulseSpace.lg),
              Text(
                details,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 15.5,
                  height: 1.65,
                ),
              ),
            ],
            const SizedBox(height: PulseSpace.lg),
            _SourcesCard(item: item, onOpenSource: onOpenSource),
            if (item.stock != null) ...[
              const SizedBox(height: PulseSpace.md),
              _StockCard(item: item, onOpen: onOpenStock),
            ],
          ],
        ),
      ),
    );
  }
}

class _SlotPill extends StatelessWidget {
  final PulseSlot slot;

  const _SlotPill({required this.slot});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final color = p.isDark ? PulseColors.tealBright : PulseColors.tealInk;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: PulseColors.teal.withValues(alpha: p.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PulseIcons.slot(context, slot), size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            'pulse.slot.${slot.name}'.tr,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tinted callout (correction notice, analysis disclaimer).
class _Note extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String? title;
  final String text;

  const _Note({
    required this.icon,
    required this.tint,
    required this.text,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: p.isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      title!,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                Text(
                  text,
                  style: TextStyle(
                    color: p.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Source, evidence, verification and publish times.
class _SourcesCard extends StatelessWidget {
  final PulseItem item;
  final VoidCallback onOpenSource;

  const _SourcesCard({required this.item, required this.onOpenSource});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final arabic = pulseIsArabic();
    final evidence = item.evidence(arabic);
    final hasLink = item.sourceUrl.isNotEmpty;

    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(color: p.textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: p.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    return PulseSurfaceBox(
      surface: PulseSurface.glass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PulseIcons.verified(context), size: 16, color: p.textMuted),
              const SizedBox(width: 7),
              Text(
                'pulse.detail.sources'.tr.toUpperCase(),
                style: TextStyle(
                  color: p.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: arabic ? 0 : 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: PulseSpace.md),
          if (item.sourceName.isNotEmpty)
            row('pulse.detail.source'.tr, item.sourceName),
          if (hasLink) row('pulse.detail.link'.tr, item.sourceUrl),
          if (evidence.isNotEmpty) row('pulse.detail.evidence'.tr, evidence),
          if (item.verifiedAt != null)
            row(
              'pulse.detail.verified'.tr,
              LocaleFormat.dateTime(item.verifiedAt!),
            ),
          if (item.publishedAt != null)
            row(
              'pulse.detail.published'.tr,
              LocaleFormat.dateTime(item.publishedAt!),
            ),
          if (hasLink) ...[
            const SizedBox(height: PulseSpace.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onOpenSource,
                icon: Icon(PulseIcons.link(context), size: 18),
                label: Text('pulse.detail.openSource'.tr),
                style: TextButton.styleFrom(
                  foregroundColor: p.isDark
                      ? PulseColors.tealBright
                      : PulseColors.tealInk,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The linked stock, how it relates to the user, and the way to open it.
class _StockCard extends StatelessWidget {
  final PulseItem item;
  final VoidCallback onOpen;

  const _StockCard({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final stock = item.stock!;
    return PulseSurfaceBox(
      surface: PulseSurface.glass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stock.name.isEmpty ? stock.ticker : stock.name,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stock.ticker} · ${stock.exchange}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: p.textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (item.relation != null) PulseStockChip(item: item),
            ],
          ),
          if (item.relation == null) ...[
            const SizedBox(height: 6),
            Text(
              'pulse.relation.none'.tr,
              style: TextStyle(color: p.textMuted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: PulseSpace.md),
          PulsePrimaryButton(
            label: 'pulse.detail.openStock'.tr,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

// ── Loading placeholders ───────────────────────────────────────────────

class _DetailLines extends StatelessWidget {
  const _DetailLines();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 14),
          SizedBox(height: 8),
          SkeletonBox(height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: 180, height: 14),
        ],
      ),
    ),
  );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(PulseSpace.lg),
    child: ExcludeSemantics(
      child: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 150, height: 22, radius: 11),
            SizedBox(height: 16),
            SkeletonBox(height: 26),
            SizedBox(height: 8),
            SkeletonBox(width: 260, height: 26),
            SizedBox(height: 20),
            SkeletonBox(height: 16),
            SizedBox(height: 8),
            SkeletonBox(height: 16),
            SizedBox(height: 8),
            SkeletonBox(width: 200, height: 16),
          ],
        ),
      ),
    ),
  );
}
