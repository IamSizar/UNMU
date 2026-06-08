package handlers

import (
	"database/sql"
	"errors"
	"fmt"
	"halalstocks/internal/models"
	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// SocialHandler exposes endpoints for experts, communities, posts, and
// subscriptions. Authenticated routes pull the caller from the JWT auth
// middleware (`user_id` and `email` keys on the gin Context).
type SocialHandler struct {
	social *repositories.SocialRepository
	users  *repositories.UserRepository
	// expertSubs is used by the post-gating logic to decide whether a caller
	// should see subscribers-only posts. Step-4 introduced this richer
	// check (active + not expired); the older `social.IsSubscribed` is kept
	// around as a fallback for legacy follow rows.
	expertSubs *repositories.ExpertSubscriptionRepository
	// interactions backfills `Liked` on returned posts so the heart icon
	// renders correctly on first paint without N point queries from the
	// client.
	interactions *repositories.PostInteractionsRepository
	// saves backfills `Saved` (the bookmark icon) the same way.
	saves *repositories.PostSavesRepository
	// events optionally logs admin-visible signals (currently only
	// deep_link_opened from GetPostByID). May be nil during tests or
	// transitional builds — call sites must nil-check.
	events *repositories.PostEventsRepository
	// hub broadcasts realtime patches like community_member_changed
	// so other connected clients can update their local state on
	// join/leave. May be nil during tests — call sites must nil-check.
	hub *realtime.Hub
	// audits records admin-side writes — currently used by
	// AdminSetExpertPricing. May be nil during tests; call sites
	// must nil-check.
	audits *repositories.AuditRepository
	// coOwners — community co-ownership (mig 0032). Used by
	// requireCommunityOwnerOrAdmin to honor co-owner permissions
	// for posts + moderation. May be nil during tests; nil-check.
	coOwners *repositories.CommunityOwnersRepo
	// notifier fans new-post pushes out to community members. Optional,
	// wired post-construction via SetNotifier; nil-check at call sites.
	notifier *services.Notifier
}

// SetNotifier wires the localized push fan-out. Best-effort; nil-safe.
func (h *SocialHandler) SetNotifier(n *services.Notifier) {
	h.notifier = n
}

func NewSocialHandler(
	social *repositories.SocialRepository,
	users *repositories.UserRepository,
	expertSubs *repositories.ExpertSubscriptionRepository,
	interactions *repositories.PostInteractionsRepository,
	saves *repositories.PostSavesRepository,
) *SocialHandler {
	return &SocialHandler{
		social: social, users: users,
		expertSubs: expertSubs, interactions: interactions,
		saves: saves,
	}
}

// SetEventsRepo wires the post-events repository on after construction
// — keeps NewSocialHandler's signature stable for existing call sites
// while enabling the new admin instrumentation. Call this from main.go
// right after the handler is built.
func (h *SocialHandler) SetEventsRepo(events *repositories.PostEventsRepository) {
	h.events = events
}

// SetHub wires the realtime hub for broadcasts that the social
// handler emits (currently community_member_changed). Same setter
// pattern as SetEventsRepo so NewSocialHandler's signature stays
// stable across the codebase.
func (h *SocialHandler) SetHub(hub *realtime.Hub) {
	h.hub = hub
}

// SetAuditRepo wires the audit repository. Same pattern — keeps the
// constructor stable while letting main.go opt into admin-side audit
// writes for pricing changes.
func (h *SocialHandler) SetAuditRepo(audits *repositories.AuditRepository) {
	h.audits = audits
}

// SetCoOwnersRepo wires the co-owners lookup so the existing
// requireCommunityOwnerOrAdmin helper can grant co-owners the same
// rights as the primary owner for post/moderation actions.
func (h *SocialHandler) SetCoOwnersRepo(co *repositories.CommunityOwnersRepo) {
	h.coOwners = co
}

// fillUserState populates Post.Liked + Post.Saved for every row in a
// single pair of round-trips. Safe with userID == 0 — anonymous viewers
// see everything outlined.
func (h *SocialHandler) fillUserState(userID int64, posts []*models.Post) {
	if userID == 0 || len(posts) == 0 {
		return
	}
	ids := make([]int64, 0, len(posts))
	for _, p := range posts {
		ids = append(ids, p.ID)
	}
	if h.interactions != nil {
		if liked, err := h.interactions.LikedPostsByUser(userID, ids); err == nil {
			for _, p := range posts {
				if liked[p.ID] {
					p.Liked = true
				}
			}
		}
	}
	if h.saves != nil {
		if saved, err := h.saves.SavedPostIDs(userID, ids); err == nil {
			for _, p := range posts {
				if saved[p.ID] {
					p.Saved = true
				}
			}
		}
	}
}

// fillLiked is kept as a backwards-compatible alias — older call sites
// still reference it. New code should call fillUserState directly.
func (h *SocialHandler) fillLiked(userID int64, posts []*models.Post) {
	h.fillUserState(userID, posts)
}

// =============================================================================
// Public listings — no auth required
// =============================================================================

// GET /api/experts
func (h *SocialHandler) ListExperts(c *gin.Context) {
	experts, err := h.social.ListExperts()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"experts": experts})
}

// GET /api/experts/:id
func (h *SocialHandler) GetExpert(c *gin.Context) {
	expert, err := h.social.GetExpert(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if expert == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "expert not found"})
		return
	}
	c.JSON(http.StatusOK, expert)
}

// GET /api/communities
func (h *SocialHandler) ListCommunities(c *gin.Context) {
	communities, err := h.social.ListCommunities()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"communities": communities})
}

// GET /api/communities/:id
func (h *SocialHandler) GetCommunity(c *gin.Context) {
	community, err := h.social.GetCommunity(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if community == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "community not found"})
		return
	}
	c.JSON(http.StatusOK, community)
}

// GetCommunityPreview — GET /api/communities/:id/preview
//
// One-shot endpoint for the pre-join "About this community" screen
// (step-23). Bundles community metadata + experts strip + sample
// public posts so the mobile renders a rich preview without N
// follow-up calls.
//
// Public route — no auth required. Anyone can preview a community
// before deciding to join. Sample posts are limited to publicly-
// readable rows (visibility=public, status=published, not hidden).
//
// Response:
//
//	{
//	  "community": Community,
//	  "experts":   []CommunityExpertSummary,
//	  "samplePosts": []Post   // up to 3, public + published only
//	}
func (h *SocialHandler) GetCommunityPreview(c *gin.Context) {
	id := c.Param("id")
	community, err := h.social.GetCommunity(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if community == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "community not found"})
		return
	}
	experts, _ := h.social.ListExpertsInCommunity(id)
	if experts == nil {
		experts = []*repositories.CommunityExpertSummary{}
	}
	posts, _ := h.social.ListCommunityPublicPosts(id, 3)
	if posts == nil {
		posts = []*models.Post{}
	}
	c.JSON(http.StatusOK, gin.H{
		"community":   community,
		"experts":     experts,
		"samplePosts": posts,
	})
}

// GET /api/communities/:id/posts
//
// Gating depends on the community's [is_public] flag (mig 0019, item 2.18):
//   * is_public=true   → any authed user can read (compose still
//                        gated to members in CreateCommunityPost).
//   * is_public=false  → members + admins only; non-members get 403
//                        with a "join to see posts" hint so the mobile
//                        UI can render a Join CTA instead of empty feed.
func (h *SocialHandler) ListCommunityPosts(c *gin.Context) {
	communityID := c.Param("id")
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	// Admin override — moderation needs read access regardless of
	// membership. Best-effort lookup; on failure fall through to
	// the membership check.
	isAdmin := false
	if h.users != nil {
		if u, lookupErr := h.users.GetByID(userID); lookupErr == nil &&
			u != nil && u.Role == "ADMIN" {
			isAdmin = true
		}
	}
	if !isAdmin {
		// Public community → drop the membership gate for read access.
		isPublic, perr := h.social.IsCommunityPublic(communityID)
		if perr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": perr.Error()})
			return
		}
		if !isPublic {
			isMember, err := h.social.IsMemberOfCommunity(userID, communityID)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			if !isMember {
				c.JSON(http.StatusForbidden, gin.H{
					"error": "join the community to see its posts",
				})
				return
			}
		}
	}
	limit := parseLimit(c.Query("limit"), 50)
	// Moderators (admin already known; plus owner / co-owner) get to see
	// hidden posts so they can un-hide them; the author sees their own
	// hidden posts via the viewerID match inside the repo query.
	canModerate := isAdmin
	if !canModerate {
		if owner, oerr := h.social.CommunityOwnerID(communityID); oerr == nil && owner == userID {
			canModerate = true
		} else if h.coOwners != nil {
			if ok, _ := h.coOwners.IsCoOwner(communityID, userID); ok {
				canModerate = true
			}
		}
	}
	posts, err := h.social.ListCommunityPosts(communityID, limit, userID, canModerate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

// =============================================================================
// Authenticated routes
// =============================================================================

// GET /api/me — returns the authed user along with role + subscriptions.
// Lets the Flutter app rehydrate its local session against the server.
func (h *SocialHandler) Me(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, ok := uid.(int64)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing user"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	subs, err := h.social.ListSubscribedExpertIDs(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if subs == nil {
		subs = []string{}
	}
	// Avatar is stored as an S3 value; sign it fresh on read so it never
	// 403s on an expired pre-signed URL — and so the field is present at all
	// (the admin dashboard's profile form reads avatarUrl from /me on load).
	avatarURL := ""
	if user.AvatarURL.Valid && user.AvatarURL.String != "" {
		avatarURL = h.social.SignMediaURL(user.AvatarURL.String)
	}
	c.JSON(http.StatusOK, gin.H{
		"id":        user.ID,
		"email":     user.Email,
		"name":      nullStr(user.Name.String, user.Name.Valid),
		"avatarUrl": avatarURL,
		"role":      user.Role,
		"expertId":  nullStr(user.ExpertID.String, user.ExpertID.Valid),
		"tier":      user.SubscriptionTier,
		"status":    user.SubscriptionStatus,
		"following": subs,
	})
}

