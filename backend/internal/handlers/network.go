// Package handlers — admin network graph view.
//
// Powers the "/network" page on the admin dashboard: a single
// snapshot of every node + edge across the platform, sized + colored
// for a force-directed graph render.
//
// One request, one response, one round-trip. The page polls this
// endpoint once on mount + re-fetches on relevant WebSocket events
// (subscription_*, application_*, community_proposal_*).
package handlers

import (
	"database/sql"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// NetworkHandler — needs nothing beyond raw DB access. We touch six
// tables (users, experts, communities, expert_subscriptions,
// community_members, expert_applications) directly because the
// existing repos don't expose the wide JOINs the graph needs.
type NetworkHandler struct {
	db *sql.DB
}

func NewNetworkHandler(db *sql.DB) *NetworkHandler {
	return &NetworkHandler{db: db}
}

// ── Response shape ─────────────────────────────────────────────────
//
// Flat JSON: three node lists + one edge list + one pending-events
// list. Frontend prefers flat arrays over a nested object tree because
// react-force-graph-2d wants `{ nodes: [], links: [] }` and we'd
// flatten anyway.

type NetExpertNode struct {
	ID              int64  `json:"id"` // users.id (the expert is a user with role=EXPERT)
	ExpertID        string `json:"expertId"`
	Name            string `json:"name"`
	Expertise       string `json:"expertise"`
	SubscriberCount int    `json:"subscriberCount"`
	CommunityCount  int    `json:"communityCount"`
	Pending         bool   `json:"pending"` // application still pending review
}

type NetUserNode struct {
	ID                int64  `json:"id"`
	Name              string `json:"name"`
	Email             string `json:"email"`
	SubscriptionCount int    `json:"subscriptionCount"`
	MembershipCount   int    `json:"membershipCount"`
}

type NetCommunityNode struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	MemberCount   int    `json:"memberCount"`
	OwnerUserID   int64  `json:"ownerUserId"`
}

type NetEdge struct {
	// "subscription" — user → expert (uses status + plan)
	// "community_member" — user → community
	// "owns" — expert → community
	Type   string `json:"type"`
	Source int64  `json:"source"`
	// Target encoded as int (user/expert id) OR string (community id).
	// We send both fields; frontend picks the right one based on `type`.
	TargetUserID    *int64  `json:"targetUserId,omitempty"`
	TargetCommunity *string `json:"targetCommunity,omitempty"`
	Status          string  `json:"status,omitempty"` // active|pending|cancelled|expired
	Plan            string  `json:"plan,omitempty"`
}

type NetPendingEvent struct {
	// One of: "expert_application" | "subscription" | "community_subscription" | "community_proposal"
	Kind         string    `json:"kind"`
	ID           int64     `json:"id"`
	// Display string — what the admin sees in the feed.
	Headline     string    `json:"headline"`
	SubText      string    `json:"subText,omitempty"`
	// Time of creation. Frontend formats relative ("2m ago").
	CreatedAt    time.Time `json:"createdAt"`
	// Optional pointers to the affected nodes so the frontend can
	// highlight them when the event is hovered/focused.
	ActorUserID  *int64    `json:"actorUserId,omitempty"`
	TargetUserID *int64    `json:"targetUserId,omitempty"`
}

type NetworkGraphResponse struct {
	Experts     []NetExpertNode    `json:"experts"`
	Users       []NetUserNode      `json:"users"`
	Communities []NetCommunityNode `json:"communities"`
	Edges       []NetEdge          `json:"edges"`
	Pending     []NetPendingEvent  `json:"pending"`
}

