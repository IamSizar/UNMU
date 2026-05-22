package repositories

import (
	"database/sql"
	"strings"
	"time"

	"github.com/lib/pq"
)

// CommunityMessagesRepository — CRUD over `community_messages`
// (migration 0014). Drives the per-community real-time chat shipped
// in the mobile app: list (paginated, newest-first) + send.
//
// Membership checks live in the handler, not here — keep the repo
// dumb so different surfaces (REST, future admin tools, scheduled
// summarisation, etc.) can decide their own auth rules.
//
// `s3` is optional. When wired, every list/get path rewrites the
// `attachment_url` column through MediaURLResolver.MediaURL so voice
// messages and image attachments stay playable past the 7-day SigV4
// signature lifetime. See the [MediaURLResolver] interface in social.go.
type CommunityMessagesRepository struct {
	db *sql.DB
	s3 MediaURLResolver
}

func NewCommunityMessagesRepository(db *sql.DB) *CommunityMessagesRepository {
	return &CommunityMessagesRepository{db: db}
}

// SetS3Storage wires the URL resolver post-construction. Pass the same
// *S3Storage the upload handler uses; nil disables resolution.
func (r *CommunityMessagesRepository) SetS3Storage(s3 MediaURLResolver) {
	r.s3 = s3
}

// resolveAttachment swaps the AttachmentURL on each message for a
// freshly-signed S3 URL. Safe to call when r.s3 is nil (no-op).
func (r *CommunityMessagesRepository) resolveAttachment(msgs []*CommunityMessage) {
	if r.s3 == nil {
		return
	}
	for _, m := range msgs {
		if m != nil && m.AttachmentURL != "" {
			m.AttachmentURL = r.s3.MediaURL(m.AttachmentURL)
		}
	}
}

// CommunityMessage — one row in the chat. AuthorName + AuthorRole
// come from the joined users table so the client can render the
// bubble (avatar tint + name) without a follow-up call per message.
//
// When this message is a reply (`parent_id IS NOT NULL`), the
// `Parent*` fields are populated from a JOIN on the parent row so
// the quote preview renders self-contained — no per-bubble follow-up
// fetch.
type CommunityMessage struct {
	ID          int64     `json:"id"`
	CommunityID string    `json:"communityId"`
	AuthorID    int64     `json:"authorId"`
	AuthorName  string    `json:"authorName"`
	AuthorEmail string    `json:"authorEmail"`
	AuthorRole  string    `json:"authorRole"`
	Body        string    `json:"body"`
	CreatedAt   time.Time `json:"createdAt"`
	// Reply / quote fields. All three are zero-valued when this is
	// a top-level message (no parent).
	ParentID         int64  `json:"parentId,omitempty"`
	ParentAuthorName string `json:"parentAuthorName,omitempty"`
	ParentBody       string `json:"parentBody,omitempty"`
	// Reaction summary — populated by List() via a follow-up
	// aggregate query. ReactionCounts is `{emoji: count}`,
	// MyReactions is the set the current viewer has placed on
	// this message (drives the "highlighted chip" rendering).
	// Empty/nil for a freshly-inserted Send() row (the broadcast
	// payload — clients can assume zeroed reactions).
	ReactionCounts map[string]int `json:"reactionCounts,omitempty"`
	MyReactions    []string       `json:"myReactions,omitempty"`
	// Optional attachment — voice messages today, image/video
	// later. AttachmentURL is the public `/uploads/...` path the
	// client can play directly (not a presigned link).
	AttachmentURL        string `json:"attachmentUrl,omitempty"`
	AttachmentType       string `json:"attachmentType,omitempty"`
	AttachmentDurationMs int    `json:"attachmentDurationMs,omitempty"`
	// PinnedAt is non-nil when this message is pinned to the top of
	// the community chat. Owner-only action; the broadcast on
	// pin/unpin carries the toggled message struct so clients can
	// patch their local copy.
	PinnedAt *time.Time `json:"pinnedAt,omitempty"`

	// Step-21 (mig 0021, item 5.22) — edit tracking.
	// EditedAt non-nil → bubble shows "edited" pill.
	EditedAt *time.Time `json:"editedAt,omitempty"`

	// Step-21 (mig 0021, item 5.18) — read receipts.
	// ReadCount: total distinct readers excluding the author. Author
	// is implicitly considered "read".
	// MyRead: whether the current viewer has read it (drives the local
	// read-state — clients use this to skip POSTing read again).
	// Authors of messages whose readers have read_receipts_enabled=false
	// don't count those readers (mutual reciprocity).
	ReadCount int  `json:"readCount"`
	MyRead    bool `json:"myRead"`

	// Step-21 (mig 0021, item 5.21) — optional poll attachment.
	// Non-nil only on poll-style messages. The bubble renders the
	// poll widget instead of plain text body.
	Poll *PollSummary `json:"poll,omitempty"`
}

