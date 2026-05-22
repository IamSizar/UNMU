import 'dart:math';

/// =============================================================================
/// Mock data layer for the Social & Educational feature (UI-only build).
///
/// Everything in this file is intentionally hardcoded. When the backend is
/// ready, swap calls to `MockSocialData.*` for real `SocialService` calls.
/// The model classes themselves are stable enough to be reused as DTOs.
/// =============================================================================

/// Verification tier for an expert.
///   - none      : no badge
///   - verified  : standard cyan checkmark
///
/// SCHOLAR was retired (migration 0013). Code reading mock data still
/// references this enum; the legacy `scholar` slot is removed and any
/// formerly-scholar mock entry now uses [verified].
enum ExpertTier { none, verified }

/// A featured financial expert / influencer.
class Expert {
  final String id;
  final String name;
  final String handle;
  final String expertise;
  final ExpertTier tier;
  final int subscriberCount;
  final List<double> sparkline; // last-30-days portfolio performance
  final double pctChange; // overall % change for the displayed sparkline
  final String currentTicker; // stock currently being analyzed
  final double currentPrice;
  final double currentChangePct;
  final String shariahGrade; // A / B / C / F
  final String bio;
  final List<ExpertPost> posts;
  final List<ExpertReel> reels;
  final List<ExpertVideo> videos;

  const Expert({
    required this.id,
    required this.name,
    required this.handle,
    required this.expertise,
    required this.tier,
    required this.subscriberCount,
    required this.sparkline,
    required this.pctChange,
    required this.currentTicker,
    required this.currentPrice,
    required this.currentChangePct,
    required this.shariahGrade,
    required this.bio,
    required this.posts,
    required this.reels,
    required this.videos,
  });
}

class ExpertPost {
  final String id;
  final String authorName;
  final String timeAgo;
  final String body;
  final List<String> tickers; // referenced symbols
  final int likes;
  final int comments;

  const ExpertPost({
    required this.id,
    required this.authorName,
    required this.timeAgo,
    required this.body,
    required this.tickers,
    required this.likes,
    required this.comments,
  });
}

class ExpertReel {
  final String id;
  final String title;
  final String duration;
  final int views;
  // Procedurally generated thumbnail color (so we don't need real assets).
  final int thumbnailSeed;

  const ExpertReel({
    required this.id,
    required this.title,
    required this.duration,
    required this.views,
    required this.thumbnailSeed,
  });
}

class ExpertVideo {
  final String id;
  final String title;
  final String description;
  final String duration;
  final int views;
  final String publishedAgo;
  final int thumbnailSeed;

  const ExpertVideo({
    required this.id,
    required this.title,
    required this.description,
    required this.duration,
    required this.views,
    required this.publishedAgo,
    required this.thumbnailSeed,
  });
}

/// A market-focused community / forum.
class Community {
  final String id;
  final String name;
  final String tagline;
  final String regionCode; // matches existing region codes (GCC, US, etc.)
  final int memberCount;
  final int activeNow;
  final List<TickerQuote> liveTickers;
  final List<ChatMessage> chatMessages;
  final List<CommunityPost> posts;
  final List<ExpertReel> reels;
  final List<ExpertVideo> videos;
  /// User id of the community owner. Drives the "⚙ Owner" gear in the
  /// detail page header — only the owner sees it. null = no owner
  /// declared (legacy / admin-managed). Lookup the actual member
  /// roster via [MockSocialData.mockMembersFor] keyed off [id].
  final int? ownerId;

  /// Wide banner image used at the top of the community detail page.
  /// Empty string when none has been uploaded — UI falls back to a
  /// region-tinted gradient block.
  final String coverUrl;

  /// Square logo (mig 0028) shown in compact tiles + as the small
  /// avatar overlapping the cover on the detail page. Empty string
  /// when none has been uploaded — UI falls back to the initials tile.
  final String avatarUrl;

  const Community({
    required this.id,
    required this.name,
    required this.tagline,
    required this.regionCode,
    required this.memberCount,
    required this.activeNow,
    required this.liveTickers,
    required this.chatMessages,
    required this.posts,
    required this.reels,
    required this.videos,
    this.ownerId,
    this.coverUrl = '',
    this.avatarUrl = '',
  });
}

