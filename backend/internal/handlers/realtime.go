package handlers

import (
	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"halalstocks/pkg/jwt"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// RealtimeHandler upgrades GET /api/ws to a WebSocket and registers the
// resulting connection with the Hub.
//
// Auth: JWT comes via the `?token=...` query string (browsers don't allow
// custom Authorization headers on the initial WS handshake from JS). Both
// the Flutter and React clients pass the same token they use elsewhere.
type RealtimeHandler struct {
	hub      *realtime.Hub
	users    *repositories.UserRepository
	// social provides the joined-community lookup so each WS client
	// auto-subscribes to `community:<id>` channels for live chat.
	social   *repositories.SocialRepository
	upgrader websocket.Upgrader
}

func NewRealtimeHandler(
	hub *realtime.Hub,
	users *repositories.UserRepository,
	social *repositories.SocialRepository,
) *RealtimeHandler {
	return &RealtimeHandler{
		hub:    hub,
		users:  users,
		social: social,
		upgrader: websocket.Upgrader{
			// We rely on the same CORS policy as REST. WS handshake doesn't
			// run our gin CORS middleware, so accept all origins here.
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}
}

func (h *RealtimeHandler) Connect(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "token query param required"})
		return
	}
	claims, err := jwt.ValidateToken(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}

	user, err := h.users.GetByID(claims.UserID)
	if err != nil || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	conn, err := h.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("[realtime] upgrade failed: %v", err)
		return
	}

	expertID := ""
	if user.ExpertID.Valid {
		expertID = user.ExpertID.String
	}
	// Best-effort fetch of the user's community memberships — failure
	// shouldn't break the WS connection itself, the user just won't
	// auto-receive community chat events for this session.
	var joinedCommunities []string
	if h.social != nil {
		if ids, ferr := h.social.ListJoinedCommunityIDs(claims.UserID); ferr == nil {
			joinedCommunities = ids
		}
	}
	client := h.hub.Register(
		claims.UserID,
		user.Role == "ADMIN",
		expertID,
		joinedCommunities,
	)
	defer h.hub.Unregister(client)

	// Reader goroutine: keeps the connection alive (we ignore inbound
	// messages for now, but reading is required so pings are processed).
	conn.SetReadLimit(4096)
	conn.SetReadDeadline(time.Now().Add(70 * time.Second))
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(70 * time.Second))
		return nil
	})
	go func() {
		defer conn.Close()
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()

	// Writer loop on the calling goroutine.
	pinger := time.NewTicker(30 * time.Second)
	defer pinger.Stop()

	for {
		select {
		case ev, ok := <-client.Send:
			if !ok {
				_ = conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			_ = conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteJSON(ev); err != nil {
				return
			}
		case <-pinger.C:
			_ = conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