// GET /api/experts/:id/posts
// Subscription-gated. Non-subscribers get HTTP 402 (Payment Required) so the
// Flutter app can render the paywall card; the gate already handles that.
// ListExpertPosts returns the post list for an expert profile.
//
// Step-2 semantics:
//   * Public posts            → returned in full to anyone (auth optional).
//   * Subscribers-only posts  → returned in full to subscribers + the owner;
//                               returned as locked teasers (no body / media)
//                               to everyone else.
//
// The 402 paywall is gone — it's replaced by per-row IsLocked flags so a
// single mixed list can be rendered as "some unlocked, some locked".
func (h *SocialHandler) ListExpertPosts(c *gin.Context) {
	expertID := c.Param("id")
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)

	// Decide gating. Owner of the expert profile sees everything, no
	// questions — including their own hidden posts (so the studio "draft"
	// flow works).
	canSeeGated := false
	includeHidden := false
	if userID != 0 {
		user, _ := h.users.GetByID(userID)
		if user != nil && user.ExpertID.Valid && user.ExpertID.String == expertID {
			canSeeGated = true
			includeHidden = true
		} else if user != nil && user.Role == "ADMIN" {
			// Admins see everything for moderation, including hidden posts.
			canSeeGated = true
			includeHidden = true
		} else {
			// Step-4: gate on an *active, unexpired* subscription. The
			// older follow-style `IsSubscribed` is kept as a fallback so
			// any legacy follows still grant access.
			active, err := h.expertSubs.HasActiveAccess(userID, expertID)
			if err == nil && active {
				canSeeGated = true
			} else {
				subscribed, err2 := h.social.IsSubscribed(userID, expertID)
				if err2 == nil && subscribed {
					canSeeGated = true
				}
			}
		}
	}

	limit := parseLimit(c.Query("limit"), 50)
	posts, err := h.social.ListPostsByExpert(expertID, "", limit, includeHidden)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Subscribers-only posts are now hidden entirely from
	// non-subscribers (no teaser). Public posts still appear so a
	// non-subscriber can preview the expert's free content and
	// decide whether to subscribe.
	if !canSeeGated {
		filtered := make([]*models.Post, 0, len(posts))
		for _, p := range posts {
			if p.Visibility != models.VisibilitySubscribersOnly {
				filtered = append(filtered, p)
			}
		}
		posts = filtered
	}

	h.fillLiked(userID, posts)
	c.JSON(http.StatusOK, gin.H{
		"posts":      posts,
		"subscribed": canSeeGated,
	})
}

// MyExpertPosts — GET /api/me/expert/posts
//
// Returns every post the authenticated expert has authored on their own
// profile, ungated. Optional ?type=article|video|reel filter for the studio
// tabs. Used by the Flutter Expert Dashboard "Studio" view.
func (h *SocialHandler) MyExpertPosts(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	if !user.ExpertID.Valid {
		c.JSON(http.StatusForbidden, gin.H{"error": "only experts have a studio"})
		return
	}
	postType := strings.ToLower(strings.TrimSpace(c.Query("type")))
	switch postType {
	case "", models.PostTypeArticle, models.PostTypeVideo, models.PostTypeReel:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "type must be article|video|reel"})
		return
	}

	// includeHidden=true — the studio is the owner's view, where they need
	// to see and manage their hidden drafts.
	posts, err := h.social.ListPostsByExpert(user.ExpertID.String, postType, parseLimit(c.Query("limit"), 100), true)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.fillLiked(userID, posts)
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

