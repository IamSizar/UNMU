package handlers

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

// CommunityPollsHandler — REST surface for chat polls (mig 0021,
// item 5.21). Routes:
//
//   POST   /api/communities/:id/polls
//   POST   /api/communities/:id/polls/:pid/vote
//   POST   /api/communities/:id/polls/:pid/close
//
// Polls always live attached to a community message — creating one
// inserts both rows in a single transaction (see
// CommunityPollsRepository.Create). The host message is broadcast on
// the community channel as a regular `community_message` event so
// existing chat clients render it inline; the message struct carries
// the embedded `Poll` so poll-aware clients render the rich widget.
type CommunityPollsHandler struct {
	polls    *repositories.CommunityPollsRepository
	messages *repositories.CommunityMessagesRepository
	social   *repositories.SocialRepository
	users    *repositories.UserRepository
	hub      *realtime.Hub
	notifier *services.Notifier // optional, set via SetNotifier
}

func NewCommunityPollsHandler(
	polls *repositories.CommunityPollsRepository,
	messages *repositories.CommunityMessagesRepository,
	social *repositories.SocialRepository,
	users *repositories.UserRepository,
	hub *realtime.Hub,
) *CommunityPollsHandler {
	return &CommunityPollsHandler{
		polls: polls, messages: messages, social: social,
		users: users, hub: hub,
	}
}

// SetNotifier wires the localized push fan-out. Best-effort; nil-safe.
func (h *CommunityPollsHandler) SetNotifier(n *services.Notifier) {
	h.notifier = n
}

// notifyMembers fans a community-content push out to every member except
// the optional excludeUserID (pass 0 to notify all). Best-effort.
func (h *CommunityPollsHandler) notifyMembers(
	c *gin.Context, communityID, notifType string,
	params map[string]string, excludeUserID int64,
) {
	if h.notifier == nil {
		return
	}
	members, err := h.social.ListMemberIDs(communityID)
	if err != nil {
		return
	}
	recipients := make([]int64, 0, len(members))
	for _, m := range members {
		if m != excludeUserID {
			recipients = append(recipients, m)
		}
	}
	h.notifier.PushToUsers(c.Request.Context(), recipients, notifType, params)
}

// communityName resolves a community's display name, falling back to its
// id when the lookup fails.
func (h *CommunityPollsHandler) communityName(communityID string) string {
	if comm, err := h.social.GetCommunity(communityID); err == nil && comm != nil {
		return comm.Name
	}
	return communityID
}

// requireMember — same gate as the messages handler. Inlined here so
// the polls handler doesn't have to depend on the messages handler's
// internal helper.
func (h *CommunityPollsHandler) requireMember(
	c *gin.Context, communityID string,
) (int64, bool) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return 0, false
	}
	ok, err := h.messages.IsMember(communityID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return 0, false
	}
	if !ok {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "join the community to participate",
		})
		return 0, false
	}
	return userID, true
}

