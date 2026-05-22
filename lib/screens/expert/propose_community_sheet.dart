import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/community_proposal.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/community_proposal_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';

/// Modal bottom-sheet that lets an expert submit a new community proposal
/// for admin review. Backed by `POST /api/me/community-proposals`.
///
/// Returns the freshly-created [CommunityProposal] via `Navigator.pop()`
/// when the submit succeeds, or null when the user dismisses without
/// submitting. The "Studio" screen uses the returned value to prepend a
/// PENDING row to its proposals list without an extra round-trip.
///
/// Validation rules (mirror the backend):
///   * name        : 3..60 chars
///   * description : 10..500 chars
///   * regionCode  : optional, must match one of the [_regions] entries
///
/// On 409 PENDING_EXISTS the sheet renders an inline banner explaining
/// the user already has a proposal awaiting review — they can dismiss
/// and check the "My proposals" list in the studio.
class ProposeCommunitySheet extends StatefulWidget {
  const ProposeCommunitySheet({super.key});

  static Future<CommunityProposal?> show(BuildContext context) {
    return showModalBottomSheet<CommunityProposal>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProposeCommunitySheet(),
    );
  }

  @override
  State<ProposeCommunitySheet> createState() => _ProposeCommunitySheetState();
}

class _ProposeCommunitySheetState extends State<ProposeCommunitySheet> {
  // Same region catalogue used by the Discover tab so the picker labels
  // are consistent across the app. Keep in sync with `discover_screen.dart`.
  //
  // Each region carries a translation `key` (resolved via `.tr` at render
  // time) plus the `code` the backend stores, so both languages map to the
  // same row.
  static const List<({String code, String labelKey, String emoji})>
      _regions = [
    (code: '',       labelKey: 'proposeCommunity.regionNone',   emoji: '🌐'),
    (code: 'GLOBAL', labelKey: 'proposeCommunity.regionGlobal', emoji: '🌍'),
    (code: 'US',     labelKey: 'proposeCommunity.regionUS',     emoji: '🇺🇸'),
    (code: 'GCC',    labelKey: 'proposeCommunity.regionGCC',    emoji: '🕌'),
    (code: 'MENA',   labelKey: 'proposeCommunity.regionMENA',   emoji: '🌙'),
    (code: 'EU',     labelKey: 'proposeCommunity.regionEU',     emoji: '🇪🇺'),
    (code: 'ASIA',   labelKey: 'proposeCommunity.regionAsia',   emoji: '🌏'),
    (code: 'CN',     labelKey: 'proposeCommunity.regionCN',     emoji: '🇨🇳'),
  ];

  final _nameCtl = TextEditingController();
  final _descCtl = TextEditingController();
  String _regionCode = ''; // empty = unspecified

  bool _submitting = false;
  String? _error;
  // When the server returns 409 we flip this flag so the banner uses a
  // calmer "info" color instead of red — the user didn't do anything
  // wrong, they just have an existing pending one.
  bool _pendingExists = false;

  @override
  void initState() {
    super.initState();
    _nameCtl.addListener(_recompute);
    _descCtl.addListener(_recompute);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  void _recompute() => setState(() {/* refresh counters + submit-enabled */});

  // ── computed ─────────────────────────────────────────────────────────
  String get _name => _nameCtl.text.trim();
  String get _desc => _descCtl.text.trim();
  bool get _nameValid => _name.length >= 3 && _name.length <= 60;
  bool get _descValid => _desc.length >= 10 && _desc.length <= 500;
  bool get _canSubmit => _nameValid && _descValid && !_submitting;

  // ── submit ───────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_canSubmit) return;
    HapticUtils.lightTap();
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
      _pendingExists = false;
    });

    final result = await CommunityProposalService.submit(
      name: _name,
      description: _desc,
      regionCode: _regionCode.isEmpty ? null : _regionCode,
    );

    if (!mounted) return;

    if (result.proposal != null) {
      await HapticUtils.success();
      if (!mounted) return;
      Navigator.of(context).pop(result.proposal);
      return;
    }

    await HapticUtils.error();
    setState(() {
      _submitting = false;
      _error = result.error ?? 'proposeCommunity.submitFailed'.tr;
      _pendingExists = result.pendingExists;
    });
  }

  // ── UI ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    // Cap at 92% to leave room for the keyboard.
    final maxH = MediaQuery.of(context).size.height * 0.92;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DismissKeyboardOnTap(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: palette.border, width: 1),
            left: BorderSide(color: palette.border, width: 1),
            right: BorderSide(color: palette.border, width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: 20 + bottomInset,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: palette.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                  // Header
                  _Header(palette: palette),
                  const SizedBox(height: 18),

                  // Info banner — what happens after submit
                  _InfoBanner(palette: palette),
                  const SizedBox(height: 16),

                  // Error / pending banner
                  if (_error != null) ...[
                    _ErrorBanner(
                      message: _error!,
                      isInfo: _pendingExists,
                      palette: palette,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Name
                  _FieldLabel(
                    text: 'proposeCommunity.nameLabel'.tr,
                    palette: palette,
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameCtl,
                    enabled: !_submitting,
                    style: TextStyle(color: palette.textPrimary, fontSize: 14),
                    maxLength: 60,
                    decoration: _inputDecoration(
                      palette,
                      hint: 'proposeCommunity.nameHint'.tr,
                      icon: Icons.groups_2_outlined,
                    ),
                  ),
                  _CharCounter(
                    current: _name.length,
                    min: 3,
                    max: 60,
                    palette: palette,
                  ),
                  const SizedBox(height: 14),

                  // Region picker
                  _FieldLabel(
                    text: 'proposeCommunity.regionLabel'.tr,
                    palette: palette,
                  ),
                  const SizedBox(height: 6),
                  _RegionPicker(
                    palette: palette,
                    regions: _regions,
                    selected: _regionCode,
                    enabled: !_submitting,
                    onChanged: (code) => setState(() => _regionCode = code),
                  ),
                  const SizedBox(height: 14),

                  // Description
                  _FieldLabel(
                    text: 'proposeCommunity.descLabel'.tr,
                    palette: palette,
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _descCtl,
                    enabled: !_submitting,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 500,
                    decoration: _inputDecoration(
                      palette,
                      hint: 'proposeCommunity.descHint'.tr,
                      icon: Icons.notes_rounded,
                      multiline: true,
                    ),
                  ),
                  _CharCounter(
                    current: _desc.length,
                    min: 10,
                    max: 500,
                    palette: palette,
                  ),
                  const SizedBox(height: 18),

                  // Submit CTA
                  _SubmitButton(
                    enabled: _canSubmit,
                    loading: _submitting,
                    onTap: _submit,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textMuted,
                      ),
                      child: Text('proposeCommunity.cancel'.tr),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    SocialPalette palette, {
    required String hint,
    required IconData icon,
    bool multiline = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: palette.textMuted, fontSize: 13.5),
      prefixIcon: multiline
          ? Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: Icon(icon, color: palette.textMuted, size: 18),
            )
          : Icon(icon, color: palette.textMuted, size: 18),
      filled: true,
      fillColor: palette.surfaceElevated,
      counterText: '', // we render our own counter below the field
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: multiline ? 14 : 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: SocialTokens.cyan, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.border, width: 1),
      ),
    );
  }
}

