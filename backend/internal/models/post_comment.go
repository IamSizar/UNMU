package models

import "time"

// PostComment is one row in post_comments. Flat — no parent_id reference,
// since v1 doesn't support reply threads.
type PostComment struct {
	ID         int64      `json:"id"`
	PostID     int64      `json:"postId"`
	AuthorID   int64      `json:"authorId"`
	AuthorName string     `json:"authorName"`
	Body       string     `json:"body"`
	CreatedAt  time.Time  `json:"createdAt"`
	// EditedAt is non-nil when the author has changed the body since
	// posting. The UI renders "(edited)" next to the timestamp.
	EditedAt   *time.Time `json:"editedAt,omitempty"`
}