// PollSummary — denormalised poll data for inline rendering. Carries
// every option + the live vote tally + the viewer's choice (when any).
type PollSummary struct {
	ID          int64     `json:"id"`
	Question    string    `json:"question"`
	IsAnonymous bool      `json:"isAnonymous"`
	ClosedAt    *time.Time `json:"closedAt,omitempty"`
	ExpiresAt   *time.Time `json:"expiresAt,omitempty"`
	Options     []PollOption `json:"options"`
	TotalVotes  int       `json:"totalVotes"`
	MyOptionID  int64     `json:"myOptionId,omitempty"`
}

// PollOption — one row in a poll. Vote count is denormalised at read
// time; we don't store running totals to avoid drift on race conditions.
type PollOption struct {
	ID         int64  `json:"id"`
	Label      string `json:"label"`
	SortOrder  int    `json:"sortOrder"`
	VoteCount  int    `json:"voteCount"`
}

// IsMember — gate used by the handler before allowing list / send.
// Owner rows are included in `community_members` (seeded by 0014 +
// the proposal-approval flow) so this single check covers both.
func (r *CommunityMessagesRepository) IsMember(communityID string, userID int64) (bool, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT 1 FROM community_members
		  WHERE community_id = $1 AND user_id = $2 LIMIT 1`,
		communityID, userID,
	).Scan(&n)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// List returns up to [limit] most-recent messages in the community,
// optionally older than [before] for keyset pagination. Newest-first
// in the SQL; the client is responsible for reversing if it wants a
// chronological top-to-bottom render.
//
// Joins users so the client gets a ready-to-render row without an
// extra round-trip per author.
func (r *CommunityMessagesRepository) List(
	communityID string, before time.Time, limit int, viewerID int64,
) ([]*CommunityMessage, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	// LEFT JOIN parent so reply rows arrive with the parent's body +
	// author preview pre-populated; top-level rows get NULL parent
	// fields which scan into empty strings via NULLIF/COALESCE.
	q := `SELECT m.id, m.community_id, m.author_id,
	             COALESCE(NULLIF(u.name, ''), u.email),
	             u.email,
	             u.role,
	             m.body, m.created_at,
	             COALESCE(m.parent_id, 0)                       AS parent_id,
	             COALESCE(NULLIF(pu.name, ''), pu.email, '')    AS parent_author,
	             COALESCE(p.body, '')                            AS parent_body,
	             COALESCE(m.attachment_url, ''),
	             COALESCE(m.attachment_type, ''),
	             COALESCE(m.attachment_duration_ms, 0),
	             m.pinned_at,
	             m.edited_at
	        FROM community_messages m
	        JOIN users u ON u.id = m.author_id
	   LEFT JOIN community_messages p  ON p.id = m.parent_id
	   LEFT JOIN users pu              ON pu.id = p.author_id
	       WHERE m.community_id = $1`
	args := []any{communityID}
	if !before.IsZero() {
		args = append(args, before)
		q += ` AND m.created_at < $` + itoa(len(args))
	}
	args = append(args, limit)
	q += ` ORDER BY m.created_at DESC LIMIT $` + itoa(len(args))
	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*CommunityMessage, 0)
	for rows.Next() {
		var m CommunityMessage
		var pinnedAt sql.NullTime
		var editedAt sql.NullTime
		if err := rows.Scan(
			&m.ID, &m.CommunityID, &m.AuthorID,
			&m.AuthorName, &m.AuthorEmail, &m.AuthorRole,
			&m.Body, &m.CreatedAt,
			&m.ParentID, &m.ParentAuthorName, &m.ParentBody,
			&m.AttachmentURL, &m.AttachmentType, &m.AttachmentDurationMs,
			&pinnedAt, &editedAt,
		); err != nil {
			return nil, err
		}
		if pinnedAt.Valid {
			t := pinnedAt.Time
			m.PinnedAt = &t
		}
		if editedAt.Valid {
			t := editedAt.Time
			m.EditedAt = &t
		}
		// Truncate parent preview at 80 chars — matches the visual
		// budget on the receiving client and keeps the JSON payload
		// small even when someone replies to a 2000-char message.
		if len(m.ParentBody) > 80 {
			m.ParentBody = m.ParentBody[:80] + "…"
		}
		out = append(out, &m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Hydrate reaction counts + viewer's own reactions in a single
	// follow-up query keyed by message id. Skipped when the page is
	// empty (no message ids → nothing to aggregate).
	if len(out) == 0 {
		return out, nil
	}
	if err := r.hydrateReactions(out, viewerID); err != nil {
		return nil, err
	}
	// Step-21 (mig 0021, items 5.18 + 5.21) — read receipts + polls.
	// Best-effort; on error we surface the messages without enrichment
	// so the chat list never blocks on a failed sub-query.
	_ = r.hydrateReadReceipts(out, viewerID)
	_ = r.hydratePolls(out, viewerID)
	r.resolveAttachment(out)
	return out, nil
}

// hydrateReactions fills [ReactionCounts] and [MyReactions] on every
// message in [msgs] via a single aggregate query.
//
// Two passes:
//
//  1. SELECT message_id, emoji, COUNT(*)  → counts per emoji.
//  2. SELECT message_id, emoji WHERE user_id = viewer  → my reactions.
//
// Worst case at limit=200 messages × 4 emojis = 800 rows; trivial.
func (r *CommunityMessagesRepository) hydrateReactions(
	msgs []*CommunityMessage, viewerID int64,
) error {
	ids := make([]int64, 0, len(msgs))
	byID := make(map[int64]*CommunityMessage, len(msgs))
	for _, m := range msgs {
		ids = append(ids, m.ID)
		byID[m.ID] = m
		// Pre-init so the JSON shape is stable even when the
		// message has zero reactions — clients can iterate without
		// nil-checking.
		m.ReactionCounts = map[string]int{}
		m.MyReactions = []string{}
	}
	// Counts.
	rows, err := r.db.Query(
		`SELECT message_id, emoji, COUNT(*)
		   FROM community_message_reactions
		  WHERE message_id = ANY($1)
		  GROUP BY message_id, emoji`,
		pq.Array(ids),
	)
	if err != nil {
		return err
	}
	for rows.Next() {
		var mid int64
		var emoji string
		var count int
		if err := rows.Scan(&mid, &emoji, &count); err != nil {
			rows.Close()
			return err
		}
		if m, ok := byID[mid]; ok {
			m.ReactionCounts[emoji] = count
		}
	}
	rows.Close()
	if viewerID <= 0 {
		return nil
	}
	// Viewer's own reactions.
	mineRows, err := r.db.Query(
		`SELECT message_id, emoji
		   FROM community_message_reactions
		  WHERE user_id = $1 AND message_id = ANY($2)`,
		viewerID, pq.Array(ids),
	)
	if err != nil {
		return err
	}
	defer mineRows.Close()
	for mineRows.Next() {
		var mid int64
		var emoji string
		if err := mineRows.Scan(&mid, &emoji); err != nil {
			return err
		}
		if m, ok := byID[mid]; ok {
			m.MyReactions = append(m.MyReactions, emoji)
		}
	}
	return mineRows.Err()
}

// ParentInCommunity — returns true if [parentID] exists AND lives in
// [communityID]. Used by the Send handler to defend against a reply
// pointing to a message in a different community (which would
// otherwise leak content across community boundaries via the JOIN
// preview). Cheap query — single index hit on the PK.
func (r *CommunityMessagesRepository) ParentInCommunity(
	parentID int64, communityID string,
) (bool, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT 1 FROM community_messages
		  WHERE id = $1 AND community_id = $2 LIMIT 1`,
		parentID, communityID,
	).Scan(&n)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// SendOptions groups the optional fields on Send so the signature
