import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/expert_post.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/upload_service.dart';

/// Multi-image picker for the article composer (mig 0020, item 4.18).
///
/// Caller passes a current list of [PostAttachment] and gets:
///
///   * `onAdd(url)`     — fired after a successful upload so the parent
///                         can persist via `ExpertPostService.addAttachment`.
///   * `onRemove(att)`  — fired when the trash icon is tapped so the
///                         parent can call `deleteAttachment`.
///
/// We delegate the actual server PATCH calls to the parent because the
/// composer's "Save draft" / "Update draft" flow may want to batch
/// changes — keeping this widget purely UI lets the parent decide.
///
/// Cap: 5 images. The "+" button greys out when [attachments.length]
/// >= 5; matches the server's 409 behaviour so the user can't even try.
class InlineImagePicker extends StatefulWidget {
  final List<PostAttachment> attachments;
  /// Fires after a fresh image has been uploaded and we have a server
  /// URL ready. Parent should persist via the API and (if successful)
  /// add the new PostAttachment to its list.
  final Future<void> Function(String url) onAdd;
  /// Fires when the user taps the trash icon. Parent should call the
  /// API to delete and remove from its list.
  final Future<void> Function(PostAttachment attachment) onRemove;
  /// Optional max — defaults to 5 to match the server cap. Lower
  /// values are honored for testing.
  final int max;

  const InlineImagePicker({
    super.key,
    required this.attachments,
    required this.onAdd,
    required this.onRemove,
    this.max = 5,
  });

  @override
  State<InlineImagePicker> createState() => _InlineImagePickerState();
}

class _InlineImagePickerState extends State<InlineImagePicker> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    if (widget.attachments.length >= widget.max || _busy) return;
    HapticFeedback.selectionClick();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 88,
    );
    if (picked == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await UploadService.uploadImage(File(picked.path));
    if (!mounted) return;
    if (res.error != null) {
      setState(() {
        _busy = false;
        _error = res.error;
      });
      return;
    }
    await widget.onAdd(res.url ?? '');
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final atCap = widget.attachments.length >= widget.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final a in widget.attachments)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: _Tile(
                    url: a.url,
                    onRemove: () async {
                      HapticFeedback.lightImpact();
                      await widget.onRemove(a);
                    },
                    palette: palette,
                  ),
                ),
              if (!atCap)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: GestureDetector(
                    onTap: _pick,
                    child: Container(
                      width: 88,
                      decoration: BoxDecoration(
                        color: palette.surfaceElevated,
                        border: Border.all(
                          color: palette.border,
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      color: palette.textMuted, size: 22),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${widget.attachments.length}/${widget.max}',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
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
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(
              color: SocialTokens.down,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String url;
  final VoidCallback onRemove;
  final SocialPalette palette;
  const _Tile({
    required this.url,
    required this.onRemove,
    required this.palette,
  });
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: palette.surfaceElevated,
            border: Border.all(color: palette.border),
            image: url.isEmpty
                ? null
                : DecorationImage(
                    image: NetworkImage(url),
                    fit: BoxFit.cover,
                  ),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close,
                    color: Colors.white, size: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
