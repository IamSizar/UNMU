/// Arabic / English localization map for the *subscriptions* surface:
///   * the in-app premium subscription screen (free vs. premium plans +
///     promo-code section) — subscription_screen.dart
///   * the "My Subscriptions" list (expert + community memberships, status
///     pills, expiry/renew affordances) — my_subscriptions_screen.dart
///   * the subscribe-to-an-expert bottom sheet (plan + payment-method
///     picker, receipt/note inputs, submit) — subscribe_modal.dart
///
/// This file is OWNED by the subscriptions localization worker. The central
/// table at `app_translations.dart` merges these two maps in — do NOT add
/// these keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   subscription.  mySubscriptions.  subscribe.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally
/// (common.cancel, common.ok, …).
///
/// NUMBERS / PRICES / AMOUNTS / currency symbols, expert & community NAMES,
/// promo codes and the brand "UNMU" are NEVER translated — only the UI chrome
/// (buttons, labels, hints, unit words, empty/error states) lives here. Digits
/// stay Western even in AR; dates are produced by `LocaleFormat.date`.
///
/// INVARIANT: `subscriptionsEn` and `subscriptionsAr` MUST contain the exact
/// same set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> subscriptionsEn = {
  // ── Realtime subscription toasts (subscription_controller.dart) ──
  'subscription.expertFallback': 'expert',
  'subscription.activeToastTitle': 'Subscription active',
  'subscription.activeToastBody': 'Your subscription to @name is now active.',
  'subscription.declinedToastTitle': 'Subscription declined',
  'subscription.declinedToastBody': 'Your subscription to @name was declined.',
  'subscription.declinedToastBodyReason':
      'Your subscription to @name was declined: @reason',

  // ── Premium subscription screen (subscription_screen.dart) ──
  'subscription.title': 'Subscription Plans',
  'subscription.planFree': 'Free',
  'subscription.planPremiumMonthly': 'Premium Monthly',
  'subscription.planPremiumAnnual': 'Premium Annual',
  'subscription.perMonth': '/ Month',
  'subscription.recommended': 'RECOMMENDED',
  'subscription.currentPlan': 'Current Plan',
  'subscription.upgradeNow': 'Upgrade Now',
  'subscription.feature.basicStockSearch': 'Basic stock search',
  'subscription.feature.limitedReports': 'Limited screening reports',
  'subscription.feature.adSupported': 'Ad-supported',
  'subscription.feature.unlimitedScreening': 'Unlimited screening',
  'subscription.feature.advancedCharts': 'Advanced charts',
  'subscription.feature.adFree': 'Ad-free experience',
  'subscription.feature.prioritySupport': 'Priority support',
  'subscription.productsUnavailable':
      'Products unavailable. The App Store products need to be configured in '
          'App Store Connect before this screen can show purchase options.',
  // Promo code section
  'subscription.promo.title': 'Have a promo code?',
  'subscription.promo.hint': 'Enter code',
  'subscription.promo.apply': 'Apply',

  // ── My Subscriptions list (my_subscriptions_screen.dart) ──
  'mySubscriptions.title': 'My Subscriptions',
  // Empty state
  'mySubscriptions.empty.title': 'No subscriptions yet',
  'mySubscriptions.empty.body':
      'Browse experts and tap Subscribe on their profile to unlock\n'
          'their articles, videos, and reels.',
  // Section headers
  'mySubscriptions.section.expertsActive': 'Experts — Active',
  'mySubscriptions.section.expertsPending': 'Experts — Pending',
  'mySubscriptions.section.expertsPast': 'Experts — Past',
  'mySubscriptions.section.communitiesActive': 'Communities — Active',
  'mySubscriptions.section.communitiesPending': 'Communities — Pending',
  'mySubscriptions.section.communitiesPast': 'Communities — Past',
  // Status pills
  'mySubscriptions.status.pending': 'Pending',
  'mySubscriptions.status.active': 'Active',
  'mySubscriptions.status.rejected': 'Rejected',
  'mySubscriptions.status.cancelled': 'Cancelled',
  'mySubscriptions.status.expired': 'Expired',
  'mySubscriptions.status.unknown': 'Unknown',
  // Tile detail lines (count/dates are Western digits)
  'mySubscriptions.expiresInDays': 'Expires in @count day@plural',
  'mySubscriptions.expiredOn': 'Expired @date',
  'mySubscriptions.accessUntil': 'Access until @date',
  'mySubscriptions.reason': 'Reason: @reason',
  // Tile actions
  'mySubscriptions.subscribeAgain': 'Subscribe again',
  // Cancel expert subscription dialog
  'mySubscriptions.cancel.title': 'Cancel subscription?',
  'mySubscriptions.cancel.bodyPending':
      'This pending request will be cancelled. You can re-submit later.',
  'mySubscriptions.cancel.bodyActive':
      'You\'ll lose access to subscriber-only posts immediately. Refunds are '
          'handled by the admin separately.',
  'mySubscriptions.cancel.keep': 'Keep it',
  'mySubscriptions.cancel.confirm': 'Cancel subscription',
  'mySubscriptions.cancelledSnack': 'Subscription cancelled',
  // Renew snackbar
  'mySubscriptions.renewSubmittedSnack': 'Renewal submitted — admin will review',
  // Cancel community subscription dialog
  'mySubscriptions.commCancel.title': 'Cancel community subscription?',
  'mySubscriptions.commCancel.bodyPending':
      'Your pending request to join @name will be cancelled.',
  'mySubscriptions.commCancel.bodyActive':
      'You\'ll lose access to @name immediately. Refunds are handled by the '
          'admin separately.',
  'mySubscriptions.commCancelledSnack': 'Community subscription cancelled',
  'mySubscriptions.commCancelFailedSnack': 'Cancel failed',
  // Expiring-soon banner
  'mySubscriptions.expiring.heading': 'Heads up — renewal time',
  'mySubscriptions.expiring.bodyOne':
      'Your subscription to @name expires in @count day@plural. You can '
          'subscribe again as soon as it expires.',
  'mySubscriptions.expiring.bodyMany':
      '@total of your subscriptions expire soon (next: @name in @count '
          'day@plural). You can subscribe again once each expires.',

  // ── Subscribe-to-expert modal (subscribe_modal.dart) ──
  'subscribe.title': 'Subscribe to @name',
  'subscribe.introIos':
      'Subscribe via the App Store for an instant activation, or pay the '
          'admin in cash / via FIB and they\'ll confirm your subscription.',
  'subscribe.introOther':
      'Pay the admin in cash or via FIB transfer. Once they confirm your '
          'payment, your subscription becomes active and you\'ll see all '
          'locked posts.',
  'subscribe.choosePlan': 'Choose a plan',
  'subscribe.paymentMethod': 'Payment method',
  'subscribe.planMonthly': 'Monthly',
  'subscribe.planYearly': 'Yearly',
  'subscribe.planYearlyTagline':
      '@yearly once a year — works out to @monthly/mo',
  'subscribe.planMonthlyTagline': '@monthly every 30 days',
  'subscribe.saveBadge': 'SAVE @pct%',
  // Payment method tile labels + sub-labels
  'subscribe.method.cashTitle': 'Cash',
  'subscribe.method.cashSub': 'Pay admin in person',
  'subscribe.method.fibSub': 'First Iraqi Bank transfer',
  'subscribe.method.appleSub': 'Charge through App Store — activates instantly',
  'subscribe.method.googleSub': 'Charge through Google Play',
  // FIB reference + note inputs
  'subscribe.fibRefLabel': 'FIB transaction reference (optional)',
  'subscribe.fibRefHint': 'Helps the admin match your payment',
  'subscribe.receiptLabel': 'Cash receipt photo (optional)',
  'subscribe.noteLabel': 'Note for the admin (optional)',
  'subscribe.noteHint': 'e.g. paid this morning at the office',
  'subscribe.promoLabel': 'Promo code (optional)',
  'subscribe.promoHint': 'Enter a code',
  'subscribe.promoApply': 'Apply',
  // Receipt picker tile
  'subscribe.receipt.addTitle': 'Add a photo of your receipt',
  'subscribe.receipt.addSub': 'Helps the admin verify cash payments',
  'subscribe.receipt.uploadedTitle': 'Receipt uploaded',
  'subscribe.receipt.uploadedSub': 'Tap to replace',
  // Submit button + footnote
  'subscribe.submit': 'Submit · @price',
  'subscribe.footnoteIap':
      'Charged immediately through the App Store. Cancel anytime from iOS '
          'Settings → Subscriptions.',
  'subscribe.footnoteAdmin':
      'You won\'t be charged automatically. Pay the admin and they\'ll mark '
          'this active.',
  // Errors
  'subscribe.error.submitFailed': 'Failed to submit',
  'subscribe.error.iapUnavailable':
      'In-app purchases are unavailable on this device.',
  'subscribe.error.planNotSetUp':
      'This plan isn\'t set up in the App Store yet. Please contact support.',
  'subscribe.error.purchaseFailed': 'Purchase failed.',
  'subscribe.error.subDidNotShow':
      'Purchase succeeded but the subscription didn\'t show up — pull to '
          'refresh.',
};

