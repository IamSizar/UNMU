import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/api_config.dart';
import '../../services/community_service.dart';
import '../../services/upload_service.dart';
import '../../utils/price_format.dart';
import 'social_tokens.dart';

/// Owner / admin-only metadata editor for a single community.
///
/// Covers items 2.13 → 2.18:
///   * 2.13 Edit description (long-form `description` text field)
///   * 2.14 Edit rules        (long-form `rules` text field)
///   * 2.15 (search/discovery is a separate screen — this sheet is the
///          source of category + tags that drive search ranking)
///   * 2.16 Category + tags
///   * 2.17 Cover image
///   * 2.18 Public vs private toggle
///
/// Open via [CommunityEditSheet.show]. Pops `true` on success so the
/// caller can refetch + repaint, `false` / null on dismiss.
class CommunityEditSheet extends StatefulWidget {
  /// Community id to edit. The sheet fetches fresh metadata via
  /// `/communities/:id` on mount so the form pre-fills with the
  /// authoritative server values, not whatever the caller had cached.
  final String communityId;

  const CommunityEditSheet({super.key, required this.communityId});

  static Future<bool?> show(
    BuildContext context, {
    required String communityId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunityEditSheet(communityId: communityId),
    );
  }

  @override
  State<CommunityEditSheet> createState() => _CommunityEditSheetState();
}

class _CommunityEditSheetState extends State<CommunityEditSheet> {
  // Form controllers — initialized from the server fetch.
  final _nameCtl = TextEditingController();
  final _taglineCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _rulesCtl = TextEditingController();
  final _tagInputCtl = TextEditingController();

  // Live state mirrored from the server response.
  String _category = '';
  bool _isPublic = false;
  String _coverUrl = '';
  // Mig 0028 — separate square avatar URL. Mirrors _coverUrl exactly:
  // string stored in state, sent to PATCH /communities/:id as
  // `avatarUrl`, empty string clears the column on the server.
  String _avatarUrl = '';
  List<String> _tags = [];
  // Step-23 — paid community pricing.
  bool _isPaidMode = false;
  final _monthlyCtl = TextEditingController(); // dollars (UI), cents (wire)
  final _yearlyCtl = TextEditingController();
  String _currency = 'usd';
  static const _currencies = ['usd', 'iqd', 'sar', 'aed', 'eur', 'gbp'];

