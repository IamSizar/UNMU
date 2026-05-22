package models

import "time"

// UserNotification — one row in user_notifications. Drives Sarah's bell
// inbox. Type values: "post_liked", "post_commented", "subscription_active",
// "subscription_pending", etc. The Flutter screen renders type-specific
// copy from these primitives.
type UserNotification struct {
	ID           int64      `json:"id"`
	UserID       int64      `json:"userId"`
	ActorID      *int64     `json:"actorId,omitempty"`
	ActorName    *string    `json:"actorName,omitempty"`
	Type         string     `json:"type"`
	PostID       *int64     `json:"postId,omitempty"`
	CommentID    *int64     `json:"commentId,omitempty"`
	BodySnippet  *string    `json:"bodySnippet,omitempty"`
	ReadAt       *time.Time `json:"readAt,omitempty"`
	CreatedAt    time.Time  `json:"createdAt"`
}
