import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../localization/locale_format.dart';
import '../../models/expert_post.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/expert_post_service.dart';

/// Bottom sheet that lists every saved snapshot of a post (mig 0020,
/// item 4.16).
///
/// Owner + admin only — anyone else gets 403 from the server, which
/// surfaces as an error inside the sheet (not a hard route block).
///
/// Each row shows the prior title (when applicable), prior body
/// (truncated to ~3 lines), prior tickers, and the timestamp. Tap a
/// row to expand the body inline; the sheet itself doesn't restore
/// the version (that would be destructive without a confirm — kept
/// out of v1 per scope).
class PostHistorySheet extends StatefulWidget {
  /// The post id whose history to show.
  final int postId;

  const PostHistorySheet({super.key, required this.postId});

  static Future<void> show(BuildContext context, {required int postId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PostHistorySheet(postId: postId),
    );
  }

  @override
  State<PostHistorySheet> createState() => _PostHistorySheetState();
}

class _PostHistorySheetState extends State<PostHistorySheet> {
  bool _loading = true;
  String? _error;
  List<PostVersion> _versions = const [];
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final res = await ExpertPostService.listHistory(widget.postId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _versions = res.versions ?? const [];
      _error = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final h = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.85),
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
            Expanded(child: _body(palette)),
          ],
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
            const Icon(Icons.history_rounded, color: SocialTokens.cyan),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'postHistory.editHistory'.tr,
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

  Widget _body(SocialPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SocialTokens.down),
          ),
        ),
      );
    }
    if (_versions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note_rounded,
                  size: 48, color: palette.textMuted),
              const SizedBox(height: 10),
              Text(
                'postHistory.noEdits'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: _versions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final v = _versions[i];
        final expanded = _expanded.contains(v.id);
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() {
              if (expanded) {
                _expanded.remove(v.id);
              } else {
                _expanded.add(v.id);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 13, color: palette.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      _relTime(v.editedAt),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: palette.textMuted,
                      size: 18,
                    ),
                  ],
                ),
                if (v.title.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    v.title,
                    maxLines: expanded ? null : 1,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  v.body,
                  maxLines: expanded ? null : 3,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                if (v.tickers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: v.tickers
                        .map((t) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: palette.border),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _relTime(DateTime t) => LocaleFormat.relative(t);
}
