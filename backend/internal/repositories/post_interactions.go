package repositories

import (
	"database/sql"
	"errors"
	"halalstocks/internal/models"
	"strings"
	"time"
)

// PostInteractionsRepository — likes + comments on posts.
type PostInteractionsRepository struct {
	db *sql.DB
}

func NewPostInteractionsRepository(db *sql.DB) *PostInteractionsRepository {
	return &PostInteractionsRepository{db: db}
}

// Like inserts a (post_id, user_id) row. Idempotent — already-liked is a
// no-op (returns the same `liked: true` state). Returns the post's new
// like count.
//
// Triggers handle the count + notification + NOTIFY plumbing.
func (r *PostInteractionsRepository) Like(postID, userID int64) (int, error) {
	_, err := r.db.Exec(`
		INSERT INTO post_likes (post_id, user_id) VALUES ($1, $2)
		ON CONFLICT (post_id, user_id) DO NOTHING
	`, postID, userID)
	if err != nil {
		return 0, err
	}
	var count int
	err = r.db.QueryRow(`SELECT likes FROM posts WHERE id = $1`, postID).Scan(&count)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return count, err
}

// Unlike deletes the (post_id, user_id) row. Idempotent.
func (r *PostInteractionsRepository) Unlike(postID, userID int64) (int, error) {
	_, err := r.db.Exec(`DELETE FROM post_likes WHERE post_id = $1 AND user_id = $2`,
		postID, userID)
	if err != nil {
		return 0, err
	}
	var count int
	err = r.db.QueryRow(`SELECT likes FROM posts WHERE id = $1`, postID).Scan(&count)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, nil
	}
	return count, err
}

// HasLiked tells the post-list handler whether to render the heart filled
// for this viewer. One small query per user-id, but it's a primary key
// lookup so essentially free.
func (r *PostInteractionsRepository) HasLiked(postID, userID int64) (bool, error) {
	if userID == 0 {
		return false, nil
	}
	var exists bool
	err := r.db.QueryRow(`
		SELECT EXISTS (SELECT 1 FROM post_likes WHERE post_id = $1 AND user_id = $2)
	`, postID, userID).Scan(&exists)
	return exists, err
}

// LikedPostsByUser returns the set of post ids that this user has liked,
// limited to a candidate set. Lets us populate `liked` on a list of posts
// in a single round-trip rather than N point queries.
func (r *PostInteractionsRepository) LikedPostsByUser(
	userID int64, postIDs []int64,
) (map[int64]bool, error) {
	out := map[int64]bool{}
	if userID == 0 || len(postIDs) == 0 {
		return out, nil
	}
	// Build $1, $2, $3... placeholders.
	placeholders := make([]string, 0, len(postIDs))
	args := make([]any, 0, len(postIDs)+1)
	args = append(args, userID)
	for i, id := range postIDs {
		args = append(args, id)
		placeholders = append(placeholders, "$"+itoa(i+2))
	}
	q := `SELECT post_id FROM post_likes
	      WHERE user_id = $1 AND post_id IN (` + strings.Join(placeholders, ",") + `)`
	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out[id] = true
	}
	return out, rows.Err()
}

// Liker is a denormalized view of one row in post_likes joined with the
// liker's user record + their expert profile (if any). Used by the post
// owner's "who liked this?" screen.
type Liker struct {
	UserID   int64     `json:"userId"`
	Name     string    `json:"name"`
	Email    string    `json:"email"`
	// Role is the user's CURRENT role ("USER" / "EXPERT" / "ADMIN").
	// Always populate from `users.role`, not derived from
	// `users.expert_id` — a demoted ex-expert can still have a non-NULL
	// expert_id from when they had the badge, so role is the source of
	// truth for "is this person currently an expert?".
	Role     string    `json:"role"`
	ExpertID string    `json:"expertId,omitempty"`
	LikedAt  time.Time `json:"likedAt"`
}

