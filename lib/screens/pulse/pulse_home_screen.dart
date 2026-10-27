import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../controllers/pulse_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/pulse_item.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/platform_adaptive/platform_refresh_indicator.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/pulse/pulse_cards.dart';
import '../../widgets/pulse/pulse_states.dart';
import '../../widgets/pulse/pulse_tokens.dart';
import '../social/social_tokens.dart';
import 'pulse_archive_screen.dart';
import 'pulse_item_screen.dart';
import 'pulse_notification_prefs_screen.dart';

/// =============================================================================
/// PulseHomeScreen — UNMU Pulse (نبض أنمو), the first tab.
///
/// A daily, hand-curated briefing: four items (top global event, top Gulf
/// event, Sharia change, opportunity to follow) laid out as a bento. Each card
/// says whether it is *confirmed information* or *analysis*, when it was
/// published, and opens the full item with its sources and evidence.
///
/// States (a screen is never blank):
///   loading  shimmering skeleton shaped like the bento
///   content  the four cards (a slot with nothing yet shows a quiet placeholder)
///   empty    nothing published today → explanation + "Open archive"
///   error    offline / server wording + Retry
/// A failed pull-to-refresh keeps the old content and shows a slim notice.
///
/// Tip (spec §5.9): a one-time, dismissible card explains Pulse on first visit.
/// =============================================================================
class PulseHomeScreen extends StatefulWidget {
  const PulseHomeScreen({super.key});

  @override
  State<PulseHomeScreen> createState() => _PulseHomeScreenState();
}

class _PulseHomeScreenState extends State<PulseHomeScreen> {
  static const _tipSeenKey = 'pulse_tip_seen';
  static const double _maxContentWidth = 640;

  late final PulseController _c = Get.find<PulseController>();
  bool _showTip = false;
  bool _visible = false;
  Worker? _dayWorker;

  @override
  void initState() {
    super.initState();
    _loadTipFlag();
    // When content arrives while the tab is on screen, count the view.
    _dayWorker = ever<PulseDay?>(_c.day, (_) => _maybeTrackView());
  }

  @override
  void dispose() {
    _dayWorker?.dispose();
    super.dispose();
  }

