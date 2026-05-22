import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../screens/social/social_tokens.dart';

/// Modal sheet to compose a chat poll (mig 0021, item 5.21).
///
/// Returns a [PollCreationResult] on submit, or null if dismissed.
/// Caller passes the result to `CommunityMessagesService.createPoll`.
class PollCreatorSheet extends StatefulWidget {
  const PollCreatorSheet({super.key});

  static Future<PollCreationResult?> show(BuildContext context) {
    return showModalBottomSheet<PollCreationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PollCreatorSheet(),
    );
  }

  @override
  State<PollCreatorSheet> createState() => _PollCreatorSheetState();
}

class _PollCreatorSheetState extends State<PollCreatorSheet> {
  final _question = TextEditingController();
  final List<TextEditingController> _opts = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _isAnonymous = false;
  int _expiresInHours = 24; // 0 = open-ended
  String? _error;

  static const _expirationOptions = [
    (0, 'pollCreator.durationOpen'),
    (1, 'pollCreator.duration1Hour'),
    (24, 'pollCreator.duration24Hours'),
    (168, 'pollCreator.duration7Days'),
  ];

  @override
  void dispose() {
    _question.dispose();
    for (final c in _opts) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_opts.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => _opts.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_opts.length <= 2) return;
    HapticFeedback.lightImpact();
    setState(() {
      _opts.removeAt(i).dispose();
    });
  }

  void _submit() {
    final q = _question.text.trim();
    if (q.isEmpty || q.length > 200) {
      setState(() => _error = 'pollCreator.errQuestionLength'.tr);
      return;
    }
    final cleanOpts = <String>[];
    final seen = <String>{};
    for (final c in _opts) {
      final t = c.text.trim();
      if (t.isEmpty) continue;
      if (t.length > 60) {
        setState(() => _error = 'pollCreator.errOptionLength'.tr);
        return;
      }
      if (!seen.add(t.toLowerCase())) {
        setState(() => _error = 'pollCreator.errDuplicate'.tr);
        return;
      }
      cleanOpts.add(t);
    }
    if (cleanOpts.length < 2) {
      setState(() => _error = 'pollCreator.errMinOptions'.tr);
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      PollCreationResult(
        question: q,
        options: cleanOpts,
        isAnonymous: _isAnonymous,
        expiresInHours: _expiresInHours,
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
        constraints: BoxConstraints(maxHeight: h * 0.88),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
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
                      _label(palette, 'pollCreator.question'.tr),
                      _textField(palette, _question,
                          hint: 'pollCreator.questionHint'.tr,
                          maxLen: 200),
                      const SizedBox(height: 18),
                      _label(palette, 'pollCreator.options'.tr),
                      for (var i = 0; i < _opts.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _textField(palette, _opts[i],
                                    hint: 'pollCreator.optionHint'
                                        .trParams({'n': '${i + 1}'}),
                                    maxLen: 60),
                              ),
                              if (_opts.length > 2)
                                IconButton(
                                  onPressed: () => _removeOption(i),
                                  icon: Icon(
                                    Icons.remove_circle_outline_rounded,
                                    color: palette.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (_opts.length < 4)
                        TextButton.icon(
                          onPressed: _addOption,
                          icon: const Icon(Icons.add_rounded),
                          label: Text('pollCreator.addOption'.tr),
                        ),
                      const SizedBox(height: 10),
                      _label(palette, 'pollCreator.duration'.tr),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final entry in _expirationOptions)
                            ChoiceChip(
                              label: Text(entry.$2.tr),
                              selected: _expiresInHours == entry.$1,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setState(() => _expiresInHours = entry.$1);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: palette.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.visibility_off_rounded,
                                color: palette.textMuted, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'pollCreator.anonymousTitle'.tr,
                                    style: TextStyle(
                                      color: palette.textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'pollCreator.anonymousSubtitle'.tr,
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _isAnonymous,
                              activeColor: SocialTokens.cyan,
                              onChanged: (v) {
                                HapticFeedback.selectionClick();
                                setState(() => _isAnonymous = v);
                              },
                            ),
                          ],
                        ),
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
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SocialTokens.cyan,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _submit,
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            'pollCreator.postPoll'.tr,
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
            const Icon(Icons.bar_chart_rounded, color: SocialTokens.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'pollCreator.title'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
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
    required String hint,
    int maxLen = 200,
  }) {
    return TextField(
      controller: ctl,
      maxLength: maxLen,
      style: TextStyle(color: palette.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: palette.textMuted.withValues(alpha: 0.7)),
        counterText: '',
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
          borderSide: const BorderSide(color: SocialTokens.cyan, width: 1.4),
        ),
      ),
    );
  }
}

/// Result returned by [PollCreatorSheet.show]. Caller passes this to
/// the createPoll service call as-is.
class PollCreationResult {
  final String question;
  final List<String> options;
  final bool isAnonymous;
  final int expiresInHours;
  const PollCreationResult({
    required this.question,
    required this.options,
    required this.isAnonymous,
    required this.expiresInHours,
  });
}
