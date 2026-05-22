package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

// allowedReactionEmojis — the curated allowlist for community-chat
// reactions. The mobile long-press overlay surfaces exactly these
// four; rejecting anything else keeps storage tidy and prevents an
// emoji-flood DoS via a crafted client.
var allowedReactionEmojis = map[string]bool{
	"👏": true,
	"👍": true,
	"👎": true,
	"🔥": true,
}

// Voice-message constants. The mobile recorder writes AAC/m4a (or
// optionally ogg/wav for tests); accept any of these and reject
// anything that isn't a known audio format. 25 MB ≈ ~25 minutes of
// 128 kbit/s AAC — well above any reasonable voice message.
const audioMaxBytes = 25 * 1024 * 1024

var audioExts = map[string]bool{
	".m4a":  true,
	".aac":  true,
	".mp3":  true,
	".mp4":  true, // some Android recorders write AAC into .mp4
	".ogg":  true,
	".oga":  true,
	".wav":  true,
	".webm": true,
}

// CommunityMessagesHandler — REST surface for per-community chat.
// Two endpoints:
//
//   GET  /api/communities/:id/messages?before=<RFC3339>&limit=<N>
//   POST /api/communities/:id/messages   body { "body": "..." }
//
// Both are auth-gated AND member-gated (see [requireMember]). Owner
// rows live in `community_members` so the same check handles owners
// without a second branch.
//
// Send pushes a `community_message` event to the `community:<id>`
// realtime channel (see realtime.ChannelCommunity) so every connected
// member of the community gets the new bubble live, without polling.
type CommunityMessagesHandler struct {
	messages *repositories.CommunityMessagesRepository
	users    *repositories.UserRepository
	// social is needed to look up community owner_id when gating
	// the owner-only Pin action. Optional — wired via SetSocialRepo
	// after construction so existing call sites stay stable.
	social *repositories.SocialRepository
	hub    *realtime.Hub
	// s3 optional — when set, voice messages stream to S3 instead of
	// local disk. Nil means we fall back to the original disk flow,
	// which matches what UploadHandler does for video/image uploads
	// so dev machines without AWS creds keep working without change.
	s3 *services.S3Storage
}

func NewCommunityMessagesHandler(
	messages *repositories.CommunityMessagesRepository,
	users *repositories.UserRepository,
	hub *realtime.Hub,
	s3 *services.S3Storage,
) *CommunityMessagesHandler {
	return &CommunityMessagesHandler{messages: messages, users: users, hub: hub, s3: s3}
}

// SetSocialRepo wires the social repository post-construction so
// the Pin handler can resolve community owners. Same setter pattern
// used for the social handler's hub wiring.
func (h *CommunityMessagesHandler) SetSocialRepo(s *repositories.SocialRepository) {
	h.social = s
}

// requireMember — shared 403 gate for both list + send. Returns
// (userId, true) on success; on failure, writes the response and
// returns (0, false) so the caller can early-exit.
func (h *CommunityMessagesHandler) requireMember(
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
			"error": "join the community to read or send messages",
		})
		return 0, false
	}
	return userID, true
}

// List — GET /api/communities/:id/messages
//
// Optional query params:
//
//   ?before=<RFC3339 timestamp>   — keyset cursor, returns messages
//                                   strictly older than this. Use the
//                                   oldest currently-loaded message's
//                                   createdAt for the next page.
//   ?limit=<int>                  — clamped 1..200, default 50.
func (h *CommunityMessagesHandler) List(c *gin.Context) {
	communityID := strings.TrimSpace(c.Param("id"))
	if _, ok := h.requireMember(c, communityID); !ok {
		return
	}

	var before time.Time
	if raw := strings.TrimSpace(c.Query("before")); raw != "" {
		if parsed, err := time.Parse(time.RFC3339Nano, raw); err == nil {
			before = parsed
		} else if parsed, err := time.Parse(time.RFC3339, raw); err == nil {
			before = parsed
		}
	}
	uid, _ := c.Get("user_id")
	viewerID, _ := uid.(int64)
	rows, err := h.messages.List(communityID, before, parseLimit(c.Query("limit"), 50), viewerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"messages": rows})
}