/// One row in the Members tab. Mirrors the backend
/// repositories.AdminCommunityMember shape so swapping mock → real
/// data is a one-line change at the call site.
class CommunityMember {
  final int userId;
  final String name;
  final String email;
  final String role; // 'USER' | 'EXPERT' | 'ADMIN'
  final DateTime joinedAt;
  final bool isOwner;

  const CommunityMember({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.joinedAt,
    this.isOwner = false,
  });
}

class TickerQuote {
  final String symbol;
  final double price;
  final double changePct;
  final String shariahGrade;

  const TickerQuote({
    required this.symbol,
    required this.price,
    required this.changePct,
    required this.shariahGrade,
  });
}

class ChatMessage {
  final String id;
  final String author;
  final String timeAgo;
  final String body;
  final List<String> tickers;
  final bool isCurrentUser;

  const ChatMessage({
    required this.id,
    required this.author,
    required this.timeAgo,
    required this.body,
    required this.tickers,
    this.isCurrentUser = false,
  });
}

class CommunityPost {
  final String id;
  final String author;
  final String timeAgo;
  final String title;
  final String body;
  final String ticker;
  final String stance; // BUY / HOLD / SELL
  final int upvotes;
  final int comments;
  // Cover image URL (e.g. a shared index chart). Empty when the post has
  // no image. Full https URL (S3) or a /uploads/ path.
  final String coverUrl;
  // Author user id — drives the "is this my post?" moderation check on the
  // community detail screen. 0 for mock/in-memory posts that don't carry it.
  final int authorId;
  // Soft-moderation flag. Hidden posts are still listed for moderators (so
  // they can un-hide) but rendered dimmed with a "Hidden" badge.
  final bool isHidden;

  const CommunityPost({
    required this.id,
    required this.author,
    required this.timeAgo,
    required this.title,
    required this.body,
    required this.ticker,
    required this.stance,
    required this.upvotes,
    required this.comments,
    this.coverUrl = '',
    this.authorId = 0,
    this.isHidden = false,
  });
}

/// =============================================================================
/// Static mock dataset.
/// =============================================================================
class MockSocialData {
  /// Inserts a new community post at the top of [community.posts] in-place
  /// (so listening pages refresh on next rebuild). Used by the in-app post
  /// composer; replace with a real API call when the backend is wired up.
  static void prependCommunityPost(Community community, CommunityPost post) {
    community.posts.insert(0, post);
  }

  /// Same idea for an expert posting on their own profile.
  static void prependExpertPost(Expert expert, ExpertPost post) {
    expert.posts.insert(0, post);
  }

