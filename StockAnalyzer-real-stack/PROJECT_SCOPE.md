# Project Scope: HalalStocks

## 1. Product Summary

HalalStocks is a cross-platform Islamic investing application made of:

- A Flutter client for iOS, Android, Web, macOS, Linux, and Windows
- A Go backend API using Gin and PostgreSQL
- A stock ingestion and Shariah-screening pipeline with multiple market-data provider options

The product combines stock discovery, Shariah compliance analysis, watchlist/portfolio tracking, zakat and DCA tools, market sentiment/index tracking, subscriptions, ads, promo codes, and bilingual UX.

## 2. Core Product Purpose

The system is designed to help Muslim investors:

- Discover stocks by region
- Check whether a stock appears Shariah-compliant
- Understand why a stock is graded as compliant, doubtful, mixed, or haram
- Track followed holdings and get notifications when status changes
- Use practical Islamic-finance tools such as zakat and DCA calculators
- Access premium market content via subscription

## 3. Primary User-Facing Scope

### 3.1 Authentication and Session Management

Implemented in the Flutter app and backend API:

- User registration
- User login
- JWT-based authenticated sessions
- Local persistence of token and user profile via shared preferences
- Logout flow

Relevant files:

- `/lib/providers/auth_provider.dart`
- `/lib/services/auth_service.dart`
- `/backend/internal/handlers/auth.go`
- `/backend/internal/middleware/auth.go`

### 3.2 Stock Discovery

The app supports public stock browsing and search:

- Default Discover tab loads the `GLOBAL` stock list
- Region-based stock browsing via backend region endpoint
- Local client-side filtering by Shariah status
- Search by ticker or company name with debounced querying
- Stock cards leading to stock detail pages

Relevant files:

- `/lib/screens/discover/discover_screen.dart`
- `/lib/screens/discover/search_screen.dart`
- `/lib/providers/stocks_provider.dart`
- `/backend/internal/handlers/public.go`

### 3.3 Stock Detail and Shariah Analysis

Each stock can expose:

- Company basics
- Fundamentals
- Shariah status
- Grade
- Debt ratio
- Haram income ratio
- Purification guidance
- Explanation and reasoning text
- Analyst ratings
- Manual per-stock zakat estimate based on entered investment amount
- Follow/unfollow action

The backend also performs on-demand screening if a stock has fundamentals but no cached status.

Relevant files:

- `/lib/screens/stock_detail/stock_detail_screen.dart`
- `/backend/internal/handlers/public.go`
- `/backend/internal/services/shariah_engine.go`
- `/backend/internal/shariah/screener.go`
- `/backend/internal/shariah/rules.go`

### 3.4 Watchlist / Portfolio

The product uses the backend `user_portfolios` table as both:

- A watchlist/following mechanism
- A lightweight portfolio store with optional shares and average buy price

Implemented capabilities:

- Add stock to user portfolio/watchlist
- Remove stock from portfolio/watchlist
- Load authenticated user watchlist
- Open stock detail from watchlist entries

Relevant files:

- `/lib/providers/watchlist_provider.dart`
- `/lib/screens/watchlist/watchlist_screen.dart`
- `/backend/internal/handlers/user.go`
- `/backend/internal/repositories/portfolio.go`

### 3.5 Notifications

The backend supports notification storage for status/purification changes, and the app has a notifications screen that:

- Loads user notifications
- Shows read/unread state
- Formats relative timestamps
- Attempts to deep-link to stock detail if ticker/exchange data exists in the payload

Relevant files:

- `/lib/screens/notifications/notifications_screen.dart`
- `/backend/internal/handlers/user.go`
- `/backend/internal/repositories/notification.go`
- `/backend/internal/services/ingestion.go`

### 3.6 Islamic Finance Tools

Implemented tools:

- Zakat calculator
  - Manual tab for generic asset-based zakat
  - Portfolio tab using backend portfolio calculation
- DCA calculator
  - Monthly contribution
  - Years
  - Annual return
  - Summary and yearly breakdown

