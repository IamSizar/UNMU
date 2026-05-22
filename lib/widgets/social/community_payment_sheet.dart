import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/community_subscription_service.dart';
import '../../services/upload_service.dart';

/// Bottom-sheet payment composer for paid community memberships
/// (step-23). Mirrors the expert-subscription payment flow:
///
///   Plan summary (already selected on the pricing card upstream)
///   ↓
///   Payment method picker (cash | FIB)
///   ↓
///   Optional reference + note
///   ↓
///   Submit → POST /communities/:id/subscribe
///
/// On success, returns the freshly-created [CommunitySubscriptionRow]
/// to the caller. On failure, the error stays inline in the sheet
/// (handler 409 / 402 etc. surface as the snackbar).
class CommunityPaymentSheet extends StatefulWidget {
  final String communityId;
  final String communityName;
  final String plan; // monthly | yearly (already chosen)
  final int priceCents;
  final String currency;

  const CommunityPaymentSheet({
    super.key,
    required this.communityId,
    required this.communityName,
    required this.plan,
    required this.priceCents,
    required this.currency,
  });

  static Future<CommunitySubscriptionRow?> show(
    BuildContext context, {
    required String communityId,
    required String communityName,
    required String plan,
    required int priceCents,
    required String currency,
  }) {
    return showModalBottomSheet<CommunitySubscriptionRow>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityPaymentSheet(
        communityId: communityId,
        communityName: communityName,
        plan: plan,
        priceCents: priceCents,
        currency: currency,
      ),
    );
  }

  @override
  State<CommunityPaymentSheet> createState() => _CommunityPaymentSheetState();
}

class _CommunityPaymentSheetState extends State<CommunityPaymentSheet> {
  String _method = 'cash'; // cash | fib
  final _ref = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Cash-receipt image upload state (mig 0025 / C9).
  String? _receiptUrl;
  bool _receiptUploading = false;

  /// Submitted-success snapshot — when non-null we render the
  /// confirmation step instead of the form.
  CommunitySubscriptionRow? _submitted;

