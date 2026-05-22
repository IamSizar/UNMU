package repositories

import (
	"database/sql"
	"errors"
	"strings"
	"time"
)

// CommunityPollsRepository — CRUD over community_polls /
// community_poll_options / community_poll_votes (mig 0021, item 5.21).
//
// A poll always hangs off a host community_message — creation always
// inserts a message FIRST, then the poll referencing that message_id.
// We do this in one transaction so a stranded poll (or stranded
// message) is impossible.
type CommunityPollsRepository struct {
	db *sql.DB
}

func NewCommunityPollsRepository(db *sql.DB) *CommunityPollsRepository {
	return &CommunityPollsRepository{db: db}
}

// CreatePollInput — fields the handler validates + passes to Create().
type CreatePollInput struct {
	CommunityID string
	AuthorID    int64
	Question    string
	Options     []string  // 2..4 entries, each ≤ 60 chars (handler-enforced)
	IsAnonymous bool
	ExpiresAt   *time.Time // nil = open-ended
}

// CreatedPoll — the (message_id, poll_id) pair returned by Create() so
// the handler can fetch the freshly hydrated CommunityMessage and
// broadcast it.
type CreatedPoll struct {
	MessageID int64
	PollID    int64
}

// Create inserts a host message, the poll itself, and every option
// inside one transaction. Body of the host message is set to the
// question (first 200 chars) so non-poll-aware clients still see
// something meaningful.
//
// Returns the new IDs; caller looks up the hydrated row via
// CommunityMessagesRepository.GetByID for the broadcast payload.
func (r *CommunityPollsRepository) Create(in CreatePollInput) (*CreatedPoll, error) {
	if len(in.Options) < 2 || len(in.Options) > 4 {
		return nil, errors.New("polls need 2..4 options")
	}
	q := strings.TrimSpace(in.Question)
	if q == "" {
		return nil, errors.New("poll question required")
	}
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// 1. Host message — body mirrors the question so existing chat
	//    clients render *something* until they upgrade to poll-aware
	//    rendering.
	var msgID int64
	if err := tx.QueryRow(
		`INSERT INTO community_messages (community_id, author_id, body)
		 VALUES ($1, $2, $3) RETURNING id`,
		in.CommunityID, in.AuthorID, q,
	).Scan(&msgID); err != nil {
		return nil, err
	}

	// 2. Poll row.
	var pollID int64
	var expiresArg any
	if in.ExpiresAt != nil {
		expiresArg = *in.ExpiresAt
	}
	if err := tx.QueryRow(
		`INSERT INTO community_polls
		     (message_id, community_id, author_id, question,
		      is_anonymous, expires_at)
		 VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
		msgID, in.CommunityID, in.AuthorID, q, in.IsAnonymous, expiresArg,
	).Scan(&pollID); err != nil {
		return nil, err
	}

	// 3. Options.
	for i, label := range in.Options {
		label = strings.TrimSpace(label)
		if label == "" {
			return nil, errors.New("option labels can't be empty")
		}
		if _, err := tx.Exec(
			`INSERT INTO community_poll_options (poll_id, label, sort_order)
			 VALUES ($1, $2, $3)`,
			pollID, label, i,
		); err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &CreatedPoll{MessageID: msgID, PollID: pollID}, nil
}

// Vote casts (or replaces) a vote for [userID] on [pollID]. Returns
// sql.ErrNoRows when the poll is closed, the option doesn't belong to
// the poll, or the poll itself doesn't exist.
//
// Replace-on-revote semantics: a user voting for a different option
// on the same poll quietly overwrites their previous vote.
func (r *CommunityPollsRepository) Vote(
	pollID, optionID, userID int64,
) error {
	// Validate poll is open + option belongs to poll.
	var closed bool
	if err := r.db.QueryRow(
		`SELECT (closed_at IS NOT NULL OR
		         (expires_at IS NOT NULL AND expires_at <= NOW()))
		   FROM community_polls WHERE id = $1`,
		pollID,
	).Scan(&closed); err != nil {
		return err
	}
	if closed {
		return errors.New("poll closed")
	}
	var ok bool
	if err := r.db.QueryRow(
		`SELECT EXISTS(SELECT 1 FROM community_poll_options
		                WHERE id = $1 AND poll_id = $2)`,
		optionID, pollID,
	).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return sql.ErrNoRows
	}
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(
		`DELETE FROM community_poll_votes
		  WHERE poll_id = $1 AND user_id = $2`,
		pollID, userID,
	); err != nil {
		return err
	}
	if _, err := tx.Exec(
		`INSERT INTO community_poll_votes (poll_id, option_id, user_id)
		 VALUES ($1, $2, $3)`,
		pollID, optionID, userID,
	); err != nil {
		return err
	}
	return tx.Commit()
}

// Close flips closed_at to NOW() if not already closed. Returns
// sql.ErrNoRows when the poll doesn't exist; returns nil (no-op) if
// already closed so callers can be idempotent.
func (r *CommunityPollsRepository) Close(pollID int64) error {
	res, err := r.db.Exec(
		`UPDATE community_polls SET closed_at = NOW()
		  WHERE id = $1 AND closed_at IS NULL`,
		pollID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		// Already closed or doesn't exist — distinguish.
		var exists bool
		_ = r.db.QueryRow(
			`SELECT EXISTS(SELECT 1 FROM community_polls WHERE id = $1)`,
			pollID,
		).Scan(&exists)
		if !exists {
			return sql.ErrNoRows
		}
	}
	return nil
}

// PollOwner returns the poll's author_id and host community_id. Used
// by the handler to gate the close endpoint (author or community
// owner only).
func (r *CommunityPollsRepository) PollOwner(
	pollID int64,
) (authorID int64, communityID string, msgID int64, err error) {
	err = r.db.QueryRow(
		`SELECT author_id, community_id, message_id
		   FROM community_polls WHERE id = $1`,
		pollID,
	).Scan(&authorID, &communityID, &msgID)
	return
}

// PromoteExpiringPolls flips expires_at-passed polls to closed.
// Returns the message ids of the freshly closed polls so the
// scheduler can broadcast a `poll_closed` realtime event for each.
func (r *CommunityPollsRepository) PromoteExpiringPolls() ([]int64, []string, []int64, error) {
	rows, err := r.db.Query(
		`UPDATE community_polls
		    SET closed_at = NOW()
		  WHERE closed_at IS NULL
		    AND expires_at IS NOT NULL
		    AND expires_at <= NOW()
		  RETURNING id, community_id, message_id`,
	)
	if err != nil {
		return nil, nil, nil, err
	}
	defer rows.Close()
	pollIDs := []int64{}
	communityIDs := []string{}
	msgIDs := []int64{}
	for rows.Next() {
		var pid, mid int64
		var cid string
		if err := rows.Scan(&pid, &cid, &mid); err != nil {
			return nil, nil, nil, err
		}
		pollIDs = append(pollIDs, pid)
		communityIDs = append(communityIDs, cid)
		msgIDs = append(msgIDs, mid)
	}
	return pollIDs, communityIDs, msgIDs, rows.Err()
}

// =============================================================================
// Admin-side queries — used by the dashboard's polls panel. Bypass the
// member-gate; admin sees every poll across every community.
// =============================================================================

// AdminPollRow — denormalised shape for the admin polls list.
type AdminPollRow struct {
	ID          int64      `json:"id"`
	MessageID   int64      `json:"messageId"`
	CommunityID string     `json:"communityId"`
	CommunityName string   `json:"communityName"`
	AuthorID    int64      `json:"authorId"`
	AuthorName  string     `json:"authorName"`
	Question    string     `json:"question"`
	IsAnonymous bool       `json:"isAnonymous"`
	TotalVotes  int        `json:"totalVotes"`
	OptionCount int        `json:"optionCount"`
	ClosedAt    *time.Time `json:"closedAt,omitempty"`
	ExpiresAt   *time.Time `json:"expiresAt,omitempty"`
	CreatedAt   time.Time  `json:"createdAt"`
}

// AdminList — every poll on the platform, newest-first. Limited to
// 100 rows; the dashboard adds a community filter via [communityID]
// (empty string = all communities).
func (r *CommunityPollsRepository) AdminList(
	communityID string,
) ([]*AdminPollRow, error) {
	q := `SELECT p.id, p.message_id, p.community_id, c.name,
	             p.author_id,
	             COALESCE(NULLIF(u.name, ''), u.email),
	             p.question, p.is_anonymous,
	             (SELECT COUNT(*) FROM community_poll_votes v WHERE v.poll_id = p.id),
	             (SELECT COUNT(*) FROM community_poll_options o WHERE o.poll_id = p.id),
	             p.closed_at, p.expires_at, p.created_at
	        FROM community_polls p
	        JOIN users u ON u.id = p.author_id
	        JOIN communities c ON c.id = p.community_id`
	args := []any{}
	if communityID != "" {
		args = append(args, communityID)
		q += ` WHERE p.community_id = $1`
	}
	q += ` ORDER BY p.created_at DESC LIMIT 100`
	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*AdminPollRow, 0)
	for rows.Next() {
		var x AdminPollRow
		var closedAt, expiresAt sql.NullTime
		if err := rows.Scan(
			&x.ID, &x.MessageID, &x.CommunityID, &x.CommunityName,
			&x.AuthorID, &x.AuthorName,
			&x.Question, &x.IsAnonymous,
			&x.TotalVotes, &x.OptionCount,
			&closedAt, &expiresAt, &x.CreatedAt,
		); err != nil {
			return nil, err
		}
		if closedAt.Valid {
			t := closedAt.Time
			x.ClosedAt = &t
		}
		if expiresAt.Valid {
			t := expiresAt.Time
			x.ExpiresAt = &t
		}
		out = append(out, &x)
	}
	return out, rows.Err()
}

// AdminPollDetail — full detail for a single poll. Drives the admin
// `/polls/:id` page. Includes per-option vote counts AND, for non-
// anonymous polls, the avatar list of voters per option.
//
// Anonymous polls intentionally NEVER carry voter rows (even for admin)
// — the author's anonymity contract is a promise to participants and
// the admin override here would break trust. Mod can still close the
// poll without seeing who voted for what.
type AdminPollDetail struct {
	*AdminPollRow
	Options []*AdminPollOptionDetail `json:"options"`
}

// AdminPollOptionDetail — one option with optional voter list.
type AdminPollOptionDetail struct {
	ID        int64        `json:"id"`
	Label     string       `json:"label"`
	SortOrder int          `json:"sortOrder"`
	VoteCount int          `json:"voteCount"`
	Voters    []*PollVoter `json:"voters,omitempty"` // nil for anonymous polls
}

// PollVoter — one row in the avatar list shown next to each option.
type PollVoter struct {
	UserID   int64     `json:"userId"`
	Name     string    `json:"name"`
	Email    string    `json:"email"`
	Role     string    `json:"role"`
	VotedAt  time.Time `json:"votedAt"`
}

// AdminGetByID — the row + every option + (when not anonymous) the
// voter list per option. Returns sql.ErrNoRows when the id doesn't
// exist.
func (r *CommunityPollsRepository) AdminGetByID(id int64) (*AdminPollDetail, error) {
	// 1. Base poll + community + author display.
	row := r.db.QueryRow(`
		SELECT p.id, p.message_id, p.community_id, c.name,
		       p.author_id,
		       COALESCE(NULLIF(u.name, ''), u.email),
		       p.question, p.is_anonymous,
		       (SELECT COUNT(*) FROM community_poll_votes v WHERE v.poll_id = p.id),
		       (SELECT COUNT(*) FROM community_poll_options o WHERE o.poll_id = p.id),
		       p.closed_at, p.expires_at, p.created_at
		  FROM community_polls p
		  JOIN users u ON u.id = p.author_id
		  JOIN communities c ON c.id = p.community_id
		 WHERE p.id = $1`, id)
	var x AdminPollRow
	var closedAt, expiresAt sql.NullTime
	if err := row.Scan(
		&x.ID, &x.MessageID, &x.CommunityID, &x.CommunityName,
		&x.AuthorID, &x.AuthorName,
		&x.Question, &x.IsAnonymous,
		&x.TotalVotes, &x.OptionCount,
		&closedAt, &expiresAt, &x.CreatedAt,
	); err != nil {
		return nil, err
	}
	if closedAt.Valid {
		t := closedAt.Time
		x.ClosedAt = &t
	}
	if expiresAt.Valid {
		t := expiresAt.Time
		x.ExpiresAt = &t
	}

	// 2. Options with vote counts.
	optRows, err := r.db.Query(`
		SELECT o.id, o.label, o.sort_order,
		       (SELECT COUNT(*) FROM community_poll_votes v WHERE v.option_id = o.id)
		  FROM community_poll_options o
		 WHERE o.poll_id = $1
		 ORDER BY o.sort_order ASC, o.id ASC`, id)
	if err != nil {
		return nil, err
	}
	defer optRows.Close()
	options := make([]*AdminPollOptionDetail, 0)
	optByID := make(map[int64]*AdminPollOptionDetail)
	for optRows.Next() {
		var o AdminPollOptionDetail
		if err := optRows.Scan(&o.ID, &o.Label, &o.SortOrder, &o.VoteCount); err != nil {
			return nil, err
		}
		options = append(options, &o)
		optByID[o.ID] = &o
	}

	// 3. For non-anonymous polls, fan-in voters per option in one
	//    query. Anonymous polls skip this entirely (admin override
	//    would break the anonymity contract).
	if !x.IsAnonymous && len(options) > 0 {
		voterRows, err := r.db.Query(`
			SELECT v.option_id, v.user_id,
			       COALESCE(NULLIF(u.name, ''), u.email),
			       u.email, u.role, v.voted_at
			  FROM community_poll_votes v
			  JOIN users u ON u.id = v.user_id
			 WHERE v.poll_id = $1
			 ORDER BY v.voted_at DESC`, id)
		if err != nil {
			return nil, err
		}
		defer voterRows.Close()
		for voterRows.Next() {
			var optID int64
			var pv PollVoter
			if err := voterRows.Scan(
				&optID, &pv.UserID, &pv.Name, &pv.Email, &pv.Role, &pv.VotedAt,
			); err != nil {
				return nil, err
			}
			if o, ok := optByID[optID]; ok {
				o.Voters = append(o.Voters, &pv)
			}
		}
		// Initialize empty voter slices on options that have no votes
		// so the JSON shape is stable.
		for _, o := range options {
			if o.Voters == nil {
				o.Voters = []*PollVoter{}
			}
		}
	}

	return &AdminPollDetail{
		AdminPollRow: &x,
		Options:      options,
	}, nil
}