// ============================================================================
// Header (icon + title + subtitle).
// ============================================================================
class _Header extends StatelessWidget {
  final SocialPalette palette;
  const _Header({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SocialTokens.cyan.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: SocialTokens.cyan.withValues(alpha: 0.45),
            ),
          ),
          child: const Icon(
            Icons.add_business_rounded,
            color: SocialTokens.cyan,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'proposeCommunity.headerTitle'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'proposeCommunity.headerSubtitle'.tr,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Calm info banner explaining what happens next.
// ============================================================================
class _InfoBanner extends StatelessWidget {
  final SocialPalette palette;
  const _InfoBanner({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SocialTokens.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SocialTokens.cyan.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: SocialTokens.cyan,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'proposeCommunity.infoBanner'.tr,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Error banner — flips to a neutral info color when the failure was just
// "you already have a pending proposal".
// ============================================================================
class _ErrorBanner extends StatelessWidget {
  final String message;
  final bool isInfo;
  final SocialPalette palette;
  const _ErrorBanner({
    required this.message,
    required this.isInfo,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final color = isInfo ? SocialTokens.gold : SocialTokens.down;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isInfo
                ? Icons.hourglass_top_rounded
                : Icons.error_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Field label.
// ============================================================================
class _FieldLabel extends StatelessWidget {
  final String text;
  final SocialPalette palette;
  const _FieldLabel({required this.text, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 12.5,
        letterSpacing: 0.2,
      ),
    );
  }
}

// ============================================================================
// Inline char counter ("12 / 60"). Goes red when current is outside
// [min, max].
// ============================================================================
class _CharCounter extends StatelessWidget {
  final int current;
  final int min;
  final int max;
  final SocialPalette palette;
  const _CharCounter({
    required this.current,
    required this.min,
    required this.max,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final valid = current >= min && current <= max;
    final color = valid ? palette.textMuted : SocialTokens.down;
    return Padding(
      // EdgeInsetsDirectional so the 4px gap stays on the trailing edge
      // even when the sheet is rendered RTL — otherwise the counter would
      // visually drift away from the field's right-aligned edge in Arabic.
      padding: const EdgeInsetsDirectional.only(top: 4, end: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Numbers are kept LTR with tabular figures regardless of locale —
          // a counter like "12 / 60" reads the same way in both directions
          // visually but the slash separates two operands that should stay
          // ordered.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '$current / $max',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Region picker — horizontal scroll of pill buttons. Same look as the
// Discover tab pills so users have a familiar mental model.
// ============================================================================
class _RegionPicker extends StatelessWidget {
  final SocialPalette palette;
  final List<({String code, String labelKey, String emoji})>
      regions;
  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _RegionPicker({
    required this.palette,
    required this.regions,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final r in regions) ...[
            _RegionPill(
              palette: palette,
              code: r.code,
              label: r.labelKey.tr,
              emoji: r.emoji,
              selected: selected == r.code,
              enabled: enabled,
              onTap: () => onChanged(r.code),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RegionPill extends StatelessWidget {
  final SocialPalette palette;
  final String code;
  final String label;
  final String emoji;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _RegionPill({
    required this.palette,
    required this.code,
    required this.label,
    required this.emoji,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? SocialTokens.cyan.withValues(alpha: 0.16)
                : palette.surfaceElevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? SocialTokens.cyan.withValues(alpha: 0.50)
                  : palette.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? SocialTokens.cyan : palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Cyan gradient submit CTA.
// ============================================================================
class _SubmitButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  const _SubmitButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: enabled
                    ? const [SocialTokens.cyan, SocialTokens.cyanDeep]
                    : [
                        SocialTokens.cyan.withValues(alpha: 0.30),
                        SocialTokens.cyanDeep.withValues(alpha: 0.30),
                      ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: SocialTokens.cyan.withValues(alpha: 0.30),
                        blurRadius: 22,
                        spreadRadius: -4,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF0A1628),
                      ),
                    ),
                  )
                else
                  const Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: Color(0xFF0A1628),
                  ),
                const SizedBox(width: 8),
                Text(
                  'proposeCommunity.submit'.tr,
                  style: const TextStyle(
                    color: Color(0xFF0A1628),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.2,
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