// MyFeed — GET /api/me/feed
//
// Aggregates posts from every expert the caller has an active subscription
// to, newest-first. Optional ?type=article|video|reel filter for the bottom-
// nav Feed tab's chip filters.
//
// Optional ?before=<RFC3339 timestamp> is a keyset cursor for pagination —
// returns only posts strictly older than the timestamp. The client passes
// the oldest currently-loaded post's createdAt to fetch the next page.
//
// Hidden rows are excluded by the repo. The result is fully unlocked content
// (no LockTeaser pass) since by definition the user has paid access.
func (h *SocialHandler) MyFeed(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postType := strings.ToLower(strings.TrimSpace(c.Query("type")))
	switch postType {
	case "", models.PostTypeArticle, models.PostTypeVideo, models.PostTypeReel:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "type must be article|video|reel"})
		return
	}

	// Parse optional before cursor. Accept both RFC3339 ("2026-05-06T…")
	// and the simpler RFC3339Nano variant; tolerate trailing whitespace
	// from URL-encoded clients. A bad timestamp is treated as "no cursor"
	// rather than a 400 — the worst case is the user gets the latest
	// page instead of the next page, which is recoverable.
	var before time.Time
	if raw := strings.TrimSpace(c.Query("before")); raw != "" {
		if parsed, err := time.Parse(time.RFC3339Nano, raw); err == nil {
			before = parsed
		} else if parsed, err := time.Parse(time.RFC3339, raw); err == nil {
			before = parsed
		}
	}

	posts, err := h.social.ListSubscribedFeed(
		userID, postType, parseLimit(c.Query("limit"), 50), before,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.fillLiked(userID, posts)
	// Step 30 — return [] instead of null for empty feed so mobile
	// clients don't have to null-coalesce. Same convention as the
	// admin list endpoints.
	if posts == nil {
		posts = []*models.Post{}
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

// GetPostByID — GET /api/posts/:id
//
// Single-post fetch used by deep-link route resolution (someone tapped a
// shared "https://unmu.app/p/123" URL). Privacy gates:
//
//   * Community posts         → members-only. Non-members + non-admins
//                               get 403 with a "join to view" hint so
//                               the mobile UI renders a Join CTA.
//   * Public expert posts     → returned in full to anyone.
//   * Subscribers-only expert → returned in full to the owner / admins /
//                               active subscribers; everyone else gets
//                               404 (we no longer ship a teaser).
//   * Hidden posts            → 404, regardless of caller.
//
// Auth required — non-authed callers get 401. The deep-link path
// resolves the shared URL after sign-in is complete.
func (h *SocialHandler) GetPostByID(c *gin.Context) {
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	post, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if post == nil || post.IsHidden {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}

	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}

	// Resolve the caller's role + admin/owner status once — both
	// the community membership check and the expert subscription
	// check use it.
	var callerUser *models.User
	isAdmin := false
	if h.users != nil {
		if u, _ := h.users.GetByID(userID); u != nil {
			callerUser = u
			if u.Role == "ADMIN" {
				isAdmin = true
			}
		}
	}

	// ── Community-target gate ────────────────────────────────
	// is_public communities skip the membership check for READ — the
	// post viewer just shows the post. Compose still requires
	// membership (enforced in CreateCommunityPost).
	if post.CommunityID != nil {
		if !isAdmin {
			isAuthor := callerUser != nil && callerUser.ID == post.AuthorID
			if !isAuthor {
				isPublic, perr := h.social.IsCommunityPublic(*post.CommunityID)
				if perr != nil {
					c.JSON(http.StatusInternalServerError,
						gin.H{"error": perr.Error()})
					return
				}
				if !isPublic {
					isMember, err := h.social.IsMemberOfCommunity(
						userID, *post.CommunityID,
					)
					if err != nil {
						c.JSON(http.StatusInternalServerError,
							gin.H{"error": err.Error()})
						return
					}
					if !isMember {
						c.JSON(http.StatusForbidden, gin.H{
							"error": "join the community to view this post",
						})
						return
					}
				}
			}
		}
	}

	// ── Expert-target gate ───────────────────────────────────
	canSeeGated := false
	if post.ExpertID == nil {
		// Community-target post — already passed the membership
		// gate above, no further check needed.
		canSeeGated = true
	} else {
		switch {
		case callerUser != nil && callerUser.ExpertID.Valid &&
			callerUser.ExpertID.String == *post.ExpertID:
			canSeeGated = true // own profile
		case isAdmin:
			canSeeGated = true
		default:
			active, err := h.expertSubs.HasActiveAccess(userID, *post.ExpertID)
			if err == nil && active {
				canSeeGated = true
			} else if subscribed, err2 := h.social.IsSubscribed(userID, *post.ExpertID); err2 == nil && subscribed {
				canSeeGated = true
			}
		}
	}

	// Subscribers-only expert posts now hide entirely from
	// non-subscribers (used to ship a locked teaser). Per the
	// privacy model: subscribed → see; everyone else → as if it
	// doesn't exist.
	if post.ExpertID != nil &&
		post.Visibility == models.VisibilitySubscribersOnly &&
		!canSeeGated {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}

	h.fillLiked(userID, []*models.Post{post})

	// Best-effort engagement log — admin uses this to see how often
	// shared `unmu.app/p/:id` links actually convert to opens. Userless
	// (deep-link tap before sign-in) is fine; we pass nil userID.
	if h.events != nil {
		var uidPtr *int64
		if userID != 0 {
			uidPtr = &userID
		}
		_ = h.events.Write(post.ID, repositories.EventDeepLinkOpened, uidPtr, nil)
	}

	c.JSON(http.StatusOK, gin.H{"post": post})
}

// POST /api/communities/:id/posts
// Body: { "title": "...", "body": "...", "ticker": "AAPL", "stance": "BUY" }
func (h *SocialHandler) CreateCommunityPost(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	communityID := c.Param("id")
	// ── Expert-only post gate ──────────────────────────────────────
	// Posting in a community is restricted to verified experts who
	// are members of that community. Two-stage check so the error
	// messages tell the user EXACTLY what's missing rather than a
	// generic 403:
	//
	//   1. role == EXPERT  AND  expert_id IS NOT NULL
	//      → has a real expert profile (not just a role tag)
	//   2. caller is in community_members for THIS community
	//      → can't post in a community they haven't joined
	//
	// Owners always satisfy both checks because the proposal-approval
	// flow only accepts EXPERT users and adds them as the first
	// member (migration 0011 + 0012). Admins can post via the
	// dashboard's parallel endpoint, not this one — keeps the gate
	// simple.
	if user.Role != "EXPERT" || !user.ExpertID.Valid {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "only experts can post in communities",
		})
		return
	}
	isMember, err := h.social.IsMemberOfCommunity(userID, communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if !isMember {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "join the community before posting",
		})
		return
	}
	// Body shape now mirrors the expert-post endpoint so community
	// owners + experts can publish articles, videos, and reels —
	// every field except title/body/ticker is optional. Older
	// callers that send only {title, body, ticker, stance} continue
	// to work because the new fields have safe defaults.
	var body struct {
		Title           string   `json:"title"`
		Body            string   `json:"body"`
		Ticker          string   `json:"ticker"`            // singular legacy
		Tickers         []string `json:"tickers"`           // optional array
		Stance          string   `json:"stance"`
		PostType        string   `json:"postType"`          // article|video|reel
		Visibility      string   `json:"visibility"`        // public|subscribers_only
		MediaURL        string   `json:"mediaUrl"`
		CoverURL        string   `json:"coverUrl"`
		DurationSeconds *int     `json:"durationSeconds"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Title = strings.TrimSpace(body.Title)
	body.Body = strings.TrimSpace(body.Body)
	body.Ticker = strings.ToUpper(strings.TrimSpace(body.Ticker))
	body.Stance = strings.ToUpper(strings.TrimSpace(body.Stance))
	body.PostType = strings.ToLower(strings.TrimSpace(body.PostType))
	body.Visibility = strings.ToLower(strings.TrimSpace(body.Visibility))
	body.MediaURL = strings.TrimSpace(body.MediaURL)
	body.CoverURL = strings.TrimSpace(body.CoverURL)
	// Normalise the ticker arrays so callers can use either shape.
	// We always pass a single primary ticker through to the repo
	// (for the legacy `ticker` column) and the full array for the
	// JSONB `tickers` column.
	tickersUpper := make([]string, 0, len(body.Tickers))
	for _, t := range body.Tickers {
		t = strings.ToUpper(strings.TrimSpace(t))
		if t != "" {
			tickersUpper = append(tickersUpper, t)
		}
	}
	if body.Ticker == "" && len(tickersUpper) > 0 {
		body.Ticker = tickersUpper[0]
	}
	// Sprint-C step 9 — `ticker` is now OPTIONAL. Many community
	// posts are discussion-style (general questions, announcements)
	// and don't reference a specific stock. We still keep the
	// column non-null at the DB level so we pass an empty string;
	// the repo CreateCommunityPost defaults it to "" if blank.
	if body.Title == "" || body.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "title and body are required",
		})
		return
	}
	switch body.Stance {
	case "BUY", "HOLD", "SELL":
	case "":
		body.Stance = "HOLD"
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "stance must be BUY|HOLD|SELL"})
		return
	}
	// Default postType = article so old payloads keep their shape.
	switch body.PostType {
	case "article", "video", "reel":
	case "":
		body.PostType = "article"
	default:
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "postType must be article|video|reel",
		})
		return
	}
	// Visibility — default subscribers_only for community posts so
	// they're members-only by default (matches the new privacy model).
	switch body.Visibility {
	case "public", "subscribers_only":
	case "":
		body.Visibility = "subscribers_only"
	default:
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "visibility must be public|subscribers_only",
		})
		return
	}
	authorName := user.Email
	if user.Name.Valid && strings.TrimSpace(user.Name.String) != "" {
		authorName = user.Name.String
	}
	post, err := h.social.CreateCommunityPost(
		communityID, userID, authorName,
		body.Title, body.Body, body.Ticker, body.Stance,
		repositories.CommunityPostExtras{
			PostType:        body.PostType,
			Visibility:      body.Visibility,
			MediaURL:        body.MediaURL,
			CoverURL:        body.CoverURL,
			DurationSeconds: body.DurationSeconds,
			Tickers:         tickersUpper,
		},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Notify other community members of the new post (push-only — too
	// high-volume to write a per-member inbox row). Best-effort.
	if h.notifier != nil {
		communityName := communityID
		if comm, cerr := h.social.GetCommunity(communityID); cerr == nil && comm != nil {
			communityName = comm.Name
		}
		if members, merr := h.social.ListMemberIDs(communityID); merr == nil {
			recipients := make([]int64, 0, len(members))
			for _, m := range members {
				if m != userID { // skip the author
					recipients = append(recipients, m)
				}
			}
			h.notifier.PushToUsers(
				c.Request.Context(), recipients, "community_new_post",
				map[string]string{"author": authorName, "community": communityName},
			)
		}
	}
	c.JSON(http.StatusCreated, post)
}

// =============================================================================
// Community-post moderation — edit / hide / delete.
//
// Permission model (per product owner): a community post can be moderated by
//   • its AUTHOR (the expert who wrote it),
//   • the community OWNER or any co-owner,
//   • a platform ADMIN (can do anything).
// All three operations share this same permission set, enforced by
// requireCommunityPostMod below.
// =============================================================================

// requireCommunityPostMod loads the post, verifies it belongs to communityID,
// and confirms the caller may moderate it (author OR owner/co-owner OR admin).
// On any failure it writes the HTTP error and returns (nil, false).
func (h *SocialHandler) requireCommunityPostMod(
	c *gin.Context, communityID string, postID int64,
) (*models.Post, bool) {
	uid, _ := c.Get("user_id")
	callerID, _ := uid.(int64)
	if callerID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return nil, false
	}
	post, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return nil, false
	}
	if post == nil || post.CommunityID == nil || *post.CommunityID != communityID {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return nil, false
	}
	// 1. Author can always moderate their own post.
	if post.AuthorID == callerID {
		return post, true
	}
	// 2. Primary owner.
	if owner, err := h.social.CommunityOwnerID(communityID); err == nil && owner == callerID {
		return post, true
	}
	// 3. Co-owner (mig 0032).
	if h.coOwners != nil {
		if ok, _ := h.coOwners.IsCoOwner(communityID, callerID); ok {
			return post, true
		}
	}
	// 4. Platform admin can do anything.
	if h.users != nil {
		if u, _ := h.users.GetByID(callerID); u != nil && u.Role == "ADMIN" {
			return post, true
		}
	}
	c.JSON(http.StatusForbidden, gin.H{
		"error": "only the author, community owner, or an admin can modify this post",
	})
	return nil, false
}

// PATCH /api/communities/:id/posts/:postId
//
// Partial edit of a community post. Body fields are all optional; only the
// ones provided are touched. Same shape as the expert-post edit endpoint.
func (h *SocialHandler) UpdateCommunityPost(c *gin.Context) {
	communityID := c.Param("id")
	postID, err := strconv.ParseInt(c.Param("postId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid postId"})
		return
	}
	if _, ok := h.requireCommunityPostMod(c, communityID, postID); !ok {
		return
	}

	var body struct {
		Title           *string   `json:"title"`
		Body            *string   `json:"body"`
		MediaURL        *string   `json:"mediaUrl"`
		CoverURL        *string   `json:"coverUrl"`
		DurationSeconds *int      `json:"durationSeconds"`
		Visibility      *string   `json:"visibility"`
		Tickers         *[]string `json:"tickers"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	upd := repositories.ExpertPostUpdate{}
	if body.Title != nil {
		t := strings.TrimSpace(*body.Title)
		upd.Title = &t
	}
	if body.Body != nil {
		t := strings.TrimSpace(*body.Body)
		upd.Body = &t
	}
	if body.MediaURL != nil {
		t := strings.TrimSpace(*body.MediaURL)
		upd.MediaURL = &t
	}
	if body.CoverURL != nil {
		t := strings.TrimSpace(*body.CoverURL)
		upd.CoverURL = &t
	}
	if body.DurationSeconds != nil {
		existing, _ := h.social.GetPostByID(postID)
		if existing != nil && existing.PostType == models.PostTypeReel &&
			(*body.DurationSeconds > 60 || *body.DurationSeconds <= 0) {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "reels must be between 1 and 60 seconds",
			})
			return
		}
		upd.DurationSeconds = body.DurationSeconds
	}
	if body.Visibility != nil {
		v := strings.ToLower(strings.TrimSpace(*body.Visibility))
		switch v {
		case models.VisibilityPublic, models.VisibilitySubscribersOnly:
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "visibility must be public|subscribers_only"})
			return
		}
		upd.Visibility = &v
	}
	if body.Tickers != nil {
		clean := make([]string, 0, len(*body.Tickers))
		for _, t := range *body.Tickers {
			t = strings.ToUpper(strings.TrimSpace(t))
			if t != "" {
				clean = append(clean, t)
			}
		}
		upd.Tickers = &clean
	}

	// Best-effort version snapshot of the pre-edit state.
	if existing, _ := h.social.GetPostByID(postID); existing != nil {
		uid, _ := c.Get("user_id")
		editorID, _ := uid.(int64)
		title := ""
		if existing.Title != nil {
			title = *existing.Title
		}
		_ = h.social.WritePostVersion(postID, editorID, title, existing.Body, existing.Tickers)
	}

	updated, err := h.social.UpdateCommunityPost(postID, upd)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// PATCH /api/communities/:id/posts/:postId/hide