  @override
  void dispose() {
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) return;
    setState(() {
      _receiptUploading = true;
      _error = null;
    });
    final res = await UploadService.uploadImage(File(picked.path));
    if (!mounted) return;
    setState(() {
      _receiptUploading = false;
      if (res.error != null) {
        _error = res.error;
      } else {
        _receiptUrl = res.url;
      }
    });
  }

  Future<void> _submit() async {
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await CommunitySubscriptionService.subscribe(
      communityId: widget.communityId,
      plan: widget.plan,
      paymentMethod: _method,
      paymentRef: _ref.text.trim(),
      receiptUrl: _receiptUrl,
      userNote: _note.text.trim(),
    );
    if (!mounted) return;
    if (res.error != null || res.sub == null) {
      setState(() {
        _busy = false;
        _error = res.error;
      });
      return;
    }
    // Step C9 — show a "submitted, awaiting admin" confirmation step
    // instead of popping straight to the previous screen, so the user
    // sees the receipt-attached state confirmed and reads what
    // happens next.
    setState(() {
      _busy = false;
      _submitted = res.sub;
    });
  }

  String _absoluteReceipt(String relative) {
    if (relative.isEmpty) return '';
    if (relative.startsWith('http')) return relative;
    final base = ApiConfig.baseUrl;
    final origin = base.split('/api').first;
    return '$origin$relative';
  }

  String get _priceDisplay {
    final dollars = widget.priceCents / 100;
    final symbol = widget.currency.toUpperCase();
    return '$symbol ${dollars.toStringAsFixed(dollars < 100 ? 2 : 0)}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final h = MediaQuery.of(context).size.height;
    if (_submitted != null) {
      return _SuccessStep(
        sub: _submitted!,
        palette: palette,
        onClose: () => Navigator.of(context).pop(_submitted),
      );
    }
    return AnimatedPadding(
      padding: MediaQuery.of(context).viewInsets,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.9),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: palette.border, width: 1),
              left: BorderSide(color: palette.border, width: 1),
              right: BorderSide(color: palette.border, width: 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _grabber(palette),
                _header(palette),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    shrinkWrap: true,
                    children: [
                      _summary(palette),
                      const SizedBox(height: 18),
                      _label(palette, 'paymentSheet.paymentMethod'.tr),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _MethodTile(
                              icon: Icons.attach_money_rounded,
                              label: 'paymentSheet.cash'.tr,
                              selected: _method == 'cash',
                              onTap: () => setState(() => _method = 'cash'),
                              palette: palette,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MethodTile(
                              icon: Icons.account_balance_rounded,
                              label: 'FIB',
                              selected: _method == 'fib',
                              onTap: () => setState(() => _method = 'fib'),
                              palette: palette,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _label(palette,
                          'paymentSheet.paymentReferenceOptional'.tr),
                      _textField(
                        palette,
                        _ref,
                        hint: _method == 'fib'
                            ? 'paymentSheet.fibTransactionHint'.tr
                            : 'paymentSheet.receiptDropHint'.tr,
                      ),
                      if (_method == 'cash') ...[
                        const SizedBox(height: 14),
                        _label(palette,
                            'paymentSheet.cashReceiptPhotoOptional'.tr),
                        const SizedBox(height: 6),
                        _ReceiptPickerTile(
                          relativeUrl: _receiptUrl,
                          uploading: _receiptUploading,
                          onTap: _busy || _receiptUploading ? null : _pickReceipt,
                          onClear: _receiptUrl == null
                              ? null
                              : () => setState(() => _receiptUrl = null),
                          absolveAbsolute: _absoluteReceipt,
                          palette: palette,
                        ),
                      ],
                      const SizedBox(height: 14),
                      _label(palette, 'paymentSheet.noteForAdminOptional'.tr),
                      _textField(
                        palette,
                        _note,
                        hint: 'paymentSheet.noteHint'.tr,
                        maxLines: 3,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: SocialTokens.down,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SocialTokens.gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _busy ? null : _submit,
                          icon: const Icon(Icons.send_rounded),
                          label: Text(
                            _busy
                                ? 'paymentSheet.submitting'.tr
                                : 'paymentSheet.submitProof'.tr,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber(SocialPalette palette) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 10),
        child: Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: palette.textMuted.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );

  Widget _header(SocialPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded,
                color: SocialTokens.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'paymentSheet.subscribeTo'
                    .trParams({'name': widget.communityName}),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.close_rounded, color: palette.textMuted),
            ),
          ],
        ),
      );

  Widget _summary(SocialPalette palette) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 16, color: SocialTokens.gold),
            const SizedBox(width: 8),
            Text(
              widget.plan == 'monthly'
                  ? 'paymentSheet.monthlyPlan'.tr
                  : 'paymentSheet.yearlyPlan'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Text(
              _priceDisplay,
              style: const TextStyle(
                color: SocialTokens.gold,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );

  Widget _label(SocialPalette palette, String text) => Text(
        text,
        style: TextStyle(
          color: palette.textMuted,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
          letterSpacing: 0.4,
        ),
      );

  Widget _textField(
    SocialPalette palette,
    TextEditingController ctl, {
    required String hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextField(
        controller: ctl,
        maxLines: maxLines,
        style: TextStyle(color: palette.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: palette.textMuted.withValues(alpha: 0.7)),
          filled: true,
          fillColor: palette.surfaceElevated,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: SocialTokens.gold, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final SocialPalette palette;
  const _MethodTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.palette,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? SocialTokens.gold.withValues(alpha: 0.14)
              : palette.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? SocialTokens.gold : palette.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SocialTokens.gold, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Receipt picker — image-thumbnail tile in the same visual style as the
// rest of the sheet. Shows a placeholder until the user picks a file,
// then a thumbnail + "tap to replace" copy.
// =============================================================================
class _ReceiptPickerTile extends StatelessWidget {
  final String? relativeUrl;
  final bool uploading;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final String Function(String) absolveAbsolute;
  final SocialPalette palette;
  const _ReceiptPickerTile({
    required this.relativeUrl,
    required this.uploading,
    required this.onTap,
    required this.onClear,
    required this.absolveAbsolute,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surfaceElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: SocialTokens.gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  image: relativeUrl == null
                      ? null
                      : DecorationImage(
                          image: NetworkImage(absolveAbsolute(relativeUrl!)),
                          fit: BoxFit.cover,
                        ),
                ),
                child: relativeUrl == null
                    ? const Icon(Icons.receipt_long_rounded,
                        color: SocialTokens.gold)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      relativeUrl == null
                          ? 'paymentSheet.addReceiptPhoto'.tr
                          : 'paymentSheet.receiptUploaded'.tr,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      relativeUrl == null
                          ? 'paymentSheet.receiptHelp'.tr
                          : 'paymentSheet.tapToReplace'.tr,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (uploading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (onClear != null)
                IconButton(
                  tooltip: 'common.remove'.tr,
                  onPressed: onClear,
                  icon: Icon(Icons.close_rounded, color: palette.textMuted),
                )
              else
                const Icon(Icons.add_a_photo_outlined, color: SocialTokens.gold),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Success / confirmation step — shown after the POST succeeds. Tells the
// user what to expect (admin reviews, you'll get a notification when
// they accept) so they don't think they missed something.
// =============================================================================
class _SuccessStep extends StatelessWidget {
  final CommunitySubscriptionRow sub;
  final SocialPalette palette;
  final VoidCallback onClose;
  const _SuccessStep({
    required this.sub,
    required this.palette,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      padding: MediaQuery.of(context).viewInsets,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: palette.border),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.textMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 64,
                  height: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 0),
                  decoration: BoxDecoration(
                    color: SocialTokens.gold.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.check_rounded,
                    color: SocialTokens.gold,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'paymentSheet.paymentSubmitted'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'paymentSheet.successBody'.trParams({
                    'plan': sub.plan,
                    'name': sub.communityName,
                  }),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SocialTokens.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: onClose,
                    child: Text(
                      'paymentSheet.gotIt'.tr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
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
