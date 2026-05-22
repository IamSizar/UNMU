import 'package:flutter/material.dart';
import 'halal_strings.dart';

class AppLocalizations {
  final BuildContext context;

  AppLocalizations(this.context);

  bool get isArabic {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'ar';
  }

  // App
  String get appName =>
      isArabic ? HalalStringsAr.appName : HalalStrings.appName;

  // Navigation
  String get discover =>
      isArabic ? HalalStringsAr.discover : HalalStrings.discover;
  String get watchlist =>
      isArabic ? HalalStringsAr.watchlist : HalalStrings.watchlist;
  String get tools => isArabic ? HalalStringsAr.tools : HalalStrings.tools;
  String get profile =>
      isArabic ? HalalStringsAr.profile : HalalStrings.profile;
  String get indexes =>
      isArabic ? HalalStringsAr.indexes : HalalStrings.indexes;

  // Common
  String get search => isArabic ? HalalStringsAr.search : HalalStrings.search;
  String get filter => isArabic ? HalalStringsAr.filter : HalalStrings.filter;
  String get all => isArabic ? HalalStringsAr.all : HalalStrings.all;
  String get loading =>
      isArabic ? HalalStringsAr.loading : HalalStrings.loading;
  String get error => isArabic ? HalalStringsAr.error : HalalStrings.error;
  String get retry => isArabic ? HalalStringsAr.retry : HalalStrings.retry;
  String get refresh =>
      isArabic ? HalalStringsAr.refresh : HalalStrings.refresh;
  String get empty => isArabic ? HalalStringsAr.empty : HalalStrings.empty;
  String get totalStocks =>
      isArabic ? HalalStringsAr.totalStocks : HalalStrings.totalStocks;
  String get available =>
      isArabic ? HalalStringsAr.available : HalalStrings.available;
  String get gradeA => isArabic ? HalalStringsAr.gradeA : HalalStrings.gradeA;
  String get allStocks =>
      isArabic ? HalalStringsAr.allStocks : HalalStrings.allStocks;
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get close => isArabic ? 'إغلاق' : 'Close';
  String get ok => isArabic ? 'موافق' : 'OK';
  String get success => isArabic ? 'نجاح' : 'Success';
  String get save => isArabic ? 'حفظ' : 'Save';
  String get delete => isArabic ? 'حذف' : 'Delete';
  String get edit => isArabic ? 'تعديل' : 'Edit';
  String get remove => isArabic ? 'إزالة' : 'Remove';
  String get yes => isArabic ? 'نعم' : 'Yes';
  String get no => isArabic ? 'لا' : 'No';

  // Regions
  String get regionUS =>
      isArabic ? HalalStringsAr.regionUS : HalalStrings.regionUS;
  String get regionGCC =>
      isArabic ? HalalStringsAr.regionGCC : HalalStrings.regionGCC;
  String get regionMENA =>
      isArabic ? HalalStringsAr.regionMENA : HalalStrings.regionMENA;
  String get regionEU =>
      isArabic ? HalalStringsAr.regionEU : HalalStrings.regionEU;
  String get regionASIA =>
      isArabic ? HalalStringsAr.regionASIA : HalalStrings.regionASIA;
  String get regionCN =>
      isArabic ? HalalStringsAr.regionCN : HalalStrings.regionCN;
  String get regionGlobal =>
      isArabic ? HalalStringsAr.regionGlobal : HalalStrings.regionGlobal;

  // Stock Status
  String get halal => isArabic ? HalalStringsAr.halal : HalalStrings.halal;
  String get haram => isArabic ? HalalStringsAr.haram : HalalStrings.haram;
  String get mixed => isArabic ? HalalStringsAr.mixed : HalalStrings.mixed;
  String get unknown =>
      isArabic ? HalalStringsAr.unknown : HalalStrings.unknown;