// Body: { "hidden": true|false } — soft-moderation toggle.
func (h *SocialHandler) SetCommunityPostHidden(c *gin.Context) {
	communityID := c.Param("id")
	postID, err := strconv.ParseInt(c.Param("postId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid postId"})
		return
	}
	if _, ok := h.requireCommunityPostMod(c, communityID, postID); !ok {
		return
	}
	var body struct {
		Hidden bool `json:"hidden"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	updated, err := h.social.SetCommunityPostHidden(postID, body.Hidden)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// DELETE /api/communities/:id/posts/:postId
// Permanently removes a community post.
func (h *SocialHandler) DeleteCommunityPost(c *gin.Context) {
	communityID := c.Param("id")
	postID, err := strconv.ParseInt(c.Param("postId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid postId"})
		return
	}
	if _, ok := h.requireCommunityPostMod(c, communityID, postID); !ok {
		return
	}
	if err := h.social.DeleteCommunityPost(postID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

// POST /api/experts/:id/posts
//
// Body (step 2):
//
//	{
//	  "postType":  "article" | "video" | "reel",
//	  "title":     "...",                       (article: required, others: optional)
//	  "body":      "...",                       (article: required, others: caption)
//	  "mediaUrl":  "https://...mp4",            (video / reel)
//	  "coverUrl":  "https://...jpg",            (video / reel)
//	  "durationSeconds": 90,                    (video / reel)
//	  "visibility": "public" | "subscribers_only",
//	  "tickers":   ["AAPL","NVDA"]
//	}
//
// Only the EXPERT/SCHOLAR who owns this profile may post here.
func (h *SocialHandler) CreateExpertPost(c *gin.Context) {
	expertID := c.Param("id")
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	if !user.ExpertID.Valid || user.ExpertID.String != expertID {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "only the owner of this expert profile may post here",
		})
		return
	}
	var body struct {
		PostType        string   `json:"postType"`
		Title           string   `json:"title"`
		Body            string   `json:"body"`
		MediaURL        string   `json:"mediaUrl"`
		CoverURL        string   `json:"coverUrl"`
		DurationSeconds *int     `json:"durationSeconds"`
		Visibility      string   `json:"visibility"`
		Tickers         []string `json:"tickers"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	// Defaults + validation.
	body.PostType = strings.ToLower(strings.TrimSpace(body.PostType))
	if body.PostType == "" {
		body.PostType = models.PostTypeArticle
	}
	switch body.PostType {
	case models.PostTypeArticle, models.PostTypeVideo, models.PostTypeReel:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "postType must be article|video|reel"})
		return
	}

	body.Visibility = strings.ToLower(strings.TrimSpace(body.Visibility))
	if body.Visibility == "" {
		body.Visibility = models.VisibilitySubscribersOnly
	}
	switch body.Visibility {
	case models.VisibilityPublic, models.VisibilitySubscribersOnly:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "visibility must be public|subscribers_only"})
		return
	}

	body.Title = strings.TrimSpace(body.Title)
	body.Body = strings.TrimSpace(body.Body)
	body.MediaURL = strings.TrimSpace(body.MediaURL)
	body.CoverURL = strings.TrimSpace(body.CoverURL)

	// Per-type required fields.
	switch body.PostType {
	case models.PostTypeArticle:
		if body.Title == "" || body.Body == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "articles require both title and body",
			})
			return
		}
	case models.PostTypeVideo, models.PostTypeReel:
		if body.MediaURL == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "videos/reels require mediaUrl",
			})
			return
		}
		// Reels are short-form: cap at 60 seconds. Videos have no cap.
		if body.PostType == models.PostTypeReel && body.DurationSeconds != nil &&
			(*body.DurationSeconds > 60 || *body.DurationSeconds <= 0) {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "reels must be between 1 and 60 seconds",
			})
			return
		}
	}

	cleanTickers := make([]string, 0, len(body.Tickers))
	for _, t := range body.Tickers {
		t = strings.ToUpper(strings.TrimSpace(t))
		if t != "" {
			cleanTickers = append(cleanTickers, t)
		}
	}
	authorName := user.Email
	if user.Name.Valid && strings.TrimSpace(user.Name.String) != "" {
		authorName = user.Name.String
	}
	post, err := h.social.CreateExpertPost(repositories.ExpertPostInput{
		ExpertID:        expertID,
		AuthorID:        userID,
		AuthorName:      authorName,
		PostType:        body.PostType,
		Title:           body.Title,
		Body:            body.Body,
		Tickers:         cleanTickers,
		MediaURL:        body.MediaURL,
		CoverURL:        body.CoverURL,
		DurationSeconds: body.DurationSeconds,
		Visibility:      body.Visibility,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, post)
}

// =============================================================================
// Step-5 — owner can edit, hide, and delete posts on their own profile.
//
// All three endpoints share the same auth check: the caller must be the
// EXPERT/SCHOLAR who owns this expert profile. Admins are also allowed to
// delete + hide for moderation, but only the post's author can edit content.
// =============================================================================

// requireOwnerOrAdmin enforces the auth rule for post mutation endpoints.
// Returns the post + a flag indicating whether the caller is the owner
// (vs a moderating admin), or writes the appropriate HTTP error and
// returns nil.
func (h *SocialHandler) requireOwnerOrAdmin(c *gin.Context, expertID string, postID int64) (*models.Post, bool, bool) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return nil, false, false
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return nil, false, false
	}
	post, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return nil, false, false
	}
	if post == nil || post.ExpertID == nil || *post.ExpertID != expertID {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return nil, false, false
	}
	isOwner := user.ExpertID.Valid && user.ExpertID.String == expertID && post.AuthorID == userID
	isAdmin := user.Role == "ADMIN"
	if !isOwner && !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the post's author or an admin can modify it"})
		return nil, false, false
	}
	return post, isOwner, isAdmin
}

// PATCH /api/experts/:id/posts/:postId
//
// Body — every field optional; only the ones provided are touched:
//
//	{
//	  "title":            "...",
//	  "body":             "...",
//	  "mediaUrl":         "https://...mp4",
//	  "coverUrl":         "https://...jpg",
//	  "durationSeconds":  90,
//	  "visibility":       "public" | "subscribers_only",
//	  "tickers":          ["AAPL","NVDA"]
//	}
//
// Only the post's author may edit content. Admins must use a separate
// moderation flow — letting admins rewrite expert content silently would
// be a credibility issue.
func (h *SocialHandler) UpdateExpertPost(c *gin.Context) {
	expertID := c.Param("id")
	postID, err := strconv.ParseInt(c.Param("postId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid postId"})
		return
	}
	_, isOwner, _ := h.requireOwnerOrAdmin(c, expertID, postID)
	if !c.Writer.Written() && !isOwner {
		// requireOwnerOrAdmin already responded if there was a hard error;
		// here we additionally block admins from editing content.
		c.JSON(http.StatusForbidden, gin.H{"error": "only the post's author may edit content"})
		return
	}
	if c.Writer.Written() {
		return
	}

	var body struct {
		Title           *string   `json:"title"`
		Body            *string   `json:"body"`
		MediaURL        *string   `json:"mediaUrl"`
		CoverURL        *string   `json:"coverUrl"`
		DurationSeconds *int      `json:"durationSeconds"`
		Visibility      *string   `json:"visibility"`
		Tickers         *[]string `json:"tickers"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	// Normalize + validate the partial update.
	upd := repositories.ExpertPostUpdate{}
	if body.Title != nil {
		t := strings.TrimSpace(*body.Title)
		upd.Title = &t
	}
	if body.Body != nil {
		t := strings.TrimSpace(*body.Body)
		upd.Body = &t
	}
	if body.MediaURL != nil {
		t := strings.TrimSpace(*body.MediaURL)
		upd.MediaURL = &t
	}
	if body.CoverURL != nil {
		t := strings.TrimSpace(*body.CoverURL)
		upd.CoverURL = &t
	}
	if body.DurationSeconds != nil {
		// Same 60s cap as create — but only for reels. Look up the
		// existing post via requireOwnerOrAdmin's lookup (already loaded
		// above) so we know its post_type.
		existing, _ := h.social.GetPostByID(postID)
		if existing != nil && existing.PostType == models.PostTypeReel &&
			(*body.DurationSeconds > 60 || *body.DurationSeconds <= 0) {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "reels must be between 1 and 60 seconds",
			})
			return
		}
		upd.DurationSeconds = body.DurationSeconds
	}
	if body.Visibility != nil {
		v := strings.ToLower(strings.TrimSpace(*body.Visibility))
		switch v {
		case models.VisibilityPublic, models.VisibilitySubscribersOnly:
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "visibility must be public|subscribers_only"})
			return
		}
		upd.Visibility = &v
	}
	if body.Tickers != nil {
		clean := make([]string, 0, len(*body.Tickers))
		for _, t := range *body.Tickers {
			t = strings.ToUpper(strings.TrimSpace(t))
			if t != "" {
				clean = append(clean, t)
			}
		}
		upd.Tickers = &clean
	}

	// Step-20 (mig 0020, item 4.16) — snapshot the pre-edit state into
	// post_versions BEFORE the update runs, so the version row captures
	// what's about to be replaced. Best-effort: a failed snapshot
	// shouldn't block the user's edit; we just log via the audit table
	// (existing infra) on the very rare fail path. The handler doesn't
	// know about audit here so we silently swallow snapshot errors.
	if existing, _ := h.social.GetPostByID(postID); existing != nil {
		uid, _ := c.Get("user_id")
		editorID, _ := uid.(int64)
		title := ""
		if existing.Title != nil {
			title = *existing.Title
		}
		_ = h.social.WritePostVersion(
			postID, editorID, title, existing.Body, existing.Tickers,
		)
	}

	updated, err := h.social.UpdateExpertPost(postID, upd)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// PATCH /api/experts/:id/posts/:postId/visibility
// Body: { "hidden": true|false }
//
// Toggles the is_hidden flag. Both the post's author and admins can call
// this — admins use it as a soft-moderation tool (hide without deleting).
func (h *SocialHandler) SetExpertPostHidden(c *gin.Context) {
	expertID := c.Param("id")
	postID, err := strconv.ParseInt(c.Param("postId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid postId"})
		return
	}
	if _, _, _ = h.requireOwnerOrAdmin(c, expertID, postID); c.Writer.Written() {
		return
	}
	var body struct {
		Hidden bool `json:"hidden"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	updated, err := h.social.SetExpertPostHidden(postID, body.Hidden)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// DELETE /api/experts/:id/posts/:postId
//
// Permanently removes the post. Both the post's author and admins can
// delete; admins shouldn't be reaching for this regularly (prefer hide)
// but it's available for clear-cut moderation cases.
func (h *SocialHandler) DeleteExpertPost(c *gin.Context) {
	expertID := c.Param("id")
	postID, err := strconv.ParseInt(c.Param("postId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid postId"})
		return
	}
	if _, _, _ = h.requireOwnerOrAdmin(c, expertID, postID); c.Writer.Written() {
		return
	}
	if err := h.social.DeleteExpertPost(postID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

// POST /api/experts/:id/subscribe — toggle on if not already subscribed.
func (h *SocialHandler) Subscribe(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if err := h.social.Subscribe(userID, c.Param("id")); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "subscribed"})
}

