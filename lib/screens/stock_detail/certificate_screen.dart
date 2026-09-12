import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../screens/social/social_tokens.dart';
import '../../services/api_service.dart';
import '../../utils/haptic_utils.dart';

/// Compliance certificate — a dated, methodology-versioned record for one
/// stock, meant to be screenshotted/shared as evidence of a compliance
/// claim. Backend: GET /api/stocks/:ticker/certificate (public, no auth),
/// added earlier this session with no UI until now.
class CertificateScreen extends StatefulWidget {
  const CertificateScreen({super.key, required this.ticker, required this.exchange});

  final String ticker;
  final String exchange;

  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  Map<String, dynamic>? _certificate;
  bool _loading = true;
  bool _failed = false;
  // Distinguishes "no screening on record for this stock" (backend 404 —
  // retrying the same request won't help) from a transient network/server
  // failure (retry might). ApiService.getComplianceCertificate reports
  // this via CertificateResult.notFound.
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final result = await ApiService.getComplianceCertificate(widget.ticker, widget.exchange);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _certificate = result.data;
      _failed = result.data == null;
      _notFound = result.notFound;
    });
  }

  Future<void> _share() async {
    final c = _certificate;
    if (c == null) return;
    final stock = c['stock'] as Map<String, dynamic>?;
    final status = c['shariah_status'] as Map<String, dynamic>?;
    HapticUtils.lightTap();
    await Share.share(
      'certificate.shareText'.trParams({
        'ticker': stock?['ticker']?.toString() ?? widget.ticker,
        'status': status?['status']?.toString() ?? '',
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'certificate.title'.tr,
          style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w800),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
        actions: [
          if (_certificate != null)
            IconButton(
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: _share,
              tooltip: 'referral.share'.tr,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? _ErrorState(palette: palette, notFound: _notFound, onRetry: _load)
              : _buildCertificate(palette),
    );
  }

  Widget _buildCertificate(SocialPalette palette) {
    final c = _certificate!;
    final stock = c['stock'] as Map<String, dynamic>? ?? {};
    final status = c['shariah_status'] as Map<String, dynamic>? ?? {};
    final methodology = c['methodology_version'] as Map<String, dynamic>? ?? {};
    final disclaimer = c['methodology_disclaimer']?.toString() ?? '';
    final issuedAt = c['issued_at']?.toString();

    final statusStr = (status['status'] as String?) ?? 'UNKNOWN';
    final statusColor = switch (statusStr) {
      'HALAL' => SocialTokens.up,
      'HARAM' => SocialTokens.down,
      _ => SocialTokens.gold,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      physics: const BouncingScrollPhysics(),
      children: [
        // ── Certificate card ──
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_rounded, color: statusColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'certificate.eyebrow'.tr,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${stock['ticker'] ?? widget.ticker}',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                ),
              ),
              Text(
                '${stock['name'] ?? ''}',
                style: TextStyle(color: palette.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusStr,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
                    ),
                    if (status['grade'] != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${'certificate.grade'.trParams({'grade': '${status['grade']}'})}',
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (status['debt_ratio'] != null)
                _CertRow(
                  palette: palette,
                  label: 'certificate.debtRatio'.tr,
                  value: '${(status['debt_ratio'] as num).toStringAsFixed(2)}%',
                ),
              if (status['haram_income_ratio'] != null)
                _CertRow(
                  palette: palette,
                  label: 'certificate.haramIncomeRatio'.tr,
                  value: '${(status['haram_income_ratio'] as num).toStringAsFixed(2)}%',
                ),
              if (status['as_of_date'] != null)
                _CertRow(
                  palette: palette,
                  label: 'certificate.asOfDate'.tr,
                  value: '${status['as_of_date']}',
                ),
              if (issuedAt != null)
                _CertRow(
                  palette: palette,
                  label: 'certificate.issuedAt'.tr,
                  value: _formatIssuedAt(issuedAt),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Methodology ──
        Text(
          'certificate.methodologyTitle'.tr,
          style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (methodology['debt_ratio_hard_fail'] != null)
                _CertRow(
                  palette: palette,
                  label: 'certificate.debtHardFail'.tr,
                  value: '${methodology['debt_ratio_hard_fail']}%',
                ),
              if (methodology['haram_income_hard_fail'] != null)
                _CertRow(
                  palette: palette,
                  label: 'certificate.haramHardFail'.tr,
                  value: '${methodology['haram_income_hard_fail']}%',
                ),
            ],
          ),
        ),
        if (disclaimer.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            disclaimer,
            style: TextStyle(color: palette.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ],
    );
  }

  String _formatIssuedAt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _CertRow extends StatelessWidget {
  const _CertRow({required this.palette, required this.label, required this.value});
  final SocialPalette palette;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: palette.textSecondary, fontSize: 13)),
          Text(
            value,
            style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.palette, required this.notFound, required this.onRetry});
  final SocialPalette palette;
  final bool notFound;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notFound ? Icons.search_off_rounded : Icons.error_outline_rounded,
              size: 48,
              color: notFound ? SocialTokens.gold : SocialTokens.down,
            ),
            const SizedBox(height: 16),
            Text(
              (notFound ? 'certificate.notFound' : 'certificate.errorLoading').tr,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            // A 404 (no screening on record) won't change on retry, so
            // only offer it for the genuinely transient case.
            if (!notFound)
              OutlinedButton(onPressed: onRetry, child: Text('common.refresh'.tr)),
          ],
        ),
      ),
    );
  }
}