// Send — POST /api/communities/:id/messages
//
// Body: { "body": "actual message text" }
//
// Body length is bounded 1..2000 chars. The hydrated row (with author
// name + role from the JOIN in repository.Send) is broadcast on the
// `community:<id>` channel so every connected member sees it within
// the same ms.
func (h *CommunityMessagesHandler) Send(c *gin.Context) {
	communityID := strings.TrimSpace(c.Param("id"))
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}

	var body struct {
		Body           string `json:"body"`
		ParentID       int64  `json:"parentId"`
		AttachmentURL  string `json:"attachmentUrl"`
		AttachmentType string `json:"attachmentType"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Body = strings.TrimSpace(body.Body)
	body.AttachmentURL = strings.TrimSpace(body.AttachmentURL)
	body.AttachmentType = strings.ToLower(strings.TrimSpace(body.AttachmentType))
	// Only image attachments are accepted on this endpoint — audio goes
	// through /messages/audio (multipart upload). The image itself was
	// already uploaded via /me/uploads/image; we just store its URL.
	if body.AttachmentURL != "" && body.AttachmentType != "image" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "only image attachments are allowed here",
		})
		return
	}
	// A message needs either text or an image (the image can stand alone,
	// with an optional caption in body).
	if body.Body == "" && body.AttachmentURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message body or attachment required"})
		return
	}
	if len(body.Body) > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "message too long (max 2000 chars)",
		})
		return
	}
	if len(body.AttachmentURL) > 2048 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "attachment url too long"})
		return
	}
	// If this is a reply, sanity-check the parent belongs to the
	// same community. Skipping this would allow a crafted client to
	// quote-leak content from a community the user isn't in via
	// the JOIN preview returned in the response payload.
	if body.ParentID > 0 {
		ok, err := h.messages.ParentInCommunity(body.ParentID, communityID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if !ok {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "parent message not in this community",
			})
			return
		}
	}

	msg, err := h.messages.Send(communityID, userID, body.Body, repositories.SendOptions{
		ParentID:       body.ParentID,
		AttachmentURL:  body.AttachmentURL,
		AttachmentType: body.AttachmentType,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Broadcast on the community channel — every connected member
	// listening to community:<id> receives this within ms. The author
	// also receives it (and de-dupes against the optimistic local
	// append on the client side).
	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"community_message",
			msg,
		)
	}

	c.JSON(http.StatusOK, gin.H{"message": msg})
}

// ───────── Reactions ──────────────────────────────────────────────

// ToggleReaction — POST /api/communities/:id/messages/:mid/reactions
//
// Body: { "emoji": "👍" }
//
// Member-gated. The emoji must be in the curated allowlist. Toggles
// the (messageID, userID, emoji) row — if the user already placed
// this emoji on this message it's removed, otherwise it's added.
//
// Broadcasts a `community_message_reaction` event on the
// `community:<id>` channel so every connected viewer can patch their
// local copy of the message without refetching.
//
// Response: { added: bool, counts: {emoji: int} }
func (h *CommunityMessagesHandler) ToggleReaction(c *gin.Context) {
	communityID := strings.TrimSpace(c.Param("id"))
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}

	messageID, err := strconv.ParseInt(strings.TrimSpace(c.Param("mid")), 10, 64)
	if err != nil || messageID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
		return
	}

	// Confirm the message lives in this community before mutating —
	// otherwise a member of community A could spam reactions on a
	// message in community B by spoofing the URL.
	msgCommunity, err := h.messages.MessageBelongsTo(messageID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if msgCommunity == "" || msgCommunity != communityID {
		c.JSON(http.StatusNotFound, gin.H{"error": "message not in this community"})
		return
	}

	var body struct {
		Emoji string `json:"emoji"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	emoji := strings.TrimSpace(body.Emoji)
	if !allowedReactionEmojis[emoji] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "emoji not allowed"})
		return
	}

	added, _, counts, err := h.messages.ToggleReaction(messageID, userID, emoji)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if h.hub != nil {
		// Broadcast the reaction patch. Consumers diff this against
		// their local state — e.g. patch reactionCounts[emoji] and
		// (if userID matches viewer) toggle myReactions membership.
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"community_message_reaction",
			gin.H{
				"messageId":   messageID,
				"communityId": communityID,
				"emoji":       emoji,
				"added":       added,
				"userId":      userID,
				"counts":      counts,
			},
		)
	}

	c.JSON(http.StatusOK, gin.H{
		"added":  added,
		"counts": counts,
	})
}