// Graph — GET /api/admin/network/graph
//
// Returns the full network state. Cheap query mix (~6 SELECTs).
// Pagination intentionally absent — the admin viewport is the whole
// platform; if we ever cross 5k users we'll switch to a windowed
// view by region/role at that point.
func (h *NetworkHandler) Graph(c *gin.Context) {
	resp := NetworkGraphResponse{
		Experts:     []NetExpertNode{},
		Users:       []NetUserNode{},
		Communities: []NetCommunityNode{},
		Edges:       []NetEdge{},
		Pending:     []NetPendingEvent{},
	}

	// ── Experts (users with role=EXPERT, joined to experts table) ───
	expertRows, err := h.db.Query(`
		SELECT
		    u.id,
		    COALESCE(u.expert_id, '') AS expert_id,
		    COALESCE(u.name, u.email) AS name,
		    COALESCE(e.expertise, '') AS expertise,
		    (SELECT count(*) FROM expert_subscriptions s
		      WHERE s.expert_id = u.expert_id AND s.status = 'active') AS subscriber_count,
		    (SELECT count(*) FROM communities c WHERE c.owner_id = u.id) AS community_count
		FROM users u
		LEFT JOIN experts e ON e.id = u.expert_id
		WHERE u.role = 'EXPERT'
	`)
	if err != nil {
		log.Printf("[network] expert query: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load experts"})
		return
	}
	defer expertRows.Close()
	for expertRows.Next() {
		var n NetExpertNode
		if err := expertRows.Scan(&n.ID, &n.ExpertID, &n.Name, &n.Expertise,
			&n.SubscriberCount, &n.CommunityCount); err != nil {
			log.Printf("[network] expert scan: %v", err)
			continue
		}
		resp.Experts = append(resp.Experts, n)
	}

	// Flag experts that still have a pending application — useful for
	// the "this expert is pending" halo in the graph.
	pendingExpertIDs := map[int64]bool{}
	pendRows, err := h.db.Query(
		`SELECT DISTINCT user_id FROM expert_applications WHERE status = 'pending'`,
	)
	if err == nil {
		for pendRows.Next() {
			var id int64
			if err := pendRows.Scan(&id); err == nil {
				pendingExpertIDs[id] = true
			}
		}
		pendRows.Close()
	}
	for i := range resp.Experts {
		if pendingExpertIDs[resp.Experts[i].ID] {
			resp.Experts[i].Pending = true
		}
	}

	// ── Users (role=USER) ──────────────────────────────────────────
	userRows, err := h.db.Query(`
		SELECT
		    u.id,
		    COALESCE(u.name, '')  AS name,
		    u.email,
		    (SELECT count(*) FROM expert_subscriptions s WHERE s.user_id = u.id AND s.status='active') AS sub_count,
		    (SELECT count(*) FROM community_members cm WHERE cm.user_id = u.id) AS mem_count
		FROM users u
		WHERE u.role = 'USER'
	`)
	if err != nil {
		log.Printf("[network] user query: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load users"})
		return
	}
	defer userRows.Close()
	for userRows.Next() {
		var n NetUserNode
		if err := userRows.Scan(&n.ID, &n.Name, &n.Email,
			&n.SubscriptionCount, &n.MembershipCount); err != nil {
			log.Printf("[network] user scan: %v", err)
			continue
		}
		resp.Users = append(resp.Users, n)
	}

	// ── Communities ────────────────────────────────────────────────
	commRows, err := h.db.Query(`
		SELECT
		    c.id,
		    COALESCE(c.name, c.id) AS name,
		    (SELECT count(*) FROM community_members cm WHERE cm.community_id = c.id) AS mem_count,
		    COALESCE(c.owner_id, 0) AS owner_user_id
		FROM communities c
	`)
	if err != nil {
		log.Printf("[network] community query: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load communities"})
		return
	}
	defer commRows.Close()
	for commRows.Next() {
		var n NetCommunityNode
		if err := commRows.Scan(&n.ID, &n.Name, &n.MemberCount, &n.OwnerUserID); err != nil {
			log.Printf("[network] community scan: %v", err)
			continue
		}
		resp.Communities = append(resp.Communities, n)
	}

	// ── Edges: subscriptions (user → expert) ───────────────────────
	subRows, err := h.db.Query(`
		SELECT s.user_id, u.id AS expert_user_id, COALESCE(s.status, 'pending'), COALESCE(s.plan, '')
		FROM expert_subscriptions s
		JOIN users u ON u.expert_id = s.expert_id
		WHERE s.status IN ('active', 'pending')
	`)
	if err == nil {
		for subRows.Next() {
			var e NetEdge
			var expertUserID int64
			if err := subRows.Scan(&e.Source, &expertUserID, &e.Status, &e.Plan); err != nil {
				continue
			}
			e.Type = "subscription"
			e.TargetUserID = &expertUserID
			resp.Edges = append(resp.Edges, e)
		}
		subRows.Close()
	}

	// ── Edges: community memberships (user → community) ───────────
	memRows, err := h.db.Query(`
		SELECT user_id, community_id FROM community_members
	`)
	if err == nil {
		for memRows.Next() {
			var e NetEdge
			var cid string
			if err := memRows.Scan(&e.Source, &cid); err != nil {
				continue
			}
			e.Type = "community_member"
			e.TargetCommunity = &cid
			resp.Edges = append(resp.Edges, e)
		}
		memRows.Close()
	}

	// ── Edges: ownership (expert-user → community) ────────────────
	ownRows, err := h.db.Query(`
		SELECT c.owner_id, c.id
		FROM communities c
		JOIN users u ON u.id = c.owner_id
		WHERE u.role = 'EXPERT'
	`)
	if err == nil {
		for ownRows.Next() {
			var e NetEdge
			var cid string
			if err := ownRows.Scan(&e.Source, &cid); err != nil {
				continue
			}
			e.Type = "owns"
			e.TargetCommunity = &cid
			resp.Edges = append(resp.Edges, e)
		}
		ownRows.Close()
	}

	// ── Pending events (for the right-side feed) ──────────────────

	// Expert applications
	appRows, err := h.db.Query(`
		SELECT id, user_id, COALESCE(full_name, ''), submitted_at
		FROM expert_applications
		WHERE status = 'pending'
		ORDER BY submitted_at DESC
		LIMIT 20
	`)
	if err == nil {
		for appRows.Next() {
			var ev NetPendingEvent
			var actorID int64
			var fullName string
			if err := appRows.Scan(&ev.ID, &actorID, &fullName, &ev.CreatedAt); err != nil {
				continue
			}
			ev.Kind = "expert_application"
			ev.Headline = fullName
			if fullName == "" {
				ev.Headline = "Expert application"
			}
			ev.SubText = "Wants to become a verified expert"
			ev.ActorUserID = &actorID
			resp.Pending = append(resp.Pending, ev)
		}
		appRows.Close()
	}

	// Pending expert subscriptions
	subPendRows, err := h.db.Query(`
		SELECT s.id, s.user_id, COALESCE(u_target.id, 0), COALESCE(u.name, u.email), COALESCE(u_target.name, ''), s.created_at, COALESCE(s.plan, '')
		FROM expert_subscriptions s
		LEFT JOIN users u ON u.id = s.user_id
		LEFT JOIN users u_target ON u_target.expert_id = s.expert_id
		WHERE s.status = 'pending'
		ORDER BY s.created_at DESC
		LIMIT 20
	`)
	if err == nil {
		for subPendRows.Next() {
			var ev NetPendingEvent
			var actorID, targetID int64
			var actorName, targetName, plan string
			if err := subPendRows.Scan(&ev.ID, &actorID, &targetID, &actorName, &targetName, &ev.CreatedAt, &plan); err != nil {
				continue
			}
			ev.Kind = "subscription"
			ev.Headline = actorName + " → " + targetName
			ev.SubText = "Subscription · " + plan
			ev.ActorUserID = &actorID
			if targetID != 0 {
				ev.TargetUserID = &targetID
			}
			resp.Pending = append(resp.Pending, ev)
		}
		subPendRows.Close()
	}

	// Pending community subscriptions
	commSubRows, err := h.db.Query(`
		SELECT cs.id, cs.user_id, COALESCE(u.name, u.email), cs.community_id, COALESCE(c.name, cs.community_id), cs.created_at
		FROM community_subscriptions cs
		LEFT JOIN users u ON u.id = cs.user_id
		LEFT JOIN communities c ON c.id = cs.community_id
		WHERE cs.status = 'pending'
		ORDER BY cs.created_at DESC
		LIMIT 20
	`)
	if err == nil {
		for commSubRows.Next() {
			var ev NetPendingEvent
			var actorID int64
			var actorName, commName, commID string
			if err := commSubRows.Scan(&ev.ID, &actorID, &actorName, &commID, &commName, &ev.CreatedAt); err != nil {
				continue
			}
			ev.Kind = "community_subscription"
			ev.Headline = actorName + " → " + commName
			ev.SubText = "Community membership"
			ev.ActorUserID = &actorID
			resp.Pending = append(resp.Pending, ev)
		}
		commSubRows.Close()
	}

	// Pending community proposals (new community ideas from experts)
	propRows, err := h.db.Query(`
		SELECT id, user_id, COALESCE(name, ''), submitted_at
		FROM community_proposals
		WHERE status = 'pending'
		ORDER BY submitted_at DESC
		LIMIT 20
	`)
	if err == nil {
		for propRows.Next() {
			var ev NetPendingEvent
			var actorID int64
			var name string
			if err := propRows.Scan(&ev.ID, &actorID, &name, &ev.CreatedAt); err != nil {
				continue
			}
			ev.Kind = "community_proposal"
			ev.Headline = name
			if name == "" {
				ev.Headline = "New community proposal"
			}
			ev.SubText = "Awaiting review"
			ev.ActorUserID = &actorID
			resp.Pending = append(resp.Pending, ev)
		}
		propRows.Close()
	}

	c.JSON(http.StatusOK, resp)
}
