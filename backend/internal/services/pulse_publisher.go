package services

import (
	"context"
	"log"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
)

// PulsePublisher publishes scheduled Pulse items when their time arrives.
//
// Same pattern as ScheduledPublisher (posts): a 60-second ticker that also runs
// once at startup, so anything that came due while the server was down goes
// live straight away. The database side (PromoteDue) uses FOR UPDATE SKIP
// LOCKED, so two running instances never publish the same item twice.
//
// onPublished, if set, is called with the items that just went live (used to
// send the "new Pulse" notification). A failure there never un-publishes
// anything: publishing already succeeded and is committed.
type PulsePublisher struct {
	repo        *repositories.PulseAdminRepository
	onPublished func(ctx context.Context, items []models.PulseAdminItem)
}

// NewPulsePublisher returns an idle publisher; call Start to run it.
func NewPulsePublisher(
	repo *repositories.PulseAdminRepository,
	onPublished func(ctx context.Context, items []models.PulseAdminItem),
) *PulsePublisher {
	return &PulsePublisher{repo: repo, onPublished: onPublished}
}

// Start launches the background loop. It returns immediately; cancelling ctx
// stops the loop.
func (p *PulsePublisher) Start(ctx context.Context) {
	go p.run(ctx)
}

func (p *PulsePublisher) run(ctx context.Context) {
	tick := time.NewTicker(60 * time.Second)
	defer tick.Stop()
	p.tick(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			p.tick(ctx)
		}
	}
}

func (p *PulsePublisher) tick(ctx context.Context) {
	promoted, err := p.repo.PromoteDue(ctx, time.Now())
	if err != nil {
		log.Printf("[pulse_publisher] promote failed: %v", err)
		return
	}
	if len(promoted) == 0 {
		return
	}
	log.Printf("[pulse_publisher] published %d scheduled item(s)", len(promoted))
	if p.onPublished != nil {
		p.onPublished(ctx, promoted)
	}
}
