class StockLogoUtils {
  /// Get stock logo URL from various sources
  /// Uses Financial Modeling Prep CDN which provides free stock logos
  static String getStockLogoUrl(String ticker, {String? exchange}) {
    // Clean ticker (remove exchange suffix if present, e.g., "AAPL.NASDAQ" -> "AAPL")
    final cleanTicker = ticker.split('.').first.split(':').first.toUpperCase();
    
    // Financial Modeling Prep provides free stock logos
    // Format: https://financialmodelingprep.com/image-stock/{ticker}.png
    return 'https://financialmodelingprep.com/image-stock/$cleanTicker.png';
  }

  /// Alternative logo sources (for future use if needed)
  static List<String> getAlternativeLogoUrls(String ticker) {
    final cleanTicker = ticker.split('.').first.split(':').first.toUpperCase();
    
    return [
      // Primary: Financial Modeling Prep
      'https://financialmodelingprep.com/image-stock/$cleanTicker.png',
      // Alternative: Using company domain (if available)
      // 'https://logo.clearbit.com/{domain}',
    ];
  }
}