// ListReactors — GET /api/communities/:id/messages/:mid/reactions
//
// Member-gated. Returns the full per-user reaction list for a
// message — drives the "who reacted with what" detail sheet.
//
// Response: { reactors: [{userId, userName, email, role, emoji, at}, ...] }
func (h *CommunityMessagesHandler) ListReactors(c *gin.Context) {
	communityID := strings.TrimSpace(c.Param("id"))
	if _, ok := h.requireMember(c, communityID); !ok {
		return
	}
	messageID, err := strconv.ParseInt(strings.TrimSpace(c.Param("mid")), 10, 64)
	if err != nil || messageID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
		return
	}
	msgCommunity, err := h.messages.MessageBelongsTo(messageID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if msgCommunity == "" || msgCommunity != communityID {
		c.JSON(http.StatusNotFound, gin.H{"error": "message not in this community"})
		return
	}
	reactors, err := h.messages.ListReactors(messageID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"reactors": reactors})
}

// ───────── Delete ─────────────────────────────────────────────────

// Delete — DELETE /api/communities/:id/messages/:mid
//
// Member-gated. The caller must be either:
//   - the message's author, or
//   - a platform admin.
//
// On success we broadcast `community_message_deleted` on
// `community:<id>` so every connected member's chat screen can
// remove the bubble live without a refetch.
//
// Cascade rules from the migrations clean up reactions
// (ON DELETE CASCADE) and detach replies (parent_id ON DELETE SET
// NULL). Replies survive but lose their quote preview.
func (h *CommunityMessagesHandler) Delete(c *gin.Context) {
	communityID := strings.TrimSpace(c.Param("id"))
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	messageID, err := strconv.ParseInt(strings.TrimSpace(c.Param("mid")), 10, 64)
	if err != nil || messageID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
		return
	}

	// Validate the message lives in the community in the URL —
	// stops a member of community A from spoofing the URL to
	// delete a message in community B even with admin privileges.
	msgCommunity, err := h.messages.MessageBelongsTo(messageID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if msgCommunity == "" || msgCommunity != communityID {
		c.JSON(http.StatusNotFound, gin.H{"error": "message not in this community"})
		return
	}

	// Resolve moderation privilege: admin OR community owner can
	// delete any message in the community. Author-only is the
	// fallback when neither holds. Best-effort lookups — failure
	// of either falls through to author-only.
	canModerate := false
	if h.users != nil {
		if u, lookupErr := h.users.GetByID(userID); lookupErr == nil &&
			u != nil &&
			u.Role == "ADMIN" {
			canModerate = true
		}
	}
	if !canModerate && h.social != nil {
		ownerID, ownerErr := h.social.CommunityOwnerID(communityID)
		if ownerErr == nil && ownerID == userID {
			canModerate = true
		}
	}

	if delErr := h.messages.Delete(messageID, userID, canModerate); delErr != nil {
		// Repo returns ErrNoRows when the row didn't exist OR the
		// caller wasn't allowed. We just confirmed the row exists
		// in this community, so this is a permission failure.
		c.JSON(http.StatusForbidden, gin.H{
			"error": "you can only delete your own messages",
		})
		return
	}

	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"community_message_deleted",
			gin.H{
				"messageId":   messageID,
				"communityId": communityID,
				"deletedBy":   userID,
			},
		)
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