// DELETE /api/experts/:id/subscribe — unsubscribe.
func (h *SocialHandler) Unsubscribe(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if err := h.social.Unsubscribe(userID, c.Param("id")); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "unsubscribed"})
}

// POST /api/communities/:id/join
//
// Free communities only — paid communities must go through
// `/communities/:id/subscribe` (step-23). Returns 402 Payment
// Required with the price + currency so the mobile client can route
// the user to the payment sheet.
func (h *SocialHandler) JoinCommunity(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	communityID := c.Param("id")
	community, err := h.social.GetCommunity(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if community == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "community not found"})
		return
	}
	if community.JoinPriceMonthlyCents > 0 || community.JoinPriceYearlyCents > 0 {
		c.JSON(http.StatusPaymentRequired, gin.H{
			"error":             "this community requires a paid subscription",
			"joinPriceMonthlyCents": community.JoinPriceMonthlyCents,
			"joinPriceYearlyCents":  community.JoinPriceYearlyCents,
			"priceCurrency":         community.PriceCurrency,
		})
		return
	}
	if err := h.social.JoinCommunity(userID, communityID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.broadcastMemberChanged(communityID)
	c.JSON(http.StatusOK, gin.H{"status": "joined"})
}

// POST /api/communities/:id/leave
//
// Removes the caller from the community. Owners get 409 — they
// must use the admin dashboard's transfer/delete flow to step down.
// Non-members get 404 so the client can clean up its local state.
func (h *SocialHandler) LeaveCommunity(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	communityID := c.Param("id")
	err := h.social.LeaveCommunity(userID, communityID)
	if err == nil {
		h.broadcastMemberChanged(communityID)
		c.JSON(http.StatusOK, gin.H{"status": "left"})
		return
	}
	if errors.Is(err, sql.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{
			"error": "you're not a member of this community",
		})
		return
	}
	if err.Error() == "owner cannot leave community" {
		c.JSON(http.StatusConflict, gin.H{
			"error": "owners cannot leave their own community",
		})
		return
	}
	c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
}

// GET /api/communities/:id/membership
//
// Lightweight check the mobile UI uses on community-detail mount
// to decide whether to render Join vs Leave. Returns
// `{member: bool, owner: bool}`.
func (h *SocialHandler) GetCommunityMembership(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	communityID := c.Param("id")
	isMember, err := h.social.IsMemberOfCommunity(userID, communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Owner check — single query, returns 0 when there's no owner.
	ownerID, err := h.social.CommunityOwnerID(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Co-owner check (mig 0032). The `owner` flag returned here is
	// used by the mobile UI to:
	//   * show the Manage gear + Invite-expert button
	//   * unlock the "compose post in community" FAB
	// Co-owners should get all three, so we collapse primary +
	// co-owner into a single `owner: true` for client consumption.
	// We also expose the more precise `primaryOwner` flag for the
	// rare case where the UI needs to distinguish (e.g. show "Leave
	// community" vs "Cannot leave — transfer first").
	isPrimary := ownerID == userID
	isCoOwner := false
	if !isPrimary && h.coOwners != nil {
		isCoOwner, _ = h.coOwners.IsCoOwner(communityID, userID)
	}
	// Live member count via aggregate — the response includes it so
	// the mobile can render an accurate header on first paint
	// without a follow-up call.
	memberCount, _ := h.social.CommunityMemberCount(communityID)
	c.JSON(http.StatusOK, gin.H{
		"member":       isMember || isPrimary || isCoOwner,
		"owner":        isPrimary || isCoOwner,
		"primaryOwner": isPrimary,
		"coOwner":      isCoOwner,
		"communityId":  communityID,
		"memberCount":  memberCount,
	})
}

// DELETE /api/communities/:id/members/:userId
//
// Owner-only. Removes a member from the community. The current
// owner can't kick themselves (would orphan ownership) — they must
// transfer first or step down via the admin dashboard.
//
// Broadcasts community_member_changed so other connected clients
// update their member counts live.
func (h *SocialHandler) RemoveCommunityMember(c *gin.Context) {
	uid, _ := c.Get("user_id")
	requesterID, _ := uid.(int64)
	if requesterID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	communityID := c.Param("id")
	targetID, perr := strconv.ParseInt(c.Param("userId"), 10, 64)
	if perr != nil || targetID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	// Authorization — must be the community owner.
	ownerID, err := h.social.CommunityOwnerID(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if ownerID != requesterID {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "only the community owner can remove members",
		})
		return
	}
	// Owner can't kick themselves — would orphan ownership.
	if targetID == ownerID {
		c.JSON(http.StatusConflict, gin.H{
			"error": "owners can't remove themselves; transfer ownership first",
		})
		return
	}

	if err := h.social.RemoveMember(communityID, targetID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "user is not a member of this community",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.broadcastMemberChanged(communityID)
	c.JSON(http.StatusOK, gin.H{"removed": true})
}

// POST /api/communities/:id/transfer-ownership
//
// Body: { "newOwnerId": <int64> }
//
// Owner-only. New owner must be a member of the community. After
// transfer, the previous owner becomes a regular member (still in
// community_members) and can leave normally.
//
// Broadcasts community_owner_changed so connected clients flip
// their owner-only UI affordances live.
func (h *SocialHandler) TransferCommunityOwnership(c *gin.Context) {
	uid, _ := c.Get("user_id")
	requesterID, _ := uid.(int64)
	if requesterID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	communityID := c.Param("id")

	var body struct {
		NewOwnerID int64 `json:"newOwnerId"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.NewOwnerID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "newOwnerId required"})
		return
	}

	currentOwnerID, err := h.social.CommunityOwnerID(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if currentOwnerID != requesterID {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "only the current owner can transfer ownership",
		})
		return
	}
	if body.NewOwnerID == currentOwnerID {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "new owner is already the owner",
		})
		return
	}
	// New owner must be a member of the community.
	isMember, err := h.social.IsMemberOfCommunity(body.NewOwnerID, communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if !isMember {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "new owner must be a member of the community",
		})
		return
	}
	// New owner must also be an EXPERT — communities are run by
	// experts, and a regular USER would suddenly inherit owner-only
	// powers (delete community, kick members, change pricing, etc.)
	// that they're not entitled to under the platform's role model.
	target, err := h.users.GetByID(body.NewOwnerID)
	if err != nil || target == nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "new owner not found",
		})
		return
	}
	if strings.ToUpper(target.Role) != "EXPERT" &&
		strings.ToUpper(target.Role) != "ADMIN" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "new owner must be an expert in this community",
		})
		return
	}

	if err := h.social.TransferOwnership(communityID, body.NewOwnerID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"community_owner_changed",
			gin.H{
				"communityId":    communityID,
				"newOwnerId":     body.NewOwnerID,
				"previousOwnerId": requesterID,
			},
		)
	}
	c.JSON(http.StatusOK, gin.H{
		"transferred": true,
		"newOwnerId":  body.NewOwnerID,
	})
}

// broadcastMemberChanged — fired from JoinCommunity / LeaveCommunity
// to push the live member count to every connected client viewing
// the community. Mobile listens on the `community:<id>` channel and
// patches its local header without a refetch.
//
// Best-effort: a failed count query or a nil hub silently drops the
// broadcast — mobile's next mount will re-fetch via membership and
// catch up.
func (h *SocialHandler) broadcastMemberChanged(communityID string) {
	if h.hub == nil {
		return
	}
	count, err := h.social.CommunityMemberCount(communityID)
	if err != nil {
		return
	}
	h.hub.PublishJSON(
		realtime.ChannelCommunity(communityID),
		"community_member_changed",
		gin.H{
			"communityId": communityID,
			"memberCount": count,
		},
	)
}

// GET /api/experts/:id/communities
//
// Public. Returns every community the expert participates in,
// owner-first then by member count. Drives the "Communities" strip
// on the expert profile screen — visitors can scan an expert's
// reach without leaving their profile.
func (h *SocialHandler) ListExpertCommunities(c *gin.Context) {
	expertID := c.Param("id")
	if expertID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "expert id required"})
		return
	}
	rows, err := h.social.ListCommunitiesForExpert(expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"communities": rows})
}

// GET /api/me/communities
//
// Auth-required. Returns the list of community ids the caller is a
// member of. Drives the "Joined" filter toggle on the mobile
// social hub — keeping it as a flat array of ids (rather than full
// Community objects) lets the client filter its already-cached
// list without a redundant payload.
func (h *SocialHandler) ListMyCommunities(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	ids, err := h.social.ListJoinedCommunityIDs(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if ids == nil {
		ids = []string{}
	}
	c.JSON(http.StatusOK, gin.H{"communityIds": ids})
}

// GET /api/communities/:id/members
//
// Auth-required (member-of-platform). Returns every member of the
// community sorted owner-first then by join time. Drives the
// "remove member" / "transfer ownership" picker sheets on mobile —
// owner-only actions, but the LIST itself isn't sensitive (the
// admin dashboard already exposes it). Limiting to authed users
// just prevents bot scraping.
func (h *SocialHandler) ListCommunityMembersPublic(c *gin.Context) {
	uid, _ := c.Get("user_id")
	if userID, _ := uid.(int64); userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	communityID := c.Param("id")
	rows, err := h.social.AdminListCommunityMembers(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"members": rows})
}

// GET /api/communities/:id/experts
//
// "Experts in this community" panel — every member with role=EXPERT
// + a real expert profile, sorted owner-first then by subscriber
// count. Drives the horizontal expert-cards strip on the mobile
// community detail screen.
//
// Public — no auth required. The list isn't sensitive (it's a
// derivative of public expert profiles + community membership).
func (h *SocialHandler) ListCommunityExperts(c *gin.Context) {
	communityID := c.Param("id")
	rows, err := h.social.ListExpertsInCommunity(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"experts": rows})
}

// =============================================================================
// Step-20 (mig 0020, items 4.15 / 4.16 / 4.18) — drafts, version history,
// inline image attachments.
// =============================================================================

// minScheduleAheadSeconds — D3 from the plan. Schedules must land at
// least this far in the future so the every-60s publisher tick doesn't
// race with the create call.
const minScheduleAheadSeconds = 5 * 60

// CreateExpertDraft — POST /api/me/expert/drafts
//
// Same body shape as CreateExpertPost (article|video|reel). Status is
// set to 'draft' regardless of body content. Caller MUST be the expert
// who owns the profile they're authoring on.
//
// The body has an extra optional `expertId` field — defaults to the
// caller's own expert profile, but admin can author a draft on behalf
// of any profile (matches the existing admin override pattern).
func (h *SocialHandler) CreateExpertDraft(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	if !user.ExpertID.Valid {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "only experts can save drafts",
		})
		return
	}
	var body struct {
		PostType        string   `json:"postType"`
		Title           string   `json:"title"`
		Body            string   `json:"body"`
		MediaURL        string   `json:"mediaUrl"`
		CoverURL        string   `json:"coverUrl"`
		DurationSeconds *int     `json:"durationSeconds"`
		Visibility      string   `json:"visibility"`
		Tickers         []string `json:"tickers"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	// Defaults — drafts are intentionally permissive on validation
	// (the user might be saving a half-finished article). Required
	// fields are only enforced at publish time.
	body.PostType = strings.ToLower(strings.TrimSpace(body.PostType))
	if body.PostType == "" {
		body.PostType = models.PostTypeArticle
	}
	switch body.PostType {
	case models.PostTypeArticle, models.PostTypeVideo, models.PostTypeReel:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "postType must be article|video|reel"})
		return
	}
	body.Visibility = strings.ToLower(strings.TrimSpace(body.Visibility))
	if body.Visibility == "" {
		body.Visibility = models.VisibilitySubscribersOnly
	}
	switch body.Visibility {
	case models.VisibilityPublic, models.VisibilitySubscribersOnly:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "visibility must be public|subscribers_only"})
		return
	}

	cleanTickers := make([]string, 0, len(body.Tickers))
	for _, t := range body.Tickers {
		t = strings.ToUpper(strings.TrimSpace(t))
		if t != "" {
			cleanTickers = append(cleanTickers, t)
		}
	}
	authorName := user.Email
	if user.Name.Valid && strings.TrimSpace(user.Name.String) != "" {
		authorName = user.Name.String
	}

	post, err := h.social.CreateExpertDraft(repositories.ExpertPostInput{
		ExpertID:        user.ExpertID.String,
		AuthorID:        userID,
		AuthorName:      authorName,
		PostType:        body.PostType,
		Title:           strings.TrimSpace(body.Title),
		Body:            strings.TrimSpace(body.Body),
		Tickers:         cleanTickers,
		MediaURL:        strings.TrimSpace(body.MediaURL),
		CoverURL:        strings.TrimSpace(body.CoverURL),
		DurationSeconds: body.DurationSeconds,
		Visibility:      body.Visibility,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, post)
}

