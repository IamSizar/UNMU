import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:get/get.dart';

import '../../models/expert_application.dart';
import '../../models/user.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/realtime_controller.dart';
import '../../services/expert_application_service.dart';
import 'apply_for_expert_screen.dart';

/// Profile-screen banner that drives the "become an expert" flow.
///
/// State machine, driven by [ExpertApplicationService.myApplication]:
///
///   1. Loading                  → small skeleton card
///   2. No application yet       → "Become an Expert" call-to-action
///   3. Status = pending         → pending review card
///   4. Status = rejected        → rejected card + re-apply button
///   5. User role != USER        → renders nothing (already an expert/admin)
///
/// Tapping the CTA opens [ApplyForExpertScreen]. When that screen pops with
/// a fresh [ExpertApplication], we update local state so the banner switches
/// to "pending" without a refresh.
class BecomeExpertBanner extends StatefulWidget {
  const BecomeExpertBanner({super.key});

  @override
  State<BecomeExpertBanner> createState() => _BecomeExpertBannerState();
}

class _BecomeExpertBannerState extends State<BecomeExpertBanner> {
  ExpertApplication? _app;
  bool _loading = true;
  StreamSubscription<dynamic>? _approvedSub;
  StreamSubscription<dynamic>? _rejectedSub;
  Worker? _userWatcher;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Realtime: refresh when the server tells us the application changed.
    final realtime = Get.find<RealtimeController>();
    _approvedSub = realtime.onApplicationApproved.listen((_) => _refresh());
    _rejectedSub = realtime.onApplicationRejected.listen((_) => _refresh());
    // Watch the auth user so switching test accounts (or any in-place user
    // change) re-fetches the application status. Without this the banner
    // shows stale data until a hot-restart.
    _userWatcher = ever<dynamic>(
      Get.find<AuthController>().userObservable,
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _approvedSub?.cancel();
    _rejectedSub?.cancel();
    _userWatcher?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final app = await ExpertApplicationService.myApplication();
    if (!mounted) return;
    setState(() {
      _app = app;
      _loading = false;
    });
  }

  /// Open the apply form. When `prefill` is non-null the form is seeded
  /// with the user's prior submission so the re-apply flow is one
  /// edit-a-field operation, not "type the same 5 fields again".
  Future<void> _openApplyForm({ExpertApplication? prefill}) async {
    final result = await Navigator.of(context).push<ExpertApplication>(
      MaterialPageRoute(
        builder: (_) => ApplyForExpertScreen(prefill: prefill),
      ),
    );
    if (result != null && mounted) {
      setState(() => _app = result);
    }
  }

  Future<void> _withdraw() async {
    final app = _app;
    if (app == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('becomeExpert.withdrawTitle'.tr),
        content: Text(
          'becomeExpert.withdrawBody'.tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('becomeExpert.withdraw'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await ExpertApplicationService.withdraw(app.id);
    if (!mounted) return;
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'becomeExpert.withdrawFailed'.tr)),
      );
      return;
    }
    setState(() => _app = null);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final user = auth.user;
    if (user == null || user.role != UserRole.user) {
      return const SizedBox.shrink();
    }

    if (_loading) return const _SkeletonCard();

    final app = _app;
    if (app == null) return _CTACard(onTap: _openApplyForm);

    switch (app.status) {
      case ApplicationStatus.pending:
        return _PendingCard(
          submittedAt: app.submittedAt,
          onWithdraw: _withdraw,
        );
      case ApplicationStatus.rejected:
        return _RejectedCard(
          reason: app.rejectionReason,
          onReapply: () => _openApplyForm(prefill: app),
        );
      case ApplicationStatus.approved:
      case ApplicationStatus.none:
        // Approved should be impossible (role would have flipped); treat both
        // as "no application" so the user can apply again.
        return _CTACard(onTap: () => _openApplyForm());
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// state cards
// ─────────────────────────────────────────────────────────────────────────────

class _CTACard extends StatelessWidget {
  final VoidCallback onTap;
  const _CTACard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.18),
              cs.tertiary.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.primary.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.school_outlined, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'becomeExpert.ctaTitle'.tr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'becomeExpert.ctaSubtitle'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            DirectionalIcon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final DateTime submittedAt;
  final VoidCallback onWithdraw;
  const _PendingCard({required this.submittedAt, required this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final daysAgo = DateTime.now().difference(submittedAt).inDays;
    final relative = daysAgo == 0
        ? 'becomeExpert.whenToday'.tr
        : (daysAgo == 1
            ? 'becomeExpert.whenYesterday'.tr
            : 'becomeExpert.whenDaysAgo'.trParams({'count': '$daysAgo'}));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.hourglass_top, color: Colors.amber),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'becomeExpert.pendingTitle'.tr,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'becomeExpert.pendingSubtitle'.trParams({'when': relative}),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onWithdraw,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text('becomeExpert.withdraw'.tr),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  final String? reason;
  final VoidCallback onReapply;
  const _RejectedCard({required this.reason, required this.onReapply});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.error.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cancel_outlined, color: cs.error),
              const SizedBox(width: 10),
              Text(
                'becomeExpert.rejectedTitle'.tr,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          if (reason != null && reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reason!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onReapply,
            child: Text('becomeExpert.applyAgain'.tr),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}
