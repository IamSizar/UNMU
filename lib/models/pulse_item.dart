/// =============================================================================
/// pulse_item.dart — models for UNMU Pulse (نبض أنمو), the daily briefing.
///
/// Mirrors the JSON of backend/internal/models/pulse.go (`PulseItem`,
/// `PulseDay`, `PulseStockRef`). Both languages arrive in every response
/// (`titleAr` / `titleEn` …) and the UI picks one from the user's language, so
/// switching language never needs a refetch.
///
/// Parsing is defensive on purpose: Pulse content is edited by people, so a
/// missing optional field must never crash a screen, and an item whose slot the
/// app does not know (a newer backend) is skipped rather than shown half-broken.
/// =============================================================================
library;

/// The four daily slots, in display order (spec §2).
enum PulseSlot {
  global,
  gulf,
  sharia,
  opportunity;

  /// Parses the backend slot key; null for an unknown slot.
  static PulseSlot? tryParse(String? key) {
    for (final s in PulseSlot.values) {
      if (s.name == key) return s;
    }
    return null;
  }
}

/// The stock / company a Pulse item is linked to. The app opens
/// `StockDetailScreen(ticker, exchange)` with it.
class PulseStockRef {
  final int id;
  final String ticker;
  final String exchange;
  final String name;

  const PulseStockRef({
    required this.id,
    required this.ticker,
    required this.exchange,
    required this.name,
  });

  factory PulseStockRef.fromJson(Map<String, dynamic> json) => PulseStockRef(
    id: (json['id'] as num?)?.toInt() ?? 0,
    ticker: json['ticker'] as String? ?? '',
    exchange: json['exchange'] as String? ?? '',
    name: json['name'] as String? ?? '',
  );
}

/// One published Pulse item as the app sees it.
class PulseItem {
  final int id;

  /// YYYY-MM-DD in the Pulse time zone (UTC+3).
  final String date;
  final PulseSlot slot;

  /// `true` = "analysis & interpretation"; `false` = "confirmed information".
  final bool isAnalysis;

  final String titleAr;
  final String titleEn;
  final String summaryAr;
  final String summaryEn;

  /// Only present on the detail endpoint.
  final String detailsAr;
  final String detailsEn;
  final String evidenceAr;
  final String evidenceEn;

  final String sourceName;
  final String sourceUrl;
  final DateTime? verifiedAt;
  final DateTime? publishedAt;
  final DateTime? lastChangedAt;

  /// "new", "updated", "corrected" or "" — decided by the server.
  final String marker;

  final PulseStockRef? stock;

  /// How the linked stock relates to this user: "portfolio", "watchlist" or
  /// null (not on any of their lists).
  final String? relation;
  final bool isSaved;

  const PulseItem({
    required this.id,
    required this.date,
    required this.slot,
    required this.isAnalysis,
    required this.titleAr,
    required this.titleEn,
    required this.summaryAr,
    required this.summaryEn,
    this.detailsAr = '',
    this.detailsEn = '',
    this.evidenceAr = '',
    this.evidenceEn = '',
    this.sourceName = '',
    this.sourceUrl = '',
    this.verifiedAt,
    this.publishedAt,
    this.lastChangedAt,
    this.marker = '',
    this.stock,
    this.relation,
    this.isSaved = false,
  });

  /// Returns null when the slot is unknown, so list parsing can skip it.
  static PulseItem? tryFromJson(Map<String, dynamic> json) {
    final slot = PulseSlot.tryParse(json['slot'] as String?);
    final id = (json['id'] as num?)?.toInt();
    if (slot == null || id == null) return null;
    return PulseItem(
      id: id,
      date: json['date'] as String? ?? '',
      slot: slot,
      isAnalysis: json['classification'] == 'analysis',
      titleAr: json['titleAr'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      summaryAr: json['summaryAr'] as String? ?? '',
      summaryEn: json['summaryEn'] as String? ?? '',
      detailsAr: json['detailsAr'] as String? ?? '',
      detailsEn: json['detailsEn'] as String? ?? '',
      evidenceAr: json['evidenceAr'] as String? ?? '',
      evidenceEn: json['evidenceEn'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      verifiedAt: _time(json['verifiedAt']),
      publishedAt: _time(json['publishedAt']),
      lastChangedAt: _time(json['lastChangedAt']),
      marker: json['marker'] as String? ?? '',
      stock: json['stock'] is Map<String, dynamic>
          ? PulseStockRef.fromJson(json['stock'] as Map<String, dynamic>)
          : null,
      relation: json['relation'] as String?,
      isSaved: json['isSaved'] as bool? ?? false,
    );
  }

  /// Picks the user's language, falling back to the other one when the
  /// preferred text is empty (so a card is never blank).
  static String _pick(String ar, String en, bool arabic) {
    final first = arabic ? ar : en;
    final second = arabic ? en : ar;
    return first.isNotEmpty ? first : second;
  }

  String title(bool arabic) => _pick(titleAr, titleEn, arabic);
  String summary(bool arabic) => _pick(summaryAr, summaryEn, arabic);
  String details(bool arabic) => _pick(detailsAr, detailsEn, arabic);
  String evidence(bool arabic) => _pick(evidenceAr, evidenceEn, arabic);

  /// The card shows a marker only for these three values.
  bool get isNew => marker == 'new';
  bool get isUpdated => marker == 'updated';
  bool get isCorrected => marker == 'corrected';

  PulseItem copyWith({bool? isSaved}) => PulseItem(
    id: id,
    date: date,
    slot: slot,
    isAnalysis: isAnalysis,
    titleAr: titleAr,
    titleEn: titleEn,
    summaryAr: summaryAr,
    summaryEn: summaryEn,
    detailsAr: detailsAr,
    detailsEn: detailsEn,
    evidenceAr: evidenceAr,
    evidenceEn: evidenceEn,
    sourceName: sourceName,
    sourceUrl: sourceUrl,
    verifiedAt: verifiedAt,
    publishedAt: publishedAt,
    lastChangedAt: lastChangedAt,
    marker: marker,
    stock: stock,
    relation: relation,
    isSaved: isSaved ?? this.isSaved,
  );

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}

/// A day of Pulse: up to four items, one per slot, in slot order.
class PulseDay {
  final String date;
  final List<PulseItem> items;

  /// Latest publish / change among the items.
  final DateTime? updatedAt;

  const PulseDay({required this.date, required this.items, this.updatedAt});

  factory PulseDay.fromJson(Map<String, dynamic> json) {
    final items =
        (json['items'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PulseItem.tryFromJson)
            .whereType<PulseItem>()
            .toList()
          ..sort((a, b) => a.slot.index.compareTo(b.slot.index));
    return PulseDay(
      date: json['date'] as String? ?? '',
      items: items,
      updatedAt: PulseItem._time(json['updatedAt']),
    );
  }

  /// The item for a slot, or null when nothing is published for it yet.
  PulseItem? bySlot(PulseSlot slot) {
    for (final i in items) {
      if (i.slot == slot) return i;
    }
    return null;
  }

  bool get isEmpty => items.isEmpty;
}

/// One page of the archive or of the saved list.
class PulsePage {
  final List<PulseItem> items;
  final bool hasMore;

  const PulsePage({required this.items, required this.hasMore});

  factory PulsePage.fromJson(Map<String, dynamic> json) => PulsePage(
    items: (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PulseItem.tryFromJson)
        .whereType<PulseItem>()
        .toList(),
    hasMore: json['hasMore'] as bool? ?? false,
  );
}