  // Predefined category list — fetched on mount.
  List<String> _categories = const [];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _taglineCtl.dispose();
    _descCtl.dispose();
    _rulesCtl.dispose();
    _tagInputCtl.dispose();
    _monthlyCtl.dispose();
    _yearlyCtl.dispose();
    super.dispose();
  }

  // Step-23 — formatters between cents (wire) and dollars (UI).
  String _centsToDollars(int cents) {
    if (cents <= 0) return '';
    final v = cents / 100;
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  int _dollarsToCents(String raw) {
    final v = double.tryParse(raw.trim()) ?? 0;
    if (v <= 0) return 0;
    return (v * 100).round();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([
      CommunityService.getMeta(widget.communityId),
      CommunityService.listCategories(),
    ]);
    if (!mounted) return;
    final metaRes = results[0] as ({CommunityMeta? meta, String? error});
    final catRes = results[1] as ({List<String>? categories, String? error});
    if (metaRes.error != null) {
      setState(() {
        _error = metaRes.error;
        _loading = false;
      });
      return;
    }
    final m = metaRes.meta!;
    setState(() {
      _nameCtl.text = m.name;
      _taglineCtl.text = m.tagline;
      _descCtl.text = m.description;
      _rulesCtl.text = m.rules;
      _category = m.category;
      _isPublic = m.isPublic;
      _coverUrl = m.coverUrl;
      _avatarUrl = m.avatarUrl;
      _tags = List.of(m.tags);
      _categories = catRes.categories ?? const [];
      // Step-23 — prefill pricing.
      _isPaidMode = m.isPaid;
      _monthlyCtl.text = _centsToDollars(m.joinPriceMonthlyCents);
      _yearlyCtl.text = _centsToDollars(m.joinPriceYearlyCents);
      _currency = m.priceCurrency.isEmpty ? 'usd' : m.priceCurrency;
      _loading = false;
    });
  }

  /// Resolves a possibly-relative coverUrl ("/uploads/images/abc.jpg")
  /// against [ApiConfig.assetBase] so the Image widget loads it.
  String _absoluteCover(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    return '$base$url';
  }

  Future<void> _pickCover() async {
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (picked == null) return;
    final upload = await UploadService.uploadImage(File(picked.path));
    if (!mounted) return;
    if (upload.error != null) {
      _showSnack(upload.error!);
      return;
    }
    setState(() => _coverUrl = upload.url ?? '');
  }

  /// Mig 0028 — pick + upload a square avatar. Same flow as [_pickCover]
  /// but caps the image at 512px since the avatar is rendered at most
  /// at ~80px on screen; serving a 1600px file wastes bytes.
  Future<void> _pickAvatar() async {
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 90,
    );
    if (picked == null) return;
    final upload = await UploadService.uploadImage(File(picked.path));
    if (!mounted) return;
    if (upload.error != null) {
      _showSnack(upload.error!);
      return;
    }
    setState(() => _avatarUrl = upload.url ?? '');
  }

  void _addTag() {
    final raw = _tagInputCtl.text.trim().toLowerCase();
    if (raw.isEmpty) return;
    if (_tags.contains(raw)) {
      _tagInputCtl.clear();
      return;
    }
    if (_tags.length >= 10) {
      _showSnack('communityEdit.maxTags'.tr);
      return;
    }
    if (raw.length > 30) {
      _showSnack('communityEdit.tagTooLong'.tr);
      return;
    }
    setState(() {
      _tags.add(raw);
      _tagInputCtl.clear();
    });
  }

  void _removeTag(String tag) {
    HapticFeedback.selectionClick();
    setState(() => _tags.remove(tag));
  }

  Future<void> _save() async {
    HapticFeedback.lightImpact();
    setState(() {
      _saving = true;
      _error = null;
    });
    // Step-23 — pricing payload. Free mode forces both prices to 0;
    // paid mode honours whatever the user typed (0 in either box is
    // allowed — means "this plan disabled").
    final monthlyCents = _isPaidMode ? _dollarsToCents(_monthlyCtl.text) : 0;
    final yearlyCents = _isPaidMode ? _dollarsToCents(_yearlyCtl.text) : 0;
    final res = await CommunityService.update(
      widget.communityId,
      name: _nameCtl.text.trim().isEmpty ? null : _nameCtl.text.trim(),
      tagline: _taglineCtl.text.trim(),
      description: _descCtl.text.trim(),
      rules: _rulesCtl.text.trim(),
      coverUrl: _coverUrl,
      avatarUrl: _avatarUrl,
      isPublic: _isPublic,
      category: _category,
      tags: _tags,
      joinPriceMonthlyCents: monthlyCents,
      joinPriceYearlyCents: yearlyCents,
      priceCurrency: _currency,
    );
    if (!mounted) return;
    if (res.error != null) {
      setState(() {
        _saving = false;
        _error = res.error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final h = MediaQuery.of(context).size.height;
    return AnimatedPadding(
      padding: MediaQuery.of(context).viewInsets,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.92),
        child: Container(
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
            child: _loading
                ? const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _grabber(palette),
                      _header(palette),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          children: [
                            _coverPreview(palette),
                            const SizedBox(height: 14),
                            // Mig 0028 — square avatar picker; sits right
                            // under the wide cover banner so the owner
                            // sees both image options together.
                            _avatarPreview(palette),
                            const SizedBox(height: 18),
                            _publicToggle(palette),
                            const SizedBox(height: 22),
                            _label(palette, 'communityEdit.name'.tr),
                            _textField(palette, _nameCtl,
                                hint: 'communityEdit.nameHint'.tr, maxLen: 60),
                            const SizedBox(height: 14),
                            _label(palette, 'communityEdit.tagline'.tr),
                            _textField(palette, _taglineCtl,
                                hint: 'communityEdit.taglineHint'.tr,
                                maxLen: 200),
                            const SizedBox(height: 14),
                            _label(palette, 'communityEdit.description'.tr),
                            _textField(palette, _descCtl,
                                hint: 'communityEdit.descriptionHint'.tr,
                                maxLen: 4000,
                                maxLines: 5),
                            const SizedBox(height: 14),
                            _label(palette, 'communityEdit.rules'.tr),
                            _textField(palette, _rulesCtl,
                                hint: 'communityEdit.rulesHint'.tr,
                                maxLen: 4000,
                                maxLines: 6),
                            const SizedBox(height: 22),
                            _label(palette, 'communityEdit.category'.tr),
                            _categoryPicker(palette),
                            const SizedBox(height: 22),
                            _label(palette, 'communityEdit.tags'.tr),
                            _tagsInput(palette),
                            const SizedBox(height: 8),
                            _tagsChipStrip(palette),
                            const SizedBox(height: 22),
                            _label(palette, 'communityEdit.pricing'.tr),
                            const SizedBox(height: 6),
                            _pricingSection(palette),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: SocialTokens.down,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            _saveButton(palette),
                            const SizedBox(height: 14),
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
            Expanded(
              child: Text(
                'communityEdit.title'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(false),
              icon: Icon(Icons.close_rounded, color: palette.textMuted),
            ),
          ],
        ),
      );

  Widget _label(SocialPalette palette, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            color: palette.textMuted,
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _textField(
    SocialPalette palette,
    TextEditingController ctl, {
    String? hint,
    int maxLen = 200,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctl,
      maxLength: maxLen,
      maxLines: maxLines,
      style: TextStyle(color: palette.textPrimary, fontSize: 14.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: palette.textMuted.withValues(alpha: 0.7),
        ),
        counterText: '',
        filled: true,
        fillColor: palette.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SocialTokens.cyan, width: 1.5),
        ),
      ),
    );
  }

  Widget _coverPreview(SocialPalette palette) {
    final hasCover = _coverUrl.isNotEmpty;
    final absolute = hasCover ? _absoluteCover(_coverUrl) : '';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _pickCover,
      child: Stack(
        children: [
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: palette.surfaceElevated,
              border: Border.all(color: palette.border),
              image: hasCover
                  ? DecorationImage(
                      image: NetworkImage(absolute),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasCover
                ? null
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_outlined,
                            color: palette.textMuted, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          'communityEdit.coverHint'.tr,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (hasCover)
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  iconSize: 18,
                  onPressed: () => setState(() => _coverUrl = ''),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'communityEdit.removeCover'.tr,
                ),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Material(
              color: SocialTokens.cyan,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _pickCover,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.upload_rounded,
                          color: Colors.black, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'communityEdit.change'.tr,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mig 0028 — avatar picker. Smaller preview (96x96 square) than the
  /// cover banner since the avatar itself only renders at ~50–80 in the
  /// UI; a giant preview here would be misleading.
  Widget _avatarPreview(SocialPalette palette) {
    final hasAvatar = _avatarUrl.isNotEmpty;
    final absolute = hasAvatar ? _absoluteCover(_avatarUrl) : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _pickAvatar,
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: palette.surfaceElevated,
              border: Border.all(color: palette.border),
              image: hasAvatar
                  ? DecorationImage(
                      image: NetworkImage(absolute),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasAvatar
                ? null
                : Icon(
                    Icons.add_a_photo_outlined,
                    color: palette.textMuted,
                    size: 26,
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'communityEdit.avatarTitle'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'communityEdit.avatarSubtitle'.tr,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _pickAvatar,
                    style: TextButton.styleFrom(
                      foregroundColor: SocialTokens.cyan,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.upload_rounded, size: 16),
                    label: Text(
                      'communityEdit.upload'.tr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  if (hasAvatar)
                    TextButton.icon(
                      onPressed: () => setState(() => _avatarUrl = ''),
                      style: TextButton.styleFrom(
                        foregroundColor: SocialTokens.down,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: Text(
                        'common.remove'.tr,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _publicToggle(SocialPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(
            _isPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
            color: _isPublic ? SocialTokens.up : SocialTokens.gold,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPublic
                      ? 'communityEdit.public'.tr
                      : 'communityEdit.private'.tr,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isPublic
                      ? 'communityEdit.publicDesc'.tr
                      : 'communityEdit.privateDesc'.tr,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isPublic,
            activeColor: SocialTokens.cyan,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _isPublic = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _categoryPicker(SocialPalette palette) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _categoryChip(palette, '', 'communityEdit.categoryNone'.tr),
        for (final c in _categories)
          _categoryChip(palette, c, _titleCase(c)),
      ],
    );
  }

  Widget _categoryChip(SocialPalette palette, String value, String label) {
    final selected = _category == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _category = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? SocialTokens.cyan.withValues(alpha: 0.18)
              : palette.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? SocialTokens.cyan : palette.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? SocialTokens.cyan : palette.textPrimary,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _tagsInput(SocialPalette palette) {
    return Row(
      children: [
        Expanded(
          child: _textField(
            palette,
            _tagInputCtl,
            hint: 'communityEdit.tagHint'.tr,
            maxLen: 30,
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: SocialTokens.cyan.withValues(alpha: 0.15),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _addTag,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.add, color: SocialTokens.cyan),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tagsChipStrip(SocialPalette palette) {
    if (_tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _tags
          .map((t) => Chip(
                label: Text('#$t'),
                labelStyle: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: palette.surfaceElevated,
                side: BorderSide(color: palette.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onDeleted: () => _removeTag(t),
                deleteIconColor: palette.textMuted,
              ))
          .toList(),
    );
  }

  // Step-23 — Free / Paid switch + per-plan price inputs + currency.
  // Gated on _isPaidMode so free communities don't see the price
  // boxes. Switching paid → free on save resets both prices to 0,
  // which makes new joiners free again. Existing paid subscribers
  // keep their access until expiry.
  Widget _pricingSection(SocialPalette palette) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isPaidMode
                    ? Icons.workspace_premium_rounded
                    : Icons.public_rounded,
                size: 20,
                color: _isPaidMode
                    ? SocialTokens.gold
                    : SocialTokens.up,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isPaidMode
                          ? 'communityEdit.paidTitle'.tr
                          : 'communityEdit.freeTitle'.tr,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isPaidMode
                          ? 'communityEdit.paidDesc'.tr
                          : 'communityEdit.freeDesc'.tr,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _isPaidMode,
                activeColor: SocialTokens.gold,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _isPaidMode = v);
                },
              ),
            ],
          ),
          if (_isPaidMode) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _priceInput(
                    palette,
                    _monthlyCtl,
                    label: 'communityEdit.monthly'.tr,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _priceInput(
                    palette,
                    _yearlyCtl,
                    label: 'communityEdit.yearly'.tr,
                  ),
                ),
              ],
            ),
            // Live "Save X%" preview — recomputes as the owner types
            // either price. Hidden when the math doesn't apply (only
            // one plan set, or yearly ≥ monthly×12). Subscribes via
            // AnimatedBuilder + Listenable.merge so we don't have to
            // wire two separate addListener calls.
            AnimatedBuilder(
              animation: Listenable.merge([_monthlyCtl, _yearlyCtl]),
              builder: (_, __) {
                final m = _dollarsToCents(_monthlyCtl.text);
                final y = _dollarsToCents(_yearlyCtl.text);
                final pct = PriceFormat.yearlySavingsPercent(m, y);
                if (pct == null) return const SizedBox(height: 10);
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: SocialTokens.up.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: SocialTokens.up.withValues(alpha: 0.40),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.savings_outlined,
                          color: SocialTokens.up,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'communityEdit.yearlySavings'
                                .trParams({'pct': '$pct'}),
                            style: const TextStyle(
                              color: SocialTokens.up,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cur in _currencies)
                  _currencyChip(palette, cur),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'communityEdit.disablePlanHint'.tr,
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

  Widget _priceInput(
    SocialPalette palette,
    TextEditingController ctl, {
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: palette.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: '0',
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(
                Icons.attach_money_rounded,
                color: palette.textMuted,
                size: 16,
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 4, vertical: 10),
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
      ],
    );
  }

  Widget _currencyChip(SocialPalette palette, String code) {
    final selected = _currency == code;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currency = code);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? SocialTokens.gold.withValues(alpha: 0.18)
              : palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? SocialTokens.gold : palette.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          code.toUpperCase(),
          style: TextStyle(
            color: selected ? SocialTokens.gold : palette.textPrimary,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _saveButton(SocialPalette palette) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: SocialTokens.cyan,
          foregroundColor: Colors.black,
          disabledBackgroundColor: palette.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : Text(
                'communityEdit.saveChanges'.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
