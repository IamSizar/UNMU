package services

import (
	"context"
	"log"
	"time"

	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// ScheduledPublisher promotes posts whose `publish_at` has passed
// from status='scheduled' to 'published'. Mig 0020 / item 4.15.
//
// Cadence: 60 seconds — same as SubscriptionExpirer for consistency.
// The query is cheap thanks to the partial index
// `idx_posts_scheduled` (only scheduled rows are scanned).
//
// For each promoted row we broadcast a `post_published` realtime
// event on the appropriate channel:
//
//   * target=community → channel `community:<id>`
//   * target=expert    → channel `expert:<id>`
//
// The mobile app can listen + prepend the new row without polling.
//
// Robustness:
//   - PromoteScheduledPosts is one atomic UPDATE … RETURNING so
//     two expirers can't double-publish the same row.
//   - A nil hub is tolerated — DB transitions still happen, no
//     events are broadcast.
//   - Errors are logged at WARN. A bad query gets retried next tick.
type ScheduledPublisher struct {
	posts *repositories.SocialRepository
	hub   *realtime.Hub
}

// NewScheduledPublisher returns an idle publisher. Call Start to
// kick off the background loop.
func NewScheduledPublisher(
	posts *repositories.SocialRepository, hub *realtime.Hub,
) *ScheduledPublisher {
	return &ScheduledPublisher{posts: posts, hub: hub}
}

// Start launches the background goroutine. Returns immediately;
// canceling [ctx] stops the loop.
func (s *ScheduledPublisher) Start(ctx context.Context) {
	go s.run(ctx)
}

func (s *ScheduledPublisher) run(ctx context.Context) {
	tick := time.NewTicker(60 * time.Second)
	defer tick.Stop()
	// Run once on startup so any rows that were due during a downtime
	// window get promoted immediately rather than waiting up to 60s.
	s.tick()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			s.tick()
		}
	}
}

func (s *ScheduledPublisher) tick() {
	promoted, err := s.posts.PromoteScheduledPosts()
	if err != nil {
		log.Printf("[scheduled_publisher] promote failed: %v", err)
		return
	}
	if len(promoted) == 0 {
		return
	}
	log.Printf("[scheduled_publisher] promoted %d post(s)", len(promoted))
	if s.hub == nil {
		return
	}
	for _, p := range promoted {
		var channel string
		switch {
		case p.CommunityID != nil:
			channel = realtime.ChannelCommunity(*p.CommunityID)
		case p.ExpertID != nil:
			channel = realtime.ChannelExpert(*p.ExpertID)
		default:
			continue
		}
		s.hub.PublishJSON(channel, "post_published", gin.H{
			"postId":     p.ID,
			"targetType": p.TargetType,
			"authorId":   p.AuthorID,
		})
	}
}
