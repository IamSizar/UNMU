package handlers

import (
	"testing"
	"time"
)

// The profile's "member since" cell reads createdAt; an unknown time must
// be left out rather than sent as year 1.
func TestMemberSince(t *testing.T) {
	if got := memberSince(time.Time{}); got != "" {
		t.Fatalf("zero time: got %q, want empty", got)
	}
	at := time.Date(2026, 5, 3, 10, 0, 0, 0, time.FixedZone("AST", 3*3600))
	if got := memberSince(at); got != "2026-05-03T07:00:00Z" {
		t.Fatalf("got %q", got)
	}
}