  // Stock Detail
  String get stockDetails =>
      isArabic ? HalalStringsAr.stockDetails : HalalStrings.stockDetails;
  String get ticker => isArabic ? HalalStringsAr.ticker : HalalStrings.ticker;
  String get exchange =>
      isArabic ? HalalStringsAr.exchange : HalalStrings.exchange;
  String get sector => isArabic ? HalalStringsAr.sector : HalalStrings.sector;
  String get industry =>
      isArabic ? HalalStringsAr.industry : HalalStrings.industry;
  String get shariahStatus =>
      isArabic ? HalalStringsAr.shariahStatus : HalalStrings.shariahStatus;
  String get grade => isArabic ? HalalStringsAr.grade : HalalStrings.grade;
  String get debtRatio =>
      isArabic ? HalalStringsAr.debtRatio : HalalStrings.debtRatio;
  String get haramIncomeRatio => isArabic
      ? HalalStringsAr.haramIncomeRatio
      : HalalStrings.haramIncomeRatio;
  String get purificationRate => isArabic
      ? HalalStringsAr.purificationRate
      : HalalStrings.purificationRate;
  String get paysZakat =>
      isArabic ? HalalStringsAr.paysZakat : HalalStrings.paysZakat;
  String get explanation =>
      isArabic ? HalalStringsAr.explanation : HalalStrings.explanation;
  String get reason => isArabic ? HalalStringsAr.reason : HalalStrings.reason;
  String get follow => isArabic ? HalalStringsAr.follow : HalalStrings.follow;
  String get unfollow =>
      isArabic ? HalalStringsAr.unfollow : HalalStrings.unfollow;
  String get following =>
      isArabic ? HalalStringsAr.following : HalalStrings.following;

  // Watchlist
  String get myWatchlist =>
      isArabic ? HalalStringsAr.myWatchlist : HalalStrings.myWatchlist;
  String get noFollowedStocks => isArabic
      ? HalalStringsAr.noFollowedStocks
      : HalalStrings.noFollowedStocks;
  String get startFollowing =>
      isArabic ? HalalStringsAr.startFollowing : HalalStrings.startFollowing;
  String get removeFromWatchlist =>
      isArabic ? 'إزالة من المتابعة' : 'Remove from Watchlist';
  String get removeFromWatchlistConfirm => isArabic
      ? 'هل تريد إزالة هذا السهم من قائمة المتابعة؟'
      : 'Are you sure you want to remove this stock from your watchlist?';

  // Notifications
  String get notifications =>
      isArabic ? HalalStringsAr.notifications : HalalStrings.notifications;
  String get noNotifications =>
      isArabic ? HalalStringsAr.noNotifications : HalalStrings.noNotifications;
  String get statusChanged =>
      isArabic ? HalalStringsAr.statusChanged : HalalStrings.statusChanged;
  String get purificationChanged => isArabic
      ? HalalStringsAr.purificationChanged
      : HalalStrings.purificationChanged;

  // Tools
  String get zakatCalculator =>
      isArabic ? HalalStringsAr.zakatCalculator : HalalStrings.zakatCalculator;
  String get dcaCalculator =>
      isArabic ? HalalStringsAr.dcaCalculator : HalalStrings.dcaCalculator;
  String get calculateZakat =>
      isArabic ? HalalStringsAr.calculateZakat : HalalStrings.calculateZakat;
  String get calculateDCA =>
      isArabic ? HalalStringsAr.calculateDCA : HalalStrings.calculateDCA;
  String get totalZakat =>
      isArabic ? HalalStringsAr.totalZakat : HalalStrings.totalZakat;
  String get monthlyAmount =>
      isArabic ? HalalStringsAr.monthlyAmount : HalalStrings.monthlyAmount;
  String get years => isArabic ? HalalStringsAr.years : HalalStrings.years;
  String get annualRate =>
      isArabic ? HalalStringsAr.annualRate : HalalStrings.annualRate;
  String get totalInvested =>
      isArabic ? HalalStringsAr.totalInvested : HalalStrings.totalInvested;
  String get projectedValue =>
      isArabic ? HalalStringsAr.projectedValue : HalalStrings.projectedValue;
  String get projectedGain =>
      isArabic ? HalalStringsAr.projectedGain : HalalStrings.projectedGain;
  String get calculateZakatDescription =>
      isArabic ? 'احسب الزكاة على محفظتك' : 'Calculate Zakat on your portfolio';
  String get calculateDCADescription => isArabic
      ? 'احسب نمو الاستثمار طويل الأجل'
      : 'Calculate long-term investment growth';