// ListLikers returns the users who liked a given post, newest-first.
//
// Joins users so we have the display name without a follow-up query.
// Caller has already verified the requester is allowed to see this list
// (post owner or admin) — likers' identities stay private from random
// viewers.
func (r *PostInteractionsRepository) ListLikers(postID int64, limit int) ([]*Liker, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	q := `
		SELECT l.user_id,
		       COALESCE(NULLIF(u.name, ''), '')              AS name,
		       u.email,
		       u.role,
		       COALESCE(u.expert_id, '')                     AS expert_id,
		       l.created_at
		FROM post_likes l
		JOIN users u ON u.id = l.user_id
		WHERE l.post_id = $1
		ORDER BY l.created_at DESC
		LIMIT $2
	`
	rows, err := r.db.Query(q, postID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Liker
	for rows.Next() {
		var liker Liker
		if err := rows.Scan(
			&liker.UserID, &liker.Name, &liker.Email,
			&liker.Role, &liker.ExpertID, &liker.LikedAt,
		); err != nil {
			return nil, err
		}
		// Defensive: if the user's expert_id is stale leftover from a
		// previous role and they're now back to a plain USER, blank
		// expert_id on the way out so the frontend never even sees the
		// stale string. Source-of-truth alignment in one place.
		if liker.Role != "EXPERT" {
			liker.ExpertID = ""
		}
		out = append(out, &liker)
	}
	return out, rows.Err()
}

// scanComment — central scan helper. Pulls (edited_at) out of a
// sql.NullTime into the PostComment.EditedAt pointer. Used by every
// read path so adding columns later is a one-place edit.
func scanComment(s interface{ Scan(dest ...any) error }) (*models.PostComment, error) {
	var c models.PostComment
	var editedAt sql.NullTime
	if err := s.Scan(
		&c.ID, &c.PostID, &c.AuthorID, &c.AuthorName, &c.Body, &c.CreatedAt, &editedAt,
	); err != nil {
		return nil, err
	}
	if editedAt.Valid {
		c.EditedAt = &editedAt.Time
	}
	return &c, nil
}

// AddComment inserts a comment row and returns it. Trigger handles count
// + notification + NOTIFY.
func (r *PostInteractionsRepository) AddComment(
	postID, authorID int64, authorName, body string,
) (*models.PostComment, error) {
	row := r.db.QueryRow(`
		INSERT INTO post_comments (post_id, author_id, author_name, body)
		VALUES ($1, $2, $3, $4)
		RETURNING id, post_id, author_id, author_name, body, created_at, edited_at
	`, postID, authorID, authorName, strings.TrimSpace(body))
	return scanComment(row)
}

// ListComments returns flat-thread comments on a post, oldest-first so a
// user reading top-to-bottom sees the conversation in order.
func (r *PostInteractionsRepository) ListComments(postID int64, limit int) ([]*models.PostComment, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := r.db.Query(`
		SELECT id, post_id, author_id, author_name, body, created_at, edited_at
		FROM post_comments
		WHERE post_id = $1
		ORDER BY created_at ASC
		LIMIT $2
	`, postID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.PostComment
	for rows.Next() {
		c, err := scanComment(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// GetComment fetches a single comment for ownership checks.
func (r *PostInteractionsRepository) GetComment(id int64) (*models.PostComment, error) {
	row := r.db.QueryRow(`
		SELECT id, post_id, author_id, author_name, body, created_at, edited_at
		FROM post_comments WHERE id = $1
	`, id)
	c, err := scanComment(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return c, nil
}

// UpdateComment replaces the body and stamps edited_at = NOW(). Caller
// has already verified ownership. Returns sql.ErrNoRows when no row
// matches (caller maps to 404).
func (r *PostInteractionsRepository) UpdateComment(id int64, body string) (*models.PostComment, error) {
	row := r.db.QueryRow(`
		UPDATE post_comments
		SET body = $1, edited_at = NOW()
		WHERE id = $2
		RETURNING id, post_id, author_id, author_name, body, created_at, edited_at
	`, strings.TrimSpace(body), id)
	c, err := scanComment(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, sql.ErrNoRows
	}
	return c, err
}

// DeleteComment removes a comment. Caller has already verified the
// requester is the comment author, the post owner, or an admin.
func (r *PostInteractionsRepository) DeleteComment(id int64) error {
	res, err := r.db.Exec(`DELETE FROM post_comments WHERE id = $1`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}
