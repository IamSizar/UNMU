package models

import (
	"database/sql"
	"encoding/json"
	"time"
)

// =============================================================================
// Social models — backed by tables created in
// `backend/migrations/0001_social_schema.sql`. See that file for the
// authoritative schema.
// =============================================================================

// Expert is a public profile for a verified expert.
//
// Step-B (mig 0024) added per-expert pricing — admins can charge a different
// monthly / yearly rate per expert. Both 0 → free expert (no paid tier).
type Expert struct {
	ID              string    `json:"id"`
	Name            string    `json:"name"`
	Expertise       string    `json:"expertise"`
	Bio             string    `json:"bio"`
	Tier            string    `json:"tier"` // always "expert" now
	SubscriberCount int       `json:"subscriberCount"`
	// Per-expert pricing (mig 0024). Currency is a 3-letter lowercase
	// ISO code; defaults to "usd" so the dashboard shows a "$" prefix.
	MonthlyPriceCents int    `json:"monthlyPriceCents"`
	YearlyPriceCents  int    `json:"yearlyPriceCents"`
	PriceCurrency    string `json:"priceCurrency"`
	CreatedAt       time.Time `json:"createdAt"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

// Community is a region-scoped discussion forum.
//
// Step-19 fields (mig 0019, items 2.13–2.18):
//   * Description / Rules — long-form metadata edited by the owner.
//   * CoverURL            — banner image at `<root>/uploads/images/...`.
//   * IsPublic            — when true, non-members can READ posts (compose
//                           still members-only). Default false → unchanged
//                           members-only behaviour.
//   * Category            — single string, predefined-list (drives the chip
//                           strip on the discovery screen).
//   * Tags                — many strings, free-form (drives search ranking).
type Community struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	RegionCode  string    `json:"regionCode"`
	Tagline     string    `json:"tagline"`
	Description string    `json:"description"`
	Rules       string    `json:"rules"`
	CoverURL    string    `json:"coverUrl,omitempty"`
	// AvatarURL (mig 0028) — square logo distinct from the wide cover.
	// Shown in compact community tiles + as the small overlapping avatar
	// on the community detail header. Null → mobile UI falls back to an
	// initials tile.
	AvatarURL   string    `json:"avatarUrl,omitempty"`
	IsPublic    bool      `json:"isPublic"`
	Category    string    `json:"category,omitempty"`
	Tags        []string  `json:"tags"`
	// Step-23 (mig 0022) — paid community membership pricing.
	// Both 0 → free community (existing default behaviour).
	JoinPriceMonthlyCents int    `json:"joinPriceMonthlyCents"`
	JoinPriceYearlyCents  int    `json:"joinPriceYearlyCents"`
	PriceCurrency         string `json:"priceCurrency"`
	MemberCount int       `json:"memberCount"`
	ActiveNow   int       `json:"activeNow"`
	// Sprint-C step 5 — owner user id, exposed in JSON so the mobile
	// hub can distinguish "owned" from "joined" communities and
	// render the gold-crown card variant. NULL in DB → nil in Go →
	// omitted from JSON.
	OwnerID *int64 `json:"ownerId,omitempty"`
	CreatedAt   time.Time `json:"createdAt"`
	UpdatedAt   time.Time `json:"updatedAt"`
}

// Post-type constants — what kind of expert content this row holds. Set on
// the new `post_type` column added in migration 0003.
const (
	PostTypeArticle = "article"
	PostTypeVideo   = "video"
	PostTypeReel    = "reel"
)

// Visibility constants — set on the new `visibility` column.
const (
	VisibilityPublic           = "public"
	VisibilitySubscribersOnly  = "subscribers_only"
)

// Post-status constants (mig 0020, item 4.15). 'published' is the default
// for legacy and freshly-published posts; 'draft' / 'scheduled' are new.
const (
	PostStatusDraft     = "draft"
	PostStatusScheduled = "scheduled"
	PostStatusPublished = "published"
)

// PostAttachment — one inline image attached to an article (mig 0020,
// item 4.18). Each post can carry up to 5; stored in the
// `post_attachments` table and embedded into the Post payload at read
// time so the client doesn't need a follow-up call.
type PostAttachment struct {
	ID        int64  `json:"id"`
	URL       string `json:"url"`
	SortOrder int    `json:"sortOrder"`
}

// Post is polymorphic — TargetType + (CommunityID OR ExpertID) determines
// which board it lives on. The DB has a CHECK constraint that enforces the
// XOR; we mirror it here for safety in handlers.
type Post struct {
	ID          int64     `json:"id"`
	TargetType  string    `json:"targetType"` // "community" | "expert"
	CommunityID *string   `json:"communityId,omitempty"`
	ExpertID    *string   `json:"expertId,omitempty"`
	AuthorID    int64     `json:"authorId"`
	AuthorName  string    `json:"authorName"`
	Title       *string   `json:"title,omitempty"`
	Body        string    `json:"body"`
	Ticker      *string   `json:"ticker,omitempty"`
	Tickers     []string  `json:"tickers"`
	Stance      *string   `json:"stance,omitempty"` // "BUY" | "HOLD" | "SELL"
	Upvotes     int       `json:"upvotes"`
	Likes       int       `json:"likes"`
	Comments    int       `json:"comments"`
	CreatedAt   time.Time `json:"createdAt"`

	// Step-2 additions — see migration 0003.
	PostType        string  `json:"postType"`         // "article" | "video" | "reel"
	MediaURL        *string `json:"mediaUrl,omitempty"`
	CoverURL        *string `json:"coverUrl,omitempty"`
	DurationSeconds *int    `json:"durationSeconds,omitempty"`
	Visibility      string  `json:"visibility"` // "public" | "subscribers_only"

	// VideoVariants — quality ladder for the in-app quality gear (mig
	// 0046). Map of label -> URL, e.g. {"auto":"<hls master.m3u8>",
	// "1080p":"...","720p":"...","480p":"..."}. nil until the transcode
	// worker fills it; the client falls back to MediaURL in that case.
	// Omitted from JSON when empty so existing single-file posts are
	// unchanged on the wire.
	VideoVariants map[string]string `json:"videoVariants,omitempty"`

	// IsLocked is set by handlers when serving a list to a non-subscriber.
	// When true, the body / mediaUrl have been stripped to a teaser.
	IsLocked bool `json:"isLocked"`

	// Liked is filled per-request by the list handlers using
	// PostInteractionsRepository.LikedPostsByUser so the heart icon shows
	// filled vs outline immediately, without the client doing N point
	// queries.
	Liked bool `json:"liked"`

	// Saved — same idea for the bookmark icon. Filled by SocialHandler.
	Saved bool `json:"saved"`

	// Step-5: owner can hide a post. Hidden rows are excluded from
	// non-owner lists; owner still sees them in their studio with a
	// "hidden" badge so they can un-hide.
	IsHidden bool `json:"isHidden"`

	// UpdatedAt mirrors the DB column — bumped by a trigger on every
	// UPDATE. Lets the UI surface "edited Xm ago" when ≠ CreatedAt.
	UpdatedAt time.Time `json:"updatedAt"`

	// Step-20 (mig 0020, item 4.15) — drafts + scheduling.
	//
	//   Status: 'draft' | 'scheduled' | 'published'
	//
	// PublishAt is non-nil only when Status == 'scheduled' — it's the
	// future timestamp at which the scheduled-publisher goroutine
	// flips the row to 'published'.
	Status    string     `json:"status"`
	PublishAt *time.Time `json:"publishAt,omitempty"`

	// Step-20 (mig 0020, item 4.18) — inline image attachments.
	// Filled lazily by the read paths via a follow-up query keyed off
	// the post id. Always non-nil after enrichment so the JSON shape
	// is stable; empty array when there are no attachments.
	Attachments []PostAttachment `json:"attachments"`

	// Source-attribution metadata — denormalized into every post
	// row at query time so the mobile UI can render a "from <X>"
	// badge without a follow-up call. Exactly one of the two
	// pairs is populated, mirroring the targetType discriminator:
	//
	//   targetType="community" → CommunityName + CommunityRegionCode set
	//   targetType="expert"    → ExpertName set (the expert's display name,
	//                            distinct from AuthorName which is the
	//                            posting user's name — usually identical
	//                            for expert posts but not for cross-posts).
	//
	// All four fields are omitted from JSON when empty so the
	// payload stays clean for clients that don't render them.
	CommunityName       string `json:"communityName,omitempty"`
	CommunityRegionCode string `json:"communityRegionCode,omitempty"`
	ExpertName          string `json:"expertName,omitempty"`
}

// scanPost is a small helper that bridges nullable SQL columns into our
// Post struct. Callers pass an *sql.Row or *sql.Rows already pointing at the
// correct column order — defined by the `postCols` constant in
// `repositories/social.go`. The trailing two columns (status, publish_at)
// were added in mig 0020 for drafts + scheduling.
//
// Returns the populated Post. Tickers are stored as JSONB in Postgres and
// scanned into []byte first, then unmarshalled.
type postRowScanner interface {
	Scan(dest ...any) error
}

func ScanPost(s postRowScanner) (*Post, error) {
	var p Post
	var (
		communityID sql.NullString
		expertID    sql.NullString
		title       sql.NullString
		ticker      sql.NullString
		stance      sql.NullString
		tickersRaw  []byte
		mediaURL    sql.NullString
		coverURL    sql.NullString
		duration    sql.NullInt32
		publishAt   sql.NullTime
		variantsRaw []byte
	)
	if err := s.Scan(
		&p.ID, &p.TargetType, &communityID, &expertID, &p.AuthorID, &p.AuthorName,
		&title, &p.Body, &ticker, &tickersRaw, &stance,
		&p.Upvotes, &p.Likes, &p.Comments, &p.CreatedAt,
		&p.PostType, &mediaURL, &coverURL, &duration, &p.Visibility,
		&p.IsHidden, &p.UpdatedAt,
		&p.Status, &publishAt, &variantsRaw,
	); err != nil {
		return nil, err
	}
	if len(variantsRaw) > 0 {
		_ = json.Unmarshal(variantsRaw, &p.VideoVariants)
	}
	if publishAt.Valid {
		p.PublishAt = &publishAt.Time
	}
	if p.Attachments == nil {
		p.Attachments = []PostAttachment{}
	}
	if communityID.Valid {
		p.CommunityID = &communityID.String
	}
	if expertID.Valid {
		p.ExpertID = &expertID.String
	}
	if title.Valid {
		p.Title = &title.String
	}
	if ticker.Valid {
		p.Ticker = &ticker.String
	}
	if stance.Valid {
		p.Stance = &stance.String
	}
	if mediaURL.Valid {
		p.MediaURL = &mediaURL.String
	}
	if coverURL.Valid {
		p.CoverURL = &coverURL.String
	}
	if duration.Valid {
		v := int(duration.Int32)
		p.DurationSeconds = &v
	}
	if len(tickersRaw) > 0 {
		_ = json.Unmarshal(tickersRaw, &p.Tickers)
	}
	if p.Tickers == nil {
		p.Tickers = []string{}
	}
	return &p, nil
}

// LockTeaser strips the body, media URL, and tickers off a post so a
// non-subscriber receives only the public-safe metadata. Sets IsLocked = true
// so the client knows to render a paywall card.
func (p *Post) LockTeaser() {
	p.Body = ""
	p.MediaURL = nil
	p.VideoVariants = nil
	p.Tickers = []string{}
	p.IsLocked = true
}
