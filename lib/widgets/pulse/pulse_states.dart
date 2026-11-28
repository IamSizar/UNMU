import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/social/social_tokens.dart';
import '../../services/pulse_service.dart';
import 'pulse_tokens.dart';

/// =============================================================================
/// pulse_states.dart — the designed "nothing to show" states of Pulse.
///
/// A screen is never blank: while loading it shows skeletons, and when there is
/// nothing to show it shows one of these — an icon, a calm one-line title, a
/// sentence saying what to do next, and (for failures) a Retry button. Raw
/// exceptions and status codes never reach the user.
/// =============================================================================

/// Primary action button in the platform's native style (Cupertino on iOS,
/// Material on Android), filled with the deep UNMU teal.
class PulsePrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const PulsePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final enabled = onPressed != null && !loading;
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator.adaptive(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          )
        : Text(label, style: const TextStyle(fontWeight: FontWeight.w700));

    if (ios) {
      return CupertinoButton(
        color: PulseColors.tealDeep,
        borderRadius: BorderRadius.circular(999),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        onPressed: enabled ? onPressed : null,
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white, fontSize: 15),
          child: child,
        ),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: PulseColors.tealDeep,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: const StadiumBorder(),
      ),
      onPressed: enabled ? onPressed : null,
      child: child,
    );
  }
}

/// A centred card: icon, title, body, optional action.
class PulseStatusView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PulseStatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  /// The standard failure view: offline vs server wording, with Retry.
  factory PulseStatusView.failure(
    BuildContext context, {
    required PulseFailure failure,
    required VoidCallback onRetry,
  }) {
    final offline = failure == PulseFailure.offline;
    return PulseStatusView(
      icon: offline ? PulseIcons.wifiOff(context) : PulseIcons.alert(context),
      title:
          (offline ? 'pulse.error.offline.title' : 'pulse.error.server.title')
              .tr,
      body:
          (offline ? 'pulse.error.offline.body' : 'pulse.error.server.body').tr,
      actionLabel: 'pulse.error.retry'.tr,
      onAction: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return Semantics(
      container: true,
      child: PulseSurfaceBox(
        surface: PulseSurface.glass,
        padding: const EdgeInsets.symmetric(
          horizontal: PulseSpace.xl,
          vertical: PulseSpace.xxl,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: PulseColors.teal.withValues(
                    alpha: p.isDark ? 0.22 : 0.14,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: p.isDark
                      ? PulseColors.tealBright
                      : PulseColors.tealInk,
                ),
              ),
              const SizedBox(height: PulseSpace.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: PulseSpace.sm),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: PulseSpace.xl),
                PulsePrimaryButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
