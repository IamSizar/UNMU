package services

import (
	"context"
	"log"
	"time"

	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// PollCloser — every 60s, flips polls whose `expires_at` has passed
// to closed and broadcasts a `poll_closed` event on each affected
// community channel. Same cadence as the other expirers.
type PollCloser struct {
	polls    *repositories.CommunityPollsRepository
	messages *repositories.CommunityMessagesRepository
	hub      *realtime.Hub
}

func NewPollCloser(
	polls *repositories.CommunityPollsRepository,
	messages *repositories.CommunityMessagesRepository,
	hub *realtime.Hub,
) *PollCloser {
	return &PollCloser{polls: polls, messages: messages, hub: hub}
}

func (p *PollCloser) Start(ctx context.Context) {
	go p.run(ctx)
}

func (p *PollCloser) run(ctx context.Context) {
	tick := time.NewTicker(60 * time.Second)
	defer tick.Stop()
	// Run once on startup so any polls expired during downtime get
	// closed without waiting for the first tick.
	p.tick()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			p.tick()
		}
	}
}

func (p *PollCloser) tick() {
	pollIDs, communityIDs, msgIDs, err := p.polls.PromoteExpiringPolls()
	if err != nil {
		log.Printf("[poll_closer] promote failed: %v", err)
		return
	}
	if len(pollIDs) == 0 {
		return
	}
	log.Printf("[poll_closer] closed %d expired poll(s)", len(pollIDs))
	if p.hub == nil {
		return
	}
	// Broadcast one `poll_closed` event per closed poll on its host
	// community channel. Each event carries the freshly hydrated host
	// message so the bubble flips locked + final-counts in one shot.
	for i := range pollIDs {
		msg, err := p.messages.GetByID(msgIDs[i], 0)
		if err != nil {
			continue
		}
		p.hub.PublishJSON(
			realtime.ChannelCommunity(communityIDs[i]),
			"poll_closed",
			gin.H{"message": msg, "pollId": pollIDs[i]},
		)
	}
}