const Map<String, String> subscriptionsAr = {
  // ── Realtime subscription toasts (subscription_controller.dart) ──
  'subscription.expertFallback': 'الخبير',
  'subscription.activeToastTitle': 'تم تفعيل الاشتراك',
  'subscription.activeToastBody': 'أصبح اشتراكك لدى @name نشطاً الآن.',
  'subscription.declinedToastTitle': 'تم رفض الاشتراك',
  'subscription.declinedToastBody': 'تم رفض اشتراكك لدى @name.',
  'subscription.declinedToastBodyReason':
      'تم رفض اشتراكك لدى @name: @reason',

  // ── Premium subscription screen (subscription_screen.dart) ──
  'subscription.title': 'خطط الاشتراك',
  'subscription.planFree': 'مجاني',
  'subscription.planPremiumMonthly': 'بريميوم شهري',
  'subscription.planPremiumAnnual': 'بريميوم سنوي',
  'subscription.perMonth': '/ شهرياً',
  'subscription.recommended': 'موصى به',
  'subscription.currentPlan': 'الخطة الحالية',
  'subscription.upgradeNow': 'الترقية الآن',
  'subscription.feature.basicStockSearch': 'بحث أساسي عن الأسهم',
  'subscription.feature.limitedReports': 'تقارير فحص محدودة',
  'subscription.feature.adSupported': 'مدعوم بالإعلانات',
  'subscription.feature.unlimitedScreening': 'فحص غير محدود',
  'subscription.feature.advancedCharts': 'رسوم بيانية متقدمة',
  'subscription.feature.adFree': 'تجربة خالية من الإعلانات',
  'subscription.feature.prioritySupport': 'دعم ذو أولوية',
  'subscription.productsUnavailable':
      'المنتجات غير متاحة. يجب إعداد منتجات App Store في App Store Connect قبل '
          'أن تتمكن هذه الشاشة من عرض خيارات الشراء.',
  // Promo code section
  'subscription.promo.title': 'لديك رمز ترويجي؟',
  'subscription.promo.hint': 'أدخل الرمز',
  'subscription.promo.apply': 'تطبيق',

  // ── My Subscriptions list (my_subscriptions_screen.dart) ──
  'mySubscriptions.title': 'اشتراكاتي',
  // Empty state
  'mySubscriptions.empty.title': 'لا توجد اشتراكات بعد',
  'mySubscriptions.empty.body':
      'تصفّح الخبراء واضغط على اشتراك في ملفهم الشخصي لفتح\n'
          'مقالاتهم وفيديوهاتهم ومقاطعهم.',
  // Section headers
  'mySubscriptions.section.expertsActive': 'الخبراء — نشط',
  'mySubscriptions.section.expertsPending': 'الخبراء — قيد الانتظار',
  'mySubscriptions.section.expertsPast': 'الخبراء — السابقة',
  'mySubscriptions.section.communitiesActive': 'المجتمعات — نشط',
  'mySubscriptions.section.communitiesPending': 'المجتمعات — قيد الانتظار',
  'mySubscriptions.section.communitiesPast': 'المجتمعات — السابقة',
  // Status pills
  'mySubscriptions.status.pending': 'قيد الانتظار',
  'mySubscriptions.status.active': 'نشط',
  'mySubscriptions.status.rejected': 'مرفوض',
  'mySubscriptions.status.cancelled': 'ملغي',
  'mySubscriptions.status.expired': 'منتهي',
  'mySubscriptions.status.unknown': 'غير معروف',
  // Tile detail lines (count/dates are Western digits)
  'mySubscriptions.expiresInDays': 'ينتهي خلال @count يوم',
  'mySubscriptions.expiredOn': 'انتهى في @date',
  'mySubscriptions.accessUntil': 'الوصول حتى @date',
  'mySubscriptions.reason': 'السبب: @reason',
  // Tile actions
  'mySubscriptions.subscribeAgain': 'اشترك مجدداً',
  // Cancel expert subscription dialog
  'mySubscriptions.cancel.title': 'إلغاء الاشتراك؟',
  'mySubscriptions.cancel.bodyPending':
      'سيتم إلغاء هذا الطلب المعلّق. يمكنك إعادة تقديمه لاحقاً.',
  'mySubscriptions.cancel.bodyActive':
      'ستفقد الوصول إلى المنشورات الخاصة بالمشتركين فوراً. تُعالَج المبالغ '
          'المستردة من قِبل المشرف بشكل منفصل.',
  'mySubscriptions.cancel.keep': 'الاحتفاظ به',
  'mySubscriptions.cancel.confirm': 'إلغاء الاشتراك',
  'mySubscriptions.cancelledSnack': 'تم إلغاء الاشتراك',
  // Renew snackbar
  'mySubscriptions.renewSubmittedSnack': 'تم إرسال طلب التجديد — سيراجعه المشرف',
  // Cancel community subscription dialog
  'mySubscriptions.commCancel.title': 'إلغاء اشتراك المجتمع؟',
  'mySubscriptions.commCancel.bodyPending':
      'سيتم إلغاء طلبك المعلّق للانضمام إلى @name.',
  'mySubscriptions.commCancel.bodyActive':
      'ستفقد الوصول إلى @name فوراً. تُعالَج المبالغ المستردة من قِبل المشرف '
          'بشكل منفصل.',
  'mySubscriptions.commCancelledSnack': 'تم إلغاء اشتراك المجتمع',
  'mySubscriptions.commCancelFailedSnack': 'فشل الإلغاء',
  // Expiring-soon banner
  'mySubscriptions.expiring.heading': 'تنبيه — حان وقت التجديد',
  'mySubscriptions.expiring.bodyOne':
      'ينتهي اشتراكك مع @name خلال @count يوم. يمكنك الاشتراك مجدداً بمجرد '
          'انتهائه.',
  'mySubscriptions.expiring.bodyMany':
      'سينتهي @total من اشتراكاتك قريباً (التالي: @name خلال @count يوم). '
          'يمكنك الاشتراك مجدداً بمجرد انتهاء كل منها.',

  // ── Subscribe-to-expert modal (subscribe_modal.dart) ──
  'subscribe.title': 'الاشتراك مع @name',
  'subscribe.introIos':
      'اشترك عبر App Store للتفعيل الفوري، أو ادفع للمشرف نقداً / عبر FIB '
          'وسيؤكد اشتراكك.',
  'subscribe.introOther':
      'ادفع للمشرف نقداً أو عبر تحويل FIB. بمجرد تأكيد دفعتك، يصبح اشتراكك '
          'نشطاً وستشاهد جميع المنشورات المقفلة.',
  'subscribe.choosePlan': 'اختر خطة',
  'subscribe.paymentMethod': 'طريقة الدفع',
  'subscribe.planMonthly': 'شهري',
  'subscribe.planYearly': 'سنوي',
  'subscribe.planYearlyTagline':
      '@yearly مرة واحدة سنوياً — أي ما يعادل @monthly/شهرياً',
  'subscribe.planMonthlyTagline': '@monthly كل 30 يوماً',
  'subscribe.saveBadge': 'وفّر @pct%',
  // Payment method tile labels + sub-labels
  'subscribe.method.cashTitle': 'نقداً',
  'subscribe.method.cashSub': 'ادفع للمشرف شخصياً',
  'subscribe.method.fibSub': 'تحويل عبر بنك العراق الأول',
  'subscribe.method.appleSub': 'الدفع عبر App Store — يُفعّل فوراً',
  'subscribe.method.googleSub': 'الدفع عبر Google Play',
  // FIB reference + note inputs
  'subscribe.fibRefLabel': 'مرجع معاملة FIB (اختياري)',
  'subscribe.fibRefHint': 'يساعد المشرف على مطابقة دفعتك',
  'subscribe.receiptLabel': 'صورة إيصال الدفع النقدي (اختياري)',
  'subscribe.noteLabel': 'ملاحظة للمشرف (اختياري)',
  'subscribe.noteHint': 'مثال: دفعت هذا الصباح في المكتب',
  'subscribe.promoLabel': 'رمز ترويجي (اختياري)',
  'subscribe.promoHint': 'أدخل الرمز',
  'subscribe.promoApply': 'تطبيق',
  // Receipt picker tile
  'subscribe.receipt.addTitle': 'أضف صورة لإيصالك',
  'subscribe.receipt.addSub': 'يساعد المشرف على التحقق من المدفوعات النقدية',
  'subscribe.receipt.uploadedTitle': 'تم رفع الإيصال',
  'subscribe.receipt.uploadedSub': 'اضغط للاستبدال',
  // Submit button + footnote
  'subscribe.submit': 'إرسال · @price',
  'subscribe.footnoteIap':
      'يُخصم المبلغ فوراً عبر App Store. يمكنك الإلغاء في أي وقت من إعدادات '
          'iOS ← الاشتراكات.',
  'subscribe.footnoteAdmin':
      'لن يتم خصم أي مبلغ تلقائياً. ادفع للمشرف وسيقوم بتفعيل هذا الاشتراك.',
  // Errors
  'subscribe.error.submitFailed': 'فشل الإرسال',
  'subscribe.error.iapUnavailable': 'عمليات الشراء داخل التطبيق غير متاحة على هذا الجهاز.',
  'subscribe.error.planNotSetUp':
      'لم يتم إعداد هذه الخطة في App Store بعد. يرجى التواصل مع الدعم.',
  'subscribe.error.purchaseFailed': 'فشل الشراء.',
  'subscribe.error.subDidNotShow':
      'نجح الشراء لكن الاشتراك لم يظهر — اسحب للأسفل للتحديث.',
};
