import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/language_controller.dart';
import '../social/social_tokens.dart';
import 'legal_content.dart';

/// Renders a Privacy Policy / Terms of Service screen from the
/// markdown constants in [legal_content.dart]. One widget for both
/// documents — the caller picks the variant via [LegalDoc].
///
/// The body uses flutter_markdown (already a dep for post articles) so
/// headings, lists, bold, and links render the same way the rest of
/// the app already renders user-written markdown.
///
/// Links open in the OS browser. mailto: links open the mail client.
class LegalScreen extends StatelessWidget {
  final LegalDoc doc;
  const LegalScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final isArabic = Get.find<LanguageController>().isArabic;

    final title = switch (doc) {
      LegalDoc.privacy => 'legal.privacyTitle'.tr,
      LegalDoc.terms => 'legal.termsTitle'.tr,
    };
    final source = switch (doc) {
      LegalDoc.privacy =>
        isArabic ? kPrivacyPolicyAr : kPrivacyPolicyEn,
      LegalDoc.terms =>
        isArabic ? kTermsOfServiceAr : kTermsOfServiceEn,
    };

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(title, style: TextStyle(color: palette.textPrimary)),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: SafeArea(
        child: Markdown(
          data: source,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          selectable: true,
          onTapLink: (text, href, title) => _openLink(href),
          styleSheet: _styleSheet(palette),
        ),
      ),
    );
  }

  Future<void> _openLink(String? href) async {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  MarkdownStyleSheet _styleSheet(SocialPalette palette) {
    final primary = palette.textPrimary;
    final muted = palette.textMuted;
    return MarkdownStyleSheet(
      p: TextStyle(color: primary, fontSize: 14.5, height: 1.6),
      h1: TextStyle(
        color: primary,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        height: 1.3,
        letterSpacing: -0.5,
      ),
      h2: TextStyle(
        color: primary,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        height: 1.4,
        letterSpacing: -0.3,
      ),
      h3: TextStyle(
        color: primary,
        fontSize: 15.5,
        fontWeight: FontWeight.w800,
      ),
      strong: TextStyle(color: primary, fontWeight: FontWeight.w900),
      em: TextStyle(color: primary, fontStyle: FontStyle.italic),
      a: const TextStyle(
        color: SocialTokens.cyan,
        decoration: TextDecoration.underline,
      ),
      listBullet: TextStyle(color: muted, fontSize: 14.5, height: 1.6),
      blockSpacing: 14,
      h1Padding: const EdgeInsets.only(top: 4, bottom: 8),
      h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 4),
    );
  }
}

enum LegalDoc { privacy, terms }
