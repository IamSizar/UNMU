import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/notification_prefs_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/platform_adaptive/platform_switch.dart';
import '../../widgets/pulse/pulse_tokens.dart';
import '../social/social_tokens.dart';

/// =============================================================================
/// PulseNotificationPrefsScreen — which Pulse events send a notification.
///
/// One master switch plus the four events from the spec (§17): a new Pulse is
/// published, a previous item is updated, a previous item is corrected, a saved
/// item changes. Switches flip at once (optimistic) and are reverted with a
/// calm message if the server cannot save them.
///
/// The settings live in the existing notification preferences (backend
/// migration 0056 adds the Pulse columns), so this screen reuses
/// [NotificationPrefsService]. Notifications arrive in the user's app language.
/// =============================================================================
class PulseNotificationPrefsScreen extends StatefulWidget {
  const PulseNotificationPrefsScreen({super.key});

  @override
  State<PulseNotificationPrefsScreen> createState() =>
      _PulseNotificationPrefsScreenState();
}

class _PulseNotificationPrefsScreenState
    extends State<PulseNotificationPrefsScreen> {
  NotificationPrefs _prefs = NotificationPrefs.initial();
  bool _loading = true;
  bool _loadFailed = false;
  String? _saving; // key of the switch being saved

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final res = await NotificationPrefsService.get();
    if (!mounted) return;
    setState(() {
      _prefs = res.prefs;
      _loadFailed = res.error != null;
      _loading = false;
    });
  }

  /// Flips one switch: update the screen now, save, and revert on failure.
  Future<void> _toggle({
    required String key,
    required bool value,
    required NotificationPrefs Function(NotificationPrefs, bool) apply,
    required Future<({NotificationPrefs? prefs, String? error})> Function(bool)
    save,
  }) async {
    HapticUtils.selection();
    final previous = _prefs;
    setState(() {
      _prefs = apply(_prefs, value);
      _saving = key;
    });
    final res = await save(value);
    if (!mounted) return;
    setState(() {
      _saving = null;
      _prefs = res.prefs ?? previous; // revert when the save failed
    });
    if (res.prefs == null) {
      HapticUtils.error();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('pulse.prefs.saveFailed'.tr)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final masterOn = _prefs.pulseEnabled;
    final arabic = Get.locale?.languageCode == 'ar';

    return PulseAuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: p.textPrimary),
          title: Text(
            'pulse.prefs.title'.tr,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                PulseSpace.lg,
                PulseSpace.sm,
                PulseSpace.lg,
                PulseSpace.xxl,
              ),
              children: [
                if (_loadFailed) ...[
                  _Banner(text: 'pulse.prefs.loadFailed'.tr, onRetry: _load),
                  const SizedBox(height: PulseSpace.md),
                ],
                if (!_prefs.pushEnabled) ...[
                  _Banner(text: 'pulse.prefs.pushOff'.tr),
                  const SizedBox(height: PulseSpace.md),
                ],
                PulseSurfaceBox(
                  surface: PulseSurface.glass,
                  padding: const EdgeInsets.symmetric(vertical: PulseSpace.xs),
                  child: _SwitchRow(
                    title: 'pulse.prefs.master'.tr,
                    subtitle: 'pulse.prefs.masterHint'.tr,
                    value: masterOn,
                    busy: _saving == 'master',
                    enabled: !_loading,
                    onChanged: (v) => _toggle(
                      key: 'master',
                      value: v,
                      apply: (s, x) => s.copyWith(pulseEnabled: x),
                      save: (x) =>
                          NotificationPrefsService.update(pulseEnabled: x),
                    ),
                  ),
                ),
                const SizedBox(height: PulseSpace.lg),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 4,
                    bottom: PulseSpace.sm,
                  ),
                  child: Text(
                    'pulse.prefs.header'.tr,
                    style: TextStyle(
                      color: p.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: arabic ? 0 : 0.8,
                    ),
                  ),
                ),
                PulseSurfaceBox(
                  surface: PulseSurface.glass,
                  padding: const EdgeInsets.symmetric(vertical: PulseSpace.xs),
                  child: Column(
                    children: [
                      _SwitchRow(
                        title: 'pulse.prefs.new'.tr,
                        value: _prefs.pulseNewEnabled,
                        busy: _saving == 'new',
                        enabled: masterOn && !_loading,
                        onChanged: (v) => _toggle(
                          key: 'new',
                          value: v,
                          apply: (s, x) => s.copyWith(pulseNewEnabled: x),
                          save: (x) => NotificationPrefsService.update(
                            pulseNewEnabled: x,
                          ),
                        ),
                      ),
                      _SwitchRow(
                        title: 'pulse.prefs.updates'.tr,
                        value: _prefs.pulseUpdatesEnabled,
                        busy: _saving == 'updates',
                        enabled: masterOn && !_loading,
                        onChanged: (v) => _toggle(
                          key: 'updates',
                          value: v,
                          apply: (s, x) => s.copyWith(pulseUpdatesEnabled: x),
                          save: (x) => NotificationPrefsService.update(
                            pulseUpdatesEnabled: x,
                          ),
                        ),
                      ),
                      _SwitchRow(
                        title: 'pulse.prefs.corrections'.tr,
                        value: _prefs.pulseCorrectionsEnabled,
                        busy: _saving == 'corrections',
                        enabled: masterOn && !_loading,
                        onChanged: (v) => _toggle(
                          key: 'corrections',
                          value: v,
                          apply: (s, x) =>
                              s.copyWith(pulseCorrectionsEnabled: x),
                          save: (x) => NotificationPrefsService.update(
                            pulseCorrectionsEnabled: x,
                          ),
                        ),
                      ),
                      _SwitchRow(
                        title: 'pulse.prefs.saved'.tr,
                        value: _prefs.pulseSavedEnabled,
                        busy: _saving == 'saved',
                        enabled: masterOn && !_loading,
                        onChanged: (v) => _toggle(
                          key: 'saved',
                          value: v,
                          apply: (s, x) => s.copyWith(pulseSavedEnabled: x),
                          save: (x) => NotificationPrefsService.update(
                            pulseSavedEnabled: x,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: PulseSpace.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'pulse.prefs.footer'.tr,
                    style: TextStyle(
                      color: p.textMuted,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final bool busy;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.value,
    required this.busy,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: title,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PulseSpace.lg,
            vertical: PulseSpace.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(color: p.textMuted, fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
                ),
              PlatformSwitch(
                value: value,
                onChanged: enabled ? onChanged : (_) {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Banner({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5A623).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(PulseIcons.alert(context), size: 18, color: p.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text('pulse.error.retry'.tr)),
        ],
      ),
    );
  }
}