// ───────── Pin / Unpin ────────────────────────────────────────────

// TogglePin — POST /api/communities/:id/messages/:mid/pin
//
// Owner-or-admin gated. Toggles the pinned_at timestamp on the
// message; broadcasts a `community_message_pinned` event with the
// new state so every connected member can patch their local copy.
//
// Returns `{pinned: bool, pinnedAt: time?}` on success.
func (h *CommunityMessagesHandler) TogglePin(c *gin.Context) {
	communityID := strings.TrimSpace(c.Param("id"))
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	messageID, err := strconv.ParseInt(strings.TrimSpace(c.Param("mid")), 10, 64)
	if err != nil || messageID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
		return
	}

	// Confirm the message lives in this community before mutating.
	msgCommunity, err := h.messages.MessageBelongsTo(messageID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if msgCommunity == "" || msgCommunity != communityID {
		c.JSON(http.StatusNotFound, gin.H{"error": "message not in this community"})
		return
	}

	// Authorization — must be (a) the community's owner OR (b) a
	// platform admin. Members can't pin even their own messages.
	authorized := false
	if h.users != nil {
		if u, lookupErr := h.users.GetByID(userID); lookupErr == nil &&
			u != nil &&
			u.Role == "ADMIN" {
			authorized = true
		}
	}
	if !authorized && h.social != nil {
		ownerID, ownerErr := h.social.CommunityOwnerID(communityID)
		if ownerErr == nil && ownerID == userID {
			authorized = true
		}
	}
	if !authorized {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "only the community owner or an admin can pin messages",
		})
		return
	}

	pinnedAt, err := h.messages.TogglePin(messageID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"community_message_pinned",
			gin.H{
				"messageId":   messageID,
				"communityId": communityID,
				"pinned":      pinnedAt != nil,
				"pinnedAt":    pinnedAt,
			},
		)
	}
	c.JSON(http.StatusOK, gin.H{
		"pinned":   pinnedAt != nil,
		"pinnedAt": pinnedAt,
	})
}

// ───────── Voice messages ─────────────────────────────────────────