  /// Lookup helper used by the auth layer when an expert/scholar logs in —
  /// resolves an expert id (e.g. "e2") to the [Expert] record.
  static Expert? findExpertById(String? id) {
    if (id == null) return null;
    for (final e in experts) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Generates a smooth-but-jittery sparkline shape.
  static List<double> _spark(int seed, {bool uptrend = true}) {
    final rng = Random(seed);
    final points = <double>[];
    double v = 100;
    for (int i = 0; i < 30; i++) {
      final drift = (uptrend ? 0.5 : -0.5) + rng.nextDouble() * 1.6 - 0.8;
      v += drift;
      points.add(v);
    }
    return points;
  }

  /// A reusable list of experts shown on the Social Hub.
  static List<Expert> experts = [
    Expert(
      id: 'e1',
      name: 'Ahmad Al-Rashid',
      handle: '@ahmad_invests',
      expertise: 'GCC Markets · Halal ETFs',
      tier: ExpertTier.verified,
      subscriberCount: 48230,
      sparkline: _spark(11, uptrend: true),
      pctChange: 12.4,
      currentTicker: 'ARAMCO',
      currentPrice: 32.85,
      currentChangePct: 1.92,
      shariahGrade: 'A',
      bio:
          'Certified Shariah scholar and equity analyst. 12+ years covering '
          'GCC large-caps and halal ETFs. Speaks on AAOIFI standards.',
      posts: _samplePosts('Ahmad Al-Rashid'),
      reels: _sampleReels(seedBase: 100),
      videos: _sampleVideos(seedBase: 200),
    ),
    Expert(
      id: 'e2',
      name: 'Sarah Chen',
      handle: '@sarah_tech',
      expertise: 'US Tech · Growth Stocks',
      tier: ExpertTier.verified,
      subscriberCount: 92110,
      sparkline: _spark(22, uptrend: true),
      pctChange: 8.1,
      currentTicker: 'NVDA',
      currentPrice: 124.50,
      currentChangePct: 2.43,
      shariahGrade: 'B',
      bio:
          'Senior research analyst focused on US tech megacaps and AI '
          'infrastructure plays. Weekly deep-dives every Sunday.',
      posts: _samplePosts('Sarah Chen'),
      reels: _sampleReels(seedBase: 110),
      videos: _sampleVideos(seedBase: 210),
    ),
  ];

  /// Communities on the Social Hub.
  static List<Community> communities = [
    Community(
      id: 'c1',
      name: 'GCC Markets',
      tagline: 'Saudi · UAE · Qatar — daily flow',
      regionCode: 'GCC',
      memberCount: 18420,
      activeNow: 312,
      liveTickers: const [
        TickerQuote(
          symbol: 'ARAMCO',
          price: 32.85,
          changePct: 1.92,
          shariahGrade: 'A',
        ),
        TickerQuote(
          symbol: 'STC',
          price: 39.10,
          changePct: 0.41,
          shariahGrade: 'A',
        ),
        TickerQuote(
          symbol: 'EMAAR',
          price: 8.42,
          changePct: -0.85,
          shariahGrade: 'A',
        ),
        TickerQuote(
          symbol: 'QNB',
          price: 16.20,
          changePct: 0.12,
          shariahGrade: 'C',
        ),
      ],
      chatMessages: _sampleChats(),
      posts: _samplePostsCommunity(),
      reels: _sampleReels(seedBase: 300),
      videos: _sampleVideos(seedBase: 310),
      ownerId: 1003, // Ahmad Al-Rashid (scholar@test.com)
    ),
    Community(
      id: 'c2',
      name: 'US Halal Tech',
      tagline: 'Shariah-friendly tech megacaps',
      regionCode: 'US',
      memberCount: 26180,
      activeNow: 588,
      liveTickers: const [
        TickerQuote(
          symbol: 'AAPL',
          price: 187.92,
          changePct: 0.84,
          shariahGrade: 'B',
        ),
        TickerQuote(
          symbol: 'MSFT',
          price: 412.15,
          changePct: 1.10,
          shariahGrade: 'B',
        ),
        TickerQuote(
          symbol: 'NVDA',
          price: 124.50,
          changePct: 2.43,
          shariahGrade: 'B',
        ),
        TickerQuote(
          symbol: 'GOOGL',
          price: 168.20,
          changePct: -0.32,
          shariahGrade: 'B',
        ),
      ],
      chatMessages: _sampleChats(),
      posts: _samplePostsCommunity(),
      reels: _sampleReels(seedBase: 320),
      videos: _sampleVideos(seedBase: 330),
      ownerId: 1002, // Sarah Chen (expert@test.com)
    ),
    Community(
      id: 'c3',
      name: 'MENA Energy & Industrials',
      tagline: 'Petrochems, utilities, logistics',
      regionCode: 'MENA',
      memberCount: 9840,
      activeNow: 142,
      liveTickers: const [
        TickerQuote(
          symbol: 'SABIC',
          price: 71.40,
          changePct: 0.92,
          shariahGrade: 'B',
        ),
        TickerQuote(
          symbol: 'MAADEN',
          price: 54.10,
          changePct: -0.21,
          shariahGrade: 'A',
        ),
        TickerQuote(
          symbol: 'DEWA',
          price: 2.61,
          changePct: 1.55,
          shariahGrade: 'A',
        ),
      ],
      chatMessages: _sampleChats(),
      posts: _samplePostsCommunity(),
      reels: _sampleReels(seedBase: 340),
      videos: _sampleVideos(seedBase: 350),
      ownerId: 2027, // Fatima Al-Zahrani (fatima@test.com)
    ),
    Community(
      id: 'c4',
      name: 'Asia Shariah Movers',
      tagline: 'Malaysia · Indonesia · Pakistan',
      regionCode: 'ASIA',
      memberCount: 7220,
      activeNow: 98,
      liveTickers: const [
        TickerQuote(
          symbol: 'MAY',
          price: 9.85,
          changePct: 0.51,
          shariahGrade: 'A',
        ),
        TickerQuote(
          symbol: 'TLKM',
          price: 3450,
          changePct: -0.42,
          shariahGrade: 'B',
        ),
      ],
      chatMessages: _sampleChats(),
      posts: _samplePostsCommunity(),
      reels: _sampleReels(seedBase: 360),
      videos: _sampleVideos(seedBase: 370),
      ownerId: 2025, // Aisha Khalil (aisha@test.com)
    ),
    Community(
      id: 'c5',
      name: 'Sukuk & Islamic Finance',
      tagline: 'Fixed income · global sukuk',
      regionCode: 'GLOBAL',
      memberCount: 5410,
      activeNow: 41,
      liveTickers: const [
        TickerQuote(
          symbol: 'IIF',
          price: 102.30,
          changePct: 0.08,
          shariahGrade: 'A',
        ),
        TickerQuote(
          symbol: 'ISDB',
          price: 99.85,
          changePct: -0.05,
          shariahGrade: 'A',
        ),
      ],
      chatMessages: _sampleChats(),
      posts: _samplePostsCommunity(),
      reels: _sampleReels(seedBase: 380),
      videos: _sampleVideos(seedBase: 390),
      ownerId: 2029, // Sheikh Abdullah (sheikh.abdullah@test.com)
    ),
  ];

  /// Stable mock member roster for the Members tab. Keyed off
  /// community.id — call this in the detail screen instead of carrying
  /// a `List<CommunityMember>` on every Community constructor (keeps
  /// the model lean while letting us scale member counts up later).
  ///
  /// Member ids + emails match the test accounts seeded in migration
  /// 0012, so when this view is later swapped for a real backend
  /// fetch, the same names + roles will appear.
  static List<CommunityMember> mockMembersFor(String communityId) {
    DateTime daysAgo(int n) =>
        DateTime.now().subtract(Duration(days: n, hours: n * 2));
    switch (communityId) {
      case 'c1': // GCC Markets — owner = Ahmad
        return [
          CommunityMember(userId: 1003, name: 'Ahmad Al-Rashid', email: 'scholar@test.com', role: 'EXPERT', joinedAt: daysAgo(40), isOwner: true),
          CommunityMember(userId: 2027, name: 'Fatima Al-Zahrani', email: 'fatima@test.com', role: 'EXPERT', joinedAt: daysAgo(28)),
          CommunityMember(userId: 1001, name: 'Sizar', email: 'user@test.com', role: 'USER', joinedAt: daysAgo(20)),
          CommunityMember(userId: 2030, name: 'Khaled Mansour', email: 'khaled@test.com', role: 'USER', joinedAt: daysAgo(7)),
          CommunityMember(userId: 2029, name: 'Sheikh Abdullah Al-Mansoori', email: 'sheikh.abdullah@test.com', role: 'EXPERT', joinedAt: daysAgo(5)),
        ];
      case 'c2': // US Halal Tech — owner = Sarah
        return [
          CommunityMember(userId: 1002, name: 'Sarah Chen', email: 'expert@test.com', role: 'EXPERT', joinedAt: daysAgo(50), isOwner: true),
          CommunityMember(userId: 2025, name: 'Aisha Khalil', email: 'aisha@test.com', role: 'EXPERT', joinedAt: daysAgo(35)),
          CommunityMember(userId: 1004, name: 'You', email: 'you@test.com', role: 'EXPERT', joinedAt: daysAgo(22)),
          CommunityMember(userId: 2031, name: 'Layla Hassan', email: 'layla@test.com', role: 'USER', joinedAt: daysAgo(11)),
          CommunityMember(userId: 2032, name: 'Omar Khalil', email: 'omar@test.com', role: 'USER', joinedAt: daysAgo(4)),
        ];
      case 'c3': // MENA Energy — owner = Fatima
        return [
          CommunityMember(userId: 2027, name: 'Fatima Al-Zahrani', email: 'fatima@test.com', role: 'EXPERT', joinedAt: daysAgo(38), isOwner: true),
          CommunityMember(userId: 1003, name: 'Ahmad Al-Rashid', email: 'scholar@test.com', role: 'EXPERT', joinedAt: daysAgo(30)),
          CommunityMember(userId: 2029, name: 'Sheikh Abdullah Al-Mansoori', email: 'sheikh.abdullah@test.com', role: 'EXPERT', joinedAt: daysAgo(18)),
          CommunityMember(userId: 2030, name: 'Khaled Mansour', email: 'khaled@test.com', role: 'USER', joinedAt: daysAgo(9)),
        ];
      case 'c4': // Asia Shariah — owner = Aisha
        return [
          CommunityMember(userId: 2025, name: 'Aisha Khalil', email: 'aisha@test.com', role: 'EXPERT', joinedAt: daysAgo(36), isOwner: true),
          CommunityMember(userId: 1002, name: 'Sarah Chen', email: 'expert@test.com', role: 'EXPERT', joinedAt: daysAgo(20)),
          CommunityMember(userId: 1004, name: 'You', email: 'you@test.com', role: 'EXPERT', joinedAt: daysAgo(13)),
          CommunityMember(userId: 2032, name: 'Omar Khalil', email: 'omar@test.com', role: 'USER', joinedAt: daysAgo(6)),
        ];
      case 'c5': // Sukuk & Islamic Finance — owner = Sheikh Abdullah
        return [
          CommunityMember(userId: 2029, name: 'Sheikh Abdullah Al-Mansoori', email: 'sheikh.abdullah@test.com', role: 'EXPERT', joinedAt: daysAgo(45), isOwner: true),
          CommunityMember(userId: 2028, name: 'Dr. Yusuf Rahman', email: 'dr.yusuf@test.com', role: 'EXPERT', joinedAt: daysAgo(32)),
          CommunityMember(userId: 2026, name: 'Mufti Bilal Khan', email: 'mufti.bilal@test.com', role: 'EXPERT', joinedAt: daysAgo(24)),
          CommunityMember(userId: 1001, name: 'Sizar', email: 'user@test.com', role: 'USER', joinedAt: daysAgo(8)),
          CommunityMember(userId: 2031, name: 'Layla Hassan', email: 'layla@test.com', role: 'USER', joinedAt: daysAgo(3)),
        ];
    }
    return const [];
  }

  /// Sample TradingView-style chart data (intraday).
  static List<double> intradayChart() {
    final rng = Random(7);
    final out = <double>[];
    double v = 124.50;
    for (int i = 0; i < 80; i++) {
      v += rng.nextDouble() * 1.4 - 0.65;
      out.add(v);
    }
    return out;
  }

  // ---- Sample-builder helpers --------------------------------------------

  static List<ExpertPost> _samplePosts(String author) => [
    ExpertPost(
      id: 'p1',
      authorName: author,
      timeAgo: '2h',
      body:
          'Just rebalanced my Halal core portfolio — adding more weight to '
          'industrials and trimming consumer discretionary. Keeping debt '
          'screen tight at <25%.',
      tickers: const ['SABIC', 'MAADEN'],
      likes: 412,
      comments: 38,
    ),
    ExpertPost(
      id: 'p2',
      authorName: author,
      timeAgo: '8h',
      body:
          'Aramco delivering steady free cash flow. Grade A on the screener — '
          'still my anchor position for GCC exposure.',
      tickers: const ['ARAMCO'],
      likes: 980,
      comments: 112,
    ),
    ExpertPost(
      id: 'p3',
      authorName: author,
      timeAgo: '1d',
      body:
          'Quick reminder on purification: even on grade B names you may need '
          'to purify ~1-3% of dividends. I cover the math in this week\'s '
          'masterclass.',
      tickers: const [],
      likes: 271,
      comments: 22,
    ),
  ];

  static List<ExpertReel> _sampleReels({required int seedBase}) => [
    ExpertReel(
      id: 'r${seedBase + 1}',
      title: 'How I screen Halal stocks',
      duration: '0:48',
      views: 24300,
      thumbnailSeed: seedBase + 1,
    ),
    ExpertReel(
      id: 'r${seedBase + 2}',
      title: 'Debt ratio explained',
      duration: '1:12',
      views: 18120,
      thumbnailSeed: seedBase + 2,
    ),
    ExpertReel(
      id: 'r${seedBase + 3}',
      title: 'Top 3 GCC dividend plays',
      duration: '0:55',
      views: 31040,
      thumbnailSeed: seedBase + 3,
    ),
    ExpertReel(
      id: 'r${seedBase + 4}',
      title: 'NVDA earnings recap',
      duration: '1:30',
      views: 47800,
      thumbnailSeed: seedBase + 4,
    ),
    ExpertReel(
      id: 'r${seedBase + 5}',
      title: 'Sukuk vs bonds — 60s',
      duration: '1:00',
      views: 9650,
      thumbnailSeed: seedBase + 5,
    ),
    ExpertReel(
      id: 'r${seedBase + 6}',
      title: 'Zakat on stocks',
      duration: '0:40',
      views: 12200,
      thumbnailSeed: seedBase + 6,
    ),
  ];

  static List<ExpertVideo> _sampleVideos({required int seedBase}) => [
    ExpertVideo(
      id: 'v${seedBase + 1}',
      title: 'Masterclass: Building a Halal portfolio from scratch',
      description:
          'A complete walkthrough — picking the universe, applying Shariah '
          'screens, sizing positions, rebalancing.',
      duration: '32:14',
      views: 84200,
      publishedAgo: '3 days ago',
      thumbnailSeed: seedBase + 1,
    ),
    ExpertVideo(
      id: 'v${seedBase + 2}',
      title: 'Webinar: GCC market outlook 2026',
      description:
          'Deep dive into Saudi, UAE and Qatar — sector by sector. Q&A at '
          'the end.',
      duration: '54:02',
      views: 41100,
      publishedAgo: '1 week ago',
      thumbnailSeed: seedBase + 2,
    ),
    ExpertVideo(
      id: 'v${seedBase + 3}',
      title: 'Purification math, in detail',
      description:
          'How to compute the purification amount for grade B/C names with '
          'mixed income — worked examples.',
      duration: '18:47',
      views: 22980,
      publishedAgo: '2 weeks ago',
      thumbnailSeed: seedBase + 3,
    ),
  ];

  static List<ChatMessage> _sampleChats() => const [
    ChatMessage(
      id: 'm1',
      author: 'Khaled',
      timeAgo: '2m',
      body: 'Anyone watching ARAMCO today? Looks like a clean breakout.',
      tickers: ['ARAMCO'],
    ),
    ChatMessage(
      id: 'm2',
      author: 'Mariam',
      timeAgo: '2m',
      body: 'Volume is solid. Holding mine.',
      tickers: [],
    ),
    ChatMessage(
      id: 'm3',
      author: 'Bilal',
      timeAgo: '1m',
      body: 'Trimmed half my SABIC, rotating into MAADEN.',
      tickers: ['SABIC', 'MAADEN'],
    ),
    ChatMessage(
      id: 'm4',
      author: 'You',
      timeAgo: 'now',
      body: 'Same — MAADEN debt ratio is much cleaner this quarter.',
      tickers: ['MAADEN'],
      isCurrentUser: true,
    ),
  ];

  static List<CommunityPost> _samplePostsCommunity() => const [
    CommunityPost(
      id: 'cp1',
      author: 'Ahmad Al-Rashid',
      timeAgo: '3h',
      title: 'ARAMCO Q1 — what the dividend tells us',
      body:
          'Free cash flow remains strong. Even with capex pressure, the '
          'payout looks safe. Sticking with my BUY thesis.',
      ticker: 'ARAMCO',
      stance: 'BUY',
      upvotes: 312,
      comments: 47,
    ),
  ];
}