  // Profile
  String get settings =>
      isArabic ? HalalStringsAr.settings : HalalStrings.settings;
  String get language =>
      isArabic ? HalalStringsAr.language : HalalStrings.language;
  String get darkMode =>
      isArabic ? HalalStringsAr.darkMode : HalalStrings.darkMode;
  String get english =>
      isArabic ? HalalStringsAr.english : HalalStrings.english;
  String get arabic => isArabic ? HalalStringsAr.arabic : HalalStrings.arabic;
  String get logout => isArabic ? HalalStringsAr.logout : HalalStrings.logout;
  String get about => isArabic ? 'حول التطبيق' : 'About';
  String get help => isArabic ? 'المساعدة' : 'Help';
  String get aboutContent => isArabic
      ? 'تطبيق تحليل الأسهم الحلال\nالإصدار 1.0.0'
      : 'Halal Stocks Analytics App\nVersion 1.0.0';
  String get helpContent => isArabic
      ? 'للمساعدة والدعم، يرجى التواصل معنا عبر البريد الإلكتروني.'
      : 'For help and support, please contact us via email.';
  String get logoutConfirm => isArabic
      ? 'هل أنت متأكد من تسجيل الخروج؟'
      : 'Are you sure you want to logout?';
  String get user => isArabic ? 'المستخدم' : 'User';

  String get premiumMember =>
      isArabic ? HalalStringsAr.premiumMember : HalalStrings.premiumMember;
  String get freeMember =>
      isArabic ? HalalStringsAr.freeMember : HalalStrings.freeMember;
  String get upgradeToUnlock =>
      isArabic ? HalalStringsAr.upgradeToUnlock : HalalStrings.upgradeToUnlock;
  String get upgrade =>
      isArabic ? HalalStringsAr.upgrade : HalalStrings.upgrade;

  // Search
  String get searchStocks =>
      isArabic ? HalalStringsAr.searchStocks : HalalStrings.searchStocks;
  String get enterTickerOrName => isArabic
      ? HalalStringsAr.enterTickerOrName
      : HalalStrings.enterTickerOrName;
  String get noResults =>
      isArabic ? HalalStringsAr.noResults : HalalStrings.noResults;

  // Zakat Calculation
  String get investmentAmount => isArabic
      ? HalalStringsAr.investmentAmount
      : HalalStrings.investmentAmount;
  String get calculateZakatForStock => isArabic
      ? HalalStringsAr.calculateZakatForStock
      : HalalStrings.calculateZakatForStock;
  String get zakatAmount =>
      isArabic ? HalalStringsAr.zakatAmount : HalalStrings.zakatAmount;
  String get companyPaysZakat => isArabic
      ? HalalStringsAr.companyPaysZakat
      : HalalStrings.companyPaysZakat;
  String get companyDoesNotPayZakat => isArabic
      ? HalalStringsAr.companyDoesNotPayZakat
      : HalalStrings.companyDoesNotPayZakat;
  String get enterInvestmentAmount => isArabic
      ? HalalStringsAr.enterInvestmentAmount
      : HalalStrings.enterInvestmentAmount;
  String get zakatRate =>
      isArabic ? HalalStringsAr.zakatRate : HalalStrings.zakatRate;
  String get fullSpecifications => isArabic
      ? HalalStringsAr.fullSpecifications
      : HalalStrings.fullSpecifications;
  String get country =>
      isArabic ? HalalStringsAr.country : HalalStrings.country;
  String get region => isArabic ? HalalStringsAr.region : HalalStrings.region;
  String get marketCap =>
      isArabic ? HalalStringsAr.marketCap : HalalStrings.marketCap;
  String get description =>
      isArabic ? HalalStringsAr.description : HalalStrings.description;
  String get fundamentals =>
      isArabic ? HalalStringsAr.fundamentals : HalalStrings.fundamentals;
  String get totalAssets =>
      isArabic ? HalalStringsAr.totalAssets : HalalStrings.totalAssets;
  String get totalDebt =>
      isArabic ? HalalStringsAr.totalDebt : HalalStrings.totalDebt;
  String get cashAndEquiv =>
      isArabic ? HalalStringsAr.cashAndEquiv : HalalStrings.cashAndEquiv;
  String get totalRevenue =>
      isArabic ? HalalStringsAr.totalRevenue : HalalStrings.totalRevenue;
  String get netIncome =>
      isArabic ? HalalStringsAr.netIncome : HalalStrings.netIncome;