// SendAudio — POST /api/communities/:id/messages/audio
//
// Multipart form fields:
//
//	file       — the recorded audio (m4a/aac/mp3/ogg/wav/webm)
//	durationMs — optional integer ms; client measures it during
//	             record. Server stores 0 when absent.
//	parentId   — optional reply target (same semantics as Send).
//
// Saves the file under `uploads/audio/<random><ext>` and inserts a
// message row pointing at it. Like Send, the result is broadcast on
// `community:<id>` so every member's chat screen lands the bubble
// live.
//
// Member-gated; same parent-in-community defence as Send.
func (h *CommunityMessagesHandler) SendAudio(c *gin.Context) {
	communityID := strings.TrimSpace(c.Param("id"))
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}

	// Cap the multipart parse size so a malicious client can't
	// blow memory by opening a huge upload before we've validated.
	if err := c.Request.ParseMultipartForm(audioMaxBytes + 4096); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid upload"})
		return
	}

	fh, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "audio file required"})
		return
	}
	if fh.Size <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "empty audio file"})
		return
	}
	if fh.Size > audioMaxBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "audio too large"})
		return
	}

	ext := strings.ToLower(filepath.Ext(fh.Filename))
	if ext == "" {
		// No extension on the client filename — default to .m4a since
		// that's what `record` writes by default on iOS/Android.
		ext = ".m4a"
	}
	if !audioExts[ext] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported audio format"})
		return
	}

	// Optional fields.
	durationMs := 0
	if raw := strings.TrimSpace(c.PostForm("durationMs")); raw != "" {
		if n, perr := strconv.Atoi(raw); perr == nil && n > 0 {
			durationMs = n
		}
	}
	parentID := int64(0)
	if raw := strings.TrimSpace(c.PostForm("parentId")); raw != "" {
		if n, perr := strconv.ParseInt(raw, 10, 64); perr == nil && n > 0 {
			parentID = n
		}
	}
	if parentID > 0 {
		ok, err := h.messages.ParentInCommunity(parentID, communityID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if !ok {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "parent message not in this community",
			})
			return
		}
	}

	// Random opaque filename — same 16-byte hex scheme used by the
	// video/image uploader so all media paths look identical.
	randBytes := make([]byte, 16)
	if _, err := rand.Read(randBytes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "rand failure"})
		return
	}
	filename := hex.EncodeToString(randBytes) + ext

	// Storage path — S3 when configured, otherwise local disk.
	//
	// `publicURL` is what gets stored in the message row's
	// `attachment_url`. `cleanupOnInsertFailure` runs only if the DB
	// insert below fails, so we don't leak orphan files (cheap on
	// disk; effectively zero for S3 since orphans are <$0.01/year).
	var publicURL string
	cleanupOnInsertFailure := func() {}

	if h.s3 != nil {
		src, err := fh.Open()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read upload"})
			return
		}
		key := "audio/" + filename
		contentType := mime.TypeByExtension(ext)
		if contentType == "" {
			// Voice messages are AAC-in-m4a by default; a generic audio
			// fallback keeps playback working across browsers if the
			// extension is missing from the mime DB.
			contentType = "audio/mp4"
		}
		uploadErr := h.s3.Upload(c.Request.Context(), key, contentType, src)
		_ = src.Close()
		if uploadErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "s3 upload: " + uploadErr.Error()})
			return
		}
		signed, err := h.s3.PresignGet(c.Request.Context(), key)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "presign: " + err.Error()})
			return
		}
		publicURL = signed
	} else {
		if err := os.MkdirAll(filepath.Join("uploads", "audio"), 0o755); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "storage init failed"})
			return
		}
		diskPath := filepath.Join("uploads", "audio", filename)
		if err := c.SaveUploadedFile(fh, diskPath); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "save failed"})
			return
		}
		publicURL = "/uploads/audio/" + filename
		cleanupOnInsertFailure = func() { _ = os.Remove(diskPath) }
	}

	msg, err := h.messages.Send(communityID, userID, "", repositories.SendOptions{
		ParentID:             parentID,
		AttachmentURL:        publicURL,
		AttachmentType:       "audio",
		AttachmentDurationMs: durationMs,
	})
	if err != nil {
		cleanupOnInsertFailure()
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

	c.JSON(http.StatusOK, gin.H{"message": msg})
}


// =============================================================================
// Step-21 (mig 0021) — search, edit, read receipts, settings, typing.
// Polls live in their own handler file (community_polls.go).
// =============================================================================

// Search — GET /api/communities/:id/messages/search?q=<query>
//
// Member-gated. Returns up to 50 matches sorted newest-first. Empty
// query returns an empty array (not an error) so the UI's blank-state
// is trivially handled.
func (h *CommunityMessagesHandler) Search(c *gin.Context) {
	communityID := c.Param("id")
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	query := strings.TrimSpace(c.Query("q"))
	results, err := h.messages.Search(communityID, query, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"messages": results, "query": query})
}

