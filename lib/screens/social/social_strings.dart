/// Localized strings for the Social & Educational feature.
///
/// Kept in a dedicated file (instead of bundling into `halal_strings.dart`)
/// so the new feature can evolve without touching the shared localization
/// file used by the rest of the app.
class SocialStrings {
  // English -----------------------------------------------------------------
  static const String social = 'Social';
  static const String topExperts = 'Top Financial Experts';
  static const String communitiesYouFollow = 'Communities You Follow';
  static const String discoverCommunities = 'Discover Communities';
  static const String subscribe = 'Subscribe';
  static const String subscribed = 'Subscribed';
  static const String join = 'Join';
  static const String joined = 'Joined';
  static const String members = 'members';
  static const String subscribers = 'subscribers';
  static const String posts = 'Posts';
  static const String reels = 'Reels';
  static const String videos = 'Videos';
  static const String chats = 'Chats';
  static const String live = 'LIVE';
  static const String verifiedExpert = 'Verified Expert';
  static const String shariahScholar = 'Shariah Scholar';
  static const String premium = 'Premium';
  static const String typeMessage = 'Type a message...';
  static const String send = 'Send';
  static const String insertSymbol = 'Insert symbol';
  static const String halalOnly = 'Halal only';
  static const String views = 'views';
  static const String likes = 'likes';
  static const String comments = 'comments';
  static const String activeNow = 'active now';
  static const String trendingNow = 'Trending now';
  static const String currentlyAnalyzing = 'Currently analyzing';
  static const String about = 'About';
  // Greeting hero & dashboard
  static const String goodMorning = 'Good morning';
  static const String goodAfternoon = 'Good afternoon';
  static const String goodEvening = 'Good evening';
  static const String yourNetwork = 'Your network';
  static const String last30d = 'Last 30 days';
  static const String topMovers = 'Top movers';
  static const String topExpertsThisWeek = 'Top experts this week';
  static const String yourCommunities = 'Your communities';
  static const String liveNow = 'Live now';
  static const String marketMood = 'Market mood';
  static const String bullish = 'Bullish';
  static const String bearish = 'Bearish';
  static const String thisWeekRank = 'This week';
  static const String marketsOpen = 'Markets open';
  static const String performance = 'Performance';

  // Arabic ------------------------------------------------------------------
  static const String socialAr = 'المجتمع';
  static const String topExpertsAr = 'كبار الخبراء الماليين';
  static const String communitiesYouFollowAr = 'المجتمعات التي تتابعها';
  static const String discoverCommunitiesAr = 'اكتشف المجتمعات';
  static const String subscribeAr = 'اشترك';
  static const String subscribedAr = 'مشترك';
  static const String joinAr = 'انضم';
  static const String joinedAr = 'منضم';
  static const String membersAr = 'عضو';
  static const String subscribersAr = 'مشترك';
  static const String postsAr = 'المنشورات';
  static const String reelsAr = 'مقاطع';
  static const String videosAr = 'فيديوهات';
  static const String chatsAr = 'المحادثات';
  static const String liveAr = 'مباشر';
  static const String verifiedExpertAr = 'خبير موثق';
  static const String shariahScholarAr = 'عالم شرعي';
  static const String premiumAr = 'مميز';
  static const String typeMessageAr = 'اكتب رسالة...';
  static const String sendAr = 'إرسال';
  static const String insertSymbolAr = 'إدراج رمز';
  static const String halalOnlyAr = 'حلال فقط';
  static const String viewsAr = 'مشاهدة';
  static const String likesAr = 'إعجاب';
  static const String commentsAr = 'تعليق';
  static const String activeNowAr = 'نشط الآن';
  static const String trendingNowAr = 'الأكثر رواجاً';
  static const String currentlyAnalyzingAr = 'يتم تحليله الآن';
  static const String aboutAr = 'حول';
  // Greeting hero & dashboard
  static const String goodMorningAr = 'صباح الخير';
  static const String goodAfternoonAr = 'مساء الخير';
  static const String goodEveningAr = 'مساء النور';
  static const String yourNetworkAr = 'شبكتك';
  static const String last30dAr = 'آخر ٣٠ يوم';
  static const String topMoversAr = 'الأكثر تحركاً';
  static const String topExpertsThisWeekAr = 'كبار الخبراء هذا الأسبوع';
  static const String yourCommunitiesAr = 'مجتمعاتك';
  static const String liveNowAr = 'مباشر الآن';
  static const String marketMoodAr = 'مزاج السوق';
  static const String bullishAr = 'صعودي';
  static const String bearishAr = 'هبوطي';
  static const String thisWeekRankAr = 'هذا الأسبوع';
  static const String marketsOpenAr = 'الأسواق مفتوحة';
  static const String performanceAr = 'الأداء';
}

/// Tiny helper that flips strings based on Arabic.
String tr({required bool isArabic, required String en, required String ar}) =>
    isArabic ? ar : en;