  // Auth
  String get login => isArabic ? 'تسجيل الدخول' : 'Login';
  String get register => isArabic ? 'تسجيل' : 'Register';
  String get email => isArabic ? 'البريد الإلكتروني' : 'Email';
  String get password => isArabic ? 'كلمة المرور' : 'Password';
  String get confirmPassword =>
      isArabic ? 'تأكيد كلمة المرور' : 'Confirm Password';
  String get name => isArabic ? 'الاسم' : 'Name (Optional)';
  String get welcomeBack => isArabic ? 'مرحباً بعودتك' : 'Welcome Back';
  String get createAccount => isArabic ? 'إنشاء حساب جديد' : 'Create Account';
  String get dontHaveAccount =>
      isArabic ? 'ليس لديك حساب؟ سجل الآن' : 'Don\'t have an account? Register';
  String get alreadyHaveAccount => isArabic
      ? 'لديك حساب بالفعل؟ تسجيل الدخول'
      : 'Already have an account? Login';
  String get loginFailed => isArabic ? 'فشل تسجيل الدخول' : 'Login failed';
  String get registrationFailed =>
      isArabic ? 'فشل التسجيل' : 'Registration failed';
  String get emailRequired =>
      isArabic ? 'يرجى إدخال بريدك الإلكتروني' : 'Please enter your email';
  String get passwordRequired =>
      isArabic ? 'يرجى إدخال كلمة المرور' : 'Please enter your password';
  String get emailInvalid =>
      isArabic ? 'يرجى إدخال بريد إلكتروني صحيح' : 'Please enter a valid email';
  String get passwordMinLength => isArabic
      ? 'كلمة المرور يجب أن تكون 6 أحرف على الأقل'
      : 'Password must be at least 6 characters';
  String get confirmPasswordRequired =>
      isArabic ? 'يرجى تأكيد كلمة المرور' : 'Please confirm your password';
  String get passwordsDoNotMatch =>
      isArabic ? 'كلمات المرور غير متطابقة' : 'Passwords do not match';

  // Shares
  String get shares => isArabic ? 'الأسهم' : 'Shares';

  // Analyst Ratings
  String get analystRatings =>
      isArabic ? HalalStringsAr.analystRatings : HalalStrings.analystRatings;
  String get noAnalystRatings => isArabic
      ? HalalStringsAr.noAnalystRatings
      : HalalStrings.noAnalystRatings;
  String get analystName =>
      isArabic ? HalalStringsAr.analystName : HalalStrings.analystName;
  String get rating => isArabic ? HalalStringsAr.rating : HalalStrings.rating;
  String get targetPrice =>
      isArabic ? HalalStringsAr.targetPrice : HalalStrings.targetPrice;
  String get ratingDate =>
      isArabic ? HalalStringsAr.ratingDate : HalalStrings.ratingDate;
  String get source => isArabic ? HalalStringsAr.source : HalalStrings.source;
  String get buy => isArabic ? HalalStringsAr.buy : HalalStrings.buy;
  String get hold => isArabic ? HalalStringsAr.hold : HalalStrings.hold;
  String get sell => isArabic ? HalalStringsAr.sell : HalalStrings.sell;

  // Ads
  String get sponsored =>
      isArabic ? HalalStringsAr.sponsored : HalalStrings.sponsored;
  String get learnMore =>
      isArabic ? HalalStringsAr.learnMore : HalalStrings.learnMore;

  // Zakat in Stock Detail
  String get zakatCalculation => isArabic
      ? HalalStringsAr.zakatCalculation
      : HalalStrings.zakatCalculation;
  String get enterAmount =>
      isArabic ? HalalStringsAr.enterAmount : HalalStrings.enterAmount;
  String get calculatedZakat =>
      isArabic ? HalalStringsAr.calculatedZakat : HalalStrings.calculatedZakat;

