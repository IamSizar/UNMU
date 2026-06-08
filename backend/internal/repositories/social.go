package repositories

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"halalstocks/internal/models"
	"strings"
	"time"

	"github.com/lib/pq"
)

// MediaURLResolver is the narrow interface repos use to refresh a stored
// media URL into a presigned S3 URL at read time. Declaring it here
// (rather than importing `services`) keeps the `repositories → services`
// import path one-way and avoids the cycle that comes with
// `services/community_subscription_expirer.go` importing this package.
//
// *services.S3Storage satisfies this with its `MediaURL(string) string`
// method — main.go wires it up via SetS3Storage on each repo.
type MediaURLResolver interface {
	MediaURL(value string) string
}

// SocialRepository owns reads + writes for experts, communities, posts, and
// subscriptions. All queries scope by the relevant join key so handlers can
// stay thin.
//
// `s3` is optional — when non-nil, every read path rewrites media URL
// columns (`media_url`, `cover_url`, `avatar_url`, post-attachment `url`)
// through MediaURLResolver.MediaURL so the bytes the client gets are
// always fronted by a freshly-signed URL. This sidesteps the 7-day SigV4
// expiry: even URLs the DB has held for months still play.
//
// When `s3 == nil` the repo behaves identically to v1 (returns whatever
// is in the DB), so dev machines without AWS credentials keep working.
type SocialRepository struct {
	db *sql.DB
	s3 MediaURLResolver
}

func NewSocialRepository(db *sql.DB) *SocialRepository {
	return &SocialRepository{db: db}
}

// SetS3Storage wires the media-URL resolver post-construction so existing
// call sites don't have to change. Pass the same *S3Storage the upload
// handler uses. Nil disables resolution and the repo falls back to v1
// behavior (returns the raw DB value).
func (r *SocialRepository) SetS3Storage(s3 MediaURLResolver) {
	r.s3 = s3
}

// resolveURL is the single chokepoint for re-signing a stored media URL
// before it leaves the repo. Returns the input unchanged when S3 isn't
// wired so it's safe to call unconditionally.
func (r *SocialRepository) resolveURL(value string) string {
	if r.s3 == nil {
		return value
	}
	return r.s3.MediaURL(value)
}

// SignMediaURL re-signs a single stored media value (e.g. a user's
// avatar_url) for a read response — the same fresh-presign treatment post and
// community media get. Exported so handlers in other packages can sign a
// one-off value; signing the stored (possibly already-expired) URL works
// because MediaURL extracts the object key and presigns anew. Safe when S3
// isn't wired (returns the input unchanged).
func (r *SocialRepository) SignMediaURL(value string) string {
	return r.resolveURL(value)
}

// resolvePostURLs walks a batch of posts and rewrites their MediaURL and
// CoverURL through [resolveURL]. Called at the same enrichment seam as
// [attachAttachmentsBatch] so every Post-returning function gets the fix
// in one line.
func (r *SocialRepository) resolvePostURLs(posts []*models.Post) {
	if r.s3 == nil {
		return
	}
	for _, p := range posts {
		if p == nil {
			continue
		}
		if p.MediaURL != nil && *p.MediaURL != "" {
			v := r.s3.MediaURL(*p.MediaURL)
			p.MediaURL = &v
		}
		if p.CoverURL != nil && *p.CoverURL != "" {
			v := r.s3.MediaURL(*p.CoverURL)
			p.CoverURL = &v
		}
		// Quality variants (mig 0046) are stored as bare S3 keys by the
		// transcode worker; sign each one fresh on read, same as MediaURL.
		for label, val := range p.VideoVariants {
			if val != "" {
				p.VideoVariants[label] = r.s3.MediaURL(val)
			}
		}
		// Post-attachment URLs (the gallery of extra images stitched on
		// reels by attachAttachmentsBatch) get the same treatment so
		// none of them rot.
		for i := range p.Attachments {
			if p.Attachments[i].URL != "" {
				p.Attachments[i].URL = r.s3.MediaURL(p.Attachments[i].URL)
			}
		}
	}
}

// resolveCommunityURLs walks a batch (or a single one as a length-1
// slice) and rewrites CoverURL + AvatarURL through resolveURL. Same
// pattern as resolvePostURLs; CommunityCard rows used in admin lists
// share the same URL fields so they go through here too.
func (r *SocialRepository) resolveCommunityURLs(list []*models.Community) {
	if r.s3 == nil {
		return
	}
	for _, c := range list {
		if c == nil {
			continue
		}
		if c.CoverURL != "" {
			c.CoverURL = r.s3.MediaURL(c.CoverURL)
		}
		if c.AvatarURL != "" {
			c.AvatarURL = r.s3.MediaURL(c.AvatarURL)
		}
	}
}

// -----------------------------------------------------------------------------
// Experts
// -----------------------------------------------------------------------------

// expertCols — canonical column list including the per-expert pricing
// columns added in mig 0024. All Expert reads share this so the scan
// function can stay private to this file.
const expertCols = `
	id, name, expertise, bio, tier, subscriber_count,
	monthly_price_cents, yearly_price_cents, price_currency,
	created_at, updated_at
`

// scanExpert reads columns in the expertCols order.
func scanExpert(s interface{ Scan(...any) error }, e *models.Expert) error {
	return s.Scan(
		&e.ID, &e.Name, &e.Expertise, &e.Bio, &e.Tier, &e.SubscriberCount,
		&e.MonthlyPriceCents, &e.YearlyPriceCents, &e.PriceCurrency,
		&e.CreatedAt, &e.UpdatedAt,
	)
}