Relevant files:

- `/lib/screens/tools/tools_screen.dart`
- `/lib/screens/tools/zakat_calculator_screen.dart`
- `/lib/screens/tools/dca_calculator_screen.dart`
- `/backend/internal/handlers/tools.go`

### 3.7 Market Intelligence

The app includes a dedicated indexes/market screen with:

- Fear & Greed index
- Categorized market indexes
- Premium-gated live refresh every 30 seconds
- Free-tier restricted content visibility
- Ad placement for free users

The backend exposes:

- Fear and Greed endpoint
- Indexes endpoint
- Exchange rate endpoint

Relevant files:

- `/lib/screens/indexes/indexes_screen.dart`
- `/lib/providers/stocks_provider.dart`
- `/backend/internal/handlers/market.go`
- `/backend/internal/marketdata/*.go`

### 3.8 Subscription, Monetization, Ads, Promo Codes

Implemented monetization scope includes:

- Free vs premium UX branching in the client
- In-app purchase product loading
- Monthly and annual subscription SKUs
- Backend subscription upgrade/cancel endpoints
- Promo code validation endpoint and client UI
- Regional banner ads for free users

Relevant files:

- `/lib/screens/subscription/subscription_screen.dart`
- `/lib/services/iap_service.dart`
- `/lib/services/promo_service.dart`
- `/lib/widgets/ads/banner_ad_widget.dart`
- `/backend/internal/handlers/subscription.go`
- `/backend/internal/handlers/promo.go`
- `/backend/internal/handlers/ads.go`

### 3.9 Personalization and UX

Implemented app-level preferences:

- Dark/light theme
- English and Arabic UI
- RTL support for Arabic
- Currency preference with exchange-rate conversion
- Platform-adaptive widgets for Material/Cupertino behavior

Relevant files:

- `/lib/main.dart`
- `/lib/providers/theme_provider.dart`
- `/lib/providers/language_provider.dart`
- `/lib/providers/currency_provider.dart`
- `/lib/widgets/platform_adaptive/*`

## 4. Backend Scope

### 4.1 API Layer

The backend exposes public and protected endpoints for:

- Health check
- Auth
- Search
- Stock details
- Region stock lists
- Ads
- Market data
- DCA
- Portfolio/watchlist
- Notifications
- Zakat
- Promo validation
- Subscription upgrade/cancel

Primary entrypoint:

- `/backend/cmd/api/main.go`

### 4.2 Persistence Layer

The PostgreSQL schema currently covers:

- `users`
- `stocks`
- `fundamentals`
- `shariah_status`
- `user_portfolios`
- `notifications`
- `analyst_ratings`
- `ads`
- `promo_codes`
- `user_promo_usage`

Later migrations also add:

- subscription fields on `users`
- pipeline/time-series support tables through additional migration files

Relevant files:

- `/backend/migrations/000001_initial_schema.up.sql`
- `/backend/migrations/000002_pipeline_schema.up.sql`
- `/backend/migrations/000003_market_data.up.sql`
- `/backend/migrations/000005_add_subscriptions.up.sql`

### 4.3 Data Ingestion and Screening

There are two overlapping backend layers:

1. A direct ingestion service used by the classic app backend
2. A more production-oriented pipeline package with provider registry and worker-pool updates

Implemented ingestion responsibilities:

- Fetch stock universes by region
- Fetch fundamentals
- Persist stocks and fundamentals
- Run Shariah screening
- Upsert current Shariah status
- Generate notifications for meaningful status changes

Relevant files:

- `/backend/internal/services/ingestion.go`
- `/backend/cmd/ingest/main.go`
- `/backend/internal/pipeline/*`
- `/backend/cmd/daily_update/main.go`

### 4.4 External Data Provider Scope

The codebase supports multiple provider strategies:

- FMP
- Alpha Vantage
- DataJockey
- EODHD-related references and provider code

Provider usage depends on environment configuration and appears to have evolved over time.

Relevant files:

