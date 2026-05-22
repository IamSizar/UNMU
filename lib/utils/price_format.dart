import 'package:intl/intl.dart';

/// Helpers for formatting + comparing community subscription prices.
///
/// All inputs are CENTS (matching the backend's
/// `join_price_monthly_cents` / `join_price_yearly_cents` columns).
/// Helpers return display strings or null when the data isn't a valid
/// comparison, so callers can hide a UI element by checking for null.
///
/// Numbers are ALWAYS rendered in Western (Latin) digits with comma
/// thousand separators (e.g. `15,000`) — the formatter is pinned to the
/// `en` number system so Arabic mode never shows Arabic-Indic digits
/// (٠١٢) for prices, matching how finance apps display money.
class PriceFormat {
  PriceFormat._();

  /// Format a raw integer into a locale-aware string with thousand
  /// separators. Examples (en):
  ///
  ///   1500    → "1,500"
  ///   15000   → "15,000"
  ///   150000  → "150,000"
  ///
  /// Use this when you already know the value is in display units. For
  /// converting cents → display units AND formatting in one call, use
  /// [formatPrice]. Always Western digits (pinned to 'en').
  static String formatAmount(int value) {
    final f = NumberFormat.decimalPattern('en');
    return f.format(value);
  }

  /// Currency code displayed alongside the amount. Always the ISO code
  /// in uppercase (USD / IQD / SAR / EUR) — the prior version used
  /// Arabic glyphs for MENA currencies (د.ع, ر.س) but the codebase
  /// treats prices as universally Latin-coded text. Using the same
  /// ISO code everywhere also makes mixed-locale screens consistent.
  static String symbolFor(String currency) {
    return currency.toUpperCase().trim();
  }

  /// Full price label, e.g. "USD 150" / "IQD 15,000" / "EUR 1,500.50".
  ///
  /// All persisted prices live in the smallest stored unit ("cents")
  /// because the admin + owner forms always multiply user input by 100
  /// before saving. So we ALWAYS divide by 100 here regardless of the
  /// currency — the previous "zero-decimal currency" branch was wrong
  /// and produced 1,500,000 IQD for what the admin entered as 15,000.
  ///
  /// Decimals:
  ///   * 15000 cents (whole)  → "USD 150"
  ///   * 15050 cents (cents)  → "USD 150.50"
  ///
  /// Always Western digits with comma thousand separators (pinned to 'en').
  static String formatPrice(int cents, String currency) {
    final symbol = symbolFor(currency);
    final units = cents / 100.0;
    // Drop the ".00" when the value is whole — matches the
    // pre-thousand-separators behaviour that callers were used to.
    final isWhole = (cents % 100) == 0;
    final f = isWhole
        ? NumberFormat.decimalPattern('en')
        : (NumberFormat.decimalPattern('en')
          ..minimumFractionDigits = 2
          ..maximumFractionDigits = 2);
    return '$symbol ${f.format(units)}';
  }

  /// Returns the rounded integer savings % when paying yearly instead
  /// of monthly × 12, or `null` when:
  ///
  ///   * Either price is ≤ 0 (free, or only one plan offered)
  ///   * Yearly is ≥ monthly × 12 (no actual saving — usually a typo,
  ///     the chip should hide rather than say "save 0%" or "save -10%")
  ///
  /// Hiding via null is intentional — callers do `if (pct != null) …`
  /// to skip the chip entirely.
  ///
  /// Example: monthly 15000, yearly 150000
  ///   annualViaMonthly = 15000 * 12 = 180000
  ///   savings           = 180000 - 150000 = 30000
  ///   savings%          = 30000 / 180000 = 16.67 → 17
  static int? yearlySavingsPercent(int monthlyCents, int yearlyCents) {
    if (monthlyCents <= 0 || yearlyCents <= 0) return null;
    final annualViaMonthly = monthlyCents * 12;
    if (yearlyCents >= annualViaMonthly) return null;
    final diff = annualViaMonthly - yearlyCents;
    // Round-to-nearest. Adding 0.5 before truncation only works for
    // positives — but we already proved `diff > 0` above.
    return ((diff / annualViaMonthly) * 100).round();
  }
}
