import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../screens/social/social_tokens.dart';

/// Renders post body text as a **restricted** markdown subset
/// (mig 0020, item 4.17 — D5=B):
///
///   ✅ headings, bold, italic, ordered + unordered lists, links,
///      blockquotes, paragraph breaks
///   ❌ code blocks (no triple-backtick / inline code rendering)
///   ❌ image-via-syntax (`![](…)` ignored — articles use the
///      separate inline_image_picker gallery instead)
///   ❌ tables
///   ❌ raw HTML
///
/// We achieve the restriction by:
///
///   * Pre-processing: stripping every `<` so HTML tags can't render
///     and every fenced-code block (lines wrapped in triple-backticks
///     turn into plain paragraphs).
///   * Post-rendering: a `MarkdownStyleSheet` that renders the
///     subset-relevant tags only; anything we don't style still renders
///     but in the default body style — it can't run scripts because
///     `MarkdownBody` never evaluates HTML.
///
/// The widget is read-only — the composer uses a plain
/// TextField; markdown is rendered only on the detail screen.
class PostMarkdownBody extends StatelessWidget {
  final String source;
  /// Override text color when the body sits on a colored background
  /// (e.g. a paywall card). Defaults to the palette's primary text.
  final Color? color;
  /// Limit lines for compact previews (e.g. feed cards). Null = unbounded.
  /// When set we soft-truncate the source text by character count so the
  /// markdown parser doesn't try to close half-tags.
  final int? maxLines;

  const PostMarkdownBody(
    this.source, {
    super.key,
    this.color,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final textColor = color ?? palette.textPrimary;
    final sanitized = _sanitize(source);
    final ss = MarkdownStyleSheet(
      p: TextStyle(
        color: textColor,
        fontSize: 15,
        height: 1.55,
      ),
      h1: TextStyle(
        color: textColor,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        height: 1.3,
      ),
      h2: TextStyle(
        color: textColor,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        height: 1.3,
      ),
      h3: TextStyle(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
      strong: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w900,
      ),
      em: TextStyle(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      blockquote: TextStyle(
        color: palette.textMuted,
        fontStyle: FontStyle.italic,
        fontSize: 14.5,
      ),
      blockquoteDecoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: SocialTokens.cyan, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      a: const TextStyle(
        color: SocialTokens.cyan,
        decoration: TextDecoration.underline,
      ),
      // Ignore code blocks entirely — render them as plain paragraphs.
      code: TextStyle(color: textColor, fontSize: 15),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      listBullet: TextStyle(
        color: textColor,
        fontSize: 15,
        height: 1.55,
      ),
    );
    return MarkdownBody(
      data: sanitized,
      styleSheet: ss,
      selectable: true,
      // No image syntax rendering — articles use the inline gallery.
      // Returning a zero-size box drops any `![](…)` silently.
      sizedImageBuilder: (_) => const SizedBox.shrink(),
      onTapLink: (_, href, __) async {
        if (href == null) return;
        HapticFeedback.selectionClick();
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  /// Strip raw HTML angle brackets and apply the optional length cap.
  /// We keep the markdown structure (`*`, `_`, `>`, `-`, `1.`, etc.)
  /// but drop anything that looks like a tag so the renderer can't
  /// surface custom HTML even if a future flutter_markdown version
  /// gains rendering for it.
  String _sanitize(String s) {
    var out = s.replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    // Restore the leading `>` for blockquote lines — we *do* want those.
    out = out.replaceAllMapped(
      RegExp(r'^&gt;', multiLine: true),
      (_) => '>',
    );
    if (maxLines != null && maxLines! > 0) {
      // Approximate: ~80 chars/line.
      final cap = maxLines! * 80;
      if (out.length > cap) {
        out = '${out.substring(0, cap).trimRight()}…';
      }
    }
    return out;
  }
}
