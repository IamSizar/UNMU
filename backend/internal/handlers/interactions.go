package handlers

import (
	"errors"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// InteractionsHandler — likes + comments on posts, plus the bell inbox.
//
// Auth assumptions: every route here is mounted under the JWT-protected
// group. The handler still defends against userID == 0 just in case the
// middleware lineup ever changes.
type InteractionsHandler struct {
	posts    *repositories.SocialRepository
	subs     *repositories.ExpertSubscriptionRepository
	users    *repositories.UserRepository
	likes    *repositories.PostInteractionsRepository
	saves    *repositories.PostSavesRepository
	notifs   *repositories.UserNotificationsRepository
}

func NewInteractionsHandler(
	posts *repositories.SocialRepository,
	subs *repositories.ExpertSubscriptionRepository,
	users *repositories.UserRepository,
	likes *repositories.PostInteractionsRepository,
	saves *repositories.PostSavesRepository,
	notifs *repositories.UserNotificationsRepository,
) *InteractionsHandler {
	return &InteractionsHandler{
		posts: posts, subs: subs, users: users,
		likes: likes, saves: saves, notifs: notifs,
	}
}

// canInteract enforces the same gating as ListExpertPosts: a user can like
// or comment on an expert post if it's public, or if they're the post
// owner / an admin / hold an active subscription to the expert. Locked
// teasers stay read-only.
func (h *InteractionsHandler) canInteract(userID, postID int64) (bool, int, string) {
	post, err := h.posts.GetPostByID(postID)
	if err != nil {
		return false, http.StatusInternalServerError, err.Error()
	}
	if post == nil {
		return false, http.StatusNotFound, "post not found"
	}
	if post.IsHidden {
		return false, http.StatusForbidden, "post not available"
	}
	if post.Visibility == "public" {
		return true, 0, ""
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		return false, http.StatusUnauthorized, "auth required"
	}
	if user.Role == "ADMIN" {
		return true, 0, ""
	}
	if post.ExpertID != nil && user.ExpertID.Valid && user.ExpertID.String == *post.ExpertID {
		return true, 0, ""
	}
	if post.ExpertID != nil {
		active, _ := h.subs.HasActiveAccess(userID, *post.ExpertID)
		if active {
			return true, 0, ""
		}
	}
	return false, http.StatusForbidden, "subscribe to interact with this post"
}

// POST /api/posts/:id/like  → toggle on
func (h *InteractionsHandler) Like(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	if ok, code, msg := h.canInteract(userID, postID); !ok {
		c.JSON(code, gin.H{"error": msg})
		return
	}
	count, err := h.likes.Like(postID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"liked": true, "likes": count})
}

// DELETE /api/posts/:id/like  → toggle off
func (h *InteractionsHandler) Unlike(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	count, err := h.likes.Unlike(postID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"liked": false, "likes": count})
}

// GET /api/posts/:id/comments
func (h *InteractionsHandler) ListComments(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	if ok, code, msg := h.canInteract(userID, postID); !ok {
		c.JSON(code, gin.H{"error": msg})
		return
	}
	limit := parseLimit(c.Query("limit"), 50)
	comments, err := h.likes.ListComments(postID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Step 30 — same convention as admin ListComments: return [] not
	// null so mobile clients don't have to null-coalesce.
	if comments == nil {
		comments = []*models.PostComment{}
	}
	c.JSON(http.StatusOK, gin.H{"comments": comments})
}

// POST /api/posts/:id/comments  body: { "body": "..." }
func (h *InteractionsHandler) CreateComment(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	if ok, code, msg := h.canInteract(userID, postID); !ok {
		c.JSON(code, gin.H{"error": msg})
		return
	}
	var body struct {
		Body string `json:"body"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Body = strings.TrimSpace(body.Body)
	if body.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "comment body required"})
		return
	}
	if len(body.Body) > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "comment too long (max 2000 chars)"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user lookup failed"})
		return
	}
	authorName := user.Email
	if user.Name.Valid && strings.TrimSpace(user.Name.String) != "" {
		authorName = user.Name.String
	}
	comment, err := h.likes.AddComment(postID, userID, authorName, body.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, comment)
}

// PATCH /api/posts/:id/comments/:commentId  body: { "body": "..." }
//
// Allowed only for the comment's author. Admins/post-owners can delete
// but not edit — editing someone else's words would be a moderation
// footgun. Body is required and capped at 2000 chars (same as create).
func (h *InteractionsHandler) UpdateComment(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	commentID, err := strconv.ParseInt(c.Param("commentId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid comment id"})
		return
	}

	var body struct {
		Body string `json:"body"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Body = strings.TrimSpace(body.Body)
	if body.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "comment body required"})
		return
	}
	if len(body.Body) > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "comment too long (max 2000 chars)"})
		return
	}

	existing, err := h.likes.GetComment(commentID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "comment not found"})
		return
	}
	if existing.AuthorID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "you can only edit your own comments"})
		return
	}
	if existing.Body == body.Body {
		// No-op update — don't mark as edited.
		c.JSON(http.StatusOK, existing)
		return
	}

	updated, err := h.likes.UpdateComment(commentID, body.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updated)
}

