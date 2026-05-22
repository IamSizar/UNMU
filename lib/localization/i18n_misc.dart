// Cross-cutting misc strings introduced during the F8 dates/numbers pass —
// e.g. the poll close-countdown phrases (a FUTURE countdown, distinct from
// LocaleFormat.relative which formats PAST "x ago" times).

const Map<String, String> miscEn = {
  'poll.closesNow': 'just now',
  'poll.closesInMin': 'in @n m',
  'poll.closesInHour': 'in @n h',
  'poll.closesInDay': 'in @n d',
  'poll.closePoll': 'Close poll',
  'poll.closesPrefix': 'closes @time',
  'poll.voteOne': '1 vote',
  'poll.votesOther': '@n votes',

  // Fear & Greed card (migrated off the legacy AppLocalizations).
  'sentiment.marketSentiment': 'Market Sentiment',
  'sentiment.fearAndGreedIndex': 'Fear & Greed Index',
  'sentiment.extremeFear': 'Extreme Fear',
  'sentiment.fear': 'Fear',
  'sentiment.neutral': 'Neutral',
  'sentiment.greed': 'Greed',
  'sentiment.extremeGreed': 'Extreme Greed',

  // Sponsored banner ad.
  'ad.sponsored': 'Sponsored',
  'ad.learnMore': 'Learn More',
  'ad.headline': 'Smart investing starts with the right data',
  'ad.subtitle': 'Unlimited screening, ad-free experience.',
  'ad.trusted': 'Trusted',
};

const Map<String, String> miscAr = {
  'poll.closesNow': 'الآن',
  'poll.closesInMin': 'بعد @n د',
  'poll.closesInHour': 'بعد @n س',
  'poll.closesInDay': 'بعد @n ي',
  'poll.closePoll': 'إغلاق التصويت',
  'poll.closesPrefix': 'يغلق @time',
  'poll.voteOne': 'صوت واحد',
  'poll.votesOther': '@n صوت',

  // Fear & Greed card (migrated off the legacy AppLocalizations).
  'sentiment.marketSentiment': 'نبض السوق',
  'sentiment.fearAndGreedIndex': 'مؤشر الخوف والطمع',
  'sentiment.extremeFear': 'خوف شديد',
  'sentiment.fear': 'خوف',
  'sentiment.neutral': 'محايد',
  'sentiment.greed': 'طمع',
  'sentiment.extremeGreed': 'طمع شديد',

  // Sponsored banner ad.
  'ad.sponsored': 'إعلان مدعوم',
  'ad.learnMore': 'اعرف المزيد',
  'ad.headline': 'استثمار ذكي يبدأ ببيانات أفضل',
  'ad.subtitle': 'افحص الأسهم بلا حدود، خالٍ من الإعلانات.',
  'ad.trusted': 'موثوق',
};