- `/backend/internal/marketdata/fmp_provider.go`
- `/backend/internal/marketdata/alphavantage_provider.go`
- `/backend/internal/marketdata/datajockey_provider.go`
- `/backend/internal/marketdata/eodhd_provider.go`
- `/backend/internal/pipeline/providers/*`

## 5. Business Logic Scope

### 5.1 Shariah Screening Model

The system currently applies:

- Activity screening against prohibited sectors/keywords
- Financial ratio screening using debt and impure income thresholds
- Grades from A to F or similar variants depending on the engine in use
- Purification-rate output
- Zakat-related flags

Important note:

There are two separate Shariah engines in the codebase:

- `/backend/internal/services/shariah_engine.go`
- `/backend/internal/shariah/screener.go`

They do not use the exact same status vocabulary or thresholds. This is part of the actual project scope because it affects output consistency.

### 5.2 Premium Entitlements

Premium affects client experience through:

- Search result limits for free users
- Ad visibility for free users
- Expanded indexes content for premium users
- 30-second market auto-refresh for premium users

This gating exists mostly in the client today.

## 6. Platform and Deployment Scope

### 6.1 Supported Platforms

Flutter targets present in the repository:

- Android
- iOS
- Web
- macOS
- Linux
- Windows

### 6.2 Deployment

Deployment artifacts indicate Railway hosting for the backend:

- Root `railway.toml`
- `/backend/railway.toml`
- `/backend/Dockerfile`

The client is configured by default to hit a deployed Railway API URL:

- `/lib/config/api_config.dart`

## 7. Documentation and Operational Scope

The repository contains substantial operational documentation for:

- Setup and quick start
- iOS running/setup
- ingestion checks
- screening completion
- backend provider switching
- pipeline architecture
- free API options
- IAP setup

This indicates the project scope includes not just product code but also deployment and data-operations workflows.

Representative files:

- `/README.md`
- `/QUICK_START.md`
- `/IAP_README.md`
- `/backend/PIPELINE_README.md`
- `/backend/PIPELINE_ARCHITECTURE.md`
- `/backend/API_PROVIDERS_GUIDE.md`

## 8. Current State Assessment

### 8.1 What is clearly implemented

- End-to-end auth
- Region/search-based stock discovery
- Stock detail with Shariah output
- Watchlist/portfolio CRUD
- Zakat and DCA tools
- Market/indexes screen
- Localization, theming, currency preferences
- Subscription UI and IAP integration scaffolding
- Ads and promo code paths
- Backend ingestion and screening pipelines

### 8.2 What appears partial, inconsistent, or risky

- Premium state is hardcoded to `true` in the client auth provider
- Subscription handler reads `userID`, but auth middleware sets `user_id`
- Documentation references endpoints that do not exist or no longer match implementation
- Multiple market-data provider strategies and docs show historical drift
- Two different Shariah engines can produce inconsistent status vocabularies
- Portfolio doubles as watchlist, which may be intentional but is conceptually mixed
- Flutter test suite is mostly boilerplate and not aligned with the current app
- Overall automated test coverage is minimal

Relevant files for these gaps:

- `/lib/providers/auth_provider.dart`
- `/backend/internal/handlers/subscription.go`
- `/backend/internal/middleware/auth.go`
- `/test/widget_test.dart`

## 9. Effective Scope Statement

In practical terms, HalalStocks is an Islamic investing companion platform whose present scope is:

- Consumer mobile-first stock discovery and screening
- Shariah-compliance evaluation backed by imported fundamentals
- Personal tracking through watchlist/portfolio and notifications
- Islamic finance utility tooling
- Market sentiment and index monitoring
- Subscription-based monetization with ads and promo codes
- Cross-platform Flutter delivery
- Go/Postgres backend with ingest-and-screen data operations

It is beyond a simple stock screener. It is a full product foundation covering data ingestion, screening logic, user accounts, monetization, preferences, and investor tools. At the same time, it is still in an in-progress state, with several scope areas present in code but not yet fully normalized into a production-consistent system.