  // Stock Detail Screen Sections
  String get keyMetrics =>
      isArabic ? HalalStringsAr.keyMetrics : HalalStrings.keyMetrics;
  String get stockInformation => isArabic
      ? HalalStringsAr.stockInformation
      : HalalStrings.stockInformation;
  String get shariahAssessment => isArabic
      ? HalalStringsAr.shariahAssessment
      : HalalStrings.shariahAssessment;
  String get zakatInformation => isArabic
      ? HalalStringsAr.zakatInformation
      : HalalStrings.zakatInformation;
  String get haramIncome =>
      isArabic ? HalalStringsAr.haramIncome : HalalStrings.haramIncome;
  String get purification =>
      isArabic ? HalalStringsAr.purification : HalalStrings.purification;
  String get target => isArabic ? HalalStringsAr.target : HalalStrings.target;
  String get marketSentiment =>
      isArabic ? HalalStringsAr.marketSentiment : HalalStrings.marketSentiment;
  String get fearAndGreedIndex => isArabic
      ? HalalStringsAr.fearAndGreedIndex
      : HalalStrings.fearAndGreedIndex;
  String get lastUpdatedLabel => isArabic
      ? HalalStringsAr.lastUpdatedLabel
      : HalalStrings.lastUpdatedLabel;
  String get benchmarks =>
      isArabic ? HalalStringsAr.benchmarks : HalalStrings.benchmarks;
  String get macro => isArabic ? HalalStringsAr.macro : HalalStrings.macro;
  String get health => isArabic ? HalalStringsAr.health : HalalStrings.health;
  String get currentPrice =>
      isArabic ? HalalStringsAr.currentPrice : HalalStrings.currentPrice;
  String get currentValue =>
      isArabic ? HalalStringsAr.currentValue : HalalStrings.currentValue;
  String get dayChange =>
      isArabic ? HalalStringsAr.dayChange : HalalStrings.dayChange;
  String get symbolLabel =>
      isArabic ? HalalStringsAr.symbolLabel : HalalStrings.symbolLabel;
  String get category =>
      isArabic ? HalalStringsAr.category : HalalStrings.category;
  String get lastUpdate =>
      isArabic ? HalalStringsAr.lastUpdate : HalalStrings.lastUpdate;
  String get dataSource =>
      isArabic ? HalalStringsAr.dataSource : HalalStrings.dataSource;
  String get aboutIndex =>
      isArabic ? HalalStringsAr.aboutIndex : HalalStrings.aboutIndex;
  String get references =>
      isArabic ? HalalStringsAr.references : HalalStrings.references;
  String get justNow =>
      isArabic ? HalalStringsAr.justNow : HalalStrings.justNow;
  String get liveFeed =>
      isArabic ? HalalStringsAr.liveFeed : HalalStrings.liveFeed;
  String get market => isArabic ? HalalStringsAr.market : HalalStrings.market;
  String get referencesContent => isArabic
      ? HalalStringsAr.referencesContent
      : HalalStrings.referencesContent;
  String get indexSingular =>
      isArabic ? HalalStringsAr.indexSingular : HalalStrings.indexSingular;
  String get neutral =>
      isArabic ? HalalStringsAr.neutral : HalalStrings.neutral;
  String get noHistoricalData => isArabic
      ? HalalStringsAr.noHistoricalData
      : HalalStrings.noHistoricalData;

  // Investment Details
  String get investmentDetails =>
      isArabic ? 'تفاصيل الاستثمار' : 'Investment Details';
  String get projection => isArabic ? 'التوقعات' : 'Projection';
  String get growthOverTime => isArabic ? 'النمو مع الوقت' : 'Growth Over Time';
  String get breakdown => isArabic ? 'التفاصيل' : 'Breakdown';
  String get pleaseLoginToCalculateZakat => isArabic
      ? 'يرجى تسجيل الدخول لحساب الزكاة'
      : 'Please login to calculate Zakat';
  String get pleaseLoginToViewNotifications => isArabic
      ? 'يرجى تسجيل الدخول لعرض الإشعارات'
      : 'Please login to view notifications';
  String get pleaseEnterValidValues =>
      isArabic ? 'يرجى إدخال قيم صحيحة' : 'Please enter valid values';

