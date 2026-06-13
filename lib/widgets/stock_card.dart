import 'package:flutter/material.dart';
import '../theme/halal_fintech_theme.dart';
import '../utils/stock_logo_utils.dart';
import 'common/app_network_image.dart';
import 'package:get/get.dart';

class StockCard extends StatelessWidget {
  final Map<String, dynamic> stock;

  const StockCard({super.key, required this.stock});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final shariahStatus = stock['shariah_status'] as Map<String, dynamic>?;
    final status = shariahStatus?['status']?.toString() ?? 'UNKNOWN';
    final statusColor = HalalFintechTheme.getStatusColor(status);

    final stockName =
        stock['name']?.toString() ?? stock['ticker']?.toString() ?? '';
    final ticker = stock['ticker']?.toString() ?? '';
    final sector = stock['sector']?.toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? HalalFintechTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? HalalFintechTheme.cardBorderDark
              : HalalFintechTheme.cardBorderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.28)
                : const Color(0xFF152033).withValues(alpha: 0.06),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: null, // Handled by parent
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _buildStockLogo(
                  ticker,
                  stock['exchange']?.toString(),
                  statusColor,
                  isDark,
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stockName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? HalalFintechTheme.textPrimaryDark
                              : HalalFintechTheme.textPrimaryLight,
                          letterSpacing: 0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : HalalFintechTheme.mutedBlue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ticker,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? HalalFintechTheme.textSecondaryDark
                                    : HalalFintechTheme.inkBlue,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          if (sector != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                sector,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.6)
                                      : Colors.black.withValues(alpha: 0.5),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: isDark ? 0.16 : 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    shariahStatus?['grade'] != null
                        ? '${'stockCard.grade'.tr} ${shariahStatus!['grade']}'
                        : _getStatusLabel(status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'HALAL':
        return 'stockCard.halal'.tr;
      case 'HARAM':
      case 'NOT_HALAL':
        return 'stockCard.haram'.tr;
      case 'MIXED':
        return 'stockCard.mixed'.tr;
      default:
        return 'stockCard.unknown'.tr;
    }
  }

  Widget _buildStockLogo(
    String ticker,
    String? exchange,
    Color fallbackColor,
    bool isDark,
  ) {
    final logoUrl = StockLogoUtils.getStockLogoUrl(ticker, exchange: exchange);
    final firstLetter = ticker.isNotEmpty
        ? ticker.substring(0, 1).toUpperCase()
        : '?';

    // Colored letter-circle — shown on a missing / failed logo.
    final letterCircle = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(color: fallbackColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        firstLetter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: fallbackColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: fallbackColor.withValues(alpha: 0.18)),
      ),
      child: ClipOval(
        // AppNetworkImage instead of a raw Image.network: a soft shimmer +
        // fade-in (no per-card CircularProgressIndicator spinning across the
        // whole list), and the in-memory image cache means a logo scrolled
        // back into view is instant and isn't re-fetched.
        child: AppNetworkImage(
          logoUrl,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          placeholderColor: fallbackColor.withValues(alpha: 0.10),
          errorWidget: letterCircle,
        ),
      ),
    );
  }
}