// stays manageable as the schema grows. Zero values are safe defaults
// — empty strings + 0 for ints all map to NULL in the column.
type SendOptions struct {
	ParentID             int64
	AttachmentURL        string
	AttachmentType       string
	AttachmentDurationMs int
}

// Send inserts one message + returns the row hydrated with the joined
// user fields so the caller can broadcast it on the realtime channel
// without a second query.
//
// [body] may be empty when [opts.AttachmentURL] is set — voice
// messages typically have an empty body. The DB-level CHECK
// constraint enforces "at least one of body/attachment".
func (r *CommunityMessagesRepository) Send(
	communityID string, authorID int64, body string, opts SendOptions,
) (*CommunityMessage, error) {
	body = strings.TrimSpace(body)
	if body == "" && strings.TrimSpace(opts.AttachmentURL) == "" {
		return nil, sql.ErrNoRows
	}
	var parent sql.NullInt64
	if opts.ParentID > 0 {
		parent = sql.NullInt64{Int64: opts.ParentID, Valid: true}
	}
	var attUrl, attType sql.NullString
	if s := strings.TrimSpace(opts.AttachmentURL); s != "" {
		attUrl = sql.NullString{String: s, Valid: true}
	}
	if s := strings.TrimSpace(opts.AttachmentType); s != "" {
		attType = sql.NullString{String: s, Valid: true}
	}
	var attDur sql.NullInt32
	if opts.AttachmentDurationMs > 0 {
		attDur = sql.NullInt32{Int32: int32(opts.AttachmentDurationMs), Valid: true}
	}

	row := r.db.QueryRow(
		`WITH ins AS (
		   INSERT INTO community_messages
		     (community_id, author_id, body, parent_id,
		      attachment_url, attachment_type, attachment_duration_ms)
		   VALUES ($1, $2, $3, $4, $5, $6, $7)
		   RETURNING id, community_id, author_id, body, created_at, parent_id,
		             attachment_url, attachment_type, attachment_duration_ms,
		             pinned_at
		 )
		 SELECT ins.id, ins.community_id, ins.author_id,
		        COALESCE(NULLIF(u.name, ''), u.email),
		        u.email,
		        u.role,
		        ins.body, ins.created_at,
		        COALESCE(ins.parent_id, 0),
		        COALESCE(NULLIF(pu.name, ''), pu.email, ''),
		        COALESCE(p.body, ''),
		        COALESCE(ins.attachment_url, ''),
		        COALESCE(ins.attachment_type, ''),
		        COALESCE(ins.attachment_duration_ms, 0),
		        ins.pinned_at
		   FROM ins
		   JOIN users u  ON u.id = ins.author_id
		   LEFT JOIN community_messages p ON p.id = ins.parent_id
		   LEFT JOIN users pu ON pu.id = p.author_id`,
		communityID, authorID, body, parent, attUrl, attType, attDur,
	)
	var m CommunityMessage
	var pinnedAt sql.NullTime
	if err := row.Scan(
		&m.ID, &m.CommunityID, &m.AuthorID,
		&m.AuthorName, &m.AuthorEmail, &m.AuthorRole,
		&m.Body, &m.CreatedAt,
		&m.ParentID, &m.ParentAuthorName, &m.ParentBody,
		&m.AttachmentURL, &m.AttachmentType, &m.AttachmentDurationMs,
		&pinnedAt,
	); err != nil {
		return nil, err
	}
	if pinnedAt.Valid {
		t := pinnedAt.Time
		m.PinnedAt = &t
	}
	if len(m.ParentBody) > 80 {
		m.ParentBody = m.ParentBody[:80] + "…"
	}
	r.resolveAttachment([]*CommunityMessage{&m})
	return &m, nil
}

