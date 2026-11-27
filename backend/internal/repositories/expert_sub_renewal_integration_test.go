package repositories

import (
	"fmt"
	"testing"
	"time"
)

// An Apple renewal of an expert subscription must push its expiry forward.
// It used to hit the one-active-per-pair index and change nothing, so the
// subscription expired after the first period while the user kept paying.
// Needs PULSE_TEST_DSN (see pulse_integration_test.go).
func TestExpertSubIAPRenewalExtendsExpiry(t *testing.T) {
	db := openPulseTestDB(t)
	f := newPulseFixture(t, db)
	repo := NewExpertSubscriptionRepository(db)
	expertID := fmt.Sprintf("it-expert-%d", time.Now().UnixNano())
	if _, err := db.Exec(`INSERT INTO experts (id, name, expertise, tier)
		VALUES ($1, 'IT Expert', 'Testing', 'expert')`, expertID); err != nil {
		t.Fatalf("insert expert: %v", err)
	}
	t.Cleanup(func() {
		db.Exec(`DELETE FROM expert_subscriptions WHERE expert_id = $1`, expertID)
		db.Exec(`DELETE FROM experts WHERE id = $1`, expertID)
	})

	now := time.Now().UTC().Truncate(time.Second)
	first, renewed := now.Add(30*24*time.Hour), now.Add(60*24*time.Hour)
	activate := func(ref string, exp time.Time) error {
		return repo.ActivateFromIAP(f.userID, expertID, "monthly", "apple_iap", ref, now, &exp)
	}
	if err := activate("apple_iap:1", first); err != nil {
		t.Fatalf("first purchase: %v", err)
	}
	if err := activate("apple_iap:2", renewed); err != nil {
		t.Fatalf("renewal: %v", err)
	}
	// A late, older receipt must not shorten it again.
	if err := activate("apple_iap:1", first); err != nil {
		t.Fatalf("older receipt: %v", err)
	}

	var count int
	var got time.Time
	if err := db.QueryRow(`SELECT count(*), max(expires_at) FROM expert_subscriptions
		WHERE user_id = $1 AND expert_id = $2 AND status = 'active'`,
		f.userID, expertID).Scan(&count, &got); err != nil {
		t.Fatalf("query: %v", err)
	}
	if count != 1 || !got.Equal(renewed) {
		t.Fatalf("active rows = %d, expires_at = %s; want 1 row expiring %s", count, got, renewed)
	}
}
