import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/language_controller.dart';

/// =============================================================================
/// Locale-aware date / relative-time formatting.
///
/// Product decision: Arabic mode uses Arabic LABELS (month names, "منذ") but
/// keeps WESTERN digits (1234) — the standard for finance UIs. So we never
/// emit Arabic-Indic numerals here; we assemble the numeric parts ourselves
/// from the raw ints (always Western) and only borrow Arabic *names* from intl.
///
/// `initializeDateFormatting()` MUST be called once at startup (see main.dart)
/// so the 'ar' month/day symbols are available.
/// =============================================================================
class LocaleFormat {
  static bool get _ar {
    try {
      return Get.find<LanguageController>().isArabic;
    } catch (_) {
      // Controller not registered (tests / very early boot) → default LTR/en.
      return false;
    }
  }

  /// "12 May 2026" (en) / "12 مايو 2026" (ar) — Western digits always.
  static String date(DateTime d) {
    if (_ar) {
      final month = DateFormat.MMMM('ar').format(d); // Arabic month NAME only
      return '${d.day} $month ${d.year}';
    }
    return DateFormat('d MMM yyyy', 'en').format(d);
  }

  /// "12 May 2026 · 14:30" (24h, Western digits).
  static String dateTime(DateTime d) {
    final time = DateFormat('HH:mm', 'en').format(d);
    return '${date(d)} · $time';
  }

  /// Compact relative time: now / 5m / 2h / 3d / 4w (en) and the Arabic
  /// equivalents ("الآن", "منذ 5 د", …) with Western digits.
  static String relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    final ar = _ar;
    if (diff.inSeconds < 60) return ar ? 'الآن' : 'now';
    if (diff.inMinutes < 60) {
      final n = diff.inMinutes;
      return ar ? 'منذ $n د' : '${n}m';
    }
    if (diff.inHours < 24) {
      final n = diff.inHours;
      return ar ? 'منذ $n س' : '${n}h';
    }
    if (diff.inDays < 7) {
      final n = diff.inDays;
      return ar ? 'منذ $n ي' : '${n}d';
    }
    final w = (diff.inDays / 7).floor();
    return ar ? 'منذ $w أ' : '${w}w';
  }

  /// 12-hour clock with Western digits and a localized AM/PM marker
  /// ("2:30 PM" / "2:30 م"). Used for message + chart timestamps.
  static String time(DateTime d) {
    final h24 = d.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final pm = h24 >= 12;
    if (_ar) return '$h12:$m ${pm ? 'م' : 'ص'}';
    return '$h12:$m ${pm ? 'PM' : 'AM'}';
  }

  /// Short month + day, Western digits ("May 12" / "12 مايو"). Used for
  /// chart axis labels on multi-day ranges.
  static String monthDay(DateTime d) {
    if (_ar) {
      final month = DateFormat.MMMM('ar').format(d);
      return '${d.day} $month';
    }
    return DateFormat('MMM d', 'en').format(d);
  }
}
