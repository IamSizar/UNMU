package handlers

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// AdminPostsHandler — moderation endpoints over `posts`. Bypasses every
// subscription / visibility gate (the route group is locked behind
// `RequireAdmin`), exposes hidden posts, and writes audit-log rows on
// every mutating action.
type AdminPostsHandler struct {
	social       *repositories.SocialRepository
	interactions *repositories.PostInteractionsRepository
	users        *repositories.UserRepository
	audit        *repositories.AuditRepository
}

func NewAdminPostsHandler(
	social *repositories.SocialRepository,
	interactions *repositories.PostInteractionsRepository,
	users *repositories.UserRepository,
	audit *repositories.AuditRepository,
) *AdminPostsHandler {
	return &AdminPostsHandler{
		social: social, interactions: interactions, users: users, audit: audit,
	}
}

// List — GET /admin/posts
//
// Query params (all optional):
//   type      = article | video | reel
//   authorId  = numeric user id
//   expertId  = expert id (string)
//   status    = all | active | hidden  (default: all)
//   q         = search term (ILIKE on title + body)
//   sort      = newest | oldest | most_liked | most_commented (default: newest)
//   before    = RFC3339 timestamp (keyset cursor for pagination)
//   limit     = 1..200 (default: 50)
func (h *AdminPostsHandler) List(c *gin.Context) {
	f := repositories.AdminPostFilter{
		PostType:   strings.ToLower(strings.TrimSpace(c.Query("type"))),
		TargetType: strings.ToLower(strings.TrimSpace(c.Query("target"))),
		ExpertID:   strings.TrimSpace(c.Query("expertId")),
		Status:     strings.ToLower(strings.TrimSpace(c.Query("status"))),
		Query:      strings.TrimSpace(c.Query("q")),
		Sort:       strings.ToLower(strings.TrimSpace(c.Query("sort"))),
		Limit:      parseLimit(c.Query("limit"), 50),
	}
	// Validate target — only "expert"/"community" or empty.
	switch f.TargetType {
	case "", "expert", "community":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "target must be expert|community"})
		return
	}
	if raw := strings.TrimSpace(c.Query("authorId")); raw != "" {
		if n, err := strconv.ParseInt(raw, 10, 64); err == nil {
			f.AuthorID = n
		}
	}
	if raw := strings.TrimSpace(c.Query("before")); raw != "" {
		if t, err := time.Parse(time.RFC3339Nano, raw); err == nil {
			f.Before = t
		} else if t, err := time.Parse(time.RFC3339, raw); err == nil {
			f.Before = t
		}
	}

	rows, err := h.social.AdminListPosts(f)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"posts": rows})
}

// Get — GET /admin/posts/:id
//
// Returns the post + a stats block (likes, comments, saves, shares,
// deep-link opens, reel-load failures). Detail page uses this.
func (h *AdminPostsHandler) Get(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	post, err := h.social.GetPostByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if post == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	stats, err := h.social.AdminPostStatsByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"post":  post,
		"stats": stats,
	})
}

// ListLikes — GET /admin/posts/:id/likes
//
// Every user who liked the post, newest-first. Same shape the in-app
// "Liked by" sheet uses (the existing /posts/:id/likes endpoint is
// owner-or-admin gated; this admin variant is purely about a clean
// admin route surface).
func (h *AdminPostsHandler) ListLikes(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	limit := parseLimit(c.Query("limit"), 200)
	if limit > 500 {
		limit = 500
	}
	likers, err := h.interactions.ListLikers(id, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if likers == nil {
		likers = []*repositories.Liker{}
	}
	c.JSON(http.StatusOK, gin.H{"likes": likers})
}

// ListComments — GET /admin/posts/:id/comments
//
// Flat list, oldest-first (matches the in-app comments sheet ordering
// so the admin sees the same thread shape). Limit clamped 1..500.
func (h *AdminPostsHandler) ListComments(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	limit := parseLimit(c.Query("limit"), 200)
	if limit > 500 {
		limit = 500
	}
	comments, err := h.interactions.ListComments(id, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if comments == nil {
		comments = []*models.PostComment{}
	}
	c.JSON(http.StatusOK, gin.H{"comments": comments})
}

// DeleteComment — DELETE /admin/posts/:id/comments/:commentId
//
// Hard-deletes the comment + audit-logs the action. The :id post id is
// validated against the comment's actual post_id so a malformed URL
// like /admin/posts/9999/comments/<real-id> can't sneak through.
func (h *AdminPostsHandler) DeleteComment(c *gin.Context) {
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	commentID, err := strconv.ParseInt(c.Param("commentId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid comment id"})
		return
	}
	existing, err := h.interactions.GetComment(commentID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "comment not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing.PostID != postID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "comment does not belong to this post"})
		return
	}
	if err := h.interactions.DeleteComment(commentID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.writeAudit(c, "admin_comment_delete", "warning", map[string]any{
		"postId":    postID,
		"commentId": commentID,
		"authorId":  existing.AuthorID,
	})
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// SetHidden — POST /admin/posts/:id/hide  and  /unhide
//
// Flips `is_hidden` on the post. Hidden posts are excluded from feeds
// and 404 on the public single-post fetch, but admin can still see
// them in the moderation list. Audit-logged.
func (h *AdminPostsHandler) SetHidden(hidden bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
			return
		}
		updated, err := h.social.SetExpertPostHidden(id, hidden)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
				return
			}
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		event := "admin_post_hide"
		if !hidden {
			event = "admin_post_unhide"
		}
		h.writeAudit(c, event, "warning", map[string]any{
			"postId": id,
			"title":  derefString(updated.Title),
		})
		c.JSON(http.StatusOK, gin.H{"post": updated})
	}
}

// Delete — DELETE /admin/posts/:id
//
// Hard delete — cascade removes likes / comments / saves via FKs. The
// audit row keeps title + author for forensics.
func (h *AdminPostsHandler) Delete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	// Snapshot the post for the audit row BEFORE deletion.
	snap, err := h.social.GetPostByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if snap == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	if err := h.social.DeleteExpertPost(id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.writeAudit(c, "admin_post_delete", "warning", map[string]any{
		"postId":     id,
		"title":      derefString(snap.Title),
		"authorId":   snap.AuthorID,
		"authorName": snap.AuthorName,
		"postType":   snap.PostType,
	})
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// writeAudit centralises the moderation audit pattern. Failure to write
// an audit row never blocks the moderation action — an admin clicking
// "delete" must succeed even if the audit table has a transient
// hiccup, otherwise the UI would falsely show the action as failed.
func (h *AdminPostsHandler) writeAudit(c *gin.Context, eventType, severity string, meta map[string]any) {
	if h.audit == nil {
		return
	}
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	var actor *int64
	if userID != 0 {
		actor = &userID
	}
	// Audit signature: eventType, severity, actorID, targetID, targetKind,
	// summary, metadata. We don't carry a stable string targetID for posts
	// (the metadata holds postId + title), so leave both pointers nil.
	targetKind := "post"
	_, _ = h.audit.Write(eventType, severity, actor, nil, &targetKind, "", meta)
}

func derefString(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
