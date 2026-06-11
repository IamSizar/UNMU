import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/payout_service.dart';
import '../../services/studio_service.dart';
import 'request_payout_sheet.dart';

/// Phase 3.3 — full-screen earnings view for the expert.
///
/// Pulls /me/expert/earnings on mount, with a window selector (7d /
/// 30d / 90d / 365d). Renders three things:
///   1. Headline tiles: lifetime, active, last-N-days.
///   2. A daily bar chart of revenue.
///   3. A list of the most-recent N days as rows for accessibility
///      (chart-only would fail screen readers).
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  int _days = 30;
  EarningsResponse? _data;
  PayoutsSnapshot? _payouts;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Run both calls in parallel — the screen renders nothing until
    // both resolve so there's no benefit to staggering.
    final results = await Future.wait([
      StudioService.earnings(days: _days),
      PayoutService.mine(),
    ]);
    if (!mounted) return;
    final earnings = results[0] as ({EarningsResponse? earnings, String? error});
    final payouts = results[1] as ({PayoutsSnapshot? snapshot, String? error});
    setState(() {
      _loading = false;
      _data = earnings.earnings;
      _payouts = payouts.snapshot;
      // Surface the first non-null error so we don't bury one behind
      // the other. Payouts is the secondary call — if its error is the
      // generic "not signed in" but earnings worked, we still render
      // the earnings section.
      _error = earnings.error ?? payouts.error;
    });
  }

  Future<void> _cancelPayout(Payout p) async {
    final res = await PayoutService.cancel(p.id);
    if (!mounted) return;
    if (res.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error!)),
      );
      return;
    }
    // Bounce back to the server for a fresh snapshot so the available
    // balance updates too (cancelling frees the held cents).
    await _load();
  }

  Future<void> _openRequestSheet() async {
    final snapshot = _payouts;
    if (snapshot == null) return;
    if (snapshot.availableCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('earnings.noBalanceYet'.tr),
        ),
      );
      return;
    }
    await RequestPayoutSheet.show(
      context,
      availableCents: snapshot.availableCents,
      currency: snapshot.currency,
      onCreated: (_) => _load(),
    );
  }

  Future<void> _switchWindow(int days) async {
    if (_days == days) return;
    setState(() => _days = days);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        title: Text('earnings.title'.tr),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            _WindowSelector(
              days: _days,
              onChange: _switchWindow,
            ),
            const SizedBox(height: 16),
            _TotalsRow(data: data, days: _days, loading: _loading),
            const SizedBox(height: 18),
            Text(
              'earnings.dailyRevenue'.tr,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (data == null || data.history.isEmpty)
                      ? Center(
                          child: Text(
                            'earnings.noRevenueYet'.tr,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : _RevenueChart(data: data),
            ),
            const SizedBox(height: 22),
            _PayoutsSection(
              snapshot: _payouts,
              loading: _loading,
              onRequest: () => _openRequestSheet(),
              onCancel: _cancelPayout,
            ),
            const SizedBox(height: 22),
            Text(
              'earnings.byDay'.tr,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (data == null || data.history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'earnings.noRevenueWindow'.tr,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              ...data.history.reversed.where((p) =>
                  p.revenueCents > 0 || p.newSubs > 0).map(
                    (p) => _DayRow(
                      point: p,
                      currency: data.currency,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─── window selector ────────────────────────────────────────────────────

class _WindowSelector extends StatelessWidget {
  final int days;
  final ValueChanged<int> onChange;
  const _WindowSelector({required this.days, required this.onChange});

  @override
  Widget build(BuildContext context) {
    const options = [7, 30, 90, 365];
    return Wrap(
      spacing: 8,
      children: options.map((opt) {
        final selected = days == opt;
        return ChoiceChip(
          selected: selected,
          onSelected: (_) => onChange(opt),
          label: Text(opt == 365
              ? 'earnings.window1y'.tr
              : 'earnings.windowDays'.trParams({'count': '$opt'})),
        );
      }).toList(),
    );
  }
}

// ─── totals row ─────────────────────────────────────────────────────────

class _TotalsRow extends StatelessWidget {
  final EarningsResponse? data;
  final int days;
  final bool loading;
  const _TotalsRow({
    required this.data,
    required this.days,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final currency = data?.currency ?? 'usd';
    final lifetime = data == null ? '—' : formatCents(data!.lifetimeRevenueCents, currency);
    final active = data == null ? '—' : formatCents(data!.activeRevenueCents, currency);
    final window =
        data == null ? '—' : formatCents(data!.windowRevenueCents, currency);
    return Row(
      children: [
        Expanded(
          child: _TotalCard(
            label: 'earnings.lastNDays'.trParams({'count': '$days'}),
            value: window,
            loading: loading,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TotalCard(
            label: 'earnings.active'.tr,
            value: active,
            loading: loading,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TotalCard(
            label: 'earnings.lifetime'.tr,
            value: lifetime,
            loading: loading,
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String label;
  final String value;
  final bool loading;
  const _TotalCard({
    required this.label,
    required this.value,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  fontSize: 10,
                ),
          ),
          const SizedBox(height: 6),
          loading
              ? SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                ),
        ],
      ),
    );
  }
}

// ─── chart ──────────────────────────────────────────────────────────────

class _RevenueChart extends StatelessWidget {
  final EarningsResponse data;
  const _RevenueChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = data.history;
    if (points.isEmpty) return const SizedBox.shrink();

    final maxDollars = points
        .map((p) => p.revenueCents / 100.0)
        .fold<double>(0, (a, b) => b > a ? b : a);
    // Round the y-axis ceiling to a clean number so bars aren't crammed.
    final yMax = maxDollars <= 0 ? 1.0 : (maxDollars * 1.2);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: yMax,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (points.length / 4).ceilToDouble().clamp(1, 100),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) {
                  return const SizedBox.shrink();
                }
                final day = points[i].day;
                // YYYY-MM-DD → MM/DD
                final parts = day.split('-');
                final label = parts.length == 3
                    ? '${parts[1]}/${parts[2]}'
                    : day;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: cs.surface.withValues(alpha: 0.95),
            getTooltipItem: (group, _, rod, __) {
              final p = points[group.x];
              final subs = 'earnings.subsCount'.trParams({
                'count': '${p.newSubs}',
                'plural': p.newSubs == 1 ? '' : 's',
              });
              return BarTooltipItem(
                '${p.day}\n${formatCents(p.revenueCents, data.currency)} · '
                '$subs',
                TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
        barGroups: List.generate(points.length, (i) {
          final p = points[i];
          final dollars = p.revenueCents / 100.0;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: dollars,
                width: 8,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
                gradient: LinearGradient(
                  colors: [
                    cs.primary,
                    cs.primary.withValues(alpha: 0.5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ─── per-day row ────────────────────────────────────────────────────────

class _DayRow extends StatelessWidget {
  final EarningsDayPoint point;
  final String currency;
  const _DayRow({required this.point, required this.currency});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  point.day,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  'earnings.newSubscribers'.trParams({
                    'count': '${point.newSubs}',
                    'plural': point.newSubs == 1 ? '' : 's',
                  }),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Text(
            formatCents(point.revenueCents, currency),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.primary,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── payouts section (Phase 3.4) ────────────────────────────────────────

class _PayoutsSection extends StatelessWidget {
  final PayoutsSnapshot? snapshot;
  final bool loading;
  final VoidCallback onRequest;
  final Future<void> Function(Payout) onCancel;

  const _PayoutsSection({
    required this.snapshot,
    required this.loading,
    required this.onRequest,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final snap = snapshot;
    final availableLabel = snap == null
        ? '—'
        : formatCents(snap.availableCents, snap.currency);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.account_balance_wallet_outlined,
                    color: cs.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'payout.availableToWithdraw'.tr,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            fontSize: 10,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      availableLabel,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: (snap == null || snap.availableCents <= 0)
                    ? null
                    : onRequest,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text('payout.request'.tr),
              ),
            ],
          ),
          if (snap != null && snap.payouts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: cs.outlineVariant.withValues(alpha: 0.4), height: 1),
            const SizedBox(height: 8),
            ...snap.payouts.map(
              (p) => _PayoutTile(
                payout: p,
                currency: snap.currency,
                onCancel: p.status == 'pending' ? () => onCancel(p) : null,
              ),
            ),
          ] else if (snap != null && !loading) ...[
            const SizedBox(height: 10),
            Text(
              'payout.noRequests'.tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  final Payout payout;
  final String currency;
  final VoidCallback? onCancel;
  const _PayoutTile({
    required this.payout,
    required this.currency,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (statusColor, statusBg, statusLabel) = _statusStyle(payout.status, cs);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      formatCents(payout.amountCents, currency),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 9,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_methodLabel(payout.method)} · ${_dateLabel(payout.requestedAt)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                if (payout.adminNote != null &&
                    payout.adminNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'payout.adminNote'
                        .trParams({'note': '${payout.adminNote}'}),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (onCancel != null)
            TextButton(
              onPressed: onCancel,
              child: Text('common.cancel'.tr),
            ),
        ],
      ),
    );
  }

  (Color, Color, String) _statusStyle(String status, ColorScheme cs) {
    switch (status) {
      case 'paid':
        return (
          Colors.green,
          Colors.green.withValues(alpha: 0.14),
          'payout.statusPaid'.tr,
        );
      case 'rejected':
        return (
          cs.error,
          cs.error.withValues(alpha: 0.14),
          'payout.statusRejected'.tr,
        );
      case 'cancelled':
        return (
          cs.onSurfaceVariant,
          cs.onSurfaceVariant.withValues(alpha: 0.14),
          'payout.statusCancelled'.tr,
        );
      default:
        return (
          cs.primary,
          cs.primary.withValues(alpha: 0.14),
          'payout.statusPending'.tr,
        );
    }
  }

  String _methodLabel(String wire) {
    return PayoutMethodX.fromWire(wire).label;
  }

  String _dateLabel(DateTime t) {
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    return '${t.year}-$m-$d';
  }
}