// UpdateExpertDraft — PATCH /api/me/expert/drafts/:id
//
// Partial-update on a draft row. Routed through the same
// UpdateExpertPost repo method as published-post edits, but with a
// pre-flight check that the row is currently a draft (or scheduled —
// flipping schedule time is allowed) authored by the caller. We
// intentionally DON'T snapshot to post_versions here because drafts
// pre-publish edit history is just noise.
func (h *SocialHandler) UpdateExpertDraft(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	existing, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "draft not found"})
		return
	}
	if existing.AuthorID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your draft"})
		return
	}
	if existing.Status == models.PostStatusPublished {
		c.JSON(http.StatusConflict, gin.H{
			"error": "post is already published — use PATCH /experts/:id/posts/:postId",
		})
		return
	}

	var body struct {
		Title           *string   `json:"title"`
		Body            *string   `json:"body"`
		MediaURL        *string   `json:"mediaUrl"`
		CoverURL        *string   `json:"coverUrl"`
		DurationSeconds *int      `json:"durationSeconds"`
		Visibility      *string   `json:"visibility"`
		Tickers         *[]string `json:"tickers"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	upd := repositories.ExpertPostUpdate{}
	if body.Title != nil {
		t := strings.TrimSpace(*body.Title)
		upd.Title = &t
	}
	if body.Body != nil {
		t := strings.TrimSpace(*body.Body)
		upd.Body = &t
	}
	if body.MediaURL != nil {
		t := strings.TrimSpace(*body.MediaURL)
		upd.MediaURL = &t
	}
	if body.CoverURL != nil {
		t := strings.TrimSpace(*body.CoverURL)
		upd.CoverURL = &t
	}
	if body.DurationSeconds != nil {
		upd.DurationSeconds = body.DurationSeconds
	}
	if body.Visibility != nil {
		v := strings.ToLower(strings.TrimSpace(*body.Visibility))
		switch v {
		case models.VisibilityPublic, models.VisibilitySubscribersOnly:
		default:
			c.JSON(http.StatusBadRequest, gin.H{"error": "visibility must be public|subscribers_only"})
			return
		}
		upd.Visibility = &v
	}
	if body.Tickers != nil {
		clean := make([]string, 0, len(*body.Tickers))
		for _, t := range *body.Tickers {
			t = strings.ToUpper(strings.TrimSpace(t))
			if t != "" {
				clean = append(clean, t)
			}
		}
		upd.Tickers = &clean
	}

	updated, err := h.social.UpdateExpertPost(postID, upd)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// PublishExpertDraft — POST /api/me/expert/drafts/:id/publish
//
// Body: { "publishAt": "<RFC3339>" } — optional. When omitted or null,
// the draft is published immediately. When set, must be at least 5
// minutes in the future (D3); the row flips to status='scheduled' and
// the publisher goroutine promotes it at the right time.
//
// Validation also enforces per-type required fields here (NOT at
// CreateExpertDraft) — articles need title+body, video/reel need a
// mediaUrl. A draft with missing required fields stays a draft.
func (h *SocialHandler) PublishExpertDraft(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	existing, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "draft not found"})
		return
	}
	if existing.AuthorID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your draft"})
		return
	}
	if existing.Status == models.PostStatusPublished {
		c.JSON(http.StatusConflict, gin.H{
			"error": "already published",
		})
		return
	}

	// Per-type required-fields gate.
	switch existing.PostType {
	case models.PostTypeArticle:
		title := ""
		if existing.Title != nil {
			title = *existing.Title
		}
		if strings.TrimSpace(title) == "" || strings.TrimSpace(existing.Body) == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "articles need both title and body before publishing",
			})
			return
		}
	case models.PostTypeVideo, models.PostTypeReel:
		if existing.MediaURL == nil || strings.TrimSpace(*existing.MediaURL) == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "videos/reels need mediaUrl before publishing",
			})
			return
		}
	}

	var body struct {
		PublishAt *string `json:"publishAt"`
	}
	_ = c.ShouldBindJSON(&body) // body is optional

	var at *time.Time
	if body.PublishAt != nil && strings.TrimSpace(*body.PublishAt) != "" {
		parsed, perr := time.Parse(time.RFC3339, strings.TrimSpace(*body.PublishAt))
		if perr != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "publishAt must be RFC3339 (e.g. 2026-05-09T18:00:00Z)",
			})
			return
		}
		if parsed.Before(time.Now().Add(minScheduleAheadSeconds * time.Second)) {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "publishAt must be at least 5 minutes in the future",
			})
			return
		}
		at = &parsed
	}

	updated, err := h.social.PublishDraftAt(postID, at)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "draft not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// ListMyDrafts — GET /api/me/expert/drafts
//
// Drafts + scheduled rows authored by the caller. Drives the studio
// "Drafts" tab.
func (h *SocialHandler) ListMyDrafts(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	posts, err := h.social.ListDraftsByAuthor(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if posts == nil {
		posts = []*models.Post{}
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

// DeleteMyDraft — DELETE /api/me/expert/drafts/:id
//
// Permanent delete. Author-only. Reuses the existing DeleteExpertPost
// repo method (which DELETEs unconditionally for target_type='expert')
// after a draft+author check so a stray DELETE can't kill a published
// post via this endpoint.
func (h *SocialHandler) DeleteMyDraft(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	existing, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "draft not found"})
		return
	}
	if existing.AuthorID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your draft"})
		return
	}
	if existing.Status == models.PostStatusPublished {
		c.JSON(http.StatusConflict, gin.H{
			"error": "post is published — use DELETE /experts/:id/posts/:postId",
		})
		return
	}
	if err := h.social.DeleteExpertPost(postID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

// ListPostHistory — GET /api/posts/:id/history
//
// Returns every snapshot in post_versions for this post, newest-first.
// Owner + admin only. Anyone else gets 403 (we don't 404 — the post
// exists, the caller just doesn't have permission to see edit history).
func (h *SocialHandler) ListPostHistory(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	post, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if post == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	isOwner := post.AuthorID == userID
	isAdmin := false
	if h.users != nil {
		if u, _ := h.users.GetByID(userID); u != nil && u.Role == "ADMIN" {
			isAdmin = true
		}
	}
	if !isOwner && !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "history is owner-only"})
		return
	}
	rows, err := h.social.ListPostVersions(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"versions": rows})
}

// AddPostAttachment — POST /api/me/posts/:id/attachments
//
// Body: { "url": "/uploads/images/...", "sortOrder": 0 }
//
// Caller MUST be the post's author (or admin). Caps at 5 attachments
// per post — 6th attempt returns 409. URL must be a /uploads/ path or
// http(s) URL (light validation; the upload endpoint already gated the
// content type).
const maxInlineAttachmentsPerPost = 5

func (h *SocialHandler) AddPostAttachment(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	post, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if post == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	if post.AuthorID != userID {
		// Admin can also attach for moderation? Conservative: NO —
		// admins editing inline content silently would be a
		// credibility issue (same rule as UpdateExpertPost).
		c.JSON(http.StatusForbidden, gin.H{"error": "not your post"})
		return
	}
	var body struct {
		URL       string `json:"url"`
		SortOrder int    `json:"sortOrder"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.URL = strings.TrimSpace(body.URL)
	if body.URL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "url required"})
		return
	}
	if !strings.HasPrefix(body.URL, "/uploads/") &&
		!strings.HasPrefix(body.URL, "http://") &&
		!strings.HasPrefix(body.URL, "https://") {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "url must be a /uploads/ path or http(s) URL",
		})
		return
	}
	count, err := h.social.CountPostAttachments(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if count >= maxInlineAttachmentsPerPost {
		c.JSON(http.StatusConflict, gin.H{
			"error": "max 5 attachments per post",
		})
		return
	}
	a, err := h.social.AddPostAttachment(postID, body.URL, body.SortOrder)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, a)
}

