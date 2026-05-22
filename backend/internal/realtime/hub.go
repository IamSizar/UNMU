// Package realtime is the in-process pub/sub layer that bridges Postgres
// LISTEN/NOTIFY notifications to connected WebSocket clients.
//
// Architecture:
//
//	  Postgres trigger ── NOTIFY ──> Listener (listener.go)
//	                                       │
//	                                       ▼
//	                                     Hub  ── per-channel fanout ──> WS clients
//
// Hub is goroutine-safe. Listener and the websocket handler both call
// Publish() / Register() / Unregister() concurrently.
package realtime

import (
	"encoding/json"
	"log"
	"sync"
	"time"
)

// Channel identifiers used by NOTIFY senders + WS subscribers.
//
//	user:<id>    — private events for one user (role changes, app status)
//	admin        — broadcast to admin clients (new applications, flagged content)
//	expert:<id>  — broadcast to subscribers of one expert (new posts)
const (
	ChannelAdmin = "admin"
)

func ChannelUser(userID int64) string      { return "user:" + itoa(userID) }
func ChannelExpert(expertID string) string { return "expert:" + expertID }

// ChannelCommunity — broadcast to every member of a community.
// Used by the chat hot-path: when a user sends a message, the
// handler publishes on this channel and every connected member
// receives the bubble live (no polling).
func ChannelCommunity(communityID string) string {
	return "community:" + communityID
}

func itoa(n int64) string {
	// Tiny inline int->string to avoid pulling strconv into a tight package.
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}

// Event is the JSON payload pushed over the wire to clients.
type Event struct {
	Type      string          `json:"type"`
	Data      json.RawMessage `json:"data,omitempty"`
	Timestamp time.Time       `json:"timestamp"`
}

// Client represents one connected WebSocket. The hub doesn't care HOW it
// writes to the network — it only knows about the Send channel. The
// websocket handler reads from Send and writes to the underlying conn.
type Client struct {
	UserID   int64
	IsAdmin  bool
	ExpertID string // "" for non-experts. Subscribed to ChannelExpert(expertID).

	Send chan Event

	hub      *Hub
	channels []string // subscribed channels (set at Register time)
}

// Hub holds every connected client and routes events to the right ones.
type Hub struct {
	mu      sync.RWMutex
	clients map[*Client]struct{}
}

func NewHub() *Hub {
	return &Hub{clients: make(map[*Client]struct{})}
}

// Register adds a new client. Subscribes them to:
//
//   * user:<their id>
//   * admin                  (only if IsAdmin)
//   * expert:<their id>      (only if they are an expert)
//   * community:<id> for each id in [communityIDs]
//
// communityIDs is sourced by the caller (the realtime handler) from
// the `community_members` table — every community the user has joined
// auto-subscribes so per-community chat broadcasts reach them without
// the client explicitly subscribing.
//
// Returns the client (also accessible via *Client.hub) so the caller
// can goroutine-pump messages from c.Send.
func (h *Hub) Register(
	userID int64,
	isAdmin bool,
	expertID string,
	communityIDs []string,
) *Client {
	c := &Client{
		UserID:   userID,
		IsAdmin:  isAdmin,
		ExpertID: expertID,
		Send:     make(chan Event, 32),
		hub:      h,
	}
	c.channels = append(c.channels, ChannelUser(userID))
	if isAdmin {
		c.channels = append(c.channels, ChannelAdmin)
	}
	if expertID != "" {
		c.channels = append(c.channels, ChannelExpert(expertID))
	}
	for _, id := range communityIDs {
		if id == "" {
			continue
		}
		c.channels = append(c.channels, ChannelCommunity(id))
	}

	h.mu.Lock()
	h.clients[c] = struct{}{}
	h.mu.Unlock()

	log.Printf("[realtime] client connected userID=%d admin=%v expert=%q channels=%v",
		userID, isAdmin, expertID, c.channels)
	return c
}

// Unregister removes the client and closes its Send channel. Idempotent.
func (h *Hub) Unregister(c *Client) {
	h.mu.Lock()
	if _, ok := h.clients[c]; ok {
		delete(h.clients, c)
		close(c.Send)
	}
	h.mu.Unlock()
}

// Publish fans an event out to every client subscribed to `channel`. Drops
// the event for any client whose Send buffer is full (slow client) — that's
// preferable to blocking the listener goroutine.
func (h *Hub) Publish(channel string, ev Event) {
	if ev.Timestamp.IsZero() {
		ev.Timestamp = time.Now()
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients {
		if !sliceContains(c.channels, channel) {
			continue
		}
		select {
		case c.Send <- ev:
		default:
			// Slow consumer — skip rather than block. They'll re-sync on
			// reconnect.
			log.Printf("[realtime] slow client userID=%d, dropping %s", c.UserID, ev.Type)
		}
	}
}

// PublishJSON marshals data and publishes a typed event in one call. Used by
// the listener.
func (h *Hub) PublishJSON(channel, eventType string, data any) {
	raw, err := json.Marshal(data)
	if err != nil {
		log.Printf("[realtime] marshal %s: %v", eventType, err)
		return
	}
	h.Publish(channel, Event{Type: eventType, Data: raw})
}

func sliceContains(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}
