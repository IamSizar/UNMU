import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/subscription_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/expert_subscription.dart';
import '../../services/community_subscription_service.dart';
import 'subscribe_modal.dart';

/// User-facing list of every subscription request the user has ever made.
/// Reachable from Profile.
class MySubscriptionsScreen extends StatefulWidget {
  const MySubscriptionsScreen({super.key});

  @override
  State<MySubscriptionsScreen> createState() => _MySubscriptionsScreenState();
}

class _MySubscriptionsScreenState extends State<MySubscriptionsScreen> {
  late final SubscriptionController controller;

  // Sprint-C step 10 — paid community subscriptions live in a separate
  // backend table from expert subscriptions. We fetch + render them in
  // the same screen so the user has ONE place to see every paid
  // membership/subscription they've ever submitted.
  List<CommunitySubscriptionRow> _communitySubs = const [];
  bool _loadingCommunitySubs = true;

  @override
  void initState() {
    super.initState();
    controller = Get.find<SubscriptionController>();
    controller.refreshAll();
    _loadCommunitySubs();
  }

  Future<void> _loadCommunitySubs() async {
    final res = await CommunitySubscriptionService.mySubs();
    if (!mounted) return;
    setState(() {
      _communitySubs = res.rows ?? const [];
      _loadingCommunitySubs = false;
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      controller.refreshAll(),
      _loadCommunitySubs(),
    ]);
  }

  Future<void> _cancelCommunitySub(CommunitySubscriptionRow sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('mySubscriptions.commCancel.title'.tr),
        content: Text(
          sub.isPending
              ? 'mySubscriptions.commCancel.bodyPending'
                  .trParams({'name': sub.communityName})
              : 'mySubscriptions.commCancel.bodyActive'
                  .trParams({'name': sub.communityName}),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('mySubscriptions.cancel.keep'.tr)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text('mySubscriptions.cancel.confirm'.tr),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await CommunitySubscriptionService.cancel(sub.id);
    if (!mounted) return;
    if (res.ok) {
      _loadCommunitySubs();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mySubscriptions.commCancelledSnack'.tr)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'mySubscriptions.commCancelFailedSnack'.tr)),
      );
    }
  }