// DeletePostAttachment — DELETE /api/me/posts/:id/attachments/:aid
//
// Author-only. Returns 404 when the row doesn't exist or doesn't belong
// to this post.
func (h *SocialHandler) DeletePostAttachment(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	attachmentID, err := strconv.ParseInt(c.Param("aid"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid attachment id"})
		return
	}
	post, err := h.social.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if post == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	if post.AuthorID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not your post"})
		return
	}
	if err := h.social.DeletePostAttachment(postID, attachmentID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "attachment not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

// =============================================================================
// Step-19 (mig 0019, items 2.13–2.18) — community metadata + discovery.
//
// Owner-or-admin flows:
//   * PATCH /communities/:id          → edit description / rules / cover /
//                                       isPublic / category / name / tagline
//   * PUT   /communities/:id/tags     → replace tag set
//   * POST  /communities/:id/cover    → multipart upload, returns coverUrl
//
// Public flow:
//   * GET   /communities/search       → discovery with q / category / tag /
//                                       limit. Public (no auth) returns only
//                                       is_public=true; auth'd returns all.
// =============================================================================

// requireCommunityOwnerOrAdmin returns (callerUserID, ownerID) when the
// caller is allowed to mutate the community's metadata, or writes the
// appropriate HTTP error and returns (0, 0).
//
// Allowed:
//   * caller is the primary owner (communities.owner_id), OR
//   * caller is a co-owner (community_owners row, mig 0032), OR
//   * caller has role == ADMIN.
//
// Co-owners are full peers of the primary owner for content +
// moderation actions — that's the whole point of the feature. The
// ONLY thing they can't do is invite/remove other co-owners or
// transfer ownership; those routes use h.coOwners.requirePrimaryOwner
// directly instead of this helper.
func (h *SocialHandler) requireCommunityOwnerOrAdmin(
	c *gin.Context, communityID string,
) (callerID, ownerID int64) {
	uid, _ := c.Get("user_id")
	cid, _ := uid.(int64)
	if cid == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return 0, 0
	}
	owner, err := h.social.CommunityOwnerID(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return 0, 0
	}
	if owner == cid {
		return cid, owner
	}
	// Co-owner override (mig 0032). Cheap point query; only runs
	// when the caller isn't already the primary owner.
	if h.coOwners != nil {
		if ok, _ := h.coOwners.IsCoOwner(communityID, cid); ok {
			return cid, owner
		}
	}
	// Admin override — same shape as the rest of the codebase.
	if h.users != nil {
		if u, _ := h.users.GetByID(cid); u != nil && u.Role == "ADMIN" {
			return cid, owner
		}
	}
	c.JSON(http.StatusForbidden, gin.H{
		"error": "only the community owner or an admin can edit",
	})
	return 0, 0
}

// PATCH /api/communities/:id
//
// Owner-or-admin only. Body fields are all optional; tags is a full
// replace (pass `[]` to clear). Returns the updated community shape so
// the client can patch its local copy without a follow-up GET.
//
// Validation:
//   * name              3..60 chars when provided
//   * tagline           ≤ 200 chars
//   * description       ≤ 4000 chars
//   * rules             ≤ 4000 chars
//   * category          ≤ 40 chars
//   * tags              ≤ 10 entries, each ≤ 30 chars
func (h *SocialHandler) UpdateCommunity(c *gin.Context) {
	communityID := c.Param("id")
	if _, _ = h.requireCommunityOwnerOrAdmin(c, communityID); c.Writer.Written() {
		return
	}
	var body struct {
		Name        *string   `json:"name"`
		Tagline     *string   `json:"tagline"`
		Description *string   `json:"description"`
		Rules       *string   `json:"rules"`
		CoverURL    *string   `json:"coverUrl"`
		// AvatarURL (mig 0028) — square logo for the small avatar tile.
		// Same validation + null-vs-empty-vs-set semantics as CoverURL.
		AvatarURL   *string   `json:"avatarUrl"`
		IsPublic    *bool     `json:"isPublic"`
		Category    *string   `json:"category"`
		Tags        *[]string `json:"tags"`
		// Step-23 — pricing. All three independently optional.
		JoinPriceMonthlyCents *int    `json:"joinPriceMonthlyCents"`
		JoinPriceYearlyCents  *int    `json:"joinPriceYearlyCents"`
		PriceCurrency         *string `json:"priceCurrency"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	upd := repositories.CommunityMetadataUpdate{}
	if body.Name != nil {
		s := strings.TrimSpace(*body.Name)
		if len(s) < 3 || len(s) > 60 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name must be 3..60 chars"})
			return
		}
		upd.Name = &s
	}
	if body.Tagline != nil {
		s := strings.TrimSpace(*body.Tagline)
		if len(s) > 200 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "tagline ≤ 200 chars"})
			return
		}
		upd.Tagline = &s
	}
	if body.Description != nil {
		s := strings.TrimSpace(*body.Description)
		if len(s) > 4000 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "description ≤ 4000 chars"})
			return
		}
		upd.Description = &s
	}
	if body.Rules != nil {
		s := strings.TrimSpace(*body.Rules)
		if len(s) > 4000 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "rules ≤ 4000 chars"})
			return
		}
		upd.Rules = &s
	}
	if body.CoverURL != nil {
		s := strings.TrimSpace(*body.CoverURL)
		// Light sanity — must be a relative /uploads/ path or a full URL.
		// Empty string clears the cover.
		if s != "" && !strings.HasPrefix(s, "/uploads/") &&
			!strings.HasPrefix(s, "http://") && !strings.HasPrefix(s, "https://") {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "coverUrl must be a /uploads/ path or http(s) URL",
			})
			return
		}
		upd.CoverURL = &s
	}
	if body.AvatarURL != nil {
		s := strings.TrimSpace(*body.AvatarURL)
		// Same shape check as coverUrl — accept relative /uploads/ paths
		// or absolute http(s) URLs. Empty string clears the avatar.
		if s != "" && !strings.HasPrefix(s, "/uploads/") &&
			!strings.HasPrefix(s, "http://") && !strings.HasPrefix(s, "https://") {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "avatarUrl must be a /uploads/ path or http(s) URL",
			})
			return
		}
		upd.AvatarURL = &s
	}
	if body.IsPublic != nil {
		upd.IsPublic = body.IsPublic
	}
	if body.Category != nil {
		s := strings.TrimSpace(*body.Category)
		if len(s) > 40 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "category ≤ 40 chars"})
			return
		}
		upd.Category = &s
	}
	// Step-23 — pricing validation. Both prices must be non-negative
	// and ≤ $100,000 (10_000_000 cents) — generous ceiling that
	// catches keypad typos. Currency lowercased + length-checked.
	if body.JoinPriceMonthlyCents != nil {
		if *body.JoinPriceMonthlyCents < 0 || *body.JoinPriceMonthlyCents > 10_000_000 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "monthly price must be 0..10000000 cents",
			})
			return
		}
		upd.JoinPriceMonthlyCents = body.JoinPriceMonthlyCents
	}
	if body.JoinPriceYearlyCents != nil {
		if *body.JoinPriceYearlyCents < 0 || *body.JoinPriceYearlyCents > 10_000_000 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "yearly price must be 0..10000000 cents",
			})
			return
		}
		upd.JoinPriceYearlyCents = body.JoinPriceYearlyCents
	}
	if body.PriceCurrency != nil {
		s := strings.ToLower(strings.TrimSpace(*body.PriceCurrency))
		if len(s) < 2 || len(s) > 8 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "priceCurrency must be 2..8 chars (e.g. usd, iqd)",
			})
			return
		}
		upd.PriceCurrency = &s
	}

	// Step-23 follow-up — track whether this PATCH flips free → paid
	// so we can broadcast a member-changed event after the kick. The
	// repo handles the actual DELETE in a transaction; we just need
	// to know if it ran so we can fan out a realtime patch.
	willTransition := false
	if body.JoinPriceMonthlyCents != nil || body.JoinPriceYearlyCents != nil {
		// Snapshot BEFORE the update — match the repo's wasFree check.
		if cur, _ := h.social.GetCommunity(communityID); cur != nil {
			beforeFree := cur.JoinPriceMonthlyCents <= 0 &&
				cur.JoinPriceYearlyCents <= 0
			afterPaid := false
			if body.JoinPriceMonthlyCents != nil && *body.JoinPriceMonthlyCents > 0 {
				afterPaid = true
			}
			if body.JoinPriceYearlyCents != nil && *body.JoinPriceYearlyCents > 0 {
				afterPaid = true
			}
			willTransition = beforeFree && afterPaid
		}
	}

	if err := h.social.UpdateCommunityMetadata(communityID, upd); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "community not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Broadcast member count change so connected clients refresh their
	// joined-list badges (most members were just kicked).
	if willTransition {
		h.broadcastMemberChanged(communityID)
	}

	if body.Tags != nil {
		// Validate before writing — keep the metadata + tag mutations in
		// the same logical transaction conceptually, even though they're
		// two SQL operations.
		clean := make([]string, 0, len(*body.Tags))
		for _, t := range *body.Tags {
			t = strings.ToLower(strings.TrimSpace(t))
			if t == "" {
				continue
			}
			if len(t) > 30 {
				c.JSON(http.StatusBadRequest, gin.H{
					"error": "each tag must be ≤ 30 chars",
				})
				return
			}
			clean = append(clean, t)
		}
		if len(clean) > 10 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "max 10 tags per community",
			})
			return
		}
		if err := h.social.ReplaceCommunityTags(communityID, clean); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	updated, err := h.social.GetCommunity(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// PUT /api/communities/:id/tags
//
// Owner-or-admin only. Body: { "tags": ["halal", "etf", ...] }.
// Replaces the entire tag set for the community. Same validation as
// UpdateCommunity's tag handling. Returns the new tag slice.
func (h *SocialHandler) ReplaceCommunityTags(c *gin.Context) {
	communityID := c.Param("id")
	if _, _ = h.requireCommunityOwnerOrAdmin(c, communityID); c.Writer.Written() {
		return
	}
	var body struct {
		Tags []string `json:"tags"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	clean := make([]string, 0, len(body.Tags))
	for _, t := range body.Tags {
		t = strings.ToLower(strings.TrimSpace(t))
		if t == "" {
			continue
		}
		if len(t) > 30 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "each tag must be ≤ 30 chars",
			})
			return
		}
		clean = append(clean, t)
	}
	if len(clean) > 10 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "max 10 tags per community"})
		return
	}
	if err := h.social.ReplaceCommunityTags(communityID, clean); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"tags": clean})
}

