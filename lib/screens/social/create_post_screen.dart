import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../models/expert_post.dart' as backend;
import '../../services/expert_post_service.dart';
import '../../widgets/auth/auth_widgets.dart';
import 'mock_social_data.dart';
import 'social_tokens.dart';

/// Two flavors of post composer, both presented as a full-screen sheet:
///
///   - [CreatePostScreen.community] for posting **into a community**
///       Form: title + body + ticker + BUY/HOLD/SELL stance
///   - [CreatePostScreen.expert] for posting **on your expert profile**
///       Form: body + tickers (comma-separated)
///
/// The composer mutates the in-memory mock dataset on submit; replace the
/// final write with an API call once the backend is wired up.
class CreatePostScreen extends StatefulWidget {
  /// Community we're posting INTO. Mutually exclusive with [expert].
  final Community? community;

  /// Expert profile we're posting ON. Mutually exclusive with [community].
  final Expert? expert;

  const CreatePostScreen.community({super.key, required this.community})
      : expert = null;

  const CreatePostScreen.expert({super.key, required this.expert})
      : community = null;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _ticker = TextEditingController();
  String _stance = 'BUY';
  bool _submitting = false;

  bool get _isCommunity => widget.community != null;
  Color get _accent => _isCommunity
      ? SocialTokens.regionColor(widget.community!.regionCode)
      : SocialTokens.cyan;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _ticker.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_isCommunity) {
      return _title.text.trim().isNotEmpty &&
          _body.text.trim().isNotEmpty &&
          _ticker.text.trim().isNotEmpty;
    } else {
      return _body.text.trim().isNotEmpty;
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();

    // Sprint-B step 17 — talk to the real backend instead of mutating
    // `MockSocialData`. Parent screen (community_detail / expert_profile)
    // re-fetches on pop=true so the new post appears without an in-
    // memory mock insert.
    String? error;
    if (_isCommunity) {
      final c = widget.community!;
      final ticker = _ticker.text.trim().toUpperCase();
      final tickers = ticker.isEmpty ? const <String>[] : [ticker];
      final res = await ExpertPostService.createCommunityPost(
        communityId: c.id,
        type: backend.PostType.article,
        visibility: backend.PostVisibility.public,
        title: _title.text.trim(),
        body: _body.text.trim(),
        ticker: ticker,
        stance: _stance,
        tickers: tickers,
      );
      error = res.error;
    } else {
      final e = widget.expert!;
      final tickers = _ticker.text
          .trim()
          .split(RegExp(r'[\s,]+'))
          .where((t) => t.isNotEmpty)
          .map((t) => t.toUpperCase())
          .toList();
      final res = await ExpertPostService.create(
        expertId: e.id,
        type: backend.PostType.article,
        visibility: backend.PostVisibility.public,
        title: null,
        body: _body.text.trim(),
        tickers: tickers,
      );
      error = res.error;
    }

    if (!mounted) return;
    if (error != null) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.of(context).pop(true); // signals "post created" — parent refetches
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: palette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isCommunity ? 'createPost.newPost'.tr : 'createPost.shareResearch'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: TextButton(
              onPressed: _canSubmit && !_submitting ? _submit : null,
              style: TextButton.styleFrom(
                foregroundColor: SocialTokens.cyan,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: SocialTokens.cyan,
                        strokeWidth: 2,
                      ),
                    )
                  : Text('createPost.post'.tr),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _contextChip(palette),
              const SizedBox(height: 20),
              if (_isCommunity) ...[
                AuthField(
                  controller: _title,
                  label: 'createPost.title'.tr,
                  hint: 'createPost.titleHint'.tr,
                  icon: Icons.title_rounded,
                  accent: SocialTokens.cyan,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
              ],
              _bodyField(palette),
              const SizedBox(height: 12),
              AuthField(
                controller: _ticker,
                label: _isCommunity
                    ? 'createPost.tickerLabel'.tr
                    : 'createPost.tickersLabel'.tr,
                hint: _isCommunity ? 'ARAMCO' : 'AAPL, NVDA',
                icon: Icons.show_chart_rounded,
                accent: SocialTokens.gold,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.text,
              ),
              if (_isCommunity) ...[
                const SizedBox(height: 16),
                _stancePicker(palette),
              ],
              const SizedBox(height: 28),
              GradientCTA(
                label: 'createPost.publish'.tr,
                trailingIcon: Icons.send_rounded,
                enabled: _canSubmit,
                loading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contextChip(SocialPalette palette) {
    final accent = _accent;
    final label = _isCommunity
        ? 'createPost.postingTo'.trParams({'name': widget.community!.name})
        : 'createPost.postingOn'.trParams({'name': widget.expert!.name});
    final icon = _isCommunity
        ? Icons.groups_rounded
        : Icons.workspace_premium_rounded;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.55)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: const Color(0xFF0A1628), size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyField(SocialPalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SocialTokens.cyan.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: SocialTokens.cyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'createPost.bodyLabel'.tr,
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 12,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14.5,
              height: 1.45,
            ),
            decoration: InputDecoration(
              hintText: _isCommunity
                  ? 'createPost.bodyHintCommunity'.tr
                  : 'createPost.bodyHintExpert'.tr,
              hintStyle: TextStyle(color: palette.textMuted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _stancePicker(SocialPalette palette) {
    final options = <_StanceChoice>[
      _StanceChoice('BUY', Icons.trending_up_rounded, SocialTokens.up),
      _StanceChoice('HOLD', Icons.balance_rounded, SocialTokens.gold),
      _StanceChoice('SELL', Icons.trending_down_rounded, SocialTokens.down),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
          child: Text(
            'createPost.stanceLabel'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Row(
          children: options.map((o) {
            final selected = _stance == o.code;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: o.code == 'SELL' ? 0 : 8,
                ),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _stance = o.code);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? o.color.withValues(alpha: 0.18)
                          : palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? o.color : palette.border,
                        width: selected ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          o.icon,
                          size: 16,
                          color: selected ? o.color : palette.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          o.code,
                          style: TextStyle(
                            color:
                                selected ? o.color : palette.textSecondary,
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _StanceChoice {
  final String code;
  final IconData icon;
  final Color color;
  const _StanceChoice(this.code, this.icon, this.color);
}