  Future<void> _renew(ExpertSubscription sub) async {
    // Re-open the SubscribeModal pre-pointed at the same expert. Backend
    // unique-active index blocks if the user still has an active sub —
    // but we only show the Renew button when status=expired (or close
    // to expiring) so the conflict can't happen in practice.
    final result = await SubscribeModal.show(
      context,
      expertId: sub.expertId,
      expertName: sub.expertName ?? sub.expertId,
    );
    if (result != null && mounted) {
      controller.refreshAll();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mySubscriptions.renewSubmittedSnack'.tr)),
      );
    }
  }

  Future<void> _confirmCancel(ExpertSubscription sub) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('mySubscriptions.cancel.title'.tr),
        content: Text(
          sub.status == SubStatus.pending
              ? 'mySubscriptions.cancel.bodyPending'.tr
              : 'mySubscriptions.cancel.bodyActive'.tr,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('mySubscriptions.cancel.keep'.tr)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text('mySubscriptions.cancel.confirm'.tr),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final result = await controller.cancel(sub.id, expertId: sub.expertId);
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mySubscriptions.cancelledSnack'.tr)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('mySubscriptions.title'.tr),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: Obx(() {
            final loading = controller.isLoadingAll || _loadingCommunitySubs;
            final subs = controller.all;
            final commSubs = _communitySubs;
            if (loading && subs.isEmpty && commSubs.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (subs.isEmpty && commSubs.isEmpty) {
              return _EmptyState();
            }
            // Group by status: active first (most useful), then
            // pending, then past (rejected / cancelled / expired
            // bucketed together). Within each group, newest first
            // — already sorted by the controller.
            final active = subs
                .where((s) => s.status == SubStatus.active)
                .toList();
            final pending = subs
                .where((s) => s.status == SubStatus.pending)
                .toList();
            final past = subs
                .where((s) =>
                    s.status == SubStatus.rejected ||
                    s.status == SubStatus.cancelled ||
                    s.status == SubStatus.expired)
                .toList();

            // Step B8 — flag any active sub expiring in <= 7 days so the
            // user sees a banner at the top, no need to scroll.
            final expiringSoon = active
                .where((s) =>
                    s.daysRemaining != null && s.daysRemaining! <= 7)
                .toList();

            // Sprint-C step 10 — split community subs into the same
            // active / pending / past buckets so they render alongside
            // the expert subs under headers that read "Community —
            // Active", "Community — Pending", etc.
            final commActive = commSubs.where((s) => s.isActive).toList();
            final commPending = commSubs.where((s) => s.isPending).toList();
            final commPast = commSubs
                .where((s) =>
                    s.status == 'rejected' ||
                    s.status == 'cancelled' ||
                    s.status == 'expired')
                .toList();

            final items = <Object>[];
            if (expiringSoon.isNotEmpty) {
              items.add(_ExpiringSoonBanner(subs: expiringSoon));
            }
            if (active.isNotEmpty) {
              items.add('mySubscriptions.section.expertsActive'.tr);
              items.addAll(active);
            }
            if (pending.isNotEmpty) {
              items.add('mySubscriptions.section.expertsPending'.tr);
              items.addAll(pending);
            }
            if (past.isNotEmpty) {
              items.add('mySubscriptions.section.expertsPast'.tr);
              items.addAll(past);
            }
            if (commActive.isNotEmpty) {
              items.add('mySubscriptions.section.communitiesActive'.tr);
              items.addAll(commActive);
            }
            if (commPending.isNotEmpty) {
              items.add('mySubscriptions.section.communitiesPending'.tr);
              items.addAll(commPending);
            }
            if (commPast.isNotEmpty) {
              items.add('mySubscriptions.section.communitiesPast'.tr);
              items.addAll(commPast);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = items[i];
                if (item is _ExpiringSoonBanner) return item;
                if (item is String) {
                  return Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 6, bottom: 2),
                    child: Text(
                      item.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                    ),
                  );
                }
                if (item is CommunitySubscriptionRow) {
                  return _CommunitySubTile(
                    sub: item,
                    onCancel: () => _cancelCommunitySub(item),
                  );
                }
                final sub = item as ExpertSubscription;
                return _SubTile(
                  sub: sub,
                  onCancel: () => _confirmCancel(sub),
                  onRenew: () => _renew(sub),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.subscriptions_outlined, size: 64, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          'mySubscriptions.empty.title'.tr,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'mySubscriptions.empty.body'.tr,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _SubTile extends StatelessWidget {
  final ExpertSubscription sub;
  final VoidCallback onCancel;
  final VoidCallback onRenew;
  const _SubTile({
    required this.sub,
    required this.onCancel,
    required this.onRenew,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = _statusSpec(sub.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cs.primary.withValues(alpha: 0.18),
                child: Text(
                  (sub.expertName ?? sub.expertId).characters.first.toUpperCase(),
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.expertName ?? sub.expertId,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      '${sub.plan.label} · ${sub.priceLabel} · ${sub.paymentMethod.label}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: spec.color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(spec.icon, size: 12, color: spec.color),
                    const SizedBox(width: 4),
                    Text(
                      spec.label.toUpperCase(),
                      style: TextStyle(
                        color: spec.color,
                        fontWeight: FontWeight.w900,
                        fontSize: 9.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (sub.status == SubStatus.active && sub.expiresAt != null) ...[
            const SizedBox(height: 8),
            // Two-line block: human-readable countdown on top, full
            // ISO-style date underneath. Without the explicit date
            // users couldn't tell whether "31 days" landed in
            // January or February.
            Text(
              'mySubscriptions.expiresInDays'.trParams({
                'count': '${sub.daysRemaining ?? 0}',
                'plural': (sub.daysRemaining ?? 0) == 1 ? '' : 's',
              }),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              LocaleFormat.date(sub.expiresAt!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
          if (sub.status == SubStatus.expired && sub.expiresAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'mySubscriptions.expiredOn'
                  .trParams({'date': LocaleFormat.date(sub.expiresAt!)}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
            ),
          ],
          if (sub.status == SubStatus.rejected && sub.rejectionReason != null) ...[
            const SizedBox(height: 8),
            Text(
              'mySubscriptions.reason'
                  .trParams({'reason': sub.rejectionReason ?? ''}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.error,
                  ),
            ),
          ],
          if (sub.status == SubStatus.pending || sub.status == SubStatus.active) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: Text('common.cancel'.tr),
              ),
            ),
            // Step 26 — the near-expiry Renew button was REMOVED.
            // It opened the SubscribeModal which tried to create a
            // new pending sub, but Sprint A's `ACTIVE_EXISTS` guard
            // (correctly) rejects that. The user would see a scary
            // 409. The right behavior: wait for the sub to expire,
            // then use the "Subscribe again" button on the expired
            // tile below. A proper `/subscriptions/:id/renew`
            // endpoint that extends `expires_at` in-place is the
            // future fix; until then, no near-expiry Renew button.
          ],
          if (sub.status == SubStatus.expired) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onRenew,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text('mySubscriptions.subscribeAgain'.tr),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _StatusSpec _statusSpec(SubStatus s) {
    switch (s) {
      case SubStatus.pending:
        return _StatusSpec(
          label: 'mySubscriptions.status.pending'.tr,
          icon: Icons.hourglass_top,
          color: Colors.amber,
        );
      case SubStatus.active:
        return _StatusSpec(
          label: 'mySubscriptions.status.active'.tr,
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF10B981),
        );
      case SubStatus.rejected:
        return _StatusSpec(
          label: 'mySubscriptions.status.rejected'.tr,
          icon: Icons.cancel_outlined,
          color: const Color(0xFFF43F5E),
        );
      case SubStatus.cancelled:
        return _StatusSpec(
          label: 'mySubscriptions.status.cancelled'.tr,
          icon: Icons.do_not_disturb_alt,
          color: const Color(0xFF94A3B8),
        );
      case SubStatus.expired:
        return _StatusSpec(
          label: 'mySubscriptions.status.expired'.tr,
          icon: Icons.history_toggle_off,
          color: const Color(0xFF94A3B8),
        );
    }
  }
}

class _StatusSpec {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusSpec({required this.label, required this.icon, required this.color});
}

/// Pinned banner that warns the user about active subs about to expire.
/// Renders at the very top of the list when at least one sub has 7 or
/// fewer days left — turns into a friendly "renew now" call-to-action.
class _ExpiringSoonBanner extends StatelessWidget {
  final List<ExpertSubscription> subs;
  const _ExpiringSoonBanner({required this.subs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = subs.length;
    final shortest = subs
        .map((s) => s.daysRemaining ?? 0)
        .reduce((a, b) => a < b ? a : b);
    final names = subs.map((s) => s.expertName ?? s.expertId).take(2).toList();
    // Step 26 — the banner used to say "Tap Renew on the row below"
    // but the Renew button conflicted with the active-sub guard.
    // Now we point users at the "Subscribe again" affordance that
    // appears once a sub actually expires.
    String body;
    if (n == 1) {
      body = 'mySubscriptions.expiring.bodyOne'.trParams({
        'name': names.first,
        'count': '$shortest',
        'plural': shortest == 1 ? '' : 's',
      });
    } else {
      body = 'mySubscriptions.expiring.bodyMany'.trParams({
        'total': '$n',
        'name': names.first,
        'count': '$shortest',
        'plural': shortest == 1 ? '' : 's',
      });
    }
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'mySubscriptions.expiring.heading'.tr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
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

// =============================================================================
// Sprint-C step 10 — Community subscription tile.
//
// Renders one row from `community_subscriptions` (joined community, paid
// membership). Visual layout matches `_SubTile` for consistency but the
// model is different (CommunitySubscriptionRow vs ExpertSubscription) so
// we don't try to unify the two — clearer to have two tiles.
// =============================================================================
class _CommunitySubTile extends StatelessWidget {
  final CommunitySubscriptionRow sub;
  final VoidCallback onCancel;
  const _CommunitySubTile({required this.sub, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = _commStatusSpec(sub.status);
    final dollars = sub.priceCents / 100;
    final priceLabel =
        '${sub.currency.toUpperCase()} ${dollars.toStringAsFixed(dollars.truncateToDouble() == dollars ? 0 : 2)}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cs.tertiary.withValues(alpha: 0.18),
                child: Icon(Icons.groups_rounded, size: 20, color: cs.tertiary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.communityName.isEmpty
                          ? sub.communityId
                          : sub.communityName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      '${sub.plan.toUpperCase()} · $priceLabel · ${sub.paymentMethod.toUpperCase()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: spec.color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(spec.icon, size: 12, color: spec.color),
                    const SizedBox(width: 4),
                    Text(
                      spec.label.toUpperCase(),
                      style: TextStyle(
                        color: spec.color,
                        fontWeight: FontWeight.w900,
                        fontSize: 9.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (sub.isActive && sub.expiresAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'mySubscriptions.accessUntil'
                  .trParams({'date': LocaleFormat.date(sub.expiresAt!)}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
          if (sub.status == 'rejected' && sub.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'mySubscriptions.reason'
                  .trParams({'reason': sub.rejectionReason}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.error,
                  ),
            ),
          ],
          if (sub.isPending || sub.isActive) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                child: Text('common.cancel'.tr),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _StatusSpec _commStatusSpec(String s) {
    switch (s) {
      case 'pending':
        return _StatusSpec(
          label: 'mySubscriptions.status.pending'.tr,
          icon: Icons.hourglass_top,
          color: Colors.amber,
        );
      case 'active':
        return _StatusSpec(
          label: 'mySubscriptions.status.active'.tr,
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF10B981),
        );
      case 'rejected':
        return _StatusSpec(
          label: 'mySubscriptions.status.rejected'.tr,
          icon: Icons.cancel_outlined,
          color: const Color(0xFFF43F5E),
        );
      case 'cancelled':
        return _StatusSpec(
          label: 'mySubscriptions.status.cancelled'.tr,
          icon: Icons.do_not_disturb_alt,
          color: const Color(0xFF94A3B8),
        );
      case 'expired':
        return _StatusSpec(
          label: 'mySubscriptions.status.expired'.tr,
          icon: Icons.history_toggle_off,
          color: const Color(0xFF94A3B8),
        );
      default:
        return _StatusSpec(
          label: 'mySubscriptions.status.unknown'.tr,
          icon: Icons.help_outline,
          color: const Color(0xFF94A3B8),
        );
    }
  }
}
