/// Arabic / English localization map for the *expert monetization* surface:
/// the full-screen earnings view (headline tiles, daily-revenue chart, by-day
/// list), the payouts section + request-payout bottom sheet, and the
/// subscription-pricing editor sheet.
///
/// This file is OWNED by the earnings/payouts/pricing localization worker. The
/// central table at `app_translations.dart` merges these two maps in — do NOT
/// add these keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   earnings.  payout.  pricing.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally
/// (common.cancel, common.ok, …).
///
/// NUMBERS / PRICES / AMOUNTS / currency symbols are produced by `formatCents`
/// and friends and are NEVER translated — only the UI chrome (labels, buttons,
/// hints, unit words like "/month") lives here. Digits stay Western even in AR.
///
/// INVARIANT: `expertsMoneyEn` and `expertsMoneyAr` MUST contain the exact same
/// set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> expertsMoneyEn = {
  // ── Earnings screen (earnings_screen.dart) ──
  'earnings.title': 'Earnings',
  'earnings.noBalanceYet':
      'No available balance yet. Once subscribers pay you, you can request a payout.',
  'earnings.dailyRevenue': 'DAILY REVENUE',
  'earnings.noRevenueYet': 'No revenue yet.',
  'earnings.byDay': 'BY DAY',
  'earnings.noRevenueWindow': 'No revenue in this window.',
  // Window selector chips ("7d" / "30d" / "90d" / "1y") — keep the number,
  // translate only the unit letter.
  'earnings.windowDays': '@countd',
  'earnings.window1y': '1y',
  // Headline tiles
  'earnings.lastNDays': 'Last @count days',
  'earnings.active': 'Active',
  'earnings.lifetime': 'Lifetime',
  // Chart tooltip + by-day rows (count is Western digits)
  'earnings.subsCount': '@count sub@plural',
  'earnings.newSubscribers': '@count new subscriber@plural',

  // ── Payouts (earnings_screen.dart section + request_payout_sheet.dart) ──
  'payout.availableToWithdraw': 'Available to withdraw',
  'payout.request': 'Request',
  'payout.noRequests': 'No payout requests yet.',
  // Status pills
  'payout.statusPaid': 'PAID',
  'payout.statusRejected': 'REJECTED',
  'payout.statusCancelled': 'CANCELLED',
  'payout.statusPending': 'PENDING',
  // Admin note line (note text itself is server-returned, kept verbatim)
  'payout.adminNote': 'Admin note: @note',
  // Request payout sheet
  'payout.requestTitle': 'Request payout',
  'payout.availableLabel': 'Available to withdraw: @amount',
  'payout.amount': 'Amount',
  'payout.method': 'Payout method',
  'payout.details': 'Payment details',
  'payout.hintBank': 'e.g. account holder name, IBAN, bank name + country',
  'payout.hintFib': 'e.g. registered mobile + name on the FIB account',
  'payout.hintPaypal': 'PayPal email',
  'payout.hintOther': "Tell the admin how you'd like to be paid",
  'payout.submit': 'Submit request',
  'payout.submittedSnack': 'Payout request submitted — admin will review.',

  // ── Subscription pricing sheet (edit_pricing_sheet.dart) ──
  'pricing.title': 'Subscription pricing',
  'pricing.subtitle':
      'Set what you charge subscribers. Prices are in USD. Existing subscribers stay on the price they signed up at — changes apply to new sign-ups only.',
  'pricing.monthly': 'Monthly',
  'pricing.monthlyHint': 'e.g. 10',
  'pricing.yearly': 'Yearly',
  'pricing.yearlyHint': 'e.g. 96',
  'pricing.save': 'Save pricing',
  'pricing.invalidAmounts': 'Enter valid dollar amounts.',
  'pricing.updatedSnack': 'Pricing updated.',
};

const Map<String, String> expertsMoneyAr = {
  // ── Earnings screen (earnings_screen.dart) ──
  'earnings.title': 'الأرباح',
  'earnings.noBalanceYet':
      'لا يوجد رصيد متاح بعد. بمجرد أن يدفع لك المشتركون، يمكنك طلب تحويل أرباحك.',
  'earnings.dailyRevenue': 'الإيراد اليومي',
  'earnings.noRevenueYet': 'لا يوجد إيراد بعد.',
  'earnings.byDay': 'حسب اليوم',
  'earnings.noRevenueWindow': 'لا يوجد إيراد في هذه الفترة.',
  // Window selector chips — keep the number, translate only the unit letter.
  'earnings.windowDays': '@count ي',
  'earnings.window1y': 'سنة',
  // Headline tiles
  'earnings.lastNDays': 'آخر @count يوم',
  'earnings.active': 'نشط',
  'earnings.lifetime': 'الإجمالي',
  // Chart tooltip + by-day rows (count is Western digits)
  'earnings.subsCount': '@count مشترك',
  'earnings.newSubscribers': '@count مشترك جديد',

  // ── Payouts (earnings_screen.dart section + request_payout_sheet.dart) ──
  'payout.availableToWithdraw': 'المتاح للسحب',
  'payout.request': 'طلب',
  'payout.noRequests': 'لا توجد طلبات تحويل بعد.',
  // Status pills
  'payout.statusPaid': 'مدفوع',
  'payout.statusRejected': 'مرفوض',
  'payout.statusCancelled': 'ملغي',
  'payout.statusPending': 'قيد الانتظار',
  // Admin note line (note text itself is server-returned, kept verbatim)
  'payout.adminNote': 'ملاحظة المشرف: @note',
  // Request payout sheet
  'payout.requestTitle': 'طلب تحويل الأرباح',
  'payout.availableLabel': 'المتاح للسحب: @amount',
  'payout.amount': 'المبلغ',
  'payout.method': 'طريقة التحويل',
  'payout.details': 'تفاصيل الدفع',
  'payout.hintBank': 'مثال: اسم صاحب الحساب، رقم الآيبان، اسم البنك + الدولة',
  'payout.hintFib': 'مثال: رقم الجوال المسجّل + الاسم على حساب FIB',
  'payout.hintPaypal': 'بريد PayPal الإلكتروني',
  'payout.hintOther': 'أخبر المشرف بالطريقة التي تفضّل أن تُدفع بها',
  'payout.submit': 'إرسال الطلب',
  'payout.submittedSnack': 'تم إرسال طلب التحويل — سيراجعه المشرف.',

  // ── Subscription pricing sheet (edit_pricing_sheet.dart) ──
  'pricing.title': 'أسعار الاشتراك',
  'pricing.subtitle':
      'حدّد ما تتقاضاه من المشتركين. الأسعار بالدولار الأمريكي. يبقى المشتركون الحاليون على السعر الذي اشتركوا به — تنطبق التغييرات على الاشتراكات الجديدة فقط.',
  'pricing.monthly': 'شهري',
  'pricing.monthlyHint': 'مثال: 10',
  'pricing.yearly': 'سنوي',
  'pricing.yearlyHint': 'مثال: 96',
  'pricing.save': 'حفظ الأسعار',
  'pricing.invalidAmounts': 'أدخل مبالغ صحيحة بالدولار.',
  'pricing.updatedSnack': 'تم تحديث الأسعار.',
};