  Future<void> _loadTipFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _showTip = !(prefs.getBool(_tipSeenKey) ?? false));
    } catch (_) {
      // Storage unavailable: skip the tip rather than nag on every visit.
    }
  }

  Future<void> _dismissTip() async {
    HapticUtils.lightTap();
    setState(() => _showTip = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_tipSeenKey, true);
    } catch (_) {}
  }

  void _maybeTrackView() {
    final day = _c.day.value;
    if (_visible && day != null && !day.isEmpty) _c.trackDayViewed(day.date);
  }

  void _open(PulseItem item) {
    HapticUtils.lightTap();
    Get.to(() => PulseItemScreen(itemId: item.id, preview: item));
  }

  void _openArchive() {
    HapticUtils.lightTap();
    Get.to(() => const PulseArchiveScreen());
  }

  void _openPrefs() {
    HapticUtils.lightTap();
    Get.to(() => const PulseNotificationPrefsScreen());
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return VisibilityDetector(
      key: const Key('pulse-home-visibility'),
      onVisibilityChanged: (info) {
        _visible = info.visibleFraction > 0.5;
        _maybeTrackView();
      },
      child: PulseAuroraBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Text(
              'pulse.title'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'pulse.notificationsTooltip'.tr,
                icon: Icon(
                  PulseIcons.settings(context),
                  color: palette.textPrimary,
                ),
                onPressed: _openPrefs,
              ),
              const ProfileAvatarButton(),
              const SizedBox(width: PulseSpace.sm),
            ],
          ),
          body: PlatformRefreshIndicator(
            onRefresh: _c.refreshToday,
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _maxContentWidth,
                    ),
                    child: Padding(
                      // Bottom space clears the floating nav pill.
                      padding: const EdgeInsets.fromLTRB(
                        PulseSpace.lg,
                        PulseSpace.sm,
                        PulseSpace.lg,
                        120,
                      ),
                      child: Obx(_buildBody),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Body state machine ──────────────────────────────────────────────

  Widget _buildBody() {
    final day = _c.day.value;
    final failure = _c.failure.value;

    if (day == null && failure == null) {
      // First load in flight.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(title: 'pulse.today'.tr, subtitle: ''),
          const SizedBox(height: PulseSpace.md),
          const PulseCardsSkeleton(),
        ],
      );
    }
    if (day == null) {
      return Padding(
        padding: const EdgeInsets.only(top: PulseSpace.xxl),
        child: PulseStatusView.failure(
          context,
          failure: failure!,
          onRetry: () => _c.loadToday(),
        ),
      );
    }
    if (day.isEmpty) {
      return Column(
        children: [
          _Header(title: 'pulse.today'.tr, subtitle: _dateLine(day)),
          const SizedBox(height: PulseSpace.lg),
          PulseStatusView(
            icon: PulseIcons.inbox(context),
            title: 'pulse.empty.title'.tr,
            body: 'pulse.empty.body'.tr,
            actionLabel: 'pulse.openArchive'.tr,
            onAction: _openArchive,
          ),
        ],
      );
    }
    return _content(day);
  }

  String _dateLine(PulseDay day) {
    final parsed = DateTime.tryParse(day.date);
    final date = parsed == null ? '' : LocaleFormat.date(parsed);
    final updated = day.updatedAt;
    if (updated == null) return date;
    final time = 'pulse.updatedAt'.trParams({'time': pulseTime(updated)});
    return date.isEmpty ? time : '$date · $time';
  }

  Widget _content(PulseDay day) {
    Widget card(PulseSlot slot, PulseCardSize size) {
      final item = day.bySlot(slot);
      return item == null
          ? PulseEmptySlotCard(slot: slot)
          : PulseItemCard(item: item, size: size, onTap: () => _open(item));
    }

    const gap = SizedBox(height: PulseSpace.sm + 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(title: 'pulse.today'.tr, subtitle: _dateLine(day)),
        if (_c.refreshFailed) ...[
          const SizedBox(height: PulseSpace.md),
          _RefreshNotice(onRetry: () => _c.refreshToday()),
        ],
        if (_showTip) ...[
          const SizedBox(height: PulseSpace.md),
          _TipCard(onDismiss: _dismissTip),
        ],
        const SizedBox(height: PulseSpace.md),
        card(PulseSlot.global, PulseCardSize.hero),
        gap,
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: card(PulseSlot.gulf, PulseCardSize.half)),
              const SizedBox(width: PulseSpace.sm + 2),
              Expanded(child: card(PulseSlot.sharia, PulseCardSize.half)),
            ],
          ),
        ),
        gap,
        card(PulseSlot.opportunity, PulseCardSize.wide),
        const SizedBox(height: PulseSpace.lg),
        Center(
          child: TextButton(
            onPressed: _openArchive,
            child: Text(
              'pulse.browseArchive'.tr,
              style: TextStyle(
                color: SocialTheme.of(context).isDark
                    ? PulseColors.tealBright
                    : PulseColors.tealInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Header({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: p.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(color: p.textMuted, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

/// Shown when a refresh failed but older content is still displayed.
class _RefreshNotice extends StatelessWidget {
  final VoidCallback onRetry;

  const _RefreshNotice({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5A623).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(PulseIcons.wifiOff(context), size: 16, color: p.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'pulse.refreshFailed'.tr,
                style: TextStyle(color: p.textSecondary, fontSize: 12.5),
              ),
            ),
            TextButton(onPressed: onRetry, child: Text('pulse.error.retry'.tr)),
          ],
        ),
      ),
    );
  }
}

/// The one-time "what is Pulse" tip.
class _TipCard extends StatelessWidget {
  final VoidCallback onDismiss;

  const _TipCard({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return PulseSurfaceBox(
      surface: PulseSurface.glass,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PulseIcons.slot(context, PulseSlot.opportunity),
                size: 18,
                color: p.isDark ? PulseColors.tealBright : PulseColors.tealInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'pulse.tip.title'.tr,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Text(
              'pulse.tip.body'.tr,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onDismiss,
              child: Text(
                'pulse.tip.dismiss'.tr,
                style: TextStyle(
                  color: p.isDark
                      ? PulseColors.tealBright
                      : PulseColors.tealInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