// ───────── Reactions ──────────────────────────────────────────────

// Delete removes a message. Authorization is enforced here:
//
//   - the row's author can always delete their own message,
//   - an admin (isAdmin == true) can delete anyone's,
//   - the community owner (canModerate == true) can delete anyone's
//     within their community,
//   - everyone else gets sql.ErrNoRows back so the handler can
//     map it to 403/404 cleanly.
//
// Cascade rules from the migrations handle the cleanup:
//   - community_message_reactions: ON DELETE CASCADE → all reactions
//     on the deleted message disappear with it.
//   - replies whose parent_id pointed at this row: ON DELETE SET NULL,
//     so they survive but lose their parent (which the read path
//     already tolerates via COALESCE).
func (r *CommunityMessagesRepository) Delete(
	messageID, userID int64, canModerate bool,
) error {
	var q string
	var args []any
	if canModerate {
		// Admin or community-owner override — allow deleting any
		// message regardless of authorship.
		q = `DELETE FROM community_messages WHERE id = $1`
		args = []any{messageID}
	} else {
		q = `DELETE FROM community_messages WHERE id = $1 AND author_id = $2`
		args = []any{messageID, userID}
	}
	res, err := r.db.Exec(q, args...)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		// Either the message doesn't exist, or it's not the user's
		// and they're not authorized to moderate. Same error from
		// the repo's POV; handler decides whether to surface as
		// 403 or 404.
		return sql.ErrNoRows
	}
	return nil
}

// TogglePin flips a message's pin state. If currently unpinned the
// row's `pinned_at` is set to NOW(); if currently pinned it's
// cleared. Returns the resulting `pinned_at` value (nil = unpinned)
// so the broadcast payload can carry it.
//
// Authorization (must be community owner OR admin) is enforced in
// the handler — this repo method just executes the toggle.
func (r *CommunityMessagesRepository) TogglePin(messageID int64) (*time.Time, error) {
	var current sql.NullTime
	err := r.db.QueryRow(
		`SELECT pinned_at FROM community_messages WHERE id = $1`,
		messageID,
	).Scan(&current)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, err
	}
	if current.Valid {
		// Currently pinned → unpin.
		_, err = r.db.Exec(
			`UPDATE community_messages SET pinned_at = NULL WHERE id = $1`,
			messageID,
		)
		if err != nil {
			return nil, err
		}
		return nil, nil
	}
	// Currently unpinned → pin (NOW()).
	var newPin time.Time
	err = r.db.QueryRow(
		`UPDATE community_messages SET pinned_at = NOW() WHERE id = $1
		 RETURNING pinned_at`,
		messageID,
	).Scan(&newPin)
	if err != nil {
		return nil, err
	}
	return &newPin, nil
}

// MessageBelongsTo returns the community id for [messageID] (or empty
// string when the row doesn't exist). Used by the reactions handlers
// to validate the message is in the community the URL claims, before
// running the member gate against that community.
func (r *CommunityMessagesRepository) MessageBelongsTo(messageID int64) (string, error) {
	var cid string
	err := r.db.QueryRow(
		`SELECT community_id FROM community_messages WHERE id = $1`,
		messageID,
	).Scan(&cid)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return cid, nil
}