  // Ranges
  String get range1D =>
      isArabic ? HalalStringsAr.range1D : HalalStrings.range1D;
  String get range5D =>
      isArabic ? HalalStringsAr.range5D : HalalStrings.range5D;
  String get range1M =>
      isArabic ? HalalStringsAr.range1M : HalalStrings.range1M;
  String get range3M =>
      isArabic ? HalalStringsAr.range3M : HalalStrings.range3M;
  String get range6M =>
      isArabic ? HalalStringsAr.range6M : HalalStrings.range6M;
  String get rangeYTD =>
      isArabic ? HalalStringsAr.rangeYTD : HalalStrings.rangeYTD;
  String get range1Y =>
      isArabic ? HalalStringsAr.range1Y : HalalStrings.range1Y;
  String get range5Y =>
      isArabic ? HalalStringsAr.range5Y : HalalStrings.range5Y;
  String get rangeAll =>
      isArabic ? HalalStringsAr.rangeAll : HalalStrings.rangeAll;

  // Descriptions
  String get descSPY =>
      isArabic ? HalalStringsAr.descSPY : HalalStrings.descSPY;
  String get descQQQ =>
      isArabic ? HalalStringsAr.descQQQ : HalalStrings.descQQQ;
  String get descDIA =>
      isArabic ? HalalStringsAr.descDIA : HalalStrings.descDIA;
  String get descTNX =>
      isArabic ? HalalStringsAr.descTNX : HalalStrings.descTNX;
  String get descVXX =>
      isArabic ? HalalStringsAr.descVXX : HalalStrings.descVXX;
  String get descCL => isArabic ? HalalStringsAr.descCL : HalalStrings.descCL;
  String get descGeneric =>
      isArabic ? HalalStringsAr.descGeneric : HalalStrings.descGeneric;
  String get descSentiment =>
      isArabic ? HalalStringsAr.descSentiment : HalalStrings.descSentiment;

  // Subscription
  String get subscriptionPlans => isArabic
      ? HalalStringsAr.subscriptionPlans
      : HalalStrings.subscriptionPlans;
  String get freePlan =>
      isArabic ? HalalStringsAr.freePlan : HalalStrings.freePlan;
  String get premiumPlan =>
      isArabic ? HalalStringsAr.premiumPlan : HalalStrings.premiumPlan;
  String get perMonth =>
      isArabic ? HalalStringsAr.perMonth : HalalStrings.perMonth;
  String get currentPlan =>
      isArabic ? HalalStringsAr.currentPlan : HalalStrings.currentPlan;
  String get recommended =>
      isArabic ? HalalStringsAr.recommended : HalalStrings.recommended;
  String get upgradeNow =>
      isArabic ? HalalStringsAr.upgradeNow : HalalStrings.upgradeNow;
  String get havePromoCode =>
      isArabic ? HalalStringsAr.havePromoCode : HalalStrings.havePromoCode;
  String get enterCode =>
      isArabic ? HalalStringsAr.enterCode : HalalStrings.enterCode;
  String get apply => isArabic ? HalalStringsAr.apply : HalalStrings.apply;
  String get upgradedSuccess =>
      isArabic ? HalalStringsAr.upgradedSuccess : HalalStrings.upgradedSuccess;
  String get upgradeFailed =>
      isArabic ? HalalStringsAr.upgradeFailed : HalalStrings.upgradeFailed;
  String get basicStockSearch => isArabic
      ? HalalStringsAr.basicStockSearch
      : HalalStrings.basicStockSearch;
  String get limitedScreeningReports => isArabic
      ? HalalStringsAr.limitedScreeningReports
      : HalalStrings.limitedScreeningReports;
  String get adSupported =>
      isArabic ? HalalStringsAr.adSupported : HalalStrings.adSupported;
  String get unlimitedScreening => isArabic
      ? HalalStringsAr.unlimitedScreening
      : HalalStrings.unlimitedScreening;
  String get advancedCharts =>
      isArabic ? HalalStringsAr.advancedCharts : HalalStrings.advancedCharts;
  String get adFreeExperience => isArabic
      ? HalalStringsAr.adFreeExperience
      : HalalStrings.adFreeExperience;
  String get prioritySupport =>
      isArabic ? HalalStringsAr.prioritySupport : HalalStrings.prioritySupport;
}

extension AppLocalizationsExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations(this);
}