// DELETE /api/posts/:id/comments/:commentId
//
// Allowed: the comment's author, the post's owner (Sarah moderating her
// own thread), or an admin.
func (h *InteractionsHandler) DeleteComment(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	commentID, err := strconv.ParseInt(c.Param("commentId"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid comment id"})
		return
	}
	comment, err := h.likes.GetComment(commentID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if comment == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "comment not found"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user lookup failed"})
		return
	}
	post, _ := h.posts.GetPostByID(comment.PostID)

	isAuthor := comment.AuthorID == userID
	isAdmin := user.Role == "ADMIN"
	isPostOwner := post != nil && post.ExpertID != nil &&
		user.ExpertID.Valid && user.ExpertID.String == *post.ExpertID
	if !isAuthor && !isAdmin && !isPostOwner {
		c.JSON(http.StatusForbidden, gin.H{"error": "not allowed"})
		return
	}
	if err := h.likes.DeleteComment(commentID); err != nil {
		if errors.Is(err, repositories.ErrSubNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "comment not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

// GET /api/me/notifications
func (h *InteractionsHandler) ListNotifications(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	limit := parseLimit(c.Query("limit"), 50)
	rows, err := h.notifs.List(userID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if rows == nil {
		rows = []*models.UserNotification{}
	}
	c.JSON(http.StatusOK, gin.H{"notifications": rows})
}

// GET /api/me/notifications/unread-count
func (h *InteractionsHandler) UnreadCount(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	count, err := h.notifs.UnreadCount(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": count})
}

// POST /api/me/notifications/read-all
func (h *InteractionsHandler) MarkAllRead(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if err := h.notifs.MarkAllRead(userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// GET /api/posts/:id/likes
//
// Returns the list of users who liked this post, newest-first. Gated to
// the post's author or an admin — likers' identities stay private from
// the wider audience even though the public count is visible everywhere.
func (h *InteractionsHandler) ListPostLikes(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	post, err := h.posts.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if post == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user lookup failed"})
		return
	}
	isOwner := post.AuthorID == userID ||
		(post.ExpertID != nil && user.ExpertID.Valid &&
			user.ExpertID.String == *post.ExpertID)
	isAdmin := user.Role == "ADMIN"
	if !isOwner && !isAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the post's author or an admin can view likes"})
		return
	}

	limit := parseLimit(c.Query("limit"), 50)
	likers, err := h.likes.ListLikers(postID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if likers == nil {
		likers = []*repositories.Liker{}
	}
	c.JSON(http.StatusOK, gin.H{"likers": likers})
}

// POST /api/posts/:id/save  → toggle on
//
// Saving is private. Anyone authenticated can save any post they can see —
// including locked teasers (so they can come back to them later). The same
// canInteract gate would over-block here, so we don't use it; saving a
// hidden post is the only thing we block.
func (h *InteractionsHandler) Save(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	post, err := h.posts.GetPostByID(postID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if post == nil || post.IsHidden {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	if err := h.saves.Save(postID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"saved": true})
}

// DELETE /api/posts/:id/save → toggle off (always idempotent).
func (h *InteractionsHandler) Unsave(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	if err := h.saves.Unsave(postID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"saved": false})
}

// GET /api/me/saved-posts — returns full Post objects, newest-saved first.
//
// Locked-teaser logic still applies: if the user saved a subscribers-only
// post and later let their sub lapse, they'll see it back as a locked
// teaser here. They can still unsave it from a locked card.
func (h *InteractionsHandler) ListSaved(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	limit := parseLimit(c.Query("limit"), 50)
	posts, err := h.saves.ListSavedByUser(userID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	user, _ := h.users.GetByID(userID)
	for _, p := range posts {
		// Per-row paywall pass — saved doesn't bypass the gate.
		if p.Visibility == "subscribers_only" && p.ExpertID != nil {
			canSee := false
			if user != nil && user.ExpertID.Valid && user.ExpertID.String == *p.ExpertID {
				canSee = true
			} else if user != nil && user.Role == "ADMIN" {
				canSee = true
			} else if active, _ := h.subs.HasActiveAccess(userID, *p.ExpertID); active {
				canSee = true
			}
			if !canSee {
				p.LockTeaser()
			}
		}
		// Always mark as saved since this list comes straight from
		// post_saves — saves the client a separate fillSaved query.
		p.Saved = true
	}
	// Like state isn't free here — fill it the same way the social handler
	// does for the other list endpoints.
	if h.likes != nil {
		ids := make([]int64, 0, len(posts))
		for _, p := range posts {
			ids = append(ids, p.ID)
		}
		if liked, err := h.likes.LikedPostsByUser(userID, ids); err == nil {
			for _, p := range posts {
				if liked[p.ID] {
					p.Liked = true
				}
			}
		}
	}
	if posts == nil {
		posts = []*models.Post{}
	}
	c.JSON(http.StatusOK, gin.H{"posts": posts})
}

// POST /api/me/notifications/:id/read
func (h *InteractionsHandler) MarkOneRead(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.notifs.MarkRead(id, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