// ListExperts powers the public "Top experts this week" leaderboard.
//
// We filter out empty / placeholder experts: an expert only appears when
//   * at least one subscriber, OR
//   * at least one published (non-deleted) post, OR
//   * linked to an active user row (i.e. promoted via UpdateRole and
//     hasn't been deleted), so legitimate fresh experts still surface.
//
// Without this filter, every stub experts row auto-created by
// UpdateRole or a leftover orphan from old test data shows up at "0
// subscribers" and pollutes the leaderboard. The MENA tester (zaid)
// flagged this when "ddsa" / "dada" / "Proposer" started appearing
// alongside their real expert row.
//
// Ranking unchanged — subscriber_count DESC, then name ASC for stable
// ordering when many experts share the same count (common at launch).
func (r *SocialRepository) ListExperts() ([]models.Expert, error) {
	rows, err := r.db.Query(`
		SELECT ` + expertCols + `
		FROM experts e
		WHERE
		    e.subscriber_count > 0
		 OR EXISTS (
		      SELECT 1 FROM posts p
		       WHERE p.expert_id = e.id AND p.is_hidden = false
		 )
		 OR EXISTS (
		      SELECT 1 FROM users u
		       WHERE u.expert_id = e.id
		 )
		ORDER BY e.subscriber_count DESC, e.name ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []models.Expert
	for rows.Next() {
		var e models.Expert
		if err := scanExpert(rows, &e); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (r *SocialRepository) GetExpert(id string) (*models.Expert, error) {
	row := r.db.QueryRow(`SELECT `+expertCols+` FROM experts WHERE id = $1`, id)
	var e models.Expert
	if err := scanExpert(row, &e); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &e, nil
}

// SetExpertPricing — admin-only update. Used by the admin Subscriptions
// page to set per-expert prices. priceCurrency is normalised to lower
// case (DB convention, mirrors mig 0024 default).
func (r *SocialRepository) SetExpertPricing(
	expertID string,
	monthlyCents, yearlyCents int,
	currency string,
) error {
	if monthlyCents < 0 || yearlyCents < 0 {
		return fmt.Errorf("prices must be non-negative")
	}
	currency = strings.ToLower(strings.TrimSpace(currency))
	if currency == "" {
		currency = "usd"
	}
	res, err := r.db.Exec(`
		UPDATE experts
		   SET monthly_price_cents = $1,
		       yearly_price_cents  = $2,
		       price_currency      = $3,
		       updated_at          = NOW()
		 WHERE id = $4
	`, monthlyCents, yearlyCents, currency, expertID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// -----------------------------------------------------------------------------
// Communities
// -----------------------------------------------------------------------------

// communityCols is the canonical SELECT list for a Community row.
// Centralised so every read path (list / get / search) stays in lockstep
// with scanCommunityRow's column order. Step-23 (mig 0022) added the
// trailing pricing trio.
//
// NOTE: `region_code` is wrapped in COALESCE because migration 0027 made
// the column nullable (for the "No specific region" path in the expert
// proposal flow). Without the COALESCE, scanning a NULL region into the
// `string` model field would fail with:
//
//   sql: Scan error on column index 2, name "region_code":
//   converting NULL to string is unsupported
//
// An empty string at the Go layer is fine — the mobile UI already
// treats `regionCode == ''` as "no region".
const communityCols = `
	c.id, c.name, COALESCE(c.region_code, ''), c.tagline,
	COALESCE(c.description, ''), COALESCE(c.rules, ''),
	c.cover_url, c.avatar_url, c.is_public, c.category,
	(SELECT COUNT(*) FROM community_members m WHERE m.community_id = c.id),
	c.active_now, c.created_at, c.updated_at,
	c.join_price_monthly_cents, c.join_price_yearly_cents, c.price_currency,
	c.owner_id
`

// scanCommunityRow consumes a single row in `communityCols` order, plus
// patches the Tags slice on top via a follow-up query (caller responsibility).
// Centralised so list / get / search can share one scan body.
func scanCommunityRow(s interface{ Scan(...any) error }) (*models.Community, error) {
	var c models.Community
	var coverURL sql.NullString
	var avatarURL sql.NullString
	var category sql.NullString
	var ownerID sql.NullInt64
	if err := s.Scan(
		&c.ID, &c.Name, &c.RegionCode, &c.Tagline,
		&c.Description, &c.Rules,
		&coverURL, &avatarURL, &c.IsPublic, &category,
		&c.MemberCount, &c.ActiveNow, &c.CreatedAt, &c.UpdatedAt,
		&c.JoinPriceMonthlyCents, &c.JoinPriceYearlyCents, &c.PriceCurrency,
		&ownerID,
	); err != nil {
		return nil, err
	}
	if coverURL.Valid {
		c.CoverURL = coverURL.String
	}
	if avatarURL.Valid {
		c.AvatarURL = avatarURL.String
	}
	if category.Valid {
		c.Category = category.String
	}
	if ownerID.Valid {
		v := ownerID.Int64
		c.OwnerID = &v
	}
	c.Tags = []string{}
	return &c, nil
}

// attachTags fills [Tags] on every community in [list] via one batched
// SELECT — avoids N+1. Best-effort; on error we leave Tags as the empty
// slices already set by scanCommunityRow.
func (r *SocialRepository) attachTags(list []*models.Community) {
	if len(list) == 0 {
		return
	}
	ids := make([]string, 0, len(list))
	for _, c := range list {
		ids = append(ids, c.ID)
	}
	rows, err := r.db.Query(
		`SELECT community_id, tag FROM community_tags WHERE community_id = ANY($1) ORDER BY tag`,
		pq.Array(ids),
	)
	if err != nil {
		return
	}
	defer rows.Close()
	idx := make(map[string]*models.Community, len(list))
	for _, c := range list {
		idx[c.ID] = c
	}
	for rows.Next() {
		var cid, tag string
		if err := rows.Scan(&cid, &tag); err != nil {
			continue
		}
		if c, ok := idx[cid]; ok {
			c.Tags = append(c.Tags, tag)
		}
	}
}

func (r *SocialRepository) ListCommunities() ([]models.Community, error) {
	rows, err := r.db.Query(`
		SELECT ` + communityCols + `
		FROM communities c
		ORDER BY (SELECT COUNT(*) FROM community_members m WHERE m.community_id = c.id) DESC, c.id ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ptrs []*models.Community
	for rows.Next() {
		c, err := scanCommunityRow(rows)
		if err != nil {
			return nil, err
		}
		ptrs = append(ptrs, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	r.attachTags(ptrs)
	r.resolveCommunityURLs(ptrs)
	out := make([]models.Community, 0, len(ptrs))
	for _, c := range ptrs {
		out = append(out, *c)
	}
	return out, nil
}

func (r *SocialRepository) GetCommunity(id string) (*models.Community, error) {
	row := r.db.QueryRow(`
		SELECT ` + communityCols + ` FROM communities c WHERE c.id = $1
	`, id)
	c, err := scanCommunityRow(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	r.resolveCommunityURLs([]*models.Community{c})
	r.attachTags([]*models.Community{c})
	return c, nil
}

// IsCommunityPublic returns whether [id] is publicly readable. Used by
// the post-list and single-post gates to decide whether to enforce
// membership for read operations. Compose stays members-only either way.
//
// A missing community returns (false, nil) — the upstream gates fall
// back to the "members-only" path which then 404s, the right behaviour
// for non-existent ids.
func (r *SocialRepository) IsCommunityPublic(id string) (bool, error) {
	var pub bool
	err := r.db.QueryRow(
		`SELECT is_public FROM communities WHERE id = $1`, id,
	).Scan(&pub)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return pub, nil
}

// CommunityMetadataUpdate — partial-update payload for the owner-only
// PATCH /communities/:id endpoint. nil fields are skipped. Mirrors the
// ExpertPostUpdate shape so handlers stay symmetrical.
type CommunityMetadataUpdate struct {
	Name        *string
	Tagline     *string
	Description *string
	Rules       *string
	CoverURL    *string
	// AvatarURL (mig 0028) — square logo distinct from the wide cover.
	// Same pointer-of-string pattern: nil = leave untouched, ""  = clear,
	// "<url>" = set.
	AvatarURL   *string
	IsPublic    *bool
	Category    *string
	// Step-23 (mig 0022) — paid community pricing. Owner can flip
	// any of the three independently. Setting both prices to 0 makes
	// the community free again.
	JoinPriceMonthlyCents *int
	JoinPriceYearlyCents  *int
	PriceCurrency         *string
}

// UpdateCommunityMetadata applies a partial patch to a community row.
// Returns sql.ErrNoRows when the id doesn't exist.
//
// Owner gating is the handler's responsibility — the repo is intentionally
// composable so the admin dashboard can call it without an owner check.
//
// Step-23 follow-up: when the caller flips a community from free → paid
// (either price was 0 and is now > 0), every member EXCEPT the owner is
// removed from `community_members` so the price gate actually kicks in.
// Existing free members would otherwise be grandfathered, which makes
// "set price to charge for access" a no-op for the existing user base.
//
// The kick runs in the same transaction as the column update so a
// half-state never reaches the DB.
func (r *SocialRepository) UpdateCommunityMetadata(
	id string, in CommunityMetadataUpdate,
) error {
	// Snapshot the BEFORE state so we can detect free → paid.
	var (
		beforeMonthly int
		beforeYearly  int
	)
	_ = r.db.QueryRow(
		`SELECT join_price_monthly_cents, join_price_yearly_cents
		   FROM communities WHERE id = $1`, id,
	).Scan(&beforeMonthly, &beforeYearly)
	wasFree := beforeMonthly <= 0 && beforeYearly <= 0
	willBePaid := false
	if in.JoinPriceMonthlyCents != nil && *in.JoinPriceMonthlyCents > 0 {
		willBePaid = true
	}
	if in.JoinPriceYearlyCents != nil && *in.JoinPriceYearlyCents > 0 {
		willBePaid = true
	}
	transitioning := wasFree && willBePaid

	sets := []string{}
	args := []any{}
	add := func(col string, v any) {
		args = append(args, v)
		sets = append(sets, col+" = $"+itoa(len(args)))
	}
	if in.Name != nil {
		add("name", *in.Name)
	}
	if in.Tagline != nil {
		add("tagline", *in.Tagline)
	}
	if in.Description != nil {
		add("description", *in.Description)
	}
	if in.Rules != nil {
		add("rules", *in.Rules)
	}
	if in.CoverURL != nil {
		// Empty string → NULL so the column stays clean for the
		// "no cover" UI fallback.
		if *in.CoverURL == "" {
			add("cover_url", nil)
		} else {
			add("cover_url", *in.CoverURL)
		}
	}
	if in.AvatarURL != nil {
		// Same empty-string → NULL pattern as cover_url. Mobile UI
		// renders the initials tile when the column is NULL.
		if *in.AvatarURL == "" {
			add("avatar_url", nil)
		} else {
			add("avatar_url", *in.AvatarURL)
		}
	}
	if in.IsPublic != nil {
		add("is_public", *in.IsPublic)
	}
	if in.Category != nil {
		if *in.Category == "" {
			add("category", nil)
		} else {
			add("category", *in.Category)
		}
	}
	if in.JoinPriceMonthlyCents != nil {
		add("join_price_monthly_cents", *in.JoinPriceMonthlyCents)
	}
	if in.JoinPriceYearlyCents != nil {
		add("join_price_yearly_cents", *in.JoinPriceYearlyCents)
	}
	if in.PriceCurrency != nil {
		add("price_currency", *in.PriceCurrency)
	}
	if len(sets) == 0 {
		return nil
	}
	sets = append(sets, "updated_at = NOW()")
	args = append(args, id)
	q := `UPDATE communities SET ` + strings.Join(sets, ", ") +
		` WHERE id = $` + itoa(len(args))

	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	res, err := tx.Exec(q, args...)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	// Step-23 follow-up: kick everyone except the owner when the
	// community just transitioned from free to paid. Without this,
	// pre-existing members keep access for free and the price gate
	// has no effect on the current user base.
	if transitioning {
		if _, err := tx.Exec(
			`DELETE FROM community_members
			  WHERE community_id = $1
			    AND user_id <> COALESCE(
			        (SELECT owner_id FROM communities WHERE id = $1),
			        -1
			    )`,
			id,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// ReplaceCommunityTags swaps the entire tag set for [communityID] in a
// single transaction. Tags are normalised lowercase on the way in and
// deduped — caller can pass dirty input.
//
// We delete-then-insert (vs an upsert dance) because tag sets are small
// (UI caps at ~10) and the simplicity is worth it.
func (r *SocialRepository) ReplaceCommunityTags(
	communityID string, tags []string,
) error {
	clean := make([]string, 0, len(tags))
	seen := map[string]bool{}
	for _, t := range tags {
		t = strings.ToLower(strings.TrimSpace(t))
		if t == "" || seen[t] {
			continue
		}
		seen[t] = true
		clean = append(clean, t)
	}
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(
		`DELETE FROM community_tags WHERE community_id = $1`, communityID,
	); err != nil {
		return err
	}
	for _, t := range clean {
		if _, err := tx.Exec(
			`INSERT INTO community_tags (community_id, tag) VALUES ($1, $2)
			 ON CONFLICT DO NOTHING`,
			communityID, t,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// CommunitySearchFilter — query / category / tag filters for the
// discovery screen. All fields optional.
type CommunitySearchFilter struct {
	Query    string // ILIKE / FT search across name+desc+tagline
	Category string // exact match on communities.category
	Tag      string // membership in community_tags
	Limit    int    // default 20, capped at 100
	OnlyPublic bool // true → drop is_public=false rows entirely
}

// SearchCommunities returns communities matching the filter. Public-only
// when [OnlyPublic] is set (used for logged-out callers); auth'd callers
// see private communities too so they can discover ones they could join.
//
// Sort: full-text rank when [Query] is set, otherwise member count desc.
func (r *SocialRepository) SearchCommunities(
	f CommunitySearchFilter,
) ([]*models.Community, error) {
	if f.Limit <= 0 || f.Limit > 100 {
		f.Limit = 20
	}
	q := `SELECT ` + communityCols + ` FROM communities c WHERE 1=1`
	args := []any{}
	if f.OnlyPublic {
		q += ` AND c.is_public = TRUE`
	}
	if f.Category != "" {
		args = append(args, f.Category)
		q += ` AND c.category = $` + itoa(len(args))
	}
	if f.Tag != "" {
		args = append(args, strings.ToLower(strings.TrimSpace(f.Tag)))
		q += ` AND EXISTS (SELECT 1 FROM community_tags t
		                    WHERE t.community_id = c.id AND t.tag = $` + itoa(len(args)) + `)`
	}
	if f.Query != "" {
		args = append(args, "%"+strings.ToLower(strings.TrimSpace(f.Query))+"%")
		idx := itoa(len(args))
		q += ` AND (LOWER(c.name) LIKE $` + idx + `
		         OR LOWER(c.tagline) LIKE $` + idx + `
		         OR LOWER(COALESCE(c.description, '')) LIKE $` + idx + `
		         OR LOWER(COALESCE(c.category, '')) LIKE $` + idx + `)`
	}
	q += ` ORDER BY (SELECT COUNT(*) FROM community_members m WHERE m.community_id = c.id) DESC, c.id ASC`
	args = append(args, f.Limit)
	q += ` LIMIT $` + itoa(len(args))

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*models.Community, 0, f.Limit)
	for rows.Next() {
		c, err := scanCommunityRow(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	r.attachTags(out)
	r.resolveCommunityURLs(out)
	return out, nil
}

func (r *SocialRepository) JoinCommunity(userID int64, communityID string) error {
	_, err := r.db.Exec(`
		INSERT INTO community_members(user_id, community_id)
		VALUES ($1,$2)
		ON CONFLICT DO NOTHING
	`, userID, communityID)
	return err
}

// LeaveCommunity removes a member row. Returns sql.ErrNoRows if the
// caller wasn't a member to begin with so the handler can surface a
// clean 404.
//
// We block the community owner from leaving their own community —
// without an ownership-transfer flow that would orphan the
// community. Owners must use the admin dashboard to delete or
// reassign instead.
func (r *SocialRepository) LeaveCommunity(userID int64, communityID string) error {
	// Owner guard — single SELECT returning the owner_id; cheap and
	// avoids an extra round-trip vs combining into the DELETE's
	// WHERE clause (we want a distinct error for the owner case).
	var ownerID sql.NullInt64
	if err := r.db.QueryRow(
		`SELECT owner_id FROM communities WHERE id = $1`,
		communityID,
	).Scan(&ownerID); err != nil {
		if err == sql.ErrNoRows {
			return sql.ErrNoRows
		}
		return err
	}
	if ownerID.Valid && ownerID.Int64 == userID {
		// Sentinel — handler maps this to a 409 Conflict with a
		// clear "owners can't leave" message.
		return errors.New("owner cannot leave community")
	}
	res, err := r.db.Exec(
		`DELETE FROM community_members
		  WHERE user_id = $1 AND community_id = $2`,
		userID, communityID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// IsMemberOfCommunity returns whether [userID] is a member of
// [communityID]. Used by the join/leave UI on mobile to decide
// which CTA to render, and to gate content-creation features.
// ListMemberIDs returns the user ids of every member of a community.
// Used to fan out content notifications (new post / poll) to members.
func (r *SocialRepository) ListMemberIDs(communityID string) ([]int64, error) {
	rows, err := r.db.Query(
		`SELECT user_id FROM community_members WHERE community_id = $1`,
		communityID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]int64, 0, 64)
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

func (r *SocialRepository) IsMemberOfCommunity(userID int64, communityID string) (bool, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT 1 FROM community_members
		  WHERE user_id = $1 AND community_id = $2 LIMIT 1`,
		userID, communityID,
	).Scan(&n)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// RemoveMember kicks [targetUserID] from [communityID]. Used by the
// owner-only "remove member" flow. Owners can't kick themselves
// (would orphan ownership) — caller must enforce that. Admins can
// kick anyone via the admin dashboard's parallel endpoint.
//
// Returns sql.ErrNoRows when the user wasn't a member to begin
// with so the handler can surface a clean 404.
func (r *SocialRepository) RemoveMember(
	communityID string, targetUserID int64,
) error {
	res, err := r.db.Exec(
		`DELETE FROM community_members
		  WHERE community_id = $1 AND user_id = $2`,
		communityID, targetUserID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// TransferOwnership flips a community's owner_id to [newOwnerID].
// Caller MUST verify in the handler that:
//
//   - the requester is the current owner,
//   - the new owner is a member of the community,
//   - the new owner is not the current owner.
//
// We don't enforce those here so this method stays composable
// (e.g. the admin dashboard can call it without an owner check).
func (r *SocialRepository) TransferOwnership(
	communityID string, newOwnerID int64,
) error {
	res, err := r.db.Exec(
		`UPDATE communities SET owner_id = $1, updated_at = NOW()
		  WHERE id = $2`,
		newOwnerID, communityID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// CommunityMemberCount returns the live aggregate count of members
// in [communityID]. Computed on demand from `community_members`
// rather than read from the stored `communities.member_count`
// column so it's always correct after a join/leave (the stored
// column is seeded but not auto-updated by triggers).
func (r *SocialRepository) CommunityMemberCount(communityID string) (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM community_members WHERE community_id = $1`,
		communityID,
	).Scan(&n)
	if err != nil {
		return 0, err
	}
	return n, nil
}

// ListCommunitiesForExpert returns every community the expert is a
// member of (and where they qualify as an expert via expert_id).
// Drives the "Communities" strip on the expert profile screen so a
// visitor can see which communities the expert participates in,
// owner-first then by member count.
//
// Returns the same Community shape as ListCommunities for code
// reuse on the client (a visitor's existing community card widgets
// can render this list without a new model).
func (r *SocialRepository) ListCommunitiesForExpert(
	expertID string,
) ([]*models.Community, error) {
	rows, err := r.db.Query(`
		SELECT `+communityCols+`
		  FROM community_members cm
		  JOIN users u       ON u.id = cm.user_id
		  JOIN communities c ON c.id = cm.community_id
		 WHERE u.expert_id = $1
		   AND u.role = 'EXPERT'
		 ORDER BY (c.owner_id = u.id) DESC,
		          (SELECT COUNT(*) FROM community_members m WHERE m.community_id = c.id) DESC,
		          c.id ASC`,
		expertID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*models.Community, 0)
	for rows.Next() {
		c, err := scanCommunityRow(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	r.attachTags(out)
	r.resolveCommunityURLs(out)
	return out, nil
}

// CommunityOwnerID returns the owner user id of a community (or 0
// when there's no owner). Cheap helper used by the membership check
// to mark the response with `owner: true` when it's the caller's
// own community.
func (r *SocialRepository) CommunityOwnerID(communityID string) (int64, error) {
	var ownerID sql.NullInt64
	err := r.db.QueryRow(
		`SELECT owner_id FROM communities WHERE id = $1`,
		communityID,
	).Scan(&ownerID)
	if err == sql.ErrNoRows {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	if !ownerID.Valid {
		return 0, nil
	}
	return ownerID.Int64, nil
}

// CommunityExpertSummary — one row in the "Experts in this
// community" panel rendered on the community detail screen. Carries
// just enough fields for the expert card + the Subscribe CTA.
type CommunityExpertSummary struct {
	UserID          int64  `json:"userId"`
	ExpertID        string `json:"expertId"`
	Name            string `json:"name"`
	Email           string `json:"email"`
	Bio             string `json:"bio"`
	Expertise       string `json:"expertise"`
	SubscriberCount int    `json:"subscriberCount"`
	IsOwner         bool   `json:"isOwner"`
}

// ListExpertsInCommunity returns every member of [communityID] whose
// users.role is 'EXPERT' AND who has an expert_id (a real expert
// profile). isOwner is true for the primary owner OR any co-owner
// (mig 0032) so the mobile UI stars co-owners the same way as the
// original owner.
//
// Subscriber count is aggregated inline so the client doesn't need
// a follow-up call per expert.
func (r *SocialRepository) ListExpertsInCommunity(
	communityID string,
) ([]*CommunityExpertSummary, error) {
	rows, err := r.db.Query(`
		SELECT u.id,
		       u.expert_id,
		       COALESCE(NULLIF(u.name, ''), u.email),
		       u.email,
		       COALESCE(e.bio, ''),
		       COALESCE(e.expertise, ''),
		       (
		         SELECT COUNT(*) FROM subscriptions s
		          WHERE s.expert_id = u.expert_id
		       ) AS subscriber_count,
		       (
		         c.owner_id = u.id
		         OR EXISTS (
		             SELECT 1 FROM community_owners co
		              WHERE co.community_id = cm.community_id
		                AND co.user_id      = u.id
		         )
		       ) AS is_owner
		  FROM community_members cm
		  JOIN users u            ON u.id = cm.user_id
		  JOIN communities c      ON c.id = cm.community_id
		  LEFT JOIN experts e     ON e.id = u.expert_id
		 WHERE cm.community_id = $1
		   AND u.role = 'EXPERT'
		   AND u.expert_id IS NOT NULL
		 ORDER BY is_owner DESC, subscriber_count DESC, u.id ASC`,
		communityID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*CommunityExpertSummary, 0)
	for rows.Next() {
		var s CommunityExpertSummary
		var expertID sql.NullString
		if err := rows.Scan(
			&s.UserID, &expertID, &s.Name, &s.Email,
			&s.Bio, &s.Expertise, &s.SubscriberCount, &s.IsOwner,
		); err != nil {
			return nil, err
		}
		if expertID.Valid {
			s.ExpertID = expertID.String
		}
		out = append(out, &s)
	}
	return out, rows.Err()
}

// -----------------------------------------------------------------------------
// Subscriptions
// -----------------------------------------------------------------------------

func (r *SocialRepository) IsSubscribed(userID int64, expertID string) (bool, error) {
	// Experts/scholars are implicitly subscribed to their own profile so they
	// can always read their own posts.
	row := r.db.QueryRow(`
		SELECT EXISTS(
		  SELECT 1 FROM users WHERE id = $1 AND expert_id = $2
		) OR EXISTS(
		  SELECT 1 FROM subscriptions WHERE user_id = $1 AND expert_id = $2
		)
	`, userID, expertID)
	var ok bool
	err := row.Scan(&ok)
	return ok, err
}

func (r *SocialRepository) Subscribe(userID int64, expertID string) error {
	// Insert; only bump the counter if the row was actually new (i.e. the
	// user wasn't already subscribed). RowsAffected == 1 → new subscription.
	res, err := r.db.Exec(`
		INSERT INTO subscriptions(user_id, expert_id) VALUES ($1,$2)
		ON CONFLICT DO NOTHING
	`, userID, expertID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return nil
	}
	_, err = r.db.Exec(`
		UPDATE experts SET subscriber_count = subscriber_count + 1
		WHERE id = $1
	`, expertID)
	return err
}

func (r *SocialRepository) Unsubscribe(userID int64, expertID string) error {
	res, err := r.db.Exec(`
		DELETE FROM subscriptions WHERE user_id = $1 AND expert_id = $2
	`, userID, expertID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		_, err = r.db.Exec(`
			UPDATE experts SET subscriber_count = GREATEST(subscriber_count - 1, 0)
			WHERE id = $1
		`, expertID)
	}
	return err
}

func (r *SocialRepository) ListSubscribedExpertIDs(userID int64) ([]string, error) {
	rows, err := r.db.Query(`
		SELECT expert_id FROM subscriptions WHERE user_id = $1
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// -----------------------------------------------------------------------------
// Posts
// -----------------------------------------------------------------------------

// EnrichPostsWithSource fills in CommunityName + CommunityRegionCode
// (for target=community posts) and ExpertName (for target=expert
// posts) on a slice of posts. Mobile renders a "from <X>" badge on
// reels / posts / videos; without this the client only has the raw
// id and would need a follow-up call per post.
//
// Implementation: two batched lookups, one per kind. Skipped when
// the slice is empty so callers can call this unconditionally.
//
// Best-effort — a failed lookup leaves the metadata fields empty
// and the client falls back to the bare id, which is still
// usable. We log nothing here; the read path stays warning-free.
func (r *SocialRepository) EnrichPostsWithSource(posts []*models.Post) error {
	if len(posts) == 0 {
		return nil
	}
	communityIDs := make([]string, 0)
	expertIDs := make([]string, 0)
	seenC := map[string]bool{}
	seenE := map[string]bool{}
	for _, p := range posts {
		if p.CommunityID != nil && !seenC[*p.CommunityID] {
			communityIDs = append(communityIDs, *p.CommunityID)
			seenC[*p.CommunityID] = true
		}
		if p.ExpertID != nil && !seenE[*p.ExpertID] {
			expertIDs = append(expertIDs, *p.ExpertID)
			seenE[*p.ExpertID] = true
		}
	}

	// Community lookup → name + region_code.
	communityMeta := map[string]struct {
		name       string
		regionCode string
	}{}
	if len(communityIDs) > 0 {
		// COALESCE the region_code → '' so the scan into a plain `string`
		// below doesn't trip on rows created via the no-region proposal
		// path (migration 0027 made the column nullable).
		rows, err := r.db.Query(
			`SELECT id, name, COALESCE(region_code, '')
			   FROM communities WHERE id = ANY($1)`,
			pq.Array(communityIDs),
		)
		if err != nil {
			return err
		}
		for rows.Next() {
			var id, name, region string
			if err := rows.Scan(&id, &name, &region); err != nil {
				rows.Close()
				return err
			}
			communityMeta[id] = struct {
				name       string
				regionCode string
			}{name, region}
		}
		rows.Close()
	}

	// Expert lookup → name. Bio/expertise are intentionally skipped
	// here; the badge only needs a display name.
	expertMeta := map[string]string{}
	if len(expertIDs) > 0 {
		rows, err := r.db.Query(
			`SELECT id, name FROM experts WHERE id = ANY($1)`,
			pq.Array(expertIDs),
		)
		if err != nil {
			return err
		}
		for rows.Next() {
			var id, name string
			if err := rows.Scan(&id, &name); err != nil {
				rows.Close()
				return err
			}
			expertMeta[id] = name
		}
		rows.Close()
	}

	// Patch each post with whatever we found. Missing rows leave
	// the fields empty.
	for _, p := range posts {
		if p.CommunityID != nil {
			if m, ok := communityMeta[*p.CommunityID]; ok {
				p.CommunityName = m.name
				p.CommunityRegionCode = m.regionCode
			}
		}
		if p.ExpertID != nil {
			if name, ok := expertMeta[*p.ExpertID]; ok {
				p.ExpertName = name
			}
		}
	}
	return nil
}

// postCols is the canonical SELECT list for a post row. Step-20 (mig
// 0020) added `status` + `publish_at` to the tail. The order MUST match
// `models.ScanPost` exactly — that scanner reads the columns left to
// right.
const postCols = `
	id, target_type, community_id, expert_id, author_id, author_name,
	title, body, ticker, tickers, stance, upvotes, likes,
	comments_count, created_at,
	post_type, media_url, cover_url, duration_seconds, visibility,
	is_hidden, updated_at,
	status, publish_at, video_variants
`

// ListCommunityPublicPosts — used by the pre-join preview endpoint
// (step-23). Returns only public + published rows so the preview is
// safe to show to any caller, including non-members and logged-out
// visitors.
func (r *SocialRepository) ListCommunityPublicPosts(
	communityID string, limit int,
) ([]*models.Post, error) {
	if limit <= 0 || limit > 20 {
		limit = 3
	}
	rows, err := r.db.Query(`
		SELECT `+postCols+`
		FROM posts
		WHERE target_type = 'community'
		  AND community_id = $1
		  AND status = 'published'
		  AND visibility = 'public'
		  AND is_hidden = FALSE
		ORDER BY created_at DESC
		LIMIT $2
	`, communityID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.Post
	for rows.Next() {
		p, err := models.ScanPost(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	r.attachAttachmentsBatch(out)
	r.resolvePostURLs(out)
	return out, nil
}

// ListCommunityPosts returns a community's published feed, newest first.
//
// Hidden posts (moderated via SetCommunityPostHidden) are filtered out for
// ordinary members so the soft-hide actually removes them from the feed.
// They remain visible to:
//   • moderators (owner / co-owner / admin) — pass canModerate=true, and
//   • the post's own author — matched via viewerID = author_id,
// so a post can always be un-hidden by someone empowered to do so.
func (r *SocialRepository) ListCommunityPosts(
	communityID string, limit int, viewerID int64, canModerate bool,
) ([]*models.Post, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	// Step-20: only published rows reach the community listing — drafts
	// + scheduled stay invisible until the publisher tick promotes them.
	rows, err := r.db.Query(`
		SELECT `+postCols+`
		FROM posts
		WHERE target_type = 'community' AND community_id = $1
		  AND status = 'published'
		  AND (is_hidden = FALSE OR $2 = TRUE OR author_id = $3)
		ORDER BY created_at DESC
		LIMIT $4
	`, communityID, canModerate, viewerID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.Post
	for rows.Next() {
		p, err := models.ScanPost(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Denormalize community/expert metadata so the client can render
	// a "from <X>" badge without follow-up calls. Best-effort.
	_ = r.EnrichPostsWithSource(out)
	r.attachAttachmentsBatch(out)
	r.resolvePostURLs(out)
	return out, nil
}

// CreateCommunityPost inserts a community-targeted post and returns the row.
// CommunityPostExtras carries the optional fields a community post
// can carry now that we've extended the endpoint to accept video +
// reel media. All defaults to safe zero values; the handler is
// responsible for normalizing PostType / Visibility before calling
// in.
type CommunityPostExtras struct {
	PostType        string   // "article" | "video" | "reel"
	Visibility      string   // "public" | "subscribers_only"
	MediaURL        string   // optional video / reel mp4 URL
	CoverURL        string   // optional thumbnail
	DurationSeconds *int     // optional video / reel length
	Tickers         []string // optional secondary symbols (legacy single
	//                         `ticker` column still set from the handler)
}

func (r *SocialRepository) CreateCommunityPost(
	communityID string,
	authorID int64,
	authorName, title, body, ticker, stance string,
	extras CommunityPostExtras,
) (*models.Post, error) {
	// Default values mirror the handler — keeps the repo callable
	// from non-handler paths (admin tools, scripts) without forcing
	// every caller to fill in defaults.
	postType := extras.PostType
	if postType == "" {
		postType = "article"
	}
	visibility := extras.Visibility
	if visibility == "" {
		visibility = "subscribers_only"
	}
	tickers := extras.Tickers
	if tickers == nil {
		tickers = []string{}
	}
	tickersJSON, err := json.Marshal(tickers)
	if err != nil {
		return nil, err
	}
	nullStr := func(s string) any {
		if s == "" {
			return nil
		}
		return s
	}
	var duration any
	if extras.DurationSeconds != nil {
		duration = *extras.DurationSeconds
	}
	row := r.db.QueryRow(`
		INSERT INTO posts (
		    target_type, community_id, author_id, author_name,
		    title, body, ticker, tickers, stance,
		    post_type, media_url, cover_url, duration_seconds, visibility
		)
		VALUES (
		    'community', $1, $2, $3,
		    $4, $5, $6, $7::jsonb, $8,
		    $9, $10, $11, $12, $13
		)
		RETURNING `+postCols,
		communityID, authorID, authorName,
		title, body, ticker, string(tickersJSON), stance,
		postType, nullStr(extras.MediaURL), nullStr(extras.CoverURL),
		duration, visibility,
	)
	return models.ScanPost(row)
}

// ExpertPostInput carries everything needed to insert a post on an expert's
// profile. Title, MediaURL, CoverURL, and DurationSeconds are optional —
// articles only need title+body, while reels/videos use media_url+cover_url.
type ExpertPostInput struct {
	ExpertID        string
	AuthorID        int64
	AuthorName      string
	PostType        string // article | video | reel
	Title           string
	Body            string
	Tickers         []string
	MediaURL        string
	CoverURL        string
	DurationSeconds *int
	Visibility      string // public | subscribers_only
}

// CreateExpertPost inserts an expert-profile-targeted post. Empty optional
// fields become NULL in Postgres so the schema constraints stay clean.
func (r *SocialRepository) CreateExpertPost(in ExpertPostInput) (*models.Post, error) {
	if in.Tickers == nil {
		in.Tickers = []string{}
	}
	tickersJSON, err := json.Marshal(in.Tickers)
	if err != nil {
		return nil, err
	}

	nullStr := func(s string) any {
		if s == "" {
			return nil
		}
		return s
	}
	var duration any
	if in.DurationSeconds != nil {
		duration = *in.DurationSeconds
	}

	row := r.db.QueryRow(`
		INSERT INTO posts (
		    target_type, expert_id, author_id, author_name,
		    post_type, title, body, tickers,
		    media_url, cover_url, duration_seconds, visibility
		)
		VALUES (
		    'expert', $1, $2, $3,
		    $4, $5, $6, $7::jsonb,
		    $8, $9, $10, $11
		)
		RETURNING `+postCols,
		in.ExpertID, in.AuthorID, in.AuthorName,
		in.PostType, nullStr(in.Title), in.Body, string(tickersJSON),
		nullStr(in.MediaURL), nullStr(in.CoverURL), duration, in.Visibility,
	)
	return models.ScanPost(row)
}

// ListPostsByExpert returns every post on an expert's profile.
//
// Hidden rows (posts.is_hidden = TRUE) are filtered out unless
// [includeHidden] is true — handlers pass true only when the caller is the
// post's author or an admin so they can manage their own hidden posts in
// the studio.
//
// Step-20 (mig 0020, item 4.15): drafts + scheduled rows are NEVER
// returned by this read path — they have a dedicated endpoint
// (`/me/expert/drafts`). The studio's main "Posts" list shows only
// published content; the Drafts tab fetches drafts separately.
//
// Optional `postType` ('article'|'video'|'reel'|'') filters by type; empty
// returns all types.
func (r *SocialRepository) ListPostsByExpert(
	expertID, postType string,
	limit int,
	includeHidden bool,
) ([]*models.Post, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	q := `SELECT ` + postCols + ` FROM posts
	      WHERE target_type = 'expert' AND expert_id = $1
	        AND status = 'published'`
	args := []any{expertID}
	if !includeHidden {
		q += ` AND is_hidden = FALSE`
	}
	if postType != "" {
		args = append(args, postType)
		q += ` AND post_type = $` + itoa(len(args))
	}
	args = append(args, limit)
	q += ` ORDER BY created_at DESC LIMIT $` + itoa(len(args))

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.Post
	for rows.Next() {
		p, err := models.ScanPost(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Denormalize community/expert metadata so the client can render
	// a "from <X>" badge without follow-up calls. Best-effort.
	_ = r.EnrichPostsWithSource(out)
	r.attachAttachmentsBatch(out)
	r.resolvePostURLs(out)
	return out, nil
}

// ListSubscribedFeed returns the latest posts from every expert the user
// holds an *active*, unexpired subscription to. Owner-of-content sees their
// own posts here too as a side-effect of subscribing to themselves doesn't
// happen — this is purely paid content the user has unlocked.
//
// The query intentionally skips hidden rows (`is_hidden = TRUE`) so a
// hidden post never leaks into a subscriber's feed.
//
// Optional `postType` ('article'|'video'|'reel'|'') filters by type.
// Optional `before` is a keyset cursor — when non-zero, only posts older
// than this timestamp are returned. Lets the client paginate by passing
// the oldest-currently-loaded post's createdAt to fetch the next page.
// `limit` is clamped 1..100, defaults to 50 when out of range.
//
// Posts are returned newest-first by `created_at`. Locked-teaser logic
// doesn't apply — by definition every row here belongs to an expert the
// user has active access to, so the body / media / tickers come back
// fully populated.
func (r *SocialRepository) ListSubscribedFeed(
	userID int64,
	postType string,
	limit int,
	before time.Time,
) ([]*models.Post, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	// Columns qualified with `p.` because expert_subscriptions also has
	// id / expert_id / created_at — Postgres would otherwise raise
	// "ambiguous column reference".
	q := `
		SELECT ` + postColsQualified("p") + `
		FROM posts p
		JOIN expert_subscriptions s
		     ON s.expert_id = p.expert_id
		    AND s.user_id   = $1
		    AND s.status    = 'active'
		    AND s.expires_at > NOW()
		WHERE p.target_type = 'expert'
		  AND p.is_hidden   = FALSE
		  AND p.status      = 'published'
	`
	args := []any{userID}
	if postType != "" {
		args = append(args, postType)
		q += ` AND p.post_type = $` + itoa(len(args))
	}
	if !before.IsZero() {
		args = append(args, before)
		q += ` AND p.created_at < $` + itoa(len(args))
	}
	args = append(args, limit)
	q += ` ORDER BY p.created_at DESC LIMIT $` + itoa(len(args))

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.Post
	for rows.Next() {
		p, err := models.ScanPost(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	r.attachAttachmentsBatch(out)
	r.resolvePostURLs(out)
	return out, nil
}

// GetPostByID fetches a single post or returns nil if it doesn't exist.
// Used by the edit/delete/hide handlers to verify ownership before
// mutating.
func (r *SocialRepository) GetPostByID(id int64) (*models.Post, error) {
	row := r.db.QueryRow(`SELECT `+postCols+` FROM posts WHERE id = $1`, id)
	p, err := models.ScanPost(row)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	// Single-row enrichment — same helper, just one element.
	one := []*models.Post{p}
	_ = r.EnrichPostsWithSource(one)
	r.attachAttachmentsBatch(one)
	r.resolvePostURLs(one)
	return p, nil
}

// ExpertPostUpdate carries the fields a post owner can edit. Pointer fields
// distinguish "not provided" (nil) from "set to empty" (non-nil empty
// string) so we can do partial updates without zeroing untouched columns.
type ExpertPostUpdate struct {
	Title           *string
	Body            *string
	MediaURL        *string
	CoverURL        *string
	DurationSeconds *int
	Visibility      *string
	Tickers         *[]string
}

// UpdateExpertPost partially updates an expert post. Returns the fresh row.
// Returns sql.ErrNoRows if the post doesn't exist.
func (r *SocialRepository) UpdateExpertPost(id int64, in ExpertPostUpdate) (*models.Post, error) {
	sets := []string{}
	args := []any{}
	add := func(col string, v any) {
		args = append(args, v)
		sets = append(sets, col+" = $"+itoa(len(args)))
	}

	if in.Title != nil {
		if *in.Title == "" {
			add("title", nil)
		} else {
			add("title", *in.Title)
		}
	}
	if in.Body != nil {
		add("body", *in.Body)
	}
	if in.MediaURL != nil {
		if *in.MediaURL == "" {
			add("media_url", nil)
		} else {
			add("media_url", *in.MediaURL)
		}
	}
	if in.CoverURL != nil {
		if *in.CoverURL == "" {
			add("cover_url", nil)
		} else {
			add("cover_url", *in.CoverURL)
		}
	}
	if in.DurationSeconds != nil {
		add("duration_seconds", *in.DurationSeconds)
	}
	if in.Visibility != nil {
		add("visibility", *in.Visibility)
	}
	if in.Tickers != nil {
		raw, err := json.Marshal(*in.Tickers)
		if err != nil {
			return nil, err
		}
		add("tickers", string(raw))
	}

	if len(sets) == 0 {
		// Nothing to change — just return current row.
		return r.GetPostByID(id)
	}

	args = append(args, id)
	q := `UPDATE posts SET ` + strings.Join(sets, ", ") +
		` WHERE id = $` + itoa(len(args)) + ` AND target_type = 'expert' RETURNING ` + postCols
	row := r.db.QueryRow(q, args...)
	return models.ScanPost(row)
}

// SetExpertPostHidden flips the is_hidden flag on a post. The realtime
// trigger emits a `hidden` event so subscribed clients refresh.
func (r *SocialRepository) SetExpertPostHidden(id int64, hidden bool) (*models.Post, error) {
	row := r.db.QueryRow(`
		UPDATE posts SET is_hidden = $1
		 WHERE id = $2 AND target_type = 'expert'
		 RETURNING `+postCols, hidden, id)
	return models.ScanPost(row)
}

// DeleteExpertPost permanently removes a post. The realtime trigger emits a
// `deleted` event with the postId + expertId so clients can drop it from
// their lists.
func (r *SocialRepository) DeleteExpertPost(id int64) error {
	res, err := r.db.Exec(`DELETE FROM posts WHERE id = $1 AND target_type = 'expert'`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// -----------------------------------------------------------------------------
// Community-post moderation. Mirrors the expert-post helpers above but scoped
// to target_type='community' so an expert-post id can never be touched through
// a community route (and vice-versa). Edit/hide/delete are gated at the handler
// layer to author OR community owner/co-owner OR platform admin.
// -----------------------------------------------------------------------------

// UpdateCommunityPost partially updates a community post. Returns the fresh row,
// or sql.ErrNoRows if no community post with that id exists. Reuses the same
// ExpertPostUpdate carrier — the fields a post author may edit are identical.
func (r *SocialRepository) UpdateCommunityPost(id int64, in ExpertPostUpdate) (*models.Post, error) {
	sets := []string{}
	args := []any{}
	add := func(col string, v any) {
		args = append(args, v)
		sets = append(sets, col+" = $"+itoa(len(args)))
	}

	if in.Title != nil {
		if *in.Title == "" {
			add("title", nil)
		} else {
			add("title", *in.Title)
		}
	}
	if in.Body != nil {
		add("body", *in.Body)
	}
	if in.MediaURL != nil {
		if *in.MediaURL == "" {
			add("media_url", nil)
		} else {
			add("media_url", *in.MediaURL)
		}
	}
	if in.CoverURL != nil {
		if *in.CoverURL == "" {
			add("cover_url", nil)
		} else {
			add("cover_url", *in.CoverURL)
		}
	}
	if in.DurationSeconds != nil {
		add("duration_seconds", *in.DurationSeconds)
	}
	if in.Visibility != nil {
		add("visibility", *in.Visibility)
	}
	if in.Tickers != nil {
		raw, err := json.Marshal(*in.Tickers)
		if err != nil {
			return nil, err
		}
		add("tickers", string(raw))
	}

	if len(sets) == 0 {
		return r.GetPostByID(id)
	}

	args = append(args, id)
	q := `UPDATE posts SET ` + strings.Join(sets, ", ") +
		` WHERE id = $` + itoa(len(args)) + ` AND target_type = 'community' RETURNING ` + postCols
	row := r.db.QueryRow(q, args...)
	return models.ScanPost(row)
}

// SetCommunityPostHidden flips is_hidden on a community post.
func (r *SocialRepository) SetCommunityPostHidden(id int64, hidden bool) (*models.Post, error) {
	row := r.db.QueryRow(`
		UPDATE posts SET is_hidden = $1
		 WHERE id = $2 AND target_type = 'community'
		 RETURNING `+postCols, hidden, id)
	return models.ScanPost(row)
}

// DeleteCommunityPost permanently removes a community post.
func (r *SocialRepository) DeleteCommunityPost(id int64) error {
	res, err := r.db.Exec(`DELETE FROM posts WHERE id = $1 AND target_type = 'community'`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// =============================================================================
// Step-20 (mig 0020) — drafts, scheduling, version history, attachments.
// =============================================================================

// CreateExpertDraft inserts a row with status='draft'. Same input shape
// as CreateExpertPost — handlers can reuse their validation. Returns
// the freshly-inserted row so the client can pin its id for follow-up
// edits.
func (r *SocialRepository) CreateExpertDraft(in ExpertPostInput) (*models.Post, error) {
	if in.Tickers == nil {
		in.Tickers = []string{}
	}
	tickersJSON, err := json.Marshal(in.Tickers)
	if err != nil {
		return nil, err
	}
	nullStr := func(s string) any {
		if s == "" {
			return nil
		}
		return s
	}
	var duration any
	if in.DurationSeconds != nil {
		duration = *in.DurationSeconds
	}
	row := r.db.QueryRow(`
		INSERT INTO posts (
		    target_type, expert_id, author_id, author_name,
		    post_type, title, body, tickers,
		    media_url, cover_url, duration_seconds, visibility,
		    status
		)
		VALUES (
		    'expert', $1, $2, $3,
		    $4, $5, $6, $7::jsonb,
		    $8, $9, $10, $11,
		    'draft'
		)
		RETURNING `+postCols,
		in.ExpertID, in.AuthorID, in.AuthorName,
		in.PostType, nullStr(in.Title), in.Body, string(tickersJSON),
		nullStr(in.MediaURL), nullStr(in.CoverURL), duration, in.Visibility,
	)
	return models.ScanPost(row)
}

// PublishDraftAt flips a row from 'draft' to either 'published' (when
// `at` is nil) or 'scheduled' with publish_at = `at` (future). The
// caller MUST verify ownership.
//
// Returns sql.ErrNoRows if the row doesn't exist or isn't currently a
// draft.
func (r *SocialRepository) PublishDraftAt(postID int64, at *time.Time) (*models.Post, error) {
	var (
		row *sql.Row
	)
	if at == nil {
		row = r.db.QueryRow(`
			UPDATE posts SET status = 'published', publish_at = NULL,
			                 updated_at = NOW(), created_at = NOW()
			 WHERE id = $1 AND status IN ('draft','scheduled')
			 RETURNING `+postCols, postID)
	} else {
		row = r.db.QueryRow(`
			UPDATE posts SET status = 'scheduled', publish_at = $2,
			                 updated_at = NOW()
			 WHERE id = $1 AND status IN ('draft','scheduled')
			 RETURNING `+postCols, postID, *at)
	}
	p, err := models.ScanPost(row)
	if err != nil {
		return nil, err
	}
	return p, nil
}

// ListDraftsByAuthor — every draft + scheduled row authored by the
// given user, regardless of target. Drives the studio "Drafts" tab.
//
// Sorted: scheduled rows first ordered by publish_at ASC, then drafts
// by updated_at DESC.
func (r *SocialRepository) ListDraftsByAuthor(authorID int64) ([]*models.Post, error) {
	rows, err := r.db.Query(`
		SELECT `+postCols+` FROM posts
		 WHERE author_id = $1
		   AND status IN ('draft','scheduled')
		 ORDER BY (status = 'scheduled') DESC,
		          publish_at ASC NULLS LAST,
		          updated_at DESC
		 LIMIT 200`, authorID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.Post
	for rows.Next() {
		p, err := models.ScanPost(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	r.attachAttachmentsBatch(out)
	r.resolvePostURLs(out)
	return out, nil
}

// PromoteScheduledPosts flips every row whose publish_at has passed
// from 'scheduled' to 'published' and returns the freshly-promoted
// rows. Called by the scheduled-publisher goroutine on every tick.
//
// We bump created_at to NOW() at promotion time so the published row
// sorts to the top of feeds (the scheduling intent is "publish at
// time X, not at draft creation time").
func (r *SocialRepository) PromoteScheduledPosts() ([]*models.Post, error) {
	rows, err := r.db.Query(`
		UPDATE posts SET status = 'published',
		                 publish_at = NULL,
		                 created_at = NOW(),
		                 updated_at = NOW()
		 WHERE status = 'scheduled' AND publish_at <= NOW()
		 RETURNING ` + postCols)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.Post
	for rows.Next() {
		p, err := models.ScanPost(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// =============================================================================
// post_versions — every post edit snapshots the prior content.
// =============================================================================

// PostVersion mirrors one row from the post_versions table.
type PostVersion struct {
	ID        int64     `json:"id"`
	PostID    int64     `json:"postId"`
	EditorID  *int64    `json:"editorId,omitempty"`
	Title     string    `json:"title,omitempty"`
	Body      string    `json:"body"`
	Tickers   []string  `json:"tickers"`
	EditedAt  time.Time `json:"editedAt"`
}

// WritePostVersion snapshots the current state of a post into
// post_versions. Called from UpdateExpertPost BEFORE the actual UPDATE
// runs — that way the snapshot captures what's about to be replaced.
func (r *SocialRepository) WritePostVersion(
	postID int64, editorID int64, title, body string, tickers []string,
) error {
	if tickers == nil {
		tickers = []string{}
	}
	tickersJSON, err := json.Marshal(tickers)
	if err != nil {
		return err
	}
	var titleArg any
	if title == "" {
		titleArg = nil
	} else {
		titleArg = title
	}
	var editorArg any
	if editorID != 0 {
		editorArg = editorID
	}
	_, err = r.db.Exec(`
		INSERT INTO post_versions (post_id, editor_id, title, body, tickers)
		VALUES ($1, $2, $3, $4, $5::jsonb)
	`, postID, editorArg, titleArg, body, string(tickersJSON))
	return err
}

// ListPostVersions returns every snapshot for a post, newest-first.
// Empty slice (not nil) when there are no versions yet so the JSON
// shape stays clean.
func (r *SocialRepository) ListPostVersions(postID int64) ([]*PostVersion, error) {
	rows, err := r.db.Query(`
		SELECT id, post_id, editor_id, title, body, tickers, edited_at
		  FROM post_versions
		 WHERE post_id = $1
		 ORDER BY edited_at DESC
		 LIMIT 200`, postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*PostVersion, 0)
	for rows.Next() {
		var v PostVersion
		var editorID sql.NullInt64
		var title sql.NullString
		var tickersRaw []byte
		if err := rows.Scan(
			&v.ID, &v.PostID, &editorID, &title, &v.Body, &tickersRaw, &v.EditedAt,
		); err != nil {
			return nil, err
		}
		if editorID.Valid {
			id := editorID.Int64
			v.EditorID = &id
		}
		if title.Valid {
			v.Title = title.String
		}
		if len(tickersRaw) > 0 {
			_ = json.Unmarshal(tickersRaw, &v.Tickers)
		}
		if v.Tickers == nil {
			v.Tickers = []string{}
		}
		out = append(out, &v)
	}
	return out, rows.Err()
}

// =============================================================================
// post_attachments — inline images embedded in articles.
// =============================================================================

// AddPostAttachment inserts one attachment row. Caller MUST verify
// ownership and that the post hasn't already hit the 5-attachment cap.
func (r *SocialRepository) AddPostAttachment(
	postID int64, url string, sortOrder int,
) (*models.PostAttachment, error) {
	row := r.db.QueryRow(`
		INSERT INTO post_attachments (post_id, url, sort_order)
		VALUES ($1, $2, $3)
		RETURNING id, url, sort_order`, postID, url, sortOrder)
	var a models.PostAttachment
	if err := row.Scan(&a.ID, &a.URL, &a.SortOrder); err != nil {
		return nil, err
	}
	return &a, nil
}

// CountPostAttachments returns how many attachment rows already exist
// for [postID]. Used by the handler to enforce the 5-image cap.
func (r *SocialRepository) CountPostAttachments(postID int64) (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM post_attachments WHERE post_id = $1`,
		postID,
	).Scan(&n)
	return n, err
}

// DeletePostAttachment removes one row. Returns sql.ErrNoRows if the
// row doesn't exist or doesn't belong to [postID].
func (r *SocialRepository) DeletePostAttachment(
	postID, attachmentID int64,
) error {
	res, err := r.db.Exec(
		`DELETE FROM post_attachments WHERE id = $1 AND post_id = $2`,
		attachmentID, postID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// ListPostAttachments returns the attachment rows for a single post.
func (r *SocialRepository) ListPostAttachments(postID int64) ([]models.PostAttachment, error) {
	rows, err := r.db.Query(
		`SELECT id, url, sort_order FROM post_attachments
		  WHERE post_id = $1 ORDER BY sort_order ASC, id ASC`,
		postID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]models.PostAttachment, 0)
	for rows.Next() {
		var a models.PostAttachment
		if err := rows.Scan(&a.ID, &a.URL, &a.SortOrder); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// attachAttachmentsBatch fills `Attachments` on every post in [posts]
// using one batched query. N+1-free.
func (r *SocialRepository) attachAttachmentsBatch(posts []*models.Post) {
	if len(posts) == 0 {
		return
	}
	ids := make([]int64, 0, len(posts))
	for _, p := range posts {
		if p.Attachments == nil {
			p.Attachments = []models.PostAttachment{}
		}
		ids = append(ids, p.ID)
	}
	rows, err := r.db.Query(
		`SELECT post_id, id, url, sort_order
		   FROM post_attachments
		  WHERE post_id = ANY($1)
		  ORDER BY sort_order ASC, id ASC`,
		pq.Array(ids),
	)
	if err != nil {
		return
	}
	defer rows.Close()
	idx := make(map[int64]*models.Post, len(posts))
	for _, p := range posts {
		idx[p.ID] = p
	}
	for rows.Next() {
		var pid int64
		var a models.PostAttachment
		if err := rows.Scan(&pid, &a.ID, &a.URL, &a.SortOrder); err != nil {
			continue
		}
		if p, ok := idx[pid]; ok {
			p.Attachments = append(p.Attachments, a)
		}
	}
}

// itoa is in audit.go — re-used here for $N placeholder formatting.
// (See repositories/audit.go for the implementation.)

// ListJoinedCommunityIDs — every community id the user is a member of.
// Used by the realtime handler to auto-subscribe a fresh WS client to
// `community:<id>` so per-community chat broadcasts reach them
// without the client explicitly asking. Cheap query (PK on
// community_members covers it).
func (r *SocialRepository) ListJoinedCommunityIDs(userID int64) ([]string, error) {
	rows, err := r.db.Query(
		`SELECT community_id FROM community_members WHERE user_id = $1`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]string, 0)
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// =============================================================================
// Admin community CRUD — list / create / update / delete + member
// inspection. Used by the admin dashboard's Communities page. The
// public-side ListCommunities + GetCommunity already exist above and
// don't need the admin-shaped joins.
// =============================================================================

// AdminCommunityRow — one row in the admin Communities table.
// Includes owner display fields + member count via subquery so the
// dashboard renders without N follow-up calls per row.
//
// Step-19 fields (mig 0019) — surfaced so the admin dashboard can show
// + edit them without a separate detail call:
//   * Description / Rules — long-form metadata.
//   * CoverURL            — banner image URL.
//   * IsPublic            — visibility toggle (read access for non-members).
//   * Category            — predefined category string.
//   * Tags                — many-to-many tag slice.
type AdminCommunityRow struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Tagline     string   `json:"tagline,omitempty"`
	Description string   `json:"description,omitempty"`
	Rules       string   `json:"rules,omitempty"`
	CoverURL    string   `json:"coverUrl,omitempty"`
	AvatarURL   string   `json:"avatarUrl,omitempty"`
	IsPublic    bool     `json:"isPublic"`
	Category    string   `json:"category,omitempty"`
	Tags        []string `json:"tags"`
	RegionCode  string   `json:"regionCode,omitempty"`
	OwnerID     *int64   `json:"ownerId,omitempty"`
	OwnerName   string   `json:"ownerName,omitempty"`
	OwnerEmail  string   `json:"ownerEmail,omitempty"`
	MemberCount int      `json:"memberCount"`
	PostCount   int      `json:"postCount"`
	// Step-23 — paid community pricing.
	JoinPriceMonthlyCents int    `json:"joinPriceMonthlyCents"`
	JoinPriceYearlyCents  int    `json:"joinPriceYearlyCents"`
	PriceCurrency         string `json:"priceCurrency"`
}

// AdminListCommunities — every community on the platform with owner
// + member + post counts joined in. Sorted by id (which mirrors the
// `c_*` slug prefix and keeps the seed-data order predictable).
func (r *SocialRepository) AdminListCommunities() ([]*AdminCommunityRow, error) {
	rows, err := r.db.Query(`
		SELECT c.id, c.name, COALESCE(c.tagline, ''), COALESCE(c.region_code, ''),
		       COALESCE(c.description, ''), COALESCE(c.rules, ''),
		       c.cover_url, c.avatar_url, c.is_public, c.category,
		       c.owner_id,
		       COALESCE(NULLIF(u.name, ''), '') AS owner_name,
		       COALESCE(u.email, '')            AS owner_email,
		       (SELECT COUNT(*) FROM community_members m WHERE m.community_id = c.id),
		       (SELECT COUNT(*) FROM posts p
		         WHERE p.target_type = 'community' AND p.community_id = c.id),
		       c.join_price_monthly_cents, c.join_price_yearly_cents, c.price_currency
		  FROM communities c
		  LEFT JOIN users u ON u.id = c.owner_id
		 ORDER BY c.id`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*AdminCommunityRow, 0)
	ids := make([]string, 0)
	for rows.Next() {
		var row AdminCommunityRow
		var coverURL, avatarURL, category sql.NullString
		if err := rows.Scan(
			&row.ID, &row.Name, &row.Tagline, &row.RegionCode,
			&row.Description, &row.Rules,
			&coverURL, &avatarURL, &row.IsPublic, &category,
			&row.OwnerID, &row.OwnerName, &row.OwnerEmail,
			&row.MemberCount, &row.PostCount,
			&row.JoinPriceMonthlyCents, &row.JoinPriceYearlyCents,
			&row.PriceCurrency,
		); err != nil {
			return nil, err
		}
		if coverURL.Valid {
			row.CoverURL = r.resolveURL(coverURL.String)
		}
		if avatarURL.Valid {
			row.AvatarURL = r.resolveURL(avatarURL.String)
		}
		if category.Valid {
			row.Category = category.String
		}
		row.Tags = []string{}
		out = append(out, &row)
		ids = append(ids, row.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Tag fan-in. Cheap — even at 1000 communities × 10 tags this is one
	// SELECT and a tiny in-memory join.
	if len(ids) > 0 {
		tagRows, terr := r.db.Query(
			`SELECT community_id, tag FROM community_tags WHERE community_id = ANY($1) ORDER BY tag`,
			pq.Array(ids),
		)
		if terr == nil {
			defer tagRows.Close()
			idx := make(map[string]*AdminCommunityRow, len(out))
			for _, c := range out {
				idx[c.ID] = c
			}
			for tagRows.Next() {
				var cid, tag string
				if err := tagRows.Scan(&cid, &tag); err == nil {
					if c, ok := idx[cid]; ok {
						c.Tags = append(c.Tags, tag)
					}
				}
			}
		}
	}
	return out, nil
}

// AdminCreateCommunity — admin-direct creation (separate from the
// expert proposal flow). Used when admin wants to spin up an "official"
// platform community (e.g. seasonal / regional). owner_id is optional;
// pass 0 for an admin-managed community with no expert owner.
func (r *SocialRepository) AdminCreateCommunity(
	id, name, tagline, regionCode string, ownerID int64,
) error {
	var ownerArg any
	if ownerID > 0 {
		ownerArg = ownerID
	}
	_, err := r.db.Exec(
		`INSERT INTO communities (id, name, tagline, region_code, owner_id)
		 VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, ''), $5)`,
		id, name, tagline, regionCode, ownerArg,
	)
	return err
}

// AdminCommunityUpdate — partial update payload for the admin dashboard.
// Mirrors CommunityMetadataUpdate but additionally allows mutating
// region_code + owner_id, which the owner-side flow doesn't expose.
type AdminCommunityUpdate struct {
	Name        *string
	Tagline     *string
	Description *string
	Rules       *string
	CoverURL    *string
	// AvatarURL (mig 0028) — same nil/empty/value semantics as CoverURL.
	AvatarURL   *string
	IsPublic    *bool
	Category    *string
	RegionCode  *string
	// OwnerID: nil = leave alone, *=-1 = clear, otherwise set.
	OwnerID *int64
	// Step-23 — admin can also set pricing on the community.
	JoinPriceMonthlyCents *int
	JoinPriceYearlyCents  *int
	PriceCurrency         *string
}

// AdminUpdateCommunity — partial-update via AdminCommunityUpdate.
// Returns sql.ErrNoRows when the id doesn't exist.
//
// Step-23 follow-up: same kick-on-free-to-paid transition as
// UpdateCommunityMetadata so the price gate actually kicks in for
// pre-existing free members. Owner is preserved.
func (r *SocialRepository) AdminUpdateCommunity(
	id string, in AdminCommunityUpdate,
) error {
	// Snapshot current price to detect free → paid transition.
	var beforeMonthly, beforeYearly int
	_ = r.db.QueryRow(
		`SELECT join_price_monthly_cents, join_price_yearly_cents
		   FROM communities WHERE id = $1`, id,
	).Scan(&beforeMonthly, &beforeYearly)
	wasFree := beforeMonthly <= 0 && beforeYearly <= 0
	willBePaid := false
	if in.JoinPriceMonthlyCents != nil && *in.JoinPriceMonthlyCents > 0 {
		willBePaid = true
	}
	if in.JoinPriceYearlyCents != nil && *in.JoinPriceYearlyCents > 0 {
		willBePaid = true
	}
	transitioning := wasFree && willBePaid

	sets := []string{}
	args := []any{}
	add := func(col string, v any) {
		args = append(args, v)
		sets = append(sets, col+" = $"+itoa(len(args)))
	}
	if in.Name != nil {
		add("name", *in.Name)
	}
	if in.Tagline != nil {
		add("tagline", *in.Tagline)
	}
	if in.Description != nil {
		add("description", *in.Description)
	}
	if in.Rules != nil {
		add("rules", *in.Rules)
	}
	if in.CoverURL != nil {
		if *in.CoverURL == "" {
			add("cover_url", nil)
		} else {
			add("cover_url", *in.CoverURL)
		}
	}
	if in.AvatarURL != nil {
		if *in.AvatarURL == "" {
			add("avatar_url", nil)
		} else {
			add("avatar_url", *in.AvatarURL)
		}
	}
	if in.IsPublic != nil {
		add("is_public", *in.IsPublic)
	}
	if in.Category != nil {
		if *in.Category == "" {
			add("category", nil)
		} else {
			add("category", *in.Category)
		}
	}
	if in.RegionCode != nil {
		add("region_code", *in.RegionCode)
	}
	if in.OwnerID != nil {
		if *in.OwnerID == -1 {
			sets = append(sets, "owner_id = NULL")
		} else {
			add("owner_id", *in.OwnerID)
		}
	}
	if in.JoinPriceMonthlyCents != nil {
		add("join_price_monthly_cents", *in.JoinPriceMonthlyCents)
	}
	if in.JoinPriceYearlyCents != nil {
		add("join_price_yearly_cents", *in.JoinPriceYearlyCents)
	}
	if in.PriceCurrency != nil {
		add("price_currency", *in.PriceCurrency)
	}
	if len(sets) == 0 {
		return nil
	}
	sets = append(sets, "updated_at = NOW()")
	args = append(args, id)
	q := `UPDATE communities SET ` + strings.Join(sets, ", ") +
		` WHERE id = $` + itoa(len(args))

	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	res, err := tx.Exec(q, args...)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	if transitioning {
		if _, err := tx.Exec(
			`DELETE FROM community_members
			  WHERE community_id = $1
			    AND user_id <> COALESCE(
			        (SELECT owner_id FROM communities WHERE id = $1),
			        -1
			    )`,
			id,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// AdminDeleteCommunity — hard delete. Cascade in the schema cleans up
// community_members and posts within the community.
func (r *SocialRepository) AdminDeleteCommunity(id string) error {
	res, err := r.db.Exec(`DELETE FROM communities WHERE id = $1`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// AdminCommunityMember — one member row in the dashboard's community
// detail page. Includes role + join time so admin can sort by recency.
type AdminCommunityMember struct {
	UserID   int64     `json:"userId"`
	Email    string    `json:"email"`
	Name     string    `json:"name"`
	Role     string    `json:"role"`
	JoinedAt time.Time `json:"joinedAt"`
	IsOwner  bool      `json:"isOwner"`
}

// AdminListCommunityMembers — every member of a community with
// owner-flagged so the UI can star the row. Newest-joined first.
//
// `is_owner` returns true for the PRIMARY owner OR any co-owner
// (mig 0032). The mobile + admin UI flag these rows with a gold
// ring + an "Owner" label. If a consumer needs to distinguish
// primary from co-owner, use the separate `/communities/:id/owners`
// endpoint which splits them.
func (r *SocialRepository) AdminListCommunityMembers(communityID string) ([]*AdminCommunityMember, error) {
	rows, err := r.db.Query(`
		SELECT cm.user_id,
		       u.email,
		       COALESCE(NULLIF(u.name, ''), ''),
		       u.role,
		       cm.joined_at,
		       (
		         c.owner_id = u.id
		         OR EXISTS (
		             SELECT 1 FROM community_owners co
		              WHERE co.community_id = cm.community_id
		                AND co.user_id      = cm.user_id
		         )
		       ) AS is_owner
		  FROM community_members cm
		  JOIN users u ON u.id = cm.user_id
		  JOIN communities c ON c.id = cm.community_id
		 WHERE cm.community_id = $1
		 ORDER BY is_owner DESC, cm.joined_at DESC`,
		communityID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*AdminCommunityMember, 0)
	for rows.Next() {
		var m AdminCommunityMember
		if err := rows.Scan(
			&m.UserID, &m.Email, &m.Name, &m.Role, &m.JoinedAt, &m.IsOwner,
		); err != nil {
			return nil, err
		}
		out = append(out, &m)
	}
	return out, rows.Err()
}

// AdminUserCommunity — one row in the admin "Communities for user X" view.
// Includes community pricing + the user's most-recent subscription (which
// may be nil for free communities or pre-paywall joins).
type AdminUserCommunity struct {
	CommunityID       string                 `json:"communityId"`
	CommunityName     string                 `json:"communityName"`
	IsOwner           bool                   `json:"isOwner"`
	Role              string                 `json:"role"` // user's role at platform level
	JoinedAt          time.Time              `json:"joinedAt"`
	IsPaid            bool                   `json:"isPaid"`
	MonthlyPriceCents int                    `json:"monthlyPriceCents"`
	YearlyPriceCents  int                    `json:"yearlyPriceCents"`
	Currency          string                 `json:"currency"`
	Subscription      *AdminUserCommSubBrief `json:"subscription,omitempty"`
}

// AdminUserCommSubBrief — subset of CommunitySubscription wide enough for the
// dashboard. Embedded inline so the admin doesn't have to do a follow-up
// fetch per row.
type AdminUserCommSubBrief struct {
	ID            int64      `json:"id"`
	Plan          string     `json:"plan"`
	Status        string     `json:"status"`
	PriceCents    int        `json:"priceCents"`
	Currency      string     `json:"currency"`
	PaymentMethod string     `json:"paymentMethod"`
	PaymentRef    *string    `json:"paymentRef,omitempty"`
	CreatedAt     time.Time  `json:"createdAt"`
	AcceptedAt    *time.Time `json:"acceptedAt,omitempty"`
	ExpiresAt     *time.Time `json:"expiresAt,omitempty"`
	CancelledAt   *time.Time `json:"cancelledAt,omitempty"`
	RejectedAt    *time.Time `json:"rejectedAt,omitempty"`
}

// AdminListUserCommunities — every community user X is a member of, plus the
// community's pricing and the user's most-recent subscription row for that
// community (nullable). Sorted owner-first then by join time.
//
// Drives the "Communities" section on the admin UserDetail page so the team
// can see at-a-glance which communities someone belongs to, what they paid,
// and whether anything is still active.
func (r *SocialRepository) AdminListUserCommunities(userID int64) ([]*AdminUserCommunity, error) {
	rows, err := r.db.Query(`
		SELECT c.id,
		       c.name,
		       (c.owner_id = $1)                AS is_owner,
		       u.role                           AS user_role,
		       cm.joined_at,
		       c.join_price_monthly_cents,
		       c.join_price_yearly_cents,
		       c.price_currency,
		       cs.id, cs.plan, cs.status, cs.price_cents, cs.currency,
		       cs.payment_method, cs.payment_ref,
		       cs.created_at, cs.accepted_at, cs.expires_at,
		       cs.cancelled_at, cs.rejected_at
		  FROM community_members cm
		  JOIN communities c ON c.id = cm.community_id
		  JOIN users u       ON u.id = cm.user_id
		  -- Most-recent sub row for this (user, community) pair. Picked by
		  -- (status priority: active > pending > everything else, then newest).
		  LEFT JOIN LATERAL (
		    SELECT *
		      FROM community_subscriptions s
		     WHERE s.user_id = cm.user_id
		       AND s.community_id = cm.community_id
		     ORDER BY CASE s.status
		                WHEN 'active'  THEN 0
		                WHEN 'pending' THEN 1
		                ELSE 2
		              END,
		              s.created_at DESC
		     LIMIT 1
		  ) cs ON TRUE
		 WHERE cm.user_id = $1
		 ORDER BY is_owner DESC, cm.joined_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*AdminUserCommunity, 0)
	for rows.Next() {
		var (
			x             AdminUserCommunity
			subID         sql.NullInt64
			subPlan       sql.NullString
			subStatus     sql.NullString
			subPriceCents sql.NullInt64
			subCurrency   sql.NullString
			subMethod     sql.NullString
			subRef        sql.NullString
			subCreated    sql.NullTime
			subAccepted   sql.NullTime
			subExpires    sql.NullTime
			subCancelled  sql.NullTime
			subRejected   sql.NullTime
		)
		if err := rows.Scan(
			&x.CommunityID, &x.CommunityName, &x.IsOwner, &x.Role, &x.JoinedAt,
			&x.MonthlyPriceCents, &x.YearlyPriceCents, &x.Currency,
			&subID, &subPlan, &subStatus, &subPriceCents, &subCurrency,
			&subMethod, &subRef,
			&subCreated, &subAccepted, &subExpires,
			&subCancelled, &subRejected,
		); err != nil {
			return nil, err
		}
		x.IsPaid = x.MonthlyPriceCents > 0 || x.YearlyPriceCents > 0
		if subID.Valid {
			brief := &AdminUserCommSubBrief{
				ID:            subID.Int64,
				Plan:          subPlan.String,
				Status:        subStatus.String,
				PriceCents:    int(subPriceCents.Int64),
				Currency:      subCurrency.String,
				PaymentMethod: subMethod.String,
				CreatedAt:     subCreated.Time,
			}
			if subRef.Valid {
				ref := subRef.String
				brief.PaymentRef = &ref
			}
			if subAccepted.Valid {
				t := subAccepted.Time
				brief.AcceptedAt = &t
			}
			if subExpires.Valid {
				t := subExpires.Time
				brief.ExpiresAt = &t
			}
			if subCancelled.Valid {
				t := subCancelled.Time
				brief.CancelledAt = &t
			}
			if subRejected.Valid {
				t := subRejected.Time
				brief.RejectedAt = &t
			}
			x.Subscription = brief
		}
		out = append(out, &x)
	}
	return out, rows.Err()
}

// =============================================================================
// Admin-side queries — bypass every subscription / visibility gate, include
// hidden posts, and accept the wide filter surface the moderation UI needs.
// Never call these from non-admin code paths.
// =============================================================================

// AdminPostFilter — filter / sort / paginate options for admin posts list.
// Each field is independently optional; the zero value of the struct returns
// the most-recent page across every author and post type.
type AdminPostFilter struct {
	// Type filter: '', 'article', 'video', 'reel'. '' means all types.
	PostType string
	// Target filter: '', 'expert', 'community' (Sprint-C step 11).
	// '' means both expert + community posts.
	TargetType string
	// AuthorID = 0 means all authors. Filters posts.author_id.
	AuthorID int64
	// ExpertID = '' means all experts. Filters posts.expert_id.
	ExpertID string
	// Status: 'all' (default), 'hidden', 'active'.
	Status string
	// Search — case-insensitive ILIKE against title + body. '' means no
	// search. Wrapped in '%...%' before the query — caller passes a bare
	// query string, no SQL wildcards needed.
	Query string
	// Keyset cursor — only return rows older than this. Zero value means
	// no cursor (newest page).
	Before time.Time
	// Sort: 'newest' (default), 'oldest', 'most_liked', 'most_commented'.
	Sort string
	// Bounded 1..200, default 50.
	Limit int
}

// AdminPostRow — one row in the moderation list. Wraps Post so we can
// return the joined author info without weakening the existing model
// for non-admin callers.
type AdminPostRow struct {
	*models.Post
	AuthorEmail string `json:"authorEmail"`
	AuthorRole  string `json:"authorRole"`
}

// AdminListPosts — moderation list. Returns admin-shaped rows including
// hidden posts and any author email / role for tooltips. Sorted by the
// chosen key DESC except `oldest` which goes ASC. Pagination uses
// `created_at < before` keyset semantics (matches the public feed).
func (r *SocialRepository) AdminListPosts(f AdminPostFilter) ([]*AdminPostRow, error) {
	if f.Limit <= 0 || f.Limit > 200 {
		f.Limit = 50
	}

	args := make([]any, 0, 8)
	q := `SELECT ` + postCols + `, COALESCE(u.email, ''), COALESCE(u.role, '')
	      FROM posts p_unused -- placeholder so we can prefix columns later
	      `
	// Rewrite — the placeholder above isn't useful; use a normal SELECT
	// with explicit columns from posts + a left join on users for email
	// and role. We left-join because some legacy rows might not match a
	// current user_id (community posts predate strict FK).
	q = `SELECT ` + postColsQualified("posts") + `,
	            COALESCE(u.email, ''), COALESCE(u.role, '')
	       FROM posts
	  LEFT JOIN users u ON u.id = posts.author_id
	      WHERE 1=1`

	if f.PostType != "" {
		args = append(args, f.PostType)
		q += ` AND posts.post_type = $` + itoa(len(args))
	}
	if f.TargetType != "" {
		args = append(args, f.TargetType)
		q += ` AND posts.target_type = $` + itoa(len(args))
	}
	if f.AuthorID != 0 {
		args = append(args, f.AuthorID)
		q += ` AND posts.author_id = $` + itoa(len(args))
	}
	if f.ExpertID != "" {
		args = append(args, f.ExpertID)
		q += ` AND posts.expert_id = $` + itoa(len(args))
	}
	switch f.Status {
	case "hidden":
		q += ` AND posts.is_hidden = TRUE`
	case "active":
		q += ` AND posts.is_hidden = FALSE`
	default:
		// "all" — no extra filter.
	}
	if f.Query != "" {
		args = append(args, "%"+f.Query+"%")
		idx := itoa(len(args))
		q += ` AND (posts.title ILIKE $` + idx + ` OR posts.body ILIKE $` + idx + `)`
	}
	if !f.Before.IsZero() {
		args = append(args, f.Before)
		q += ` AND posts.created_at < $` + itoa(len(args))
	}

	switch f.Sort {
	case "oldest":
		q += ` ORDER BY posts.created_at ASC`
	case "most_liked":
		q += ` ORDER BY posts.likes DESC, posts.created_at DESC`
	case "most_commented":
		q += ` ORDER BY posts.comments_count DESC, posts.created_at DESC`
	default:
		q += ` ORDER BY posts.created_at DESC`
	}

	args = append(args, f.Limit)
	q += ` LIMIT $` + itoa(len(args))

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*AdminPostRow, 0, f.Limit)
	// Collect Post pointers as we build the rows so we can pipe them
	// through resolvePostURLs in one batch after the loop — cheaper
	// than per-row signing and keeps the URL refresh logic centralized.
	posts := make([]*models.Post, 0, f.Limit)
	for rows.Next() {
		row := &AdminPostRow{}
		// ScanPost only consumes the first 22 columns; the trailing
		// COALESCE columns we tack on need their own scan slot. Build a
		// scanner that delegates the post fields to ScanPost via the
		// extras-aware variant.
		p, email, role, err := scanAdminPostRow(rows)
		if err != nil {
			return nil, err
		}
		row.Post = p
		row.AuthorEmail = email
		row.AuthorRole = role
		out = append(out, row)
		posts = append(posts, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	r.resolvePostURLs(posts)
	return out, nil
}

// AdminPostStats — extra counters surfaced on the post-detail page that
// don't live on the post row itself. Kept separate so the cheap list
// query doesn't have to JOIN four extra tables for every row.
type AdminPostStats struct {
	Likes           int `json:"likes"`
	Comments        int `json:"comments"`
	Saves           int `json:"saves"`
	Shares          int `json:"shares"`
	DeepLinkOpens   int `json:"deepLinkOpens"`
	ReelLoadFails   int `json:"reelLoadFails"`
}

// AdminPostStatsByID — one round-trip aggregate of every counter the
// detail page wants to show. UNION ALL so a single network call gets
// us every number.
func (r *SocialRepository) AdminPostStatsByID(postID int64) (AdminPostStats, error) {
	var s AdminPostStats
	row := r.db.QueryRow(`
		SELECT
			(SELECT COUNT(*) FROM post_likes    WHERE post_id = $1),
			(SELECT COUNT(*) FROM post_comments WHERE post_id = $1),
			(SELECT COUNT(*) FROM post_saves    WHERE post_id = $1),
			(SELECT COUNT(*) FROM post_events   WHERE post_id = $1 AND event_type = 'share_tapped'),
			(SELECT COUNT(*) FROM post_events   WHERE post_id = $1 AND event_type = 'deep_link_opened'),
			(SELECT COUNT(*) FROM post_events   WHERE post_id = $1 AND event_type = 'reel_load_failed')
	`, postID)
	err := row.Scan(&s.Likes, &s.Comments, &s.Saves, &s.Shares, &s.DeepLinkOpens, &s.ReelLoadFails)
	if err != nil {
		return s, err
	}
	return s, nil
}

// ExpertEngagementTotals — sum of likes / comments / saves / shares
// across every (non-hidden, non-deleted) post the expert has authored.
// Used by the studio dashboard's metrics row (Phase 3.1) as a stand-in
// for per-post "views" — we don't have view-tracking yet, so we use
// engagement events instead.
type ExpertEngagementTotals struct {
	Posts    int `json:"posts"`
	Likes    int `json:"likes"`
	Comments int `json:"comments"`
	Saves    int `json:"saves"`
	Shares   int `json:"shares"`
}

func (r *SocialRepository) ExpertEngagementTotalsForExpert(expertID string) (*ExpertEngagementTotals, error) {
	var t ExpertEngagementTotals
	err := r.db.QueryRow(`
		WITH expert_posts AS (
		  SELECT id FROM posts
		   WHERE expert_id = $1
		     AND target_type = 'expert'
		     AND is_hidden = false
		     AND deleted_at IS NULL
		)
		SELECT
		  (SELECT COUNT(*) FROM expert_posts),
		  (SELECT COUNT(*) FROM post_likes    pl WHERE pl.post_id IN (SELECT id FROM expert_posts)),
		  (SELECT COUNT(*) FROM post_comments pc WHERE pc.post_id IN (SELECT id FROM expert_posts)),
		  (SELECT COUNT(*) FROM post_saves    ps WHERE ps.post_id IN (SELECT id FROM expert_posts)),
		  (SELECT COUNT(*) FROM post_events   pe
		    WHERE pe.post_id IN (SELECT id FROM expert_posts)
		      AND pe.event_type = 'share_tapped')
	`, expertID).Scan(&t.Posts, &t.Likes, &t.Comments, &t.Saves, &t.Shares)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

// scanAdminPostRow — local helper that scans a row containing every
// `posts` column (in postCols order) followed by author email + role.
//
// Mirrors the nullable-column + JSON-tickers handling in
// `models.ScanPost` exactly — the post schema has nullable text columns
// (communityID, expertID, title, ticker, stance, mediaURL, coverURL),
// a nullable int (durationSeconds), and a JSONB tickers array stored
// as bytes. Scanning straight into `*string` / `[]string` blows up on
// any of those, which is what produced the
// `unsupported Scan, storing driver.Value type []uint8 into type *[]string`
// error from the first version of this function.
func scanAdminPostRow(scanner interface {
	Scan(dest ...any) error
}) (*models.Post, string, string, error) {
	p := &models.Post{}
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
		email, role string
	)
	if err := scanner.Scan(
		&p.ID, &p.TargetType, &communityID, &expertID,
		&p.AuthorID, &p.AuthorName,
		&title, &p.Body, &ticker, &tickersRaw, &stance,
		&p.Upvotes, &p.Likes, &p.Comments, &p.CreatedAt,
		&p.PostType, &mediaURL, &coverURL, &duration, &p.Visibility,
		&p.IsHidden, &p.UpdatedAt,
		&p.Status, &publishAt, &variantsRaw,
		&email, &role,
	); err != nil {
		return nil, "", "", err
	}
	if len(variantsRaw) > 0 {
		_ = json.Unmarshal(variantsRaw, &p.VideoVariants)
	}
	if publishAt.Valid {
		p.PublishAt = &publishAt.Time
	}
	if p.Attachments == nil {
		p.Attachments = []models.PostAttachment{}
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
	return p, email, role, nil
}

// postColsQualified — same column list as `postCols` but with a table
// alias prepended so we can JOIN safely without ambiguity. Trailing two
// columns added by mig 0020 — keep in lockstep with postCols.
func postColsQualified(alias string) string {
	return alias + ".id, " +
		alias + ".target_type, " + alias + ".community_id, " + alias + ".expert_id, " +
		alias + ".author_id, " + alias + ".author_name, " +
		alias + ".title, " + alias + ".body, " + alias + ".ticker, " + alias + ".tickers, " + alias + ".stance, " +
		alias + ".upvotes, " + alias + ".likes, " + alias + ".comments_count, " + alias + ".created_at, " +
		alias + ".post_type, " + alias + ".media_url, " + alias + ".cover_url, " + alias + ".duration_seconds, " +
		alias + ".visibility, " +
		alias + ".is_hidden, " + alias + ".updated_at, " +
		alias + ".status, " + alias + ".publish_at, " + alias + ".video_variants"
}
