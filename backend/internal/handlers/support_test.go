package handlers

import (
	"testing"
	"time"
)

// supportTakeToken is the in-memory throttle that guards the support
// chat against accidental double-taps and basic spam. Contract:
//
//   - first call for a given user returns true (lets the message through)
//   - second call within `minGap` returns false
//   - call after `minGap` has elapsed returns true again
//   - the throttle is per-user — one user's token does not affect another
//
// The map that backs the throttle is package-level state, so each test
// uses a fresh high user ID to avoid cross-test interference.

func TestSupportTakeToken_FirstCallAllowed(t *testing.T) {
	const uid = int64(900_001)
	if !supportTakeToken(uid, 100*time.Millisecond) {
		t.Fatal("first call should be allowed")
	}
}

func TestSupportTakeToken_RapidSecondCallDenied(t *testing.T) {
	const uid = int64(900_002)
	const gap = 200 * time.Millisecond
	if !supportTakeToken(uid, gap) {
		t.Fatal("first call should be allowed")
	}
	if supportTakeToken(uid, gap) {
		t.Fatal("second call inside the window should be denied")
	}
}

func TestSupportTakeToken_AfterWindowAllowsAgain(t *testing.T) {
	const uid = int64(900_003)
	const gap = 30 * time.Millisecond
	if !supportTakeToken(uid, gap) {
		t.Fatal("first call should be allowed")
	}
	// Sleep slightly longer than the gap so the wall-clock check
	// inside the throttle has crossed the boundary.
	time.Sleep(gap + 20*time.Millisecond)
	if !supportTakeToken(uid, gap) {
		t.Fatal("call after the window should be allowed")
	}
}

func TestSupportTakeToken_PerUserIsolation(t *testing.T) {
	const u1 = int64(900_004)
	const u2 = int64(900_005)
	const gap = time.Second
	if !supportTakeToken(u1, gap) {
		t.Fatal("u1 first call should be allowed")
	}
	if !supportTakeToken(u2, gap) {
		t.Fatal("u2 first call should not be blocked by u1 having just taken its token")
	}
	if supportTakeToken(u1, gap) {
		t.Fatal("u1 second call within window should still be denied")
	}
}

func TestSupportTakeToken_ZeroGapAlwaysAllows(t *testing.T) {
	// A minGap of 0 means "no throttling" — every call should pass.
	// Guards against a refactor that flips the comparator and starts
	// denying all sends when the configured gap is zero.
	const uid = int64(900_006)
	for i := 0; i < 5; i++ {
		if !supportTakeToken(uid, 0) {
			t.Fatalf("call %d with zero gap should be allowed", i+1)
		}
	}
}
