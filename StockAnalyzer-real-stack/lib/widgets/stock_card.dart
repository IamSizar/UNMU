import 'package:flutter/material.dart';
import '../theme/halal_fintech_theme.dart';
import '../localization/halal_strings.dart';
import '../providers/language_provider.dart';
import '../utils/stock_logo_utils.dart';
import 'package:provider/provider.dart';

class StockCard extends StatelessWidget {
  final Map<String, dynamic> stock;

  const StockCard({super.key, required this.stock});

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LanguageProvider>().isArabic;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final shariahStatus = stock['shariah_status'] as Map<String, dynamic>?;
    final status = shariahStatus?['status']?.toString() ?? 'UNKNOWN';
    final statusColor = HalalFintechTheme.getStatusColor(status);

    final stockName =
        stock['name']?.toString() ?? stock['ticker']?.toString() ?? '';
    final ticker = stock['ticker']?.toString() ?? '';
    final sector = stock['sector']?.toString();

    // Fintech-style floating card with green accent glow
    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12,
      ), // Horizontal margins for floating effect
      decoration: BoxDecoration(
        color: isDark ? HalalFintechTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(
          16,
        ), // Rounded corners for floating effect
        // Floating effect with enhanced shadows and green glow
        boxShadow: [
          // Main floating shadow
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          // Secondary shadow for depth
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
          // Green accent glow on all sides (contained with negative spread)
          BoxShadow(
            color: HalalFintechTheme.accentGreen.withValues(alpha: 0.25),
            blurRadius: 16,
            spreadRadius: -4, // Negative spread keeps glow inside card
            offset: const Offset(0, 0),
          ),
          // Additional green glow for more visibility
          BoxShadow(
            color: HalalFintechTheme.accentGreen.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: -2,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: null, // Handled by parent
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                // Stock logo or colored circle fallback
                _buildStockLogo(
                  ticker,
                  stock['exchange']?.toString(),
                  statusColor,
                  isDark,
                ),
                const SizedBox(width: 16),

                // Stock Info - Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stock Name
                      Text(
                        stockName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Ticker and Sector
                      Row(
                        children: [
                          Text(
                            ticker,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.6)
                                  : Colors.black.withValues(alpha: 0.5),
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (sector != null) ...[
                            Text(
                              ' • ',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.4),
                              ),
                            ),
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

                // Status indicator - Right side
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status text
                    Text(
                      shariahStatus?['grade'] != null
                          ? '${isArabic ? HalalStringsAr.grade : HalalStrings.grade} ${shariahStatus!['grade']}'
                          : _getStatusLabel(status, isArabic),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            FontWeight.w700, // Slightly bolder for grade
                        color: statusColor,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusLabel(String status, bool isArabic) {
    switch (status.toUpperCase()) {
      case 'HALAL':
        return isArabic ? HalalStringsAr.halal : HalalStrings.halal;
      case 'HARAM':
      case 'NOT_HALAL':
        return isArabic ? HalalStringsAr.haram : HalalStrings.haram;
      case 'MIXED':
        return isArabic ? HalalStringsAr.mixed : HalalStrings.mixed;
      default:
        return isArabic ? HalalStringsAr.unknown : HalalStrings.unknown;
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

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: fallbackColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.network(
          logoUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: fallbackColor.withValues(alpha: 0.1),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(fallbackColor),
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            // Fallback to colored circle with first letter
            return Container(
              decoration: BoxDecoration(
                color: fallbackColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  firstLetter,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
