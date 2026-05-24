package repositories

import (
	"database/sql"
	"encoding/json"
)

// TranscodeRepository is the persistence layer for the FFmpeg transcode
// queue (the in-app video "quality" gear). It keeps repositories →
// services one-way: this file imports nothing from services, so the
// transcode *worker* (in services) can depend on this repo without a
// cycle.
type TranscodeRepository struct {
	db *sql.DB
}

func NewTranscodeRepository(db *sql.DB) *TranscodeRepository {
	return &TranscodeRepository{db: db}
}

// TranscodeMaxAttempts caps retries so a permanently-broken source video
// (corrupt, audio-only, deleted from S3) stops looping forever.
const TranscodeMaxAttempts = 3

// TranscodeJob is one claimed unit of work.
type TranscodeJob struct {
	PostID    int64
	SourceURL string // the post's stored media_url
	Attempts  int
}

// EnqueueMissing inserts a pending job for every published video/reel post
// that has a source media_url but no variants computed yet — and no job
// row already. Idempotent (PRIMARY KEY on post_id + ON CONFLICT DO
// NOTHING), so it's safe to call on every sweep.
func (r *TranscodeRepository) EnqueueMissing() error {
	_, err := r.db.Exec(`
		INSERT INTO transcode_jobs (post_id, source_url)
		SELECT p.id, p.media_url
		FROM posts p
		WHERE p.post_type IN ('video', 'reel')
		  AND p.media_url IS NOT NULL AND p.media_url <> ''
		  AND p.video_variants IS NULL
		ON CONFLICT (post_id) DO NOTHING
	`)
	return err
}

// ClaimNext atomically promotes one eligible job (pending, or failed but
// still under the retry cap) to 'running', bumps its attempt counter, and
// returns it. FOR UPDATE SKIP LOCKED lets multiple workers/instances run
// without grabbing the same row. Returns (nil, nil) when the queue is
// empty.
func (r *TranscodeRepository) ClaimNext() (*TranscodeJob, error) {
	var j TranscodeJob
	err := r.db.QueryRow(`
		UPDATE transcode_jobs
		SET status = 'running', attempts = attempts + 1, updated_at = NOW()
		WHERE post_id = (
			SELECT post_id FROM transcode_jobs
			WHERE status IN ('pending', 'failed') AND attempts < $1
			ORDER BY created_at ASC
			LIMIT 1
			FOR UPDATE SKIP LOCKED
		)
		RETURNING post_id, source_url, attempts
	`, TranscodeMaxAttempts).Scan(&j.PostID, &j.SourceURL, &j.Attempts)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &j, nil
}

// MarkDone writes the computed variant map onto the post and flips the job
// to 'done' in one transaction. An empty map is still stored (as '{}') so
// EnqueueMissing — which only re-enqueues rows where video_variants IS
// NULL — never re-queues a post whose source was simply too small for any
// lower rung.
func (r *TranscodeRepository) MarkDone(postID int64, variants map[string]string) error {
	raw, err := json.Marshal(variants)
	if err != nil {
		return err
	}
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.Exec(
		`UPDATE posts SET video_variants = $1 WHERE id = $2`, raw, postID,
	); err != nil {
		return err
	}
	if _, err := tx.Exec(
		`UPDATE transcode_jobs SET status = 'done', error = NULL, updated_at = NOW()
		 WHERE post_id = $1`, postID,
	); err != nil {
		return err
	}
	return tx.Commit()
}

// MarkFailed records the error and leaves the row eligible for one more
// attempt (until it hits TranscodeMaxAttempts, after which ClaimNext skips
// it). The post's video_variants stays NULL, so the client keeps playing
// the original — no user-visible breakage.
func (r *TranscodeRepository) MarkFailed(postID int64, errMsg string) error {
	_, err := r.db.Exec(
		`UPDATE transcode_jobs SET status = 'failed', error = $2, updated_at = NOW()
		 WHERE post_id = $1`, postID, errMsg,
	)
	return err
}