// Create — POST /api/communities/:id/polls
//
// Body:
//
//	{
//	  "question":   "Will $NVDA hit $200 by Dec?",
//	  "options":    ["Yes","No","Already there"],
//	  "isAnonymous": false,
//	  "expiresInHours": 24            // optional: 1, 24, or 168
//	}
//
// Validation:
//   * question      1..200 chars
//   * 2..4 options, each 1..60 chars, no duplicates
//   * expiresInHours: 0 = open-ended, otherwise 1..720 (≈30 days)
//
// On success, broadcasts the host message on the community channel.
func (h *CommunityPollsHandler) Create(c *gin.Context) {
	communityID := c.Param("id")
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	var body struct {
		Question       string   `json:"question"`
		Options        []string `json:"options"`
		IsAnonymous    bool     `json:"isAnonymous"`
		ExpiresInHours int      `json:"expiresInHours"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Question = strings.TrimSpace(body.Question)
	if len(body.Question) < 1 || len(body.Question) > 200 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "question must be 1..200 chars",
		})
		return
	}
	cleanOpts := make([]string, 0, len(body.Options))
	seen := map[string]bool{}
	for _, o := range body.Options {
		o = strings.TrimSpace(o)
		if o == "" {
			continue
		}
		if len(o) > 60 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "each option must be ≤ 60 chars",
			})
			return
		}
		key := strings.ToLower(o)
		if seen[key] {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "duplicate option labels",
			})
			return
		}
		seen[key] = true
		cleanOpts = append(cleanOpts, o)
	}
	if len(cleanOpts) < 2 || len(cleanOpts) > 4 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "need 2..4 options",
		})
		return
	}
	var expiresAt *time.Time
	if body.ExpiresInHours > 0 {
		if body.ExpiresInHours > 720 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "expiresInHours must be ≤ 720 (≈30 days)",
			})
			return
		}
		t := time.Now().Add(time.Duration(body.ExpiresInHours) * time.Hour)
		expiresAt = &t
	}

	created, err := h.polls.Create(repositories.CreatePollInput{
		CommunityID: communityID,
		AuthorID:    userID,
		Question:    body.Question,
		Options:     cleanOpts,
		IsAnonymous: body.IsAnonymous,
		ExpiresAt:   expiresAt,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Fetch the host message hydrated so the broadcast carries the
	// embedded poll. Existing clients render the bubble (body =
	// question), poll-aware clients render the rich widget.
	msg, err := h.messages.GetByID(created.MessageID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"community_message",
			msg,
		)
	}
	// Fan a localized push out to members (except the author).
	h.notifyMembers(c, communityID, "poll_created", map[string]string{
		"author":    subscriberDisplayName(h.users, userID),
		"community": h.communityName(communityID),
	}, userID)
	c.JSON(http.StatusCreated, gin.H{"message": msg})
}

// Vote — POST /api/communities/:id/polls/:pid/vote
//
// Body: { "optionId": <int> }
//
// Member-gated. One vote per user per poll — re-voting silently
// replaces the previous vote. Closed polls return 409.
func (h *CommunityPollsHandler) Vote(c *gin.Context) {
	communityID := c.Param("id")
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	pid, perr := strconv.ParseInt(c.Param("pid"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid poll id"})
		return
	}
	var body struct {
		OptionID int64 `json:"optionId"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.OptionID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "optionId required"})
		return
	}
	if err := h.polls.Vote(pid, body.OptionID, userID); err != nil {
		switch {
		case errors.Is(err, sql.ErrNoRows):
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "option not in this poll",
			})
		case err.Error() == "poll closed":
			c.JSON(http.StatusConflict, gin.H{"error": "poll closed"})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}
	// Broadcast the host message refreshed with new vote counts so
	// every client patches its local copy live.
	_, _, msgID, err := h.polls.PollOwner(pid)
	if err == nil && msgID > 0 {
		if msg, err := h.messages.GetByID(msgID, 0); err == nil && h.hub != nil {
			h.hub.PublishJSON(
				realtime.ChannelCommunity(communityID),
				"poll_voted",
				msg,
			)
		}
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// Close — POST /api/communities/:id/polls/:pid/close
//
// Author or community owner only. Idempotent — closing an already
// closed poll returns 200 with `alreadyClosed: true`.
func (h *CommunityPollsHandler) Close(c *gin.Context) {
	communityID := c.Param("id")
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	pid, perr := strconv.ParseInt(c.Param("pid"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid poll id"})
		return
	}
	authorID, pollCommunityID, msgID, err := h.polls.PollOwner(pid)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "poll not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if pollCommunityID != communityID {
		c.JSON(http.StatusNotFound, gin.H{"error": "poll not in this community"})
		return
	}
	// Author OR community owner OR admin can close.
	canClose := authorID == userID
	if !canClose && h.social != nil {
		ownerID, _ := h.social.CommunityOwnerID(communityID)
		if ownerID == userID {
			canClose = true
		}
	}
	if !canClose && h.users != nil {
		if u, _ := h.users.GetByID(userID); u != nil && u.Role == "ADMIN" {
			canClose = true
		}
	}
	if !canClose {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "only the poll author, community owner, or admin can close",
		})
		return
	}
	if err := h.polls.Close(pid); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if h.hub != nil && msgID > 0 {
		if msg, err := h.messages.GetByID(msgID, userID); err == nil {
			h.hub.PublishJSON(
				realtime.ChannelCommunity(communityID),
				"poll_closed",
				msg,
			)
		}
	}
	// Let members know the results are in (push-only).
	h.notifyMembers(c, communityID, "poll_closed", map[string]string{
		"community": h.communityName(communityID),
	}, 0)
	c.JSON(http.StatusOK, gin.H{"closed": true})
}

// =============================================================================
// Admin polls panel
// =============================================================================

// AdminList — GET /admin/polls (optional ?communityId=<id>)
func (h *CommunityPollsHandler) AdminList(c *gin.Context) {
	communityID := strings.TrimSpace(c.Query("communityId"))
	rows, err := h.polls.AdminList(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"polls": rows})
}

// AdminGet — GET /admin/polls/:pid
//
// Single-poll detail with full option breakdown + voter list (when
// the poll isn't anonymous). Drives the `/polls/:id` admin page.
func (h *CommunityPollsHandler) AdminGet(c *gin.Context) {
	pid, perr := strconv.ParseInt(c.Param("pid"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid poll id"})
		return
	}
	detail, err := h.polls.AdminGetByID(pid)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "poll not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, detail)
}

// AdminClose — POST /admin/polls/:pid/close
//
// Admin override. Same as the owner-side Close but bypasses the
// author/community-owner check.
func (h *CommunityPollsHandler) AdminClose(c *gin.Context) {
	pid, perr := strconv.ParseInt(c.Param("pid"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid poll id"})
		return
	}
	_, communityID, msgID, err := h.polls.PollOwner(pid)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "poll not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if err := h.polls.Close(pid); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if h.hub != nil && msgID > 0 {
		if msg, err := h.messages.GetByID(msgID, 0); err == nil {
			h.hub.PublishJSON(
				realtime.ChannelCommunity(communityID),
				"poll_closed",
				msg,
			)
		}
	}
	// Let members know the results are in (push-only).
	h.notifyMembers(c, communityID, "poll_closed", map[string]string{
		"community": h.communityName(communityID),
	}, 0)
	c.JSON(http.StatusOK, gin.H{"closed": true})
}
