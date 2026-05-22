package repositories

import (
	"database/sql"
	"errors"
	"halalstocks/internal/models"
	"strings"
)

// PostSavesRepository — bookmarks. (post_id, user_id) pairs that mark a
// post as "saved" by a user. Mirrors the shape of PostInteractionsRepo,
// kept as its own file because likes + comments + saves have different
// sharing / privacy stories.
type PostSavesRepository struct {
	db *sql.DB
	s3 MediaURLResolver
}

func NewPostSavesRepository(db *sql.DB) *PostSavesRepository {
	return &PostSavesRepository{db: db}
}

// SetS3Storage wires the sign-on-read URL resolver. Calling repos here
// only matters for ListSavedByUser, which JOINs onto posts; everything
// else returns ids/counts.
func (r *PostSavesRepository) SetS3Storage(s3 MediaURLResolver) {
	r.s3 = s3
}

// Save — idempotent insert.
func (r *PostSavesRepository) Save(postID, userID int64) error {
	_, err := r.db.Exec(`
		INSERT INTO post_saves (post_id, user_id) VALUES ($1, $2)
		ON CONFLICT (post_id, user_id) DO NOTHING
	`, postID, userID)
	return err
}

// Unsave — idempotent delete.
func (r *PostSavesRepository) Unsave(postID, userID int64) error {
	_, err := r.db.Exec(`DELETE FROM post_saves WHERE post_id = $1 AND user_id = $2`,
		postID, userID)
	return err
}

// HasSaved — single bool used by the saved-icon toggle.
func (r *PostSavesRepository) HasSaved(postID, userID int64) (bool, error) {
	if userID == 0 {
		return false, nil
	}
	var exists bool
	err := r.db.QueryRow(`
		SELECT EXISTS (SELECT 1 FROM post_saves WHERE post_id = $1 AND user_id = $2)
	`, postID, userID).Scan(&exists)
	return exists, err
}

// SavedPostIDs returns the set of post ids the user has saved, restricted
// to the candidate slice — used by the list handlers' fillSaved pass.
func (r *PostSavesRepository) SavedPostIDs(
	userID int64, postIDs []int64,
) (map[int64]bool, error) {
	out := map[int64]bool{}
	if userID == 0 || len(postIDs) == 0 {
		return out, nil
	}
	placeholders := make([]string, 0, len(postIDs))
	args := make([]any, 0, len(postIDs)+1)
	args = append(args, userID)
	for i, id := range postIDs {
		args = append(args, id)
		placeholders = append(placeholders, "$"+itoa(i+2))
	}
	q := `SELECT post_id FROM post_saves
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

// ListSavedByUser returns the user's saved posts joined with the posts
// table, newest-saved first. Skips hidden rows (an expert may have
// hidden a post the user previously saved — surfacing it would be
// confusing). The bookmark itself stays so re-publishing brings it back.
func (r *PostSavesRepository) ListSavedByUser(
	userID int64, limit int,
) ([]*models.Post, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	q := `
		SELECT p.id, p.target_type, p.community_id, p.expert_id,
		       p.author_id, p.author_name,
		       p.title, p.body, p.ticker, p.tickers, p.stance,
		       p.upvotes, p.likes, p.comments_count, p.created_at,
		       p.post_type, p.media_url, p.cover_url, p.duration_seconds,
		       p.visibility, p.is_hidden, p.updated_at
		FROM post_saves s
		JOIN posts p ON p.id = s.post_id
		WHERE s.user_id = $1 AND p.is_hidden = FALSE
		ORDER BY s.created_at DESC
		LIMIT $2
	`
	rows, err := r.db.Query(q, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*models.Post
	for rows.Next() {
		p, err := models.ScanPost(rows)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				continue
			}
			return nil, err
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// Sign-on-read — only if S3 is wired (dev fallback returns untouched).
	if r.s3 != nil {
		for _, p := range out {
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
		}
	}
	return out, nil
}