// GET /api/communities/search
//
// Public — auth optional. Returns communities matching the filter.
// Logged-out callers see only is_public=true rows; logged-in callers
// see all so they can discover private communities they could request
// to join. Compose stays members-only either way.
//
// Query params:
//   * q          — free-text, ILIKE'd against name + tagline + description + category
//   * category   — exact match
//   * tag        — exact-match against community_tags.tag
//   * limit      — default 20, max 100
func (h *SocialHandler) SearchCommunities(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	onlyPublic := userID == 0
	limit, _ := strconv.Atoi(c.Query("limit"))
	rows, err := h.social.SearchCommunities(repositories.CommunitySearchFilter{
		Query:      strings.TrimSpace(c.Query("q")),
		Category:   strings.TrimSpace(c.Query("category")),
		Tag:        strings.TrimSpace(c.Query("tag")),
		Limit:      limit,
		OnlyPublic: onlyPublic,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"communities": rows})
}

// GET /api/communities/categories
//
// Predefined category list. Returned to mobile so the discovery screen
// can render a chip strip without hard-coding the taxonomy on the
// client. Static slice — admin-managed via code (no admin UI yet for
// adding categories; intentionally narrow taxonomy keeps the chip
// strip focused).
func (h *SocialHandler) ListCommunityCategories(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"categories": communityCategories,
	})
}

// communityCategories — predefined category taxonomy. Order shown to
// the user. Lower-cased server-side; the mobile UI title-cases for
// display.
var communityCategories = []string{
	"general",
	"tech",
	"finance",
	"halal",
	"energy",
	"crypto",
	"realestate",
	"healthcare",
	"consumer",
	"industrial",
	"emerging",
	"etf",
}

// =============================================================================
// Admin pricing — PATCH /api/admin/experts/:expertId/pricing
// =============================================================================

// AdminSetExpertPricingRequest — body shape for the pricing edit.
//
// Both fields are in CENTS (USD). Frontend sends e.g. monthlyCents=1500
// for $15.00/mo. We validate non-negative + an upper bound so a typo
// can't price an expert into the millions.
type AdminSetExpertPricingRequest struct {
	MonthlyCents int `json:"monthlyCents" binding:"min=0,max=1000000"`
	YearlyCents  int `json:"yearlyCents"  binding:"min=0,max=10000000"`
}

// AdminSetExpertPricing — PATCH /api/admin/experts/:expertId/pricing.
//
// The admin Experts page hits this when the operator edits a row's
// monthly / yearly prices. Writes are auditable (EXPERT_PRICING_UPDATED
// event with before/after metadata). Currency is locked to USD by
// product decision (UNMU is global-but-USD for v1).
func (h *SocialHandler) AdminSetExpertPricing(c *gin.Context) {
	expertID := strings.TrimSpace(c.Param("expertId"))
	if expertID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "expertId is required"})
		return
	}

	// Look up the existing row first so the audit metadata can carry
	// the before-prices for diff display.
	before, err := h.social.GetExpert(expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load expert"})
		return
	}
	if before == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "expert not found"})
		return
	}

	var req AdminSetExpertPricingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Defense in depth — the repo also rejects negatives, but we
	// duplicate the check here so the API returns a friendly 400
	// rather than a 500 from the DB layer.
	if req.MonthlyCents < 0 || req.YearlyCents < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "prices must be non-negative"})
		return
	}

	if err := h.social.SetExpertPricing(
		expertID, req.MonthlyCents, req.YearlyCents, "usd",
	); err != nil {
		log.Printf("[admin pricing] SetExpertPricing(%s): %v", expertID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update pricing"})
		return
	}

	// Audit — capture before/after so the audit-log detail page can
	// render a clear "$10 → $15 monthly, $96 → $144 yearly" diff.
	if h.audits != nil {
		uid, _ := c.Get("user_id")
		actorID, _ := uid.(int64)
		var actor *int64
		if actorID != 0 {
			actor = &actorID
		}
		targetID := expertID
		targetKind := "expert"
		_, _ = h.audits.Write(
			models.AuditExpertPricingUpdated,
			models.SeverityInfo,
			actor,
			&targetID,
			&targetKind,
			fmt.Sprintf(
				"Updated pricing for %s: $%.2f/mo, $%.2f/yr",
				before.Name,
				float64(req.MonthlyCents)/100,
				float64(req.YearlyCents)/100,
			),
			map[string]any{
				"expertId":         expertID,
				"expertName":       before.Name,
				"oldMonthlyCents":  before.MonthlyPriceCents,
				"oldYearlyCents":   before.YearlyPriceCents,
				"newMonthlyCents":  req.MonthlyCents,
				"newYearlyCents":   req.YearlyCents,
				"currency":         "usd",
			},
		)
	}

	// Return the updated row so the admin UI can refresh inline
	// without a second GET.
	updated, _ := h.social.GetExpert(expertID)
	c.JSON(http.StatusOK, gin.H{
		"ok":     true,
		"expert": updated,
	})
}

// =============================================================================
// helpers
// =============================================================================

func parseLimit(raw string, fallback int) int {
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return fallback
	}
	if n > 200 {
		return 200
	}
	return n
}

func nullStr(s string, ok bool) any {
	if !ok {
		return nil
	}
	return s
}