// ToggleReaction enforces a "one reaction per user per message" rule:
//
//   - tapping the same emoji you already reacted with → remove it
//     (you now have no reaction).
//   - tapping a different emoji → replace the previous one
//     (DELETE old + INSERT new in a single tx).
//   - tapping when you had nothing → insert.
//
// Returns:
//   - added    : true when the user ends up WITH this emoji (insert
//                or replace path), false when the user ended up
//                without it (toggle-off path).
//   - newCount : the post-toggle count of rows for (messageID, emoji).
//   - allCounts: the post-toggle full {emoji: count} map for the
//                message — broadcast payload + reconcile source.
func (r *CommunityMessagesRepository) ToggleReaction(
	messageID, userID int64, emoji string,
) (added bool, newCount int, allCounts map[string]int, err error) {
	emoji = strings.TrimSpace(emoji)
	if emoji == "" {
		return false, 0, nil, sql.ErrNoRows
	}
	// Find the user's CURRENT reaction on this message (if any).
	var current sql.NullString
	row := r.db.QueryRow(
		`SELECT emoji FROM community_message_reactions
		  WHERE message_id = $1 AND user_id = $2 LIMIT 1`,
		messageID, userID,
	)
	if scanErr := row.Scan(&current); scanErr != nil && scanErr != sql.ErrNoRows {
		return false, 0, nil, scanErr
	}

	// Wrap the mutation in a tx so a "replace" never leaves the user
	// reactionless mid-flight (visible to a concurrent List call).
	tx, err := r.db.Begin()
	if err != nil {
		return false, 0, nil, err
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	if current.Valid && current.String == emoji {
		// Same emoji → toggle off (remove).
		_, err = tx.Exec(
			`DELETE FROM community_message_reactions
			  WHERE message_id = $1 AND user_id = $2 AND emoji = $3`,
			messageID, userID, emoji,
		)
		if err != nil {
			return false, 0, nil, err
		}
		added = false
	} else {
		// Different emoji (or none) → replace.
		if current.Valid {
			_, err = tx.Exec(
				`DELETE FROM community_message_reactions
				  WHERE message_id = $1 AND user_id = $2`,
				messageID, userID,
			)
			if err != nil {
				return false, 0, nil, err
			}
		}
		_, err = tx.Exec(
			`INSERT INTO community_message_reactions (message_id, user_id, emoji)
			 VALUES ($1, $2, $3)
			 ON CONFLICT (message_id, user_id, emoji) DO NOTHING`,
			messageID, userID, emoji,
		)
		if err != nil {
			return false, 0, nil, err
		}
		added = true
	}
	if err = tx.Commit(); err != nil {
		return false, 0, nil, err
	}

	// Recompute the message's full reaction map.
	rows, qerr := r.db.Query(
		`SELECT emoji, COUNT(*)
		   FROM community_message_reactions
		  WHERE message_id = $1
		  GROUP BY emoji`,
		messageID,
	)
	if qerr != nil {
		return added, 0, nil, qerr
	}
	defer rows.Close()
	allCounts = map[string]int{}
	for rows.Next() {
		var e string
		var n int
		if serr := rows.Scan(&e, &n); serr != nil {
			return added, 0, nil, serr
		}
		allCounts[e] = n
		if e == emoji {
			newCount = n
		}
	}
	if rerr := rows.Err(); rerr != nil {
		return added, 0, nil, rerr
	}
	return added, newCount, allCounts, nil
}

// Reactor — one entry in the "who reacted" detail sheet.
type Reactor struct {
	UserID   int64     `json:"userId"`
	UserName string    `json:"userName"`
	Email    string    `json:"email"`
	Role     string    `json:"role"`
	Emoji    string    `json:"emoji"`
	At       time.Time `json:"at"`
}

// ListReactors returns every reaction on [messageID] joined to the
// reactor's display name + role. Newest reactions first so the bottom
// sheet's per-emoji tabs read most-recent → oldest.
func (r *CommunityMessagesRepository) ListReactors(messageID int64) ([]*Reactor, error) {
	rows, err := r.db.Query(
		`SELECT r.user_id,
		        COALESCE(NULLIF(u.name, ''), u.email),
		        u.email, u.role, r.emoji, r.created_at
		   FROM community_message_reactions r
		   JOIN users u ON u.id = r.user_id
		  WHERE r.message_id = $1
		  ORDER BY r.created_at DESC`,
		messageID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*Reactor, 0)
	for rows.Next() {
		var x Reactor
		if err := rows.Scan(
			&x.UserID, &x.UserName, &x.Email, &x.Role, &x.Emoji, &x.At,
		); err != nil {
			return nil, err
		}
		out = append(out, &x)
	}
	return out, rows.Err()
}

// =============================================================================
// Step-21 (mig 0021) — search, edit, read receipts, polls
// =============================================================================

// hydrateReadReceipts fills `ReadCount` + `MyRead` on every message in
// [msgs]. Excludes the message author from the count (authors are
// implicitly considered read). Honours the per-user opt-out — a reader
// with read_receipts_enabled=FALSE is removed from the count for
// reciprocity.
//
// Single batched query keyed by message id — one round-trip regardless
// of page size.
func (r *CommunityMessagesRepository) hydrateReadReceipts(
	msgs []*CommunityMessage, viewerID int64,
) error {
	if len(msgs) == 0 {
		return nil
	}
	ids := make([]int64, 0, len(msgs))
	byID := make(map[int64]*CommunityMessage, len(msgs))
	for _, m := range msgs {
		ids = append(ids, m.ID)
		byID[m.ID] = m
	}
	// Counts excluding author + opt-outs.
	rows, err := r.db.Query(
		`SELECT mr.message_id, COUNT(*)
		   FROM community_message_reads mr
		   JOIN users u ON u.id = mr.user_id
		   JOIN community_messages m ON m.id = mr.message_id
		  WHERE mr.message_id = ANY($1)
		    AND u.read_receipts_enabled = TRUE
		    AND mr.user_id <> m.author_id
		  GROUP BY mr.message_id`,
		pq.Array(ids),
	)
	if err != nil {
		return err
	}
	for rows.Next() {
		var mid int64
		var c int
		if err := rows.Scan(&mid, &c); err != nil {
			rows.Close()
			return err
		}
		if m, ok := byID[mid]; ok {
			m.ReadCount = c
		}
	}
	rows.Close()
	if viewerID <= 0 {
		return nil
	}
	// Viewer's own reads — drives the local "I've already read" flag.
	myRows, err := r.db.Query(
		`SELECT message_id FROM community_message_reads
		  WHERE user_id = $1 AND message_id = ANY($2)`,
		viewerID, pq.Array(ids),
	)
	if err != nil {
		return err
	}
	defer myRows.Close()
	for myRows.Next() {
		var mid int64
		if err := myRows.Scan(&mid); err != nil {
			return err
		}
		if m, ok := byID[mid]; ok {
			m.MyRead = true
		}
	}
	return myRows.Err()
}

// hydratePolls fills `Poll` on every message in [msgs] that has a poll
// attached. Two queries — polls + options keyed by message_id, then
// votes by poll_id. Caller's vote (`MyOptionID`) is filled per
// [viewerID] when non-zero.
func (r *CommunityMessagesRepository) hydratePolls(
	msgs []*CommunityMessage, viewerID int64,
) error {
	if len(msgs) == 0 {
		return nil
	}
	msgIDs := make([]int64, 0, len(msgs))
	byMsgID := make(map[int64]*CommunityMessage, len(msgs))
	for _, m := range msgs {
		msgIDs = append(msgIDs, m.ID)
		byMsgID[m.ID] = m
	}
	pollRows, err := r.db.Query(
		`SELECT id, message_id, question, is_anonymous, closed_at, expires_at
		   FROM community_polls
		  WHERE message_id = ANY($1)`,
		pq.Array(msgIDs),
	)
	if err != nil {
		return err
	}
	pollByMsg := make(map[int64]*PollSummary)
	pollIDs := make([]int64, 0)
	for pollRows.Next() {
		var p PollSummary
		var msgID int64
		var closedAt, expiresAt sql.NullTime
		if err := pollRows.Scan(
			&p.ID, &msgID, &p.Question, &p.IsAnonymous, &closedAt, &expiresAt,
		); err != nil {
			pollRows.Close()
			return err
		}
		if closedAt.Valid {
			t := closedAt.Time
			p.ClosedAt = &t
		}
		if expiresAt.Valid {
			t := expiresAt.Time
			p.ExpiresAt = &t
		}
		p.Options = []PollOption{}
		pollByMsg[msgID] = &p
		pollIDs = append(pollIDs, p.ID)
	}
	pollRows.Close()
	if len(pollIDs) == 0 {
		return nil
	}
	// Options + counts in one query.
	optRows, err := r.db.Query(
		`SELECT o.id, o.poll_id, o.label, o.sort_order,
		        (SELECT COUNT(*) FROM community_poll_votes v
		          WHERE v.option_id = o.id)
		   FROM community_poll_options o
		  WHERE o.poll_id = ANY($1)
		  ORDER BY o.sort_order ASC, o.id ASC`,
		pq.Array(pollIDs),
	)
	if err != nil {
		return err
	}
	pollByID := make(map[int64]*PollSummary, len(pollIDs))
	for _, p := range pollByMsg {
		pollByID[p.ID] = p
	}
	for optRows.Next() {
		var o PollOption
		var pollID int64
		if err := optRows.Scan(
			&o.ID, &pollID, &o.Label, &o.SortOrder, &o.VoteCount,
		); err != nil {
			optRows.Close()
			return err
		}
		if p, ok := pollByID[pollID]; ok {
			p.Options = append(p.Options, o)
			p.TotalVotes += o.VoteCount
		}
	}
	optRows.Close()
	// Viewer's vote — single query keyed by poll_id.
	if viewerID > 0 {
		myRows, err := r.db.Query(
			`SELECT poll_id, option_id FROM community_poll_votes
			  WHERE user_id = $1 AND poll_id = ANY($2)`,
			viewerID, pq.Array(pollIDs),
		)
		if err != nil {
			return err
		}
		for myRows.Next() {
			var pid, oid int64
			if err := myRows.Scan(&pid, &oid); err != nil {
				myRows.Close()
				return err
			}
			if p, ok := pollByID[pid]; ok {
				p.MyOptionID = oid
			}
		}
		myRows.Close()
	}
	// Attach to the host message.
	for msgID, p := range pollByMsg {
		if m, ok := byMsgID[msgID]; ok {
			m.Poll = p
		}
	}
	return nil
}

// MarkRead inserts a read row for [userID] / [messageID]. Idempotent —
// re-reading is a silent no-op via ON CONFLICT.
//
// Skipped silently when the user has read_receipts_enabled=FALSE so
// their reads stop accumulating in the DB the moment they opt out
// (mutual reciprocity from the author's perspective is enforced at
// hydrateReadReceipts time).
func (r *CommunityMessagesRepository) MarkRead(messageID, userID int64) error {
	// Honour the per-user opt-out before writing.
	var enabled bool
	if err := r.db.QueryRow(
		`SELECT read_receipts_enabled FROM users WHERE id = $1`,
		userID,
	).Scan(&enabled); err != nil {
		return err
	}
	if !enabled {
		return nil
	}
	_, err := r.db.Exec(
		`INSERT INTO community_message_reads (message_id, user_id)
		 VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		messageID, userID,
	)
	return err
}

// MarkBatchRead — same as MarkRead but for many messages at once.
// Returns the count actually inserted (already-read rows skip via
// ON CONFLICT and don't bump the count).
func (r *CommunityMessagesRepository) MarkBatchRead(
	messageIDs []int64, userID int64,
) (int, error) {
	if len(messageIDs) == 0 {
		return 0, nil
	}
	var enabled bool
	if err := r.db.QueryRow(
		`SELECT read_receipts_enabled FROM users WHERE id = $1`,
		userID,
	).Scan(&enabled); err != nil {
		return 0, err
	}
	if !enabled {
		return 0, nil
	}
	// One INSERT … SELECT unnest avoids round-trip-per-row.
	res, err := r.db.Exec(
		`INSERT INTO community_message_reads (message_id, user_id)
		 SELECT m, $2 FROM unnest($1::bigint[]) AS m
		 ON CONFLICT DO NOTHING`,
		pq.Array(messageIDs), userID,
	)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return int(n), nil
}

// ListReaders — names + read time of every user who's read [messageID].
// Honours opt-out: users with read_receipts_enabled=FALSE are excluded.
// Used by the "Seen by N" → avatar-list sheet.
func (r *CommunityMessagesRepository) ListReaders(
	messageID int64,
) ([]*Reader, error) {
	rows, err := r.db.Query(
		`SELECT mr.user_id,
		        COALESCE(NULLIF(u.name, ''), u.email),
		        u.email, u.role, mr.read_at
		   FROM community_message_reads mr
		   JOIN users u ON u.id = mr.user_id
		   JOIN community_messages m ON m.id = mr.message_id
		  WHERE mr.message_id = $1
		    AND u.read_receipts_enabled = TRUE
		    AND mr.user_id <> m.author_id
		  ORDER BY mr.read_at DESC`,
		messageID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*Reader, 0)
	for rows.Next() {
		var x Reader
		if err := rows.Scan(
			&x.UserID, &x.Name, &x.Email, &x.Role, &x.ReadAt,
		); err != nil {
			return nil, err
		}
		out = append(out, &x)
	}
	return out, rows.Err()
}

// Reader — one row in the "Seen by" sheet.
type Reader struct {
	UserID int64     `json:"userId"`
	Name   string    `json:"name"`
	Email  string    `json:"email"`
	Role   string    `json:"role"`
	ReadAt time.Time `json:"readAt"`
}

// SetReadReceiptsEnabled flips the per-user toggle. When disabling,
// existing reads stay in the DB (deleting them on opt-out would create
// a "ghost" effect for senders who had already seen the receipt) — but
// from the moment of disable, no new reads are recorded AND existing
// ones are filtered from `hydrateReadReceipts`.
func (r *CommunityMessagesRepository) SetReadReceiptsEnabled(
	userID int64, enabled bool,
) error {
	_, err := r.db.Exec(
		`UPDATE users SET read_receipts_enabled = $1 WHERE id = $2`,
		enabled, userID,
	)
	return err
}

// GetReadReceiptsEnabled reads the toggle. Used by the "settings"
// surface to render the Switch's initial state.
func (r *CommunityMessagesRepository) GetReadReceiptsEnabled(
	userID int64,
) (bool, error) {
	var enabled bool
	err := r.db.QueryRow(
		`SELECT read_receipts_enabled FROM users WHERE id = $1`,
		userID,
	).Scan(&enabled)
	return enabled, err
}

// EditMessage — rewrites [body] on a message. Returns sql.ErrNoRows
// when the message doesn't exist OR the editor isn't the author OR
// the 15-min edit window has passed.
//
// Captures the original body on the first edit only (leaves
// original_body alone on subsequent edits) so the moderator's
// "edited from X to Y" view always shows the original-original.
const editWindowSeconds = 15 * 60

func (r *CommunityMessagesRepository) EditMessage(
	messageID, editorID int64, body string,
) (*CommunityMessage, error) {
	body = strings.TrimSpace(body)
	if body == "" {
		return nil, sql.ErrNoRows
	}
	res, err := r.db.Exec(
		`UPDATE community_messages
		    SET original_body = COALESCE(original_body, body),
		        body          = $1,
		        edited_at     = NOW()
		  WHERE id = $2
		    AND author_id = $3
		    AND created_at > NOW() - $4 * INTERVAL '1 second'`,
		body, messageID, editorID, editWindowSeconds,
	)
	if err != nil {
		return nil, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return nil, sql.ErrNoRows
	}
	return r.GetByID(messageID, editorID)
}

// GetByID — single-row fetch hydrated like List(). Used by the edit
// handler to broadcast the updated row, and by the realtime side
// after a poll vote so clients can patch their local copy.
func (r *CommunityMessagesRepository) GetByID(
	messageID, viewerID int64,
) (*CommunityMessage, error) {
	row := r.db.QueryRow(
		`SELECT m.id, m.community_id, m.author_id,
		        COALESCE(NULLIF(u.name, ''), u.email),
		        u.email, u.role,
		        m.body, m.created_at,
		        COALESCE(m.parent_id, 0),
		        COALESCE(NULLIF(pu.name, ''), pu.email, ''),
		        COALESCE(p.body, ''),
		        COALESCE(m.attachment_url, ''),
		        COALESCE(m.attachment_type, ''),
		        COALESCE(m.attachment_duration_ms, 0),
		        m.pinned_at, m.edited_at
		   FROM community_messages m
		   JOIN users u ON u.id = m.author_id
		   LEFT JOIN community_messages p ON p.id = m.parent_id
		   LEFT JOIN users pu ON pu.id = p.author_id
		  WHERE m.id = $1`,
		messageID,
	)
	var m CommunityMessage
	var pinnedAt, editedAt sql.NullTime
	if err := row.Scan(
		&m.ID, &m.CommunityID, &m.AuthorID,
		&m.AuthorName, &m.AuthorEmail, &m.AuthorRole,
		&m.Body, &m.CreatedAt,
		&m.ParentID, &m.ParentAuthorName, &m.ParentBody,
		&m.AttachmentURL, &m.AttachmentType, &m.AttachmentDurationMs,
		&pinnedAt, &editedAt,
	); err != nil {
		return nil, err
	}
	if pinnedAt.Valid {
		t := pinnedAt.Time
		m.PinnedAt = &t
	}
	if editedAt.Valid {
		t := editedAt.Time
		m.EditedAt = &t
	}
	one := []*CommunityMessage{&m}
	_ = r.hydrateReactions(one, viewerID)
	_ = r.hydrateReadReceipts(one, viewerID)
	_ = r.hydratePolls(one, viewerID)
	r.resolveAttachment(one)
	return &m, nil
}

// SearchResult — one row in the chat-search response. Includes the
// surrounding context the client can use for a "jump-to" affordance.
type SearchResult struct {
	*CommunityMessage
}

// Search — full-text + ILIKE against community_messages.body, scoped
// to a single community. Only members may call this (the handler
// enforces); the repo trusts its inputs.
//
// Limits to 50 results, newest-first. Empty query returns empty slice
// (not an error) so the UI's blank-search state is trivially handled.
func (r *CommunityMessagesRepository) Search(
	communityID, query string, viewerID int64,
) ([]*CommunityMessage, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return []*CommunityMessage{}, nil
	}
	// Two-pronged: tsvector match for word boundaries + ILIKE for
	// substring (catches partial cashtags, partial words). We OR them
	// so either matches.
	rows, err := r.db.Query(`
		SELECT m.id, m.community_id, m.author_id,
		       COALESCE(NULLIF(u.name, ''), u.email),
		       u.email, u.role,
		       m.body, m.created_at,
		       COALESCE(m.parent_id, 0),
		       COALESCE(NULLIF(pu.name, ''), pu.email, ''),
		       COALESCE(p.body, ''),
		       COALESCE(m.attachment_url, ''),
		       COALESCE(m.attachment_type, ''),
		       COALESCE(m.attachment_duration_ms, 0),
		       m.pinned_at, m.edited_at
		  FROM community_messages m
		  JOIN users u ON u.id = m.author_id
		  LEFT JOIN community_messages p ON p.id = m.parent_id
		  LEFT JOIN users pu ON pu.id = p.author_id
		 WHERE m.community_id = $1
		   AND (m.search_tsv @@ plainto_tsquery('simple', $2)
		        OR m.body ILIKE '%' || $2 || '%')
		 ORDER BY m.created_at DESC
		 LIMIT 50`,
		communityID, query,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*CommunityMessage, 0)
	for rows.Next() {
		var m CommunityMessage
		var pinnedAt, editedAt sql.NullTime
		if err := rows.Scan(
			&m.ID, &m.CommunityID, &m.AuthorID,
			&m.AuthorName, &m.AuthorEmail, &m.AuthorRole,
			&m.Body, &m.CreatedAt,
			&m.ParentID, &m.ParentAuthorName, &m.ParentBody,
			&m.AttachmentURL, &m.AttachmentType, &m.AttachmentDurationMs,
			&pinnedAt, &editedAt,
		); err != nil {
			return nil, err
		}
		if pinnedAt.Valid {
			t := pinnedAt.Time
			m.PinnedAt = &t
		}
		if editedAt.Valid {
			t := editedAt.Time
			m.EditedAt = &t
		}
		out = append(out, &m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	_ = r.hydrateReactions(out, viewerID)
	_ = r.hydratePolls(out, viewerID)
	r.resolveAttachment(out)
	return out, nil
}