// MarkRead — POST /api/communities/:id/messages/:mid/read
//
// Member-gated. Idempotent — re-reading is a no-op. Honours the
// per-user read-receipts opt-out at the repo level.
func (h *CommunityMessagesHandler) MarkRead(c *gin.Context) {
	communityID := c.Param("id")
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	mid, perr := strconv.ParseInt(c.Param("mid"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
		return
	}
	if err := h.messages.MarkRead(mid, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"message_read",
			gin.H{"messageId": mid, "userId": userID},
		)
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// MarkBatchRead — POST /api/communities/:id/messages/read-batch
//
// Body: { "messageIds": [<int>, ...] } — up to 200 ids per call.
// Used by mobile to mark a screenful of messages read on scroll-to-view.
func (h *CommunityMessagesHandler) MarkBatchRead(c *gin.Context) {
	communityID := c.Param("id")
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	var body struct {
		MessageIDs []int64 `json:"messageIds"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if len(body.MessageIDs) == 0 {
		c.JSON(http.StatusOK, gin.H{"inserted": 0})
		return
	}
	if len(body.MessageIDs) > 200 {
		body.MessageIDs = body.MessageIDs[:200]
	}
	n, err := h.messages.MarkBatchRead(body.MessageIDs, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if h.hub != nil && n > 0 {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"message_read_batch",
			gin.H{"messageIds": body.MessageIDs, "userId": userID},
		)
	}
	c.JSON(http.StatusOK, gin.H{"inserted": n})
}

// ListReaders — GET /api/communities/:id/messages/:mid/reads
//
// Member-gated. Returns the avatar list for the "Seen by N" sheet.
func (h *CommunityMessagesHandler) ListReaders(c *gin.Context) {
	communityID := c.Param("id")
	if _, ok := h.requireMember(c, communityID); !ok {
		return
	}
	mid, perr := strconv.ParseInt(c.Param("mid"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
		return
	}
	readers, err := h.messages.ListReaders(mid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"readers": readers})
}

// EditMessage — PATCH /api/communities/:id/messages/:mid
//
// Body: { "body": "<new text>" }
//
// Author-only. 15-min edit window enforced at the repo level — past
// the window we return 409. After successful edit, broadcasts a
// `community_message_edited` event on the community channel.
func (h *CommunityMessagesHandler) EditMessage(c *gin.Context) {
	communityID := c.Param("id")
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	mid, perr := strconv.ParseInt(c.Param("mid"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid message id"})
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
		c.JSON(http.StatusBadRequest, gin.H{"error": "body required"})
		return
	}
	updated, err := h.messages.EditMessage(mid, userID, body.Body)
	if err != nil {
		c.JSON(http.StatusConflict, gin.H{
			"error": "can't edit (not author, or 15-minute window expired)",
		})
		return
	}
	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			"community_message_edited",
			updated,
		)
	}
	c.JSON(http.StatusOK, gin.H{"message": updated})
}

// SetReadReceiptsEnabled — PATCH /api/me/settings/read-receipts
//
// Body: { "enabled": true|false }
func (h *CommunityMessagesHandler) SetReadReceiptsEnabled(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	var body struct {
		Enabled bool `json:"enabled"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if err := h.messages.SetReadReceiptsEnabled(userID, body.Enabled); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"enabled": body.Enabled})
}

// GetReadReceiptsEnabled — GET /api/me/settings/read-receipts
func (h *CommunityMessagesHandler) GetReadReceiptsEnabled(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	enabled, err := h.messages.GetReadReceiptsEnabled(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"enabled": enabled})
}

// Typing — POST /api/communities/:id/typing
//
// Body: { "stopped": true|false }   (default: false → "started")
//
// Pure realtime fan-out — no DB writes. Member-gated so non-members
// can't spam typing events. Auto-clears on the client after 5s of
// silence (mobile sends stopped: true when text goes empty).
func (h *CommunityMessagesHandler) Typing(c *gin.Context) {
	communityID := c.Param("id")
	userID, ok := h.requireMember(c, communityID)
	if !ok {
		return
	}
	var body struct {
		Stopped bool `json:"stopped"`
	}
	_ = c.ShouldBindJSON(&body)

	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user not found"})
		return
	}
	displayName := user.Email
	if user.Name.Valid && strings.TrimSpace(user.Name.String) != "" {
		displayName = user.Name.String
	}
	event := "typing_started"
	if body.Stopped {
		event = "typing_stopped"
	}
	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(communityID),
			event,
			gin.H{
				"userId":      userID,
				"name":        displayName,
				"communityId": communityID,
			},
		)
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// time import is used by the existing handler, mute unused warning
var _ = time.Now
