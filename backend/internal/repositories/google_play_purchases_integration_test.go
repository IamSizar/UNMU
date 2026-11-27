package repositories

import (
	"errors"
	"fmt"
	"testing"
	"time"
)

// A Play purchase token (and any token linked to it by an upgrade or
// re-subscribe) belongs to the first account that verified it. Re-verifying
// the same token updates its expiry. Needs PULSE_TEST_DSN.
func TestGooglePlayPurchaseOwnership(t *testing.T) {
	db := openPulseTestDB(t)
	f := newPulseFixture(t, db)
	repo := NewGooglePlayPurchaseRepository(db)
	tok := fmt.Sprintf("it-gp-%d", time.Now().UnixNano())
	t.Cleanup(func() {
		db.Exec(`DELETE FROM google_play_purchases WHERE purchase_token LIKE $1`, tok+"%")
	})
	exp1, exp2 := time.Now().Add(time.Hour).UTC().Truncate(time.Second), time.Now().Add(48*time.Hour).UTC().Truncate(time.Second)
	save := func(user int64, token, linked string, exp time.Time) (*GooglePlayPurchase, error) {
		return repo.Upsert(GooglePlayPurchase{
			UserID: user, PurchaseToken: token, LinkedPurchaseToken: linked,
			OrderID: "GPA." + token, ProductID: "com.unmu.premium.monthly",
			SubscriptionState: "SUBSCRIPTION_STATE_ACTIVE", PurchaseDate: time.Now(),
			ExpiresDate: &exp, RawPayload: []byte(`{}`),
		})
	}

	if _, err := save(f.userID, tok, "", exp1); err != nil {
		t.Fatalf("first verify: %v", err)
	}
	row, err := save(f.userID, tok, "", exp2) // renewal: same token, later expiry
	if err != nil || row.ExpiresDate == nil || !row.ExpiresDate.Equal(exp2) {
		t.Fatalf("renewal update: row=%+v err=%v", row, err)
	}
	if _, err := save(f.otherID, tok, "", exp2); !errors.Is(err, ErrStorePurchaseOwnedByAnotherUser) {
		t.Fatalf("other account, same token: err = %v", err)
	}
	if _, err := save(f.otherID, tok+"-upgrade", tok, exp2); !errors.Is(err, ErrStorePurchaseOwnedByAnotherUser) {
		t.Fatalf("other account, linked token: err = %v", err)
	}
	if _, err := save(f.userID, tok+"-upgrade", tok, exp2); err != nil {
		t.Fatalf("owner upgrading: %v", err)
	}
}
