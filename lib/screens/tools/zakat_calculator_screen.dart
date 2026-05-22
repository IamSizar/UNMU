import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/currency_controller.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/api_service.dart';
import '../../utils/haptic_utils.dart';

/// =============================================================================
/// Zakat Calculator — modern fintech form.
///
///   ▸ Themed app bar
///   ▸ Pill-style tab switcher (Manual · Portfolio)
///   ▸ Hero result card at top (gold-tinted) showing zakat due
///   ▸ Inputs styled as the rest of the app
///   ▸ Big calculate button with cyan gradient
/// =============================================================================
class ZakatCalculatorScreen extends StatefulWidget {
  const ZakatCalculatorScreen({super.key});

  @override
  State<ZakatCalculatorScreen> createState() => _ZakatCalculatorScreenState();
}

class _ZakatCalculatorScreenState extends State<ZakatCalculatorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Manual inputs
  final _cash = TextEditingController();
  final _gold = TextEditingController();
  final _shares = TextEditingController();
  final _other = TextEditingController();
  double _manualZakat = 0;
  double _manualTotal = 0;

  // Portfolio
  Map<String, dynamic>? _portfolio;
  bool _loadingPortfolio = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadPortfolio();
  }

  @override
  void dispose() {
    _tab.dispose();
    _cash.dispose();
    _gold.dispose();
    _shares.dispose();
    _other.dispose();
    super.dispose();
  }

  void _calculateManual() {
    final c = double.tryParse(_cash.text) ?? 0;
    final g = double.tryParse(_gold.text) ?? 0;
    final s = double.tryParse(_shares.text) ?? 0;
    final o = double.tryParse(_other.text) ?? 0;
    final total = c + g + s + o;
    setState(() {
      _manualTotal = total;
      _manualZakat = total * 0.025;
    });
    HapticUtils.success();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _loadPortfolio() async {
    final auth = Get.find<AuthController>();
    if (!auth.isAuthenticated) return;
    setState(() => _loadingPortfolio = true);
    try {
      final data = await ApiService.calculateZakat(auth.token!);
      if (mounted) {
        setState(() {
          _portfolio = data;
          _loadingPortfolio = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPortfolio = false);
    }
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
          'zakat.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: Column(
        children: [
          // Pill-style segmented control
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _PillTabs(
              palette: palette,
              controller: _tab,
              labels: [
                'zakat.tabManual'.tr,
                'zakat.tabPortfolio'.tr,
              ],
              icons: const [
                Icons.edit_rounded,
                Icons.bookmark_rounded,
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildManualTab(palette),
                _buildPortfolioTab(palette),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Manual tab ───────────────────────────────────────────────────────────
  Widget _buildManualTab(SocialPalette palette) {
    final cur = Get.find<CurrencyController>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      physics: const BouncingScrollPhysics(),
      children: [
        // Result hero (always visible — shows 0 before calculation)
        _ZakatResultHero(
          palette: palette,
          totalAssets: _manualTotal,
          zakatDue: _manualZakat,
          formatPrice: cur.formatPrice,
        ),
        const SizedBox(height: 18),
        _MiniSectionHeader(
          palette: palette,
          eyebrow: 'zakat.assetsEyebrow'.tr,
          title: 'zakat.assetsTitle'.tr,
        ),
        const SizedBox(height: 12),
        // Inputs card
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            gradient: palette.cardGradient(),
            borderRadius: BorderRadius.circular(18),
            border: palette.highlightedBorder(),
            boxShadow: palette.cardShadow(),
          ),
          child: Column(
            children: [
              _MoneyInput(
                palette: palette,
                controller: _cash,
                label: 'zakat.cashBank'.tr,
                icon: Icons.attach_money_rounded,
                accent: SocialTokens.up,
                prefix: cur.selectedCurrency.symbol,
              ),
              const SizedBox(height: 12),
              _MoneyInput(
                palette: palette,
                controller: _gold,
                label: 'zakat.goldSilver'.tr,
                icon: Icons.workspace_premium_rounded,
                accent: SocialTokens.gold,
                prefix: cur.selectedCurrency.symbol,
              ),
              const SizedBox(height: 12),
              _MoneyInput(
                palette: palette,
                controller: _shares,
                label: 'zakat.sharesTrading'.tr,
                icon: Icons.show_chart_rounded,
                accent: SocialTokens.cyan,
                prefix: cur.selectedCurrency.symbol,
              ),
              const SizedBox(height: 12),
              _MoneyInput(
                palette: palette,
                controller: _other,
                label: 'zakat.otherAssets'.tr,
                icon: Icons.account_balance_wallet_rounded,
                accent: const Color(0xFF8B5CF6),
                prefix: cur.selectedCurrency.symbol,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _CalculateButton(
          label: 'zakat.calculate'.tr,
          onPressed: _calculateManual,
        ),
        const SizedBox(height: 16),
        _NisabNote(palette: palette),
      ],
    );
  }

  // ── Portfolio tab ────────────────────────────────────────────────────────
  Widget _buildPortfolioTab(SocialPalette palette) {
    final auth = Get.find<AuthController>();
    final cur = Get.find<CurrencyController>();

    if (!auth.isAuthenticated) {
      return _CenteredEmpty(
        palette: palette,
        icon: Icons.lock_outline_rounded,
        accent: SocialTokens.gold,
        title: 'zakat.pleaseLogin'.tr,
        subtitle: '',
      );
    }

    if (_loadingPortfolio) {
      return const Center(
        child: CircularProgressIndicator(color: SocialTokens.cyan),
      );
    }

    final data = _portfolio ?? {'total_zakat': 0.0, 'breakdown': []};
    final total = (data['total_zakat'] as num?)?.toDouble() ?? 0.0;
    final breakdown = (data['breakdown'] as List?) ?? [];

    if (total == 0 && breakdown.isEmpty) {
      return _CenteredEmpty(
        palette: palette,
        icon: Icons.show_chart_rounded,
        accent: SocialTokens.cyan,
        title: 'zakat.noZakatDue'.tr,
        subtitle: 'zakat.noZakatDueSubtitle'.tr,
        ctaLabel: 'common.refresh'.tr,
        onCta: _loadPortfolio,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      physics: const BouncingScrollPhysics(),
      children: [
        _ZakatResultHero(
          palette: palette,
          totalAssets: total / 0.025, // back-calculate ~total assets
          zakatDue: total,
          formatPrice: cur.formatPrice,
        ),
        const SizedBox(height: 18),
        if (breakdown.isNotEmpty) ...[
          _MiniSectionHeader(
            palette: palette,
            eyebrow: 'zakat.breakdownEyebrow'.tr,
            title: 'zakat.perHolding'.tr,
          ),
          const SizedBox(height: 12),
          ...breakdown.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BreakdownRow(
                palette: palette,
                title: item['name']?.toString() ?? '',
                subtitle: 'zakat.sharesCount'.trParams({
                  'count': '${item['shares']}',
                }),
                value: cur.formatPrice(
                  ((item['zakat_amount'] ?? 0.0) as num).toDouble(),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// Pill-style segmented tabs
// ============================================================================
class _PillTabs extends StatelessWidget {
  final SocialPalette palette;
  final TabController controller;
  final List<String> labels;
  final List<IconData> icons;
  const _PillTabs({
    required this.palette,
    required this.controller,
    required this.labels,
    required this.icons,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: AnimatedBuilder(
        animation: controller.animation!,
        builder: (_, __) {
          final t = controller.animation!.value;
          return Stack(
            children: [
              // Sliding indicator pill
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment(2 * t - 1, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / labels.length,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: SocialTokens.cyan.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: List.generate(labels.length, (i) {
                  final selected = controller.index == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => controller.animateTo(i),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icons[i],
                              size: 14,
                              color: selected
                                  ? const Color(0xFF0A1628)
                                  : palette.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              labels[i],
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFF0A1628)
                                    : palette.textSecondary,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// Result hero — gold-themed card showing zakat due
// ============================================================================
class _ZakatResultHero extends StatelessWidget {
  final SocialPalette palette;
  final double totalAssets;
  final double zakatDue;
  final String Function(double) formatPrice;
  const _ZakatResultHero({
    required this.palette,
    required this.totalAssets,
    required this.zakatDue,
    required this.formatPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: SocialTokens.gold.withValues(alpha: 0.45),
          width: 1.4,
        ),
        boxShadow: palette.cardShadow(accent: SocialTokens.gold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: SocialTokens.gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: SocialTokens.gold.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.workspace_premium_rounded,
                      size: 11,
                      color: SocialTokens.gold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'zakat.eyebrow'.tr.toUpperCase(),
                      style: const TextStyle(
                        color: SocialTokens.gold,
                        fontWeight: FontWeight.w900,
                        fontSize: 9.5,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'zakat.due'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatPrice(zakatDue),
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 36,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 1,
            color: palette.subtleDivider,
            margin: const EdgeInsets.symmetric(vertical: 10),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'zakat.totalAssets'.tr,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPrice(totalAssets),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 30, color: palette.subtleDivider),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'zakat.rate'.tr,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '2.5%',
                      style: TextStyle(
                        color: SocialTokens.gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MoneyInput — labeled text field with accent icon tile + currency prefix
// ============================================================================
class _MoneyInput extends StatelessWidget {
  final SocialPalette palette;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color accent;
  final String prefix;

  const _MoneyInput({
    required this.palette,
    required this.controller,
    required this.label,
    required this.icon,
    required this.accent,
    required this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '0',
                    hintStyle: TextStyle(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                    prefixText: '$prefix ',
                    prefixStyle: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Calculate button — full-width cyan gradient pill with glow
// ============================================================================
class _CalculateButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const _CalculateButton({
    required this.label,
    required this.onPressed,
    // `loading` is wired through to a spinner state — kept available
    // for future callers even though every current callsite uses
    // the default. Suppressed so the analyzer doesn't flag it.
    // ignore: unused_element_parameter
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: SocialTokens.cyan.withValues(alpha: 0.45),
            blurRadius: 18,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Color(0xFF0A1628),
                      strokeWidth: 2.4,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFF0A1628),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFF0A1628),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 0.3,
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

// ============================================================================
// Section header
// ============================================================================
class _MiniSectionHeader extends StatelessWidget {
  final SocialPalette palette;
  final String eyebrow;
  final String title;
  const _MiniSectionHeader({
    required this.palette,
    required this.eyebrow,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: SocialTokens.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Nisab info note
// ============================================================================
class _NisabNote extends StatelessWidget {
  final SocialPalette palette;
  const _NisabNote({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.subtleDivider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: SocialTokens.cyan,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'zakat.nisabNote'.tr,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11.5,
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
// Centered empty / unauth states
// ============================================================================
class _CenteredEmpty extends StatelessWidget {
  final SocialPalette palette;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  const _CenteredEmpty({
    required this.palette,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 12.5),
              ),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onCta,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  ctaLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SocialTokens.cyan,
                  side: const BorderSide(color: SocialTokens.cyan, width: 1.4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Per-holding breakdown row
// ============================================================================
class _BreakdownRow extends StatelessWidget {
  final SocialPalette palette;
  final String title;
  final String subtitle;
  final String value;
  const _BreakdownRow({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SocialTokens.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              size: 18,
              color: SocialTokens.gold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: SocialTokens.gold,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
