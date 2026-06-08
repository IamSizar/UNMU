package main

import (
	"context"
	"halalstocks/internal/config"
	"halalstocks/internal/db"
	"halalstocks/internal/handlers"
	"halalstocks/internal/marketdata"
	"halalstocks/internal/middleware"
	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"halalstocks/pkg/jwt"
	"log"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize JWT
	jwt.Init(cfg.JWTSecret)

	// Connect to database
	database, err := db.Connect(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer database.Close()

	// Initialize repositories
	userRepo := repositories.NewUserRepository(database)
	stockRepo := repositories.NewStockRepository(database)
	fundamentalRepo := repositories.NewFundamentalRepository(database)
	shariahRepo := repositories.NewShariahStatusRepository(database)
	portfolioRepo := repositories.NewPortfolioRepository(database)
	notificationRepo := repositories.NewNotificationRepository(database)
	analystRepo := repositories.NewAnalystRatingRepository(database)
	adRepo := repositories.NewAdRepository(database)
	promoRepo := repositories.NewPromoCodeRepository(database)
	marketRepo := repositories.NewMarketRepository(database)
	socialRepo := repositories.NewSocialRepository(database)
	expertAppRepo := repositories.NewExpertApplicationRepository(database)
	auditRepo := repositories.NewAuditRepository(database)
	emailVerifyRepo := repositories.NewEmailVerificationRepository(database)
	expertSubRepo := repositories.NewExpertSubscriptionRepository(database)
	// post_events table (migration 0010). Powers the share / deep-link /
	// reel-load-failed instrumentation surfaced in the admin dashboard.
	postEventsRepo := repositories.NewPostEventsRepository(database)
	// community_proposals table (migration 0011). Drives the
	// expert-proposes / admin-approves community flow.
	communityProposalsRepo := repositories.NewCommunityProposalsRepository(database)
	// support_threads + support_messages (mig 0029) — built-in user ↔
	// admin chat surfaced from Settings → Contact Admin.
	supportRepo := repositories.NewSupportRepository(database)
	// community_messages table (migration 0014). Real per-community
	// chat — list + send, gated on community membership.
	communityMessagesRepo := repositories.NewCommunityMessagesRepository(database)
	// community_polls + options + votes (mig 0021, item 5.21).
	communityPollsRepo := repositories.NewCommunityPollsRepository(database)
	// Step-23 (mig 0022) — paid community memberships.
	communitySubsRepo := repositories.NewCommunitySubscriptionsRepository(database)

	// Initialize Services
	shariahEngine := services.NewShariahEngineService()

	// Initialize Market Provider
	var marketProvider marketdata.MarketDataProvider
	switch cfg.StockAPIProvider {
	case "alphavantage", "alpha":
		avp := marketdata.NewAlphaVantageProvider(cfg.AlphaVantageAPIKey)
		avp.SetStore(marketRepo)
		marketProvider = avp
	case "fmp":
		marketProvider = marketdata.NewFMPProvider(cfg.StockAPIKey)
	case "datajockey":
		marketProvider = marketdata.NewDataJockeyProvider(cfg.DataJockeyAPIKey)
	case "eodhd":
		ep := marketdata.NewEODHDProvider(cfg.EODHDAPIKey)
		ep.SetStore(marketRepo)
		marketProvider = ep
	case "mock":
		// Deterministic in-memory provider — no API quotas, no network
		// flakiness. Use for local dev / demo / when external provider
		// keys are dead. Switch back to a real provider via the
		// STOCK_API_PROVIDER env var.
		marketProvider = marketdata.NewMockProvider()
	default:
		avp := marketdata.NewAlphaVantageProvider(cfg.AlphaVantageAPIKey)
		avp.SetStore(marketRepo)
		marketProvider = avp
	}

	// SMTP email sender (verification codes, password-reset links). Soft-
	// fails to nil when SMTP_HOST isn't set — handlers degrade to
	// stdout-only behavior in that case (still works for dev).
	emailSender := services.NewEmailSender()
	if emailSender == nil {
		log.Printf("[email] SMTP not configured (set SMTP_HOST + SMTP_FROM + " +
			"SMTP_USER + SMTP_PASSWORD to enable transactional email). " +
			"Verification codes will only print to stdout.")
	}

	// Password reset tokens (migration 0034). Hashed-at-rest one-time
	// tokens for the forgot-password flow.
	passwordResetRepo := repositories.NewPasswordResetTokenRepository(database)

	// Initialize handlers
	authHandler := handlers.NewAuthHandler(userRepo, auditRepo, emailVerifyRepo, passwordResetRepo, emailSender)

	// Firebase OAuth bridge — Google + Apple sign-in (migration 0031).
	// Soft-failure: if Firebase credentials aren't configured yet, log a
	// warning and skip the route. Email/password auth keeps working so
	// you can run the server while finishing the Firebase console setup.
	firebaseAuthHandler, firebaseErr := handlers.NewFirebaseAuthHandler(userRepo, auditRepo)
	if firebaseErr != nil {
		log.Printf("[firebase] Firebase OAuth disabled: %v (set FIREBASE_PROJECT_ID + GOOGLE_APPLICATION_CREDENTIALS to enable)", firebaseErr)
	}

	// Push notifications — graceful soft-fail like firebase_auth: if
	// the Firebase service account isn't configured we keep running
	// without it. POST /api/me/push-token still persists the token
	// (so when the admin later configures FCM, every previously-
	// stored token is immediately addressable). Only the broadcast
	// endpoint returns 503 until creds are wired.
	pushTokenRepo := repositories.NewPushTokenRepository(database)
	fcmSender, fcmErr := services.NewFCMSender(context.Background())
	if fcmErr != nil {
		log.Printf("[fcm] FCM admin send disabled: %v (set FIREBASE_PROJECT_ID + GOOGLE_APPLICATION_CREDENTIALS to enable)", fcmErr)
	} else {
		log.Printf("[fcm] FCM admin send enabled — project=%s", os.Getenv("FIREBASE_PROJECT_ID"))
	}
	pushHandler := handlers.NewPushHandler(pushTokenRepo, fcmSender)

	// Abuse-reports queue (mig 0036). Users submit reports against
	// posts / users / comments / communities / messages; admins triage
	// them. Required for App Store + Play Store compliance.
	reportRepo := repositories.NewReportRepository(database)
	reportsHandler := handlers.NewReportsHandler(reportRepo, auditRepo)

	// User profile updates (mig 0038–0041). Hosts PATCH /me/profile,
	// POST /me/change-password, POST /me/change-email/{request,confirm},
	// DELETE /me/account, GET+PATCH /me/notification-prefs. Reuses the
	// existing email-verification repo + email sender for the change-
	// email code path.
	emailChangeRepo := repositories.NewEmailChangeRequestRepository(database)
	notificationPrefsRepo := repositories.NewNotificationPrefsRepository(database)
	// Localized push fan-out (mig 0043). Renders notifications in the
	// recipient's chosen language; no-op when FCM isn't configured.
	// Constructed early so subscription handlers + expirers can be wired
	// with it before they start ticking.
	notifier := services.NewNotifier(
		userRepo, notificationPrefsRepo, pushTokenRepo, fcmSender,
	)
	// TEMPORARY: deps for the notification smoke-test endpoint.
	pushHandler.SetTestDeps(notifier, userRepo)
	// Scheduled "countdown" push notifications (mig 0048). The repo backs
	// the schedule endpoints; the sender fires due rows server-side so a
	// scheduled push survives the dashboard being closed.
	scheduledPushRepo := repositories.NewScheduledPushRepository(database)
	pushHandler.SetScheduledRepo(scheduledPushRepo)
	services.NewScheduledPushSender(scheduledPushRepo, pushTokenRepo, fcmSender).
		Start(context.Background())
	profileHandler := handlers.NewProfileHandler(
		userRepo, emailVerifyRepo, emailChangeRepo,
		notificationPrefsRepo, emailSender, auditRepo,
	)

	// Per-expert studio endpoints (Phase 3.1–3.3). The dashboard,
	// earnings history, and self-serve pricing routes live here. All
	// gated by the auth middleware + an in-handler "is this user an
	// expert?" check so non-experts get a clean 403 instead of empty
	// data.
	studioHandler := handlers.NewStudioHandler(userRepo, socialRepo, expertSubRepo)

	// Payout requests (Phase 3.4, mig 0042). Experts request cash-outs
	// against their earned revenue; admins mark them paid out-of-band.
	payoutsRepo := repositories.NewPayoutsRepository(database)
	payoutsHandler := handlers.NewPayoutsHandler(payoutsRepo, expertSubRepo, userRepo, auditRepo)

	// Admin home-page metrics rollup (Phase 4.1). One endpoint feeding
	// every card + chart on the Dashboard so the React side fetches
	// once on mount instead of half a dozen times.
	adminMetricsHandler := handlers.NewAdminMetricsHandler(database)

	// Admin stocks page (Phase 4.4). List + filter + manual shariah
	// override. Inserts a fresh shariah_status row dated today so the
	// existing DISTINCT-ON-latest read paths pick the override
	// automatically.
	adminStocksHandler := handlers.NewAdminStocksHandler(database, auditRepo)

	devHandler := handlers.NewDevHandler(database, userRepo)
	auditHandler := handlers.NewAuditHandler(auditRepo)
	// Network/graph view — one big JOIN over users + experts +
	// communities + subscriptions. Powers /network on the admin
	// dashboard. Takes raw DB because the existing repos don't
	// expose the wide cross-table view we need.
	networkHandler := handlers.NewNetworkHandler(database)
	publicHandler := handlers.NewPublicHandler(stockRepo, fundamentalRepo, shariahRepo, analystRepo, shariahEngine)
	userHandler := handlers.NewUserHandler(portfolioRepo, notificationRepo)
	toolsHandler := handlers.NewToolsHandler(portfolioRepo, stockRepo, shariahRepo, fundamentalRepo)
	adsHandler := handlers.NewAdsHandler(adRepo)
	promoHandler := handlers.NewPromoHandler(promoRepo)
	promoHandler.SetAudits(auditRepo)
	marketHandler := handlers.NewMarketHandler(marketProvider)
	// SocialHandler needs the post-interactions + post-saves repos (used
	// by fillUserState) — declare them inline-early so we can pass them.
	postInteractionsRepoEarly := repositories.NewPostInteractionsRepository(database)
	postSavesRepoEarly := repositories.NewPostSavesRepository(database)
	socialHandler := handlers.NewSocialHandler(
		socialRepo, userRepo, expertSubRepo,
		postInteractionsRepoEarly, postSavesRepoEarly,
	)
	// Optional events plumbing — lets GetPostByID log a deep_link_opened
	// event without changing NewSocialHandler's signature for callers
	// that don't need it.
	socialHandler.SetEventsRepo(postEventsRepo)
	// Hub wired post-construction — the hub is built later in this
	// file (see "Realtime: Postgres LISTEN/NOTIFY" block). We attach
	// it once both exist so social handlers can broadcast events
	// like community_member_changed without reordering construction.
	eventsHandler := handlers.NewEventsHandler(postEventsRepo)
	adminDiagnosticsHandler := handlers.NewAdminDiagnosticsHandler("uploads")
	adminPostsHandler := handlers.NewAdminPostsHandler(
		socialRepo,
		postInteractionsRepoEarly,
		userRepo,
		auditRepo,
	)
	adminCommunitiesHandler := handlers.NewAdminCommunitiesHandler(
		socialRepo, userRepo, auditRepo,
	)
	expertAppHandler := handlers.NewExpertApplicationHandler(expertAppRepo, userRepo)
	adminUsersHandler := handlers.NewAdminUsersHandler(userRepo, socialRepo)
	expertSubHandler := handlers.NewExpertSubscriptionHandler(expertSubRepo, userRepo, socialRepo)
	expertSubHandler.SetPromo(promoRepo, auditRepo)

	// Apple In-App-Purchase verification (mig 0035). Soft-fails to nil
	// when APPLE_IAP_SHARED_SECRET is unset — the /me/iap/apple/verify
	// endpoint will then return 503 with a configuration hint, and the
	// cash/FIB payment path keeps working unchanged.
	appleIAPVerifier := services.NewAppleIAPVerifier()
	if appleIAPVerifier == nil {
		log.Printf("[apple-iap] verification disabled (set APPLE_IAP_SHARED_SECRET " +
			"from App Store Connect → In-App Purchases → App-Specific Shared Secret " +
			"to enable). Cash/FIB payment paths are unaffected.")
	}
	appleIAPRepo := repositories.NewAppleIAPTransactionRepository(database)
	iapHandler := handlers.NewIAPHandler(appleIAPVerifier, appleIAPRepo, expertSubRepo, userRepo)
	// Reel videos + cover images upload here. When AWS_S3_BUCKET is set
	// the bytes stream straight to S3 and the response URL is a pre-
	// signed GET; otherwise the handler falls back to the original
	// local-disk flow served by the /uploads static mount below.
	var s3Storage *services.S3Storage
	if cfg.AWSS3Bucket != "" {
		ttl := time.Duration(cfg.AWSS3PresignGetHours) * time.Hour
		s3Storage, err = services.NewS3Storage(
			context.Background(),
			cfg.AWSRegion, cfg.AWSS3Bucket,
			cfg.AWSAccessKeyID, cfg.AWSSecretAccessKey,
			ttl,
		)
		if err != nil {
			log.Fatalf("Failed to init S3 storage: %v", err)
		}
		log.Printf("[uploads] S3 enabled — bucket=%s region=%s presign-get-ttl=%s",
			cfg.AWSS3Bucket, cfg.AWSRegion, ttl)
	} else {
		log.Printf("[uploads] S3 disabled (AWS_S3_BUCKET unset) — using local disk")
	}
	uploadHandler := handlers.NewUploadHandler("uploads", "/uploads", s3Storage)

	// Sign-on-read wiring. Every repo that returns rows containing a
	// media / cover / avatar / attachment URL re-signs the value through
	// s3Storage on read, so URLs the DB has held for months still play
	// even though SigV4 pre-signed URLs cap out at 7 days. Repos default
	// to pass-through behavior when s3Storage is nil — dev machines with
	// no AWS creds keep working unchanged.
	socialRepo.SetS3Storage(s3Storage)
	communityMessagesRepo.SetS3Storage(s3Storage)
	expertAppRepo.SetS3Storage(s3Storage)
	postSavesRepoEarly.SetS3Storage(s3Storage)

	// Background video transcode worker — generates the lower-quality MP4
	// rungs behind the in-app quality gear. Best-effort: it self-disables
	// when S3 or ffmpeg/ffprobe are missing, so dev machines without those
	// just keep serving single-quality video.
	transcodeRepo := repositories.NewTranscodeRepository(database)
	transcoder := services.NewTranscoder(transcodeRepo, s3Storage)
	transcoder.Start(context.Background())
	// Likes + comments + saves + notifications inbox. Reuse the repos we
	// already created so SocialHandler.fillUserState and the interactions
	// handler share the same instances.
	userNotificationsRepo := repositories.NewUserNotificationsRepository(database)
	interactionsHandler := handlers.NewInteractionsHandler(
		socialRepo, expertSubRepo, userRepo,
		postInteractionsRepoEarly, postSavesRepoEarly, userNotificationsRepo,
	)

	// ─── Realtime: Postgres LISTEN/NOTIFY → WebSocket fan-out ───
	hub := realtime.NewHub()
	pgListener := realtime.NewPgListener(hub, cfg.DatabaseDSN())
	pgListener.Start(context.Background())
	realtimeHandler := handlers.NewRealtimeHandler(hub, userRepo, socialRepo)
	// Now that the hub exists, attach it to the social handler so
	// community join/leave can broadcast member-count patches.
	socialHandler.SetHub(hub)
	// Audit repo — used by the admin pricing edit endpoint so changes
	// land in the audit log with before/after metadata.
	socialHandler.SetAuditRepo(auditRepo)

	// Community co-owners (mig 0032). Repo + handler are constructed
	// together; SocialHandler also gets a reference so its existing
	// ownership check can grant co-owners the same rights as the
	// primary owner.
	coOwnersRepo := repositories.NewCommunityOwnersRepo(database)
	socialHandler.SetCoOwnersRepo(coOwnersRepo)
	socialHandler.SetNotifier(notifier)
	coOwnersHandler := handlers.NewCommunityOwnersHandler(coOwnersRepo, socialRepo, userRepo)
	coOwnersHandler.SetAuditRepo(auditRepo)
	coOwnersHandler.SetHub(hub)
	// Subscription approval/rejection notifications fan out on the
	// subscriber's user channel — wire the hub so the handler can
	// emit subscription_accepted / subscription_rejected events.
	expertSubHandler.SetHub(hub)
	// Persist subscription lifecycle events into the unified inbox
	// so they survive past the realtime snackbar and show up in
	// notification history.
	expertSubHandler.SetUserNotifications(userNotificationsRepo)
	expertSubHandler.SetNotifier(notifier)
	// Same wiring for the Become-Expert flow — welcome inbox row on
	// approve, rejection-reason row on reject, demotion row on demote.
	// Hub wired too so the demote endpoint can publish a
	// `user_role_changed` event (the SQL trigger only fires on app
	// status changes, not role flips).
	expertAppHandler.SetUserNotifications(userNotificationsRepo)
	expertAppHandler.SetHub(hub)
	// Background expirer — flips active subs to expired when their
	// expires_at passes, broadcasts a per-user `subscription_expired`
	// event so mobile drops subscriber-only gating immediately.
	// Same userNotifs repo wired so the expired event also lands in
	// the inbox.
	subscriptionExpirer := services.NewSubscriptionExpirer(
		expertSubRepo, socialRepo, hub, userNotificationsRepo,
	)
	subscriptionExpirer.SetNotifier(notifier)
	subscriptionExpirer.Start(context.Background())
	// Step-20 (mig 0020, item 4.15) — scheduled-post promoter. Ticks
	// every 60s, flips status='scheduled' rows whose publish_at has
	// passed to 'published' and broadcasts a `post_published` realtime
	// event so connected clients prepend the new row without polling.
	scheduledPublisher := services.NewScheduledPublisher(socialRepo, hub)
	scheduledPublisher.Start(context.Background())
	// Unified inbox — merges `notifications` (stock) and
	// `user_notifications` (social/sub) behind one endpoint. The
	// mobile app reads only this endpoint going forward; the legacy
	// per-table routes stay for backward compat.
	inboxRepo := repositories.NewInboxRepository(database)
	inboxHandler := handlers.NewInboxHandler(inboxRepo)
	communityMessagesHandler := handlers.NewCommunityMessagesHandler(
		communityMessagesRepo, userRepo, hub, s3Storage,
	)
	// Pin / unpin needs the social repo to look up community owner —
	// wired post-construction so the constructor signature stays
	// stable for any other call sites that build the handler.
	communityMessagesHandler.SetSocialRepo(socialRepo)
	// CommunityProposalsHandler needs the hub for realtime fan-out on
	// approve/reject — construct it once the hub exists.
	communityProposalsHandler := handlers.NewCommunityProposalsHandler(
		communityProposalsRepo, userRepo, hub, auditRepo,
	)
	// Mig 0029 — Contact Admin chat. Hub passed in so AdminClose can
	// fan a thread-closed event to the user; message inserts get fanned
	// out automatically by the pg_notify trigger. AuditRepo (added with
	// the audit-trail task, June 2026) lets the handler record every
	// admin mutate (edit/delete/pin/unpin/close) to audit_logs so the
	// dashboard's Support tab in the Audit Log page can render them.
	supportHandler := handlers.NewSupportHandler(supportRepo, hub, auditRepo)
	// Surface admin replies in the user's inbox + a localized push.
	supportHandler.SetUserNotifications(userNotificationsRepo)
	supportHandler.SetNotifier(notifier)
	// Admin DB export — JSON dump + pg_dump SQL. cfg is passed for the
	// pg_dump arg construction (host/port/user/password/db name).
	adminExportHandler := handlers.NewAdminExportHandler(database, cfg)
	// Step-21 (mig 0021, item 5.21) — chat polls handler.
	communityPollsHandler := handlers.NewCommunityPollsHandler(
		communityPollsRepo, communityMessagesRepo, socialRepo, userRepo, hub,
	)
	communityPollsHandler.SetNotifier(notifier)
	// Step-21 (mig 0021, item 5.21) — background poll-closer.
	pollCloser := services.NewPollCloser(
		communityPollsRepo, communityMessagesRepo, hub,
	)
	pollCloser.Start(context.Background())
	// Step-23 (mig 0022) — paid community memberships handler +
	// background expirer.
	communitySubsHandler := handlers.NewCommunitySubscriptionsHandler(
		communitySubsRepo, socialRepo, userRepo, hub,
	)
	// Step-C of the audit (mig 0025) — wire inbox writer so accept /
	// reject / cancel / expire lay down a persistent notification row,
	// matching the expert-subscription handler's behaviour.
	communitySubsHandler.SetUserNotifications(userNotificationsRepo)
	communitySubsHandler.SetNotifier(notifier)
	communitySubsHandler.SetPromo(promoRepo, auditRepo)
	communitySubsExpirer := services.NewCommunitySubscriptionExpirer(
		communitySubsRepo, hub, userNotificationsRepo,
	)
	communitySubsExpirer.SetNotifier(notifier)
	communitySubsExpirer.Start(context.Background())

	// Start background refresh for market provider if it supports it
	if avp, ok := marketProvider.(*marketdata.AlphaVantageProvider); ok {
		avp.StartBackgroundRefresh()
	}
	if ep, ok := marketProvider.(*marketdata.EODHDProvider); ok {
		ep.StartBackgroundRefresh()
	}

	// Setup router
	router := gin.Default()

	// Compression middleware (gzip responses)
	router.Use(middleware.CompressionMiddleware())

	// CORS middleware
	router.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, PATCH, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	})

	// Static serving for user-uploaded reel videos + cover images. Files
	// land here via POST /api/me/uploads/(video|image) and are served
	// publicly — they're meant to be embedded in posts that anyone with
	// access to the post can view.
	router.Static("/uploads", "./uploads")

	// Global feature flags (mig 0045) — backs the admin community
	// kill-switch (master + chat + posts sub-toggles).
	appSettingsRepo := repositories.NewAppSettingsRepository(database)
	adminSettingsHandler := handlers.NewAdminSettingsHandler(appSettingsRepo, auditRepo)

	// Public routes
	api := router.Group("/api")
	// Community kill-switch — one middleware gates every community route
	// (public + protected); admin routes stay exempt so the toggle and
	// moderation always work even while communities are disabled.
	api.Use(middleware.CommunityGate(appSettingsRepo))
	{
		// Health check
		api.GET("/health", func(c *gin.Context) {
			c.JSON(200, gin.H{"status": "ok"})
		})

		// Public feature flags — the mobile app reads these to hide
		// disabled features (e.g. the Community tab when communities are off).
		api.GET("/app-config", adminSettingsHandler.Get)

		// Auth (no caching)
		api.POST("/auth/register", authHandler.Register)
		api.POST("/auth/login", authHandler.Login)
		// Email-first onboarding (no verification step). The mobile app
		// uses check-email to branch login vs create-account, then signup
		// to create an immediately-verified account + JWT. Replaces the
		// register + verify-email pair (those stay registered, but unused).
		api.POST("/auth/check-email", authHandler.CheckEmail)
		api.POST("/auth/signup", authHandler.Signup)
		// Email verification (migration 0026). In dev mode the codes are
		// returned in the API response + logged to stdout — no SMTP needed.
		api.POST("/auth/verify-email", authHandler.VerifyEmail)

		// Firebase OAuth (migration 0031). Mobile sends a Firebase
		// idToken obtained via Google or Apple sign-in; backend verifies
		// it with the Admin SDK and returns our normal JWT.
		if firebaseAuthHandler != nil {
			api.POST("/auth/oauth/firebase", firebaseAuthHandler.OAuth)
		}
		api.POST("/auth/resend-code", authHandler.ResendCode)

		// Forgot password (migration 0034). Request mints a one-time
		// token, hashes it, emails the raw token to the user. Confirm
		// consumes the token and updates the password. Both endpoints
		// return generic 200s for unknown emails so attackers can't
		// enumerate accounts.
		api.POST("/auth/password-reset/request", authHandler.RequestPasswordReset)
		api.POST("/auth/password-reset/confirm", authHandler.ConfirmPasswordReset)

		// Dev-only switcher routes. Gated inside the handler by
		// APP_ENV != "production" — they return 404 in real deploys.
		// Used by the Flutter "Switch account" sheet so testers can
		// list every account in the DB and impersonate any of them
		// in one tap.
		api.GET("/dev/users", devHandler.ListUsers)
		api.POST("/dev/impersonate", devHandler.Impersonate)
		// Wipes every user-generated row except admin (id=1000). Requires
		// the X-Confirm: yes-wipe-everything header on top of the dev
		// gate. Reference data (stocks, shariah, ads) is preserved.
		api.POST("/dev/reset", devHandler.Reset)

		// Public stock data (with caching)
		stockData := api.Group("")
		stockData.Use(middleware.CacheMiddleware(5 * time.Minute)) // Cache for 5 minutes
		{
			stockData.GET("/search", publicHandler.SearchStocks)
			stockData.GET("/stocks/:ticker", publicHandler.GetStockDetails)
			stockData.GET("/regions/:code/stocks", publicHandler.GetStocksByRegion)
		}

		// Ads (with caching)
		api.GET("/ads", middleware.CacheMiddleware(15*time.Minute), adsHandler.GetAds)

		// Market Data
		api.GET("/market/fear-greed", middleware.CacheMiddleware(1*time.Minute), marketHandler.GetFearAndGreedIndex)
		api.GET("/market/indexes", middleware.CacheMiddleware(1*time.Minute), marketHandler.GetIndexes)
		api.GET("/market/exchange-rate", middleware.CacheMiddleware(1*time.Hour), marketHandler.GetExchangeRate)

		// Public Tools
		tools := api.Group("/tools")
		{
			tools.GET("/dca", toolsHandler.CalculateDCA)
		}

		// Realtime — WebSocket upgrade. Auth is via ?token=<jwt> query param
		// because browsers can't send Authorization headers on the WS handshake.
		api.GET("/ws", realtimeHandler.Connect)

		// Public social listings — experts, communities and community posts
		// are visible to anyone. Expert posts are protected (paywall lives
		// in the protected group below).
		api.GET("/experts", socialHandler.ListExperts)
		api.GET("/experts/:id", socialHandler.GetExpert)
		api.GET("/communities", socialHandler.ListCommunities)
		// Step-19 (item 2.15) — discovery search. Public — auth optional.
		// Logged-out callers see only is_public communities; logged-in
		// callers see all so they can find private communities they
		// could request to join. OptionalAuthMiddleware sets user_id
		// when a valid token is present without 401-ing anonymous calls.
		// MUST be registered BEFORE the dynamic /communities/:id route
		// so gin doesn't bind "search" as the :id parameter.
		api.GET(
			"/communities/search",
			middleware.OptionalAuthMiddleware(),
			socialHandler.SearchCommunities,
		)
		// Step-19 (item 2.16) — predefined category taxonomy.
		api.GET("/communities/categories", socialHandler.ListCommunityCategories)
		api.GET("/communities/:id", socialHandler.GetCommunity)
		// Step-23 — pre-join preview. Public route. Bundles community
		// metadata + experts strip + sample public posts so mobile
		// renders the pre-join screen in one network call.
		api.GET(
			"/communities/:id/preview",
			socialHandler.GetCommunityPreview,
		)
		// /communities/:id/posts moved to the protected group below
		// so the membership gate has access to the caller's user_id.
		// Non-members get 403; admins always see the list.
		// "Experts in this community" — public, drives the
		// horizontal expert-cards strip on the community detail
		// screen. Lists every member with role=EXPERT, owner-first.
		api.GET("/communities/:id/experts", socialHandler.ListCommunityExperts)
		// Public — every community an expert participates in,
		// rendered as a horizontal strip on the expert profile.
		api.GET(
			"/experts/:id/communities",
			socialHandler.ListExpertCommunities,
		)
	}

	// Protected routes
	protected := api.Group("/")
	protected.Use(middleware.AuthMiddleware())
	{
		// User
		protected.GET("/user/portfolio", userHandler.GetPortfolio)
		protected.POST("/user/portfolio", userHandler.AddToPortfolio)
		protected.DELETE("/user/portfolio/:stock_id", userHandler.RemoveFromPortfolio)
		protected.GET("/user/notifications", userHandler.GetNotifications)
		protected.PUT("/user/notifications/:id/read", userHandler.MarkNotificationRead)

		// Tools
		protected.GET("/tools/zakat", toolsHandler.CalculateZakat)

		// Promo codes
		protected.POST("/promo/validate", promoHandler.ValidatePromo)
		protected.POST("/promo/redeem", promoHandler.RedeemPromo)

		// Tier upgrades go through the expert-subscription + community-subscription
		// flows (with their own IAP / admin-verified payment paths). The legacy
		// /subscription/upgrade and /subscription/cancel routes used to live here
		// and were demo-only (no payment verification) — removed in the launch
		// hardening pass.

		// ─────── Social (auth-gated) ───────
		// Identity for the current user (role + which experts they follow).
		protected.GET("/me", socialHandler.Me)

		// Expert posts are subscription-gated. The handler returns 402
		// Payment Required when the caller isn't a subscriber, which the
		// Flutter client surfaces as the paywall card.
		protected.GET("/experts/:id/posts", socialHandler.ListExpertPosts)
		protected.POST("/experts/:id/posts", socialHandler.CreateExpertPost)
		// Step-5: owner / admin can edit, hide, or delete a post.
		protected.PATCH("/experts/:id/posts/:postId", socialHandler.UpdateExpertPost)
		protected.PATCH("/experts/:id/posts/:postId/visibility", socialHandler.SetExpertPostHidden)
		protected.DELETE("/experts/:id/posts/:postId", socialHandler.DeleteExpertPost)
		protected.POST("/experts/:id/subscribe", socialHandler.Subscribe)
		protected.DELETE("/experts/:id/subscribe", socialHandler.Unsubscribe)

		// Community membership + composing.
		protected.POST("/communities/:id/join", socialHandler.JoinCommunity)
		// Leave a community — owners get 409, non-members 404.
		protected.POST("/communities/:id/leave", socialHandler.LeaveCommunity)
		// Auth-required member list — drives the owner-only
		// remove-member / transfer-ownership picker sheets on mobile.
		protected.GET(
			"/communities/:id/members",
			socialHandler.ListCommunityMembersPublic,
		)
		// "Communities I'm in" — drives the Joined filter on the
		// social hub. Returns just the community ids so the client
		// can filter its already-cached list.
		protected.GET("/me/communities", socialHandler.ListMyCommunities)
		// Owner-only moderation: remove a member, transfer ownership.
		protected.DELETE(
			"/communities/:id/members/:userId",
			socialHandler.RemoveCommunityMember,
		)
		protected.POST(
			"/communities/:id/transfer-ownership",
			socialHandler.TransferCommunityOwnership,
		)

		// ── Co-owners + invitations (mig 0032) ───────────────────
		// Primary owner sends an invitation to an EXPERT user.
		protected.POST(
			"/me/communities/:id/invitations",
			coOwnersHandler.SendInvitation,
		)
		// Primary owner views their community's outbox.
		protected.GET(
			"/me/communities/:id/invitations",
			coOwnersHandler.ListForCommunity,
		)
		// Invitee's inbox + accept / reject / cancel.
		protected.GET("/me/community-invitations", coOwnersHandler.ListIncoming)
		protected.POST("/me/community-invitations/:id/accept", coOwnersHandler.Accept)
		protected.POST("/me/community-invitations/:id/reject", coOwnersHandler.Reject)
		protected.DELETE("/me/community-invitations/:id", coOwnersHandler.Cancel)
		// Owners list — public (anyone can see who runs a community).
		protected.GET("/communities/:id/owners", coOwnersHandler.ListOwners)
		// Primary owner removes a co-owner.
		protected.DELETE(
			"/me/communities/:id/owners/:userId",
			coOwnersHandler.RemoveCoOwner,
		)
		// Lightweight membership probe used by the mobile UI on
		// community-detail mount to flip the Join/Leave CTA.
		protected.GET(
			"/communities/:id/membership",
			socialHandler.GetCommunityMembership,
		)
		protected.GET(
			"/communities/:id/posts",
			socialHandler.ListCommunityPosts,
		)
		protected.POST("/communities/:id/posts", socialHandler.CreateCommunityPost)
		// Community-post moderation — author OR owner/co-owner OR admin.
		protected.PATCH("/communities/:id/posts/:postId", socialHandler.UpdateCommunityPost)
		protected.PATCH("/communities/:id/posts/:postId/hide", socialHandler.SetCommunityPostHidden)
		protected.DELETE("/communities/:id/posts/:postId", socialHandler.DeleteCommunityPost)

		// Step-19 (mig 0019, items 2.13–2.18) — owner-or-admin metadata
		// patch + tag replace. Cover image goes through the existing
		// /me/uploads/image endpoint and the resulting URL is sent
		// through PATCH as `coverUrl`.
		protected.PATCH(
			"/communities/:id",
			socialHandler.UpdateCommunity,
		)
		protected.PUT(
			"/communities/:id/tags",
			socialHandler.ReplaceCommunityTags,
		)

		// ─────── Community chat (real-time messages) ───────
		// Member-gated on both list + send. Send broadcasts on
		// `community:<id>` so every connected member receives the
		// new bubble live.
		protected.GET("/communities/:id/messages", communityMessagesHandler.List)
		protected.POST("/communities/:id/messages", communityMessagesHandler.Send)
		// Delete a message — author-only by default, admin override.
		// Broadcasts community_message_deleted on success.
		protected.DELETE(
			"/communities/:id/messages/:mid",
			communityMessagesHandler.Delete,
		)
		// Voice-message multipart upload — saves to uploads/audio/
		// and broadcasts the resulting message on community:<id>
		// just like a text Send.
		protected.POST(
			"/communities/:id/messages/audio",
			communityMessagesHandler.SendAudio,
		)
		// Pin / unpin a message — community-owner-or-admin only.
		// Broadcasts community_message_pinned on success so all
		// connected members can patch their local copy.
		protected.POST(
			"/communities/:id/messages/:mid/pin",
			communityMessagesHandler.TogglePin,
		)
		// Per-message emoji reactions — toggle (POST) + viewer list
		// (GET, drives the "who reacted with what" sheet).
		protected.POST(
			"/communities/:id/messages/:mid/reactions",
			communityMessagesHandler.ToggleReaction,
		)
		protected.GET(
			"/communities/:id/messages/:mid/reactions",
			communityMessagesHandler.ListReactors,
		)

		// ─── Step-21 (mig 0021, items 5.17 / 5.18 / 5.19 / 5.21 / 5.22) ───
		// Chat search (5.17) — per-community FTS + ILIKE.
		// MUST be registered BEFORE /messages/:mid so gin doesn't match
		// "search" as the message id parameter.
		protected.GET(
			"/communities/:id/messages/search",
			communityMessagesHandler.Search,
		)
		// Read receipts (5.18). Single + batch + reader-list endpoints.
		protected.POST(
			"/communities/:id/messages/read-batch",
			communityMessagesHandler.MarkBatchRead,
		)
		protected.POST(
			"/communities/:id/messages/:mid/read",
			communityMessagesHandler.MarkRead,
		)
		protected.GET(
			"/communities/:id/messages/:mid/reads",
			communityMessagesHandler.ListReaders,
		)
		// Edit own message (5.22). Author-only, 15-min window.
		protected.PATCH(
			"/communities/:id/messages/:mid",
			communityMessagesHandler.EditMessage,
		)
		// Typing indicators (5.19). Pure WS fan-out.
		protected.POST(
			"/communities/:id/typing",
			communityMessagesHandler.Typing,
		)
		// Polls (5.21).
		protected.POST(
			"/communities/:id/polls",
			communityPollsHandler.Create,
		)
		protected.POST(
			"/communities/:id/polls/:pid/vote",
			communityPollsHandler.Vote,
		)
		protected.POST(
			"/communities/:id/polls/:pid/close",
			communityPollsHandler.Close,
		)
		// Read-receipts opt-out toggle (5.18). Per-user setting, not
		// per-community.
		protected.GET(
			"/me/settings/read-receipts",
			communityMessagesHandler.GetReadReceiptsEnabled,
		)
		protected.PATCH(
			"/me/settings/read-receipts",
			communityMessagesHandler.SetReadReceiptsEnabled,
		)

		// ─── Step-23 (mig 0022) — paid community memberships ───
		protected.POST(
			"/communities/:id/subscribe",
			communitySubsHandler.Subscribe,
		)
		protected.GET(
			"/me/community-subscriptions",
			communitySubsHandler.MySubscriptions,
		)
		protected.DELETE(
			"/community-subscriptions/:id",
			communitySubsHandler.Cancel,
		)

		// ─────── Expert applications (Step 1) ───────
		// Any authenticated user can submit an application or check their own.
		protected.POST("/expert-applications", expertAppHandler.Submit)
		protected.GET("/me/expert-application", expertAppHandler.MyApplication)
		// Withdraw a pending application — only the applicant themselves,
		// only while status=pending. Frees them up to re-apply immediately
		// (the cool-down kicks in on rejection, not withdrawal).
		protected.DELETE("/me/expert-applications/:id", expertAppHandler.Withdraw)

		// ─────── Expert studio (Step 2) ───────
		// The authenticated expert's own post list — bypasses subscription gating.
		protected.GET("/me/expert/posts", socialHandler.MyExpertPosts)

		// ─────── Subscriber feed (Step 5) ───────
		// One stream of posts from every expert the user has an active
		// subscription to. Used by the bottom-nav Feed tab.
		protected.GET("/me/feed", socialHandler.MyFeed)

		// ─────── Single-post fetch (deep-link route resolution) ───────
		// Used when the app receives a shared `unmu.app/p/:id` URL — the
		// DeepLinkService fetches the post by id, then routes to the
		// PostViewerScreen. Subject to the same per-post visibility gate
		// as the expert-profile listing.
		protected.GET("/posts/:id", socialHandler.GetPostByID)

		// ─────── Uploads (reels + cover images) ───────
		// Multipart file uploads from the post composer. Each handler
		// returns a `{ url }` the client puts on the post body as
		// mediaUrl / coverUrl.
		protected.POST("/me/uploads/video", uploadHandler.UploadVideo)
		protected.POST("/me/uploads/image", uploadHandler.UploadImage)
		// Resume / credentials PDF upload — used by the expert
		// application form. PDF only, capped at 10 MB.
		protected.POST("/me/uploads/document", uploadHandler.UploadDocument)
		// Chunked video upload — three-step protocol (init → chunk × N
		// → complete). Used by the post composer for reels so cellular
		// drops only lose one chunk and the user sees real progress.
		// The single-shot endpoint above stays for image uploads + as a
		// fallback for tiny videos.
		protected.POST("/me/uploads/video/init", uploadHandler.InitVideoChunkUpload)
		protected.POST("/me/uploads/video/chunk", uploadHandler.UploadVideoChunk)
		protected.POST("/me/uploads/video/complete", uploadHandler.CompleteVideoChunkUpload)

		// Direct-to-S3 multipart upload (Phase A) — the bytes go straight
		// from the phone to S3 via pre-signed PUT URLs the backend mints
		// here. Backend bandwidth per upload = 0; client sees ~3× faster
		// uploads on cellular. The chunked endpoints above stay as a
		// fallback for clients that haven't migrated, and for environments
		// where S3 isn't configured.
		protected.POST("/me/uploads/video/multipart/init", uploadHandler.InitMultipartUpload)
		protected.POST("/me/uploads/video/multipart/complete", uploadHandler.CompleteMultipartUpload)
		protected.POST("/me/uploads/video/multipart/abort", uploadHandler.AbortMultipartUpload)

		// Push notification token registration. The Flutter app calls
		// this after Firebase Messaging hands it an FCM token (and on
		// every onTokenRefresh) so the admin "Send to all" broadcast
		// has an up-to-date device fan-out list.
		protected.POST("/me/push-token", pushHandler.RegisterToken)

		// In-app-purchase verification (Apple StoreKit, mig 0035). The
		// Flutter `in_app_purchase` plugin sends the receipt blob here
		// after a successful purchase or restore; the backend hits Apple's
		// verifyReceipt endpoint, persists the transaction (idempotent),
		// and optionally flips the matching expert subscription to active.
		// Returns 503 when APPLE_IAP_SHARED_SECRET isn't configured.
		protected.POST("/me/iap/apple/verify", iapHandler.VerifyApple)

		// Abuse / safety reports (mig 0036). User-facing report submission
		// + their own report history.
		protected.POST("/me/reports", reportsHandler.Create)
		protected.GET("/me/reports", reportsHandler.ListMine)
		protected.GET("/me/reports/reasons", reportsHandler.ListReasons)

		// User profile updates (mig 0038). Partial update — clients
		// send only the fields they're changing. Returns the full
		// refreshed user record.
		protected.PATCH("/me/profile", profileHandler.Update)

		// UI language sync (mig 0043). The app PATCHes this on every
		// language toggle + once after login so the backend can localize
		// notification pushes to the recipient's chosen language.
		protected.PATCH("/me/locale", profileHandler.UpdateLocale)

		// Account management — change password, change email (two-step
		// with code-by-email), delete account (mig 0039 + 0040). Each
		// requires the user's current password (except the OAuth-only
		// branch of DELETE which accepts a JWT-only confirmation).
		protected.POST("/me/change-password", profileHandler.ChangePassword)
		// First-time setup for Google/Apple users: set name + local
		// password (guarded by the no-password sentinel). Authed via the
		// JWT minted at OAuth sign-in.
		protected.POST("/me/complete-onboarding", profileHandler.CompleteOnboarding)
		protected.POST("/me/change-email/request", profileHandler.ChangeEmailRequest)
		protected.POST("/me/change-email/confirm", profileHandler.ChangeEmailConfirm)
		protected.DELETE("/me/account", profileHandler.DeleteAccount)

		// Notification preferences (mig 0041). The admin push broadcast
		// honors push_enabled here; per-category flags are surfaced on
		// the client and will gate individual senders in a follow-up.
		protected.GET("/me/notification-prefs", profileHandler.GetNotificationPrefs)
		protected.PATCH("/me/notification-prefs", profileHandler.UpdateNotificationPrefs)

		// Studio (Phase 3.1–3.3). Each handler refuses non-experts.
		protected.GET("/me/expert/dashboard", studioHandler.Dashboard)
		protected.GET("/me/expert/earnings", studioHandler.Earnings)
		protected.PATCH("/me/expert/pricing", studioHandler.SetPricing)

		// Payouts (Phase 3.4, mig 0042). Experts request → admins
		// approve / reject out-of-band.
		protected.GET("/me/expert/payouts", payoutsHandler.ListMyPayouts)
		protected.POST("/me/expert/payouts/request", payoutsHandler.RequestPayout)
		protected.POST("/me/expert/payouts/:id/cancel", payoutsHandler.CancelMyPayout)

		// ─── Step-20 (mig 0020, items 4.15 / 4.16 / 4.18) ───
		// Drafts + scheduling.
		protected.POST("/me/expert/drafts", socialHandler.CreateExpertDraft)
		protected.GET("/me/expert/drafts", socialHandler.ListMyDrafts)
		protected.PATCH(
			"/me/expert/drafts/:id",
			socialHandler.UpdateExpertDraft,
		)
		protected.DELETE(
			"/me/expert/drafts/:id",
			socialHandler.DeleteMyDraft,
		)
		protected.POST(
			"/me/expert/drafts/:id/publish",
			socialHandler.PublishExpertDraft,
		)
		// Edit history (item 4.16) — owner + admin only.
		protected.GET(
			"/posts/:id/history",
			socialHandler.ListPostHistory,
		)
		// Inline image attachments (item 4.18) — author-only.
		protected.POST(
			"/me/posts/:id/attachments",
			socialHandler.AddPostAttachment,
		)
		protected.DELETE(
			"/me/posts/:id/attachments/:aid",
			socialHandler.DeletePostAttachment,
		)

		// ─────── Engagement / reliability event logging ───────
		// Mobile clients call these to tell us "user just shared this
		// post" or "this reel failed to load". Best-effort — backend
		// errors are swallowed by the handler so the user flow can't
		// fail because of a logging hiccup.
		protected.POST("/posts/:id/share-event", eventsHandler.LogShare)
		protected.POST("/me/events/reel-load-failed", eventsHandler.LogReelLoadFailed)

		// ─────── Expert-proposed communities ───────
		// Expert submits → admin reviews → on accept they become owner.
		// Submit + ListMine are authed-user surface; the admin variants
		// of these endpoints live under /admin further down.
		protected.POST("/me/community-proposals", communityProposalsHandler.Submit)
		protected.GET("/me/community-proposals", communityProposalsHandler.ListMine)

		// ─────── Contact-admin support chat (mig 0029) ───────
		// One thread per user. Mobile reads /me/support/messages on open,
		// posts to /me/support/messages, and calls /me/support/read to
		// zero the unread counter. Realtime fan-out is handled by the
		// support_message_events Postgres channel.
		protected.GET("/me/support/thread",    supportHandler.MyThread)
		protected.GET("/me/support/messages",  supportHandler.MyMessages)
		protected.POST("/me/support/messages", supportHandler.Send)
		protected.POST("/me/support/read",     supportHandler.MarkRead)
		// Mig 0030 — user can edit (only) their own messages.
		protected.PATCH("/me/support/messages/:id", supportHandler.EditMyMessage)

		// ─────── Likes + comments (Step 6) ───────
		protected.POST("/posts/:id/like", interactionsHandler.Like)
		protected.DELETE("/posts/:id/like", interactionsHandler.Unlike)
		// Owner-or-admin only — see who liked the post.
		protected.GET("/posts/:id/likes", interactionsHandler.ListPostLikes)
		protected.GET("/posts/:id/comments", interactionsHandler.ListComments)
		protected.POST("/posts/:id/comments", interactionsHandler.CreateComment)
		// Edit own comment (mig 0037 — adds the `edited_at` column).
		protected.PATCH("/posts/:id/comments/:commentId", interactionsHandler.UpdateComment)
		protected.DELETE("/posts/:id/comments/:commentId", interactionsHandler.DeleteComment)

		// ─────── Notifications inbox ───────
		protected.GET("/me/notifications", interactionsHandler.ListNotifications)
		protected.GET("/me/notifications/unread-count", interactionsHandler.UnreadCount)
		protected.POST("/me/notifications/read-all", interactionsHandler.MarkAllRead)
		protected.POST("/me/notifications/:id/read", interactionsHandler.MarkOneRead)

		// ─── Unified inbox (merges social + stock notifications) ───
		// Replaces the per-table endpoints above on the mobile side.
		// Each item carries a `source` discriminator ("social" |
		// "stock") so the client can route mark-read calls back to
		// the correct table.
		protected.GET("/me/inbox", inboxHandler.List)
		protected.GET("/me/inbox/unread-count", inboxHandler.UnreadCount)
		protected.POST("/me/inbox/read-all", inboxHandler.MarkAllRead)
		protected.POST("/me/inbox/:source/:id/read", inboxHandler.MarkRead)

		// ─────── Saved posts (Step 7) ───────
		protected.POST("/posts/:id/save", interactionsHandler.Save)
		protected.DELETE("/posts/:id/save", interactionsHandler.Unsave)
		protected.GET("/me/saved-posts", interactionsHandler.ListSaved)

		// ─────── Expert subscriptions (Step 4) ───────
		// User pays admin (cash / FIB), admin verifies and accepts, then
		// the user's status flips to 'active' and they can read locked posts.
		protected.POST("/experts/:id/subscriptions", expertSubHandler.Subscribe)
		protected.GET("/me/subscriptions", expertSubHandler.MySubscriptions)
		protected.GET("/me/subscriptions/expert/:id", expertSubHandler.MySubscriptionForExpert)
		protected.DELETE("/subscriptions/:id", expertSubHandler.Cancel)
	}

	// ─────── Admin-only routes ───────
	admin := api.Group("/admin")
	admin.Use(middleware.AuthMiddleware(), middleware.RequireAdmin(userRepo))
	{
		// Feature flags — community kill-switch (master + chat + posts).
		admin.GET("/settings", adminSettingsHandler.Get)
		admin.PATCH("/settings", adminSettingsHandler.Update)

		admin.GET("/expert-applications", expertAppHandler.List)
		// Pending-count for the sidebar badge (A12). Cheap COUNT(*) — must
		// be registered BEFORE the dynamic-id route so gin doesn't bind
		// "pending-count" as the :id parameter.
		admin.GET("/expert-applications/pending-count", expertAppHandler.PendingCount)
		// Step-22 — single-application detail for the admin
		// drill-in page. Same shape as a List() row.
		admin.GET("/expert-applications/:id", expertAppHandler.Get)
		admin.POST("/expert-applications/:id/approve", expertAppHandler.Approve)
		admin.POST("/expert-applications/:id/reject", expertAppHandler.Reject)
		// Demote a previously-approved expert back to USER (A8). Soft —
		// the experts row stays so historical posts/subs don't FK-fail.
		admin.POST("/users/:id/demote-expert", expertAppHandler.Demote)
		admin.GET("/audit-logs", auditHandler.List)
		// Network graph snapshot — one round-trip for the admin
		// /network page (force-directed visualization).
		admin.GET("/network/graph", networkHandler.Graph)
		// Per-expert pricing edit — drives the Experts page's
		// "Edit pricing" modal. Writes an EXPERT_PRICING_UPDATED
		// audit row with before/after metadata.
		admin.PATCH("/experts/:expertId/pricing", socialHandler.AdminSetExpertPricing)
		// Step-22 — single audit row, used by the audit-detail page.
		admin.GET("/audit-logs/:id", auditHandler.Get)
		// User management — list everyone, change roles.
		admin.GET("/users", adminUsersHandler.List)
		admin.PATCH("/users/:id/role", adminUsersHandler.UpdateRole)
		// Per-user community membership view — one row per community
		// the user is in, joined with their most-recent paid sub.
		admin.GET("/users/:id/communities", adminUsersHandler.ListCommunities)
		// Expert-subscription review (Step 4).
		admin.GET("/subscriptions", expertSubHandler.AdminList)
		admin.GET("/subscriptions/pending-count", expertSubHandler.AdminPendingCount)
		// Aggregate counts + revenue for the admin Subscriptions header.
		admin.GET("/subscriptions/totals", expertSubHandler.AdminTotals)
		// Step-22 — single-subscription detail for the drill-in page.
		// MUST be registered BEFORE the dynamic-id action routes so
		// gin doesn't bind "pending-count" as the :id parameter.
		admin.GET("/subscriptions/:id", expertSubHandler.AdminGet)
		admin.POST("/subscriptions/:id/accept", expertSubHandler.AdminAccept)
		admin.POST("/subscriptions/:id/reject", expertSubHandler.AdminReject)

		// Engagement / reliability events (today's instrumentation
		// surfaced for admin dashboards).
		admin.GET("/events/summary", eventsHandler.AdminSummary)
		admin.GET("/events/timeseries", eventsHandler.AdminTimeseries)

		// In-flight chunked-upload monitor + manual sweep button.
		admin.GET("/uploads/in-flight", adminDiagnosticsHandler.ListInFlightUploads)
		admin.POST("/uploads/sweep", adminDiagnosticsHandler.SweepUploads)

		// Universal Link / App Link well-known reachability check.
		admin.GET("/diagnostics/deep-links", adminDiagnosticsHandler.DeepLinkDiagnostics)

		// Admin broadcast — send a push notification to all users or a
		// targeted subset. Returns success/failure counts so the admin
		// dashboard can show delivery stats. Invalid tokens are pruned
		// from the DB inline so the next broadcast doesn't re-attempt
		// them.
		admin.POST("/push/send", pushHandler.AdminSend)
		// Scheduled "countdown" push (mig 0048): queue / list / cancel.
		admin.POST("/push/schedule", pushHandler.ScheduleSend)
		admin.GET("/push/scheduled", pushHandler.ListScheduled)
		admin.DELETE("/push/scheduled/:id", pushHandler.CancelScheduled)
		// TEMPORARY smoke test — fire every notification type at all users.
		admin.POST("/push/test-all", pushHandler.AdminTestAllNotifications)

		// Abuse-reports queue (mig 0036). The admin dashboard's Reports
		// page hits these for triage.
		admin.GET("/reports", reportsHandler.AdminList)
		admin.GET("/reports/pending-count", reportsHandler.AdminPendingCount)
		admin.GET("/reports/:id", reportsHandler.AdminGet)
		admin.POST("/reports/:id/resolve", reportsHandler.AdminResolve)

		// Payouts admin queue (Phase 3.4). Admin marks requests as
		// paid (after wiring funds out-of-band) or rejects them.
		admin.GET("/payouts", payoutsHandler.AdminList)
		admin.GET("/payouts/pending-count", payoutsHandler.AdminPendingCount)
		admin.POST("/payouts/:id/resolve", payoutsHandler.AdminResolve)

		// Home-page metrics rollup (Phase 4.1).
		admin.GET("/metrics", adminMetricsHandler.Metrics)

		// Stocks admin (Phase 4.4) — paginated list + manual shariah
		// override. Override audit-trails to `STOCK_SHARIAH_OVERRIDE`.
		admin.GET("/stocks", adminStocksHandler.List)
		admin.GET("/stocks/totals", adminStocksHandler.Totals)
		admin.POST("/stocks/:id/shariah-override", adminStocksHandler.ShariahOverride)

		// Ads admin CRUD. Public read at /api/ads stays unchanged; these
		// power the admin dashboard's Ads page.
		admin.GET("/ads", adsHandler.AdminList)
		admin.GET("/ads/:id", adsHandler.AdminGet)
		admin.POST("/ads", adsHandler.AdminCreate)
		admin.PATCH("/ads/:id", adsHandler.AdminUpdate)
		admin.DELETE("/ads/:id", adsHandler.AdminDelete)

		// Promo codes admin CRUD. Public validate at /api/promo/validate
		// stays auth-gated and unchanged.
		admin.GET("/promos", promoHandler.AdminList)
		admin.GET("/promos/:id", promoHandler.AdminGet)
		admin.POST("/promos", promoHandler.AdminCreate)
		admin.PATCH("/promos/:id", promoHandler.AdminUpdate)
		admin.DELETE("/promos/:id", promoHandler.AdminDelete)

		// ─────── Posts moderation (articles + videos + reels) ───────
		// One unified surface — type filter on the query string. Admin
		// sees hidden posts, can hide / unhide / delete, can list and
		// delete individual comments. Every mutation is audit-logged.
		admin.GET("/posts", adminPostsHandler.List)
		admin.GET("/posts/:id", adminPostsHandler.Get)
		admin.GET("/posts/:id/comments", adminPostsHandler.ListComments)
		admin.GET("/posts/:id/likes", adminPostsHandler.ListLikes)
		admin.DELETE("/posts/:id/comments/:commentId", adminPostsHandler.DeleteComment)
		admin.POST("/posts/:id/hide", adminPostsHandler.SetHidden(true))
		admin.POST("/posts/:id/unhide", adminPostsHandler.SetHidden(false))
		admin.DELETE("/posts/:id", adminPostsHandler.Delete)

		// ─────── Communities (admin direct CRUD) ───────
		admin.GET("/communities", adminCommunitiesHandler.List)
		admin.POST("/communities", adminCommunitiesHandler.Create)
		admin.PATCH("/communities/:id", adminCommunitiesHandler.Update)
		admin.DELETE("/communities/:id", adminCommunitiesHandler.Delete)
		admin.GET("/communities/:id/members", adminCommunitiesHandler.ListMembers)
		// Admin moderation — kick a member or hand the community
		// to a different owner. Auditable; same underlying repo
		// as the owner-side flow.
		admin.DELETE(
			"/communities/:id/members/:userId",
			adminCommunitiesHandler.RemoveMember,
		)
		admin.POST(
			"/communities/:id/transfer-ownership",
			adminCommunitiesHandler.TransferOwner,
		)

		// ─────── Community proposals (expert → admin review) ───────
		admin.GET("/community-proposals", communityProposalsHandler.AdminList)
		admin.GET("/community-proposals/pending-count", communityProposalsHandler.AdminPendingCount)
		// Step-22 — single-proposal detail (must register BEFORE
		// the action routes so gin doesn't bind "pending-count" as :id).
		admin.GET("/community-proposals/:id", communityProposalsHandler.AdminGet)
		admin.POST("/community-proposals/:id/approve", communityProposalsHandler.AdminApprove)
		admin.POST("/community-proposals/:id/reject", communityProposalsHandler.AdminReject)

		// ─────── Support chat (mig 0029) ───────
		// AdminListThreads + pending-count drive the inbox + sidebar
		// badge. AdminThread loads + marks-read on open. AdminReply
		// posts the message; AdminClose flips status (user re-opens
		// implicitly on next message). pending-count MUST be registered
		// before the :id route or gin binds it as the id.
		admin.GET("/support/threads",            supportHandler.AdminListThreads)
		admin.GET("/support/pending-count",      supportHandler.AdminPendingCount)
		admin.GET("/support/threads/:id",        supportHandler.AdminThread)
		admin.POST("/support/threads/:id/messages", supportHandler.AdminReply)
		admin.POST("/support/threads/:id/close",  supportHandler.AdminClose)
		// Mig 0030 — edit / soft-delete / pin (admin can do all 3 on
		// any message; user-side edit is on the protected user routes
		// above, restricted to own messages).
		admin.POST("/support/threads/:id/pin",   supportHandler.AdminPinMessage)
		admin.PATCH("/support/messages/:id",     supportHandler.AdminEditMessage)
		admin.DELETE("/support/messages/:id",    supportHandler.AdminDeleteMessage)

		// ─────── Full-database export ───────
		// JSON dump (one object keyed by table name) + pg_dump SQL
		// (restorable plain-SQL backup with --clean --if-exists). Both
		// stream as file-attachment downloads. Admin-only by virtue of
		// being mounted under the /admin route group.
		admin.GET("/export/json", adminExportHandler.ExportJSON)
		admin.GET("/export/sql",  adminExportHandler.ExportSQL)

		// ─── Step-23 (mig 0022) — admin community-subs queue ───
		admin.GET(
			"/community-subscriptions",
			communitySubsHandler.AdminList,
		)
		admin.GET(
			"/community-subscriptions/pending-count",
			communitySubsHandler.AdminPendingCount,
		)
		// Step C11/C12 — totals strip + per-user "other subs" link.
		// Both must be registered BEFORE the dynamic `/:id` route so
		// gin doesn't bind the literal path as the :id parameter.
		admin.GET(
			"/community-subscriptions/totals",
			communitySubsHandler.AdminTotals,
		)
		admin.GET(
			"/users/:id/community-subscriptions",
			communitySubsHandler.AdminListForUser,
		)
		admin.GET(
			"/community-subscriptions/:id",
			communitySubsHandler.AdminGet,
		)
		admin.POST(
			"/community-subscriptions/:id/accept",
			communitySubsHandler.AdminAccept,
		)
		admin.POST(
			"/community-subscriptions/:id/reject",
			communitySubsHandler.AdminReject,
		)

		// ─── Step-21 (mig 0021, item 5.21) — admin polls panel ───
		admin.GET("/polls", communityPollsHandler.AdminList)
		// Step-22 — single-poll detail (full options + voters when not
		// anonymous). Drives the /polls/:id admin page.
		admin.GET("/polls/:pid", communityPollsHandler.AdminGet)
		admin.POST("/polls/:pid/close", communityPollsHandler.AdminClose)
	}

	// Start server
	log.Printf("Starting server on port %s", cfg.ServerPort)
	if err := router.Run(":" + cfg.ServerPort); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
