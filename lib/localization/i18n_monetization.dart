/// Arabic / English localization map for the community *monetization* surface:
/// the join/payment bottom sheet (`community_payment_sheet.dart`), the community
/// pricing card (`community_pricing_card.dart`), and the subscription /
/// members-only gate overlay (`subscription_gate.dart`).
///
/// This file is OWNED by the monetization localization worker. The central
/// table at `app_translations.dart` merges these two maps in — do NOT add these
/// keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   pricingCard.  subGate.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally
/// (common.ok, common.cancel, …).
///
/// NUMBERS / PRICES / AMOUNTS / percentages / currency symbols / payment-brand
/// labels (FIB, Apple Pay, …) / names / tickers are NEVER translated — only the
/// UI chrome (labels, buttons, hints, period words like "/month") lives here.
/// Digits stay Western even in AR.
///
/// INVARIANT: `monetizationEn` and `monetizationAr` MUST contain the exact same
/// set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> monetizationEn = {
  // ── Payment sheet (community_payment_sheet.dart) ──

  // ── Pricing card (community_pricing_card.dart) ──
  'pricingCard.saveBadge': 'Save @pct%',
  'pricingCard.paidCommunity': 'Paid community',
  'pricingCard.intro':
      'Subscribe to unlock posts, chat, and member-only content.',
  'pricingCard.monthly': 'Monthly',
  'pricingCard.yearly': 'Yearly',
  'pricingCard.perMonth': '/month',
  'pricingCard.perYear': '/year',
  'pricingCard.alreadySubscribed': 'Already subscribed',
  'pricingCard.submitting': 'Submitting…',
  'pricingCard.subscribePrice': 'Subscribe — @price',
  'pricingCard.footnote':
      "Payment goes through admin (cash or FIB transfer). You'll gain access once admin verifies your payment.",

  // ── Subscription / members-only gate (subscription_gate.dart) ──
  'subGate.subscribeToView': 'Subscribe to view',
  'subGate.accessBody':
      "Get full access to @name's posts, research, and updates.",
  'subGate.subscribe': 'Subscribe',
};

const Map<String, String> monetizationAr = {
  // ── Payment sheet (community_payment_sheet.dart) ──

  // ── Pricing card (community_pricing_card.dart) ──
  'pricingCard.saveBadge': 'وفّر @pct%',
  'pricingCard.paidCommunity': 'مجتمع مدفوع',
  'pricingCard.intro': 'اشترك لفتح المنشورات والدردشة والمحتوى الخاص بالأعضاء.',
  'pricingCard.monthly': 'شهري',
  'pricingCard.yearly': 'سنوي',
  'pricingCard.perMonth': '/شهر',
  'pricingCard.perYear': '/سنة',
  'pricingCard.alreadySubscribed': 'مشترك بالفعل',
  'pricingCard.submitting': 'جارٍ الإرسال…',
  'pricingCard.subscribePrice': 'اشترك — @price',
  'pricingCard.footnote':
      'يتم الدفع عبر المشرف (نقداً أو تحويل FIB). ستحصل على الوصول بمجرد تحقق المشرف من دفعتك.',

  // ── Subscription / members-only gate (subscription_gate.dart) ──
  'subGate.subscribeToView': 'اشترك للعرض',
  'subGate.accessBody': 'احصل على وصول كامل لمنشورات @name وأبحاثه وتحديثاته.',
  'subGate.subscribe': 'اشترك',
};
