package repositories

import (
	"errors"
	"fmt"
	"testing"
	"time"
)

// A subscription (one original_transaction_id) belongs to the first account
// that verified it. Renewals carry new transaction ids, so checking only
// transaction_id let another account claim a renewal of someone else's sub.
// Needs PULSE_TEST_DSN (see pulse_integration_test.go).
func TestAppleIAPRenewalOfAnotherUsersSubRejected(t *testing.T) {
	db := openPulseTestDB(t)
	f := newPulseFixture(t, db)
	repo := NewAppleIAPTransactionRepository(db)
	orig := fmt.Sprintf("IT-ORIG-%d", time.Now().UnixNano())
	t.Cleanup(func() {
		db.Exec(`DELETE FROM apple_iap_transactions WHERE original_transaction_id = $1`, orig)
	})
	exp := time.Now().Add(time.Hour)
	upsert := func(user int64, txn string) error {
		_, _, err := repo.Upsert(user, txn, orig, "com.unmu.premium.monthly",
			"Sandbox", time.Now(), &exp, []byte(`{}`))
		return err
	}

	if err := upsert(f.userID, orig); err != nil {
		t.Fatalf("first purchase: %v", err)
	}
	if err := upsert(f.otherID, orig+"-r1"); !errors.Is(err, ErrAppleSubOwnedByAnotherUser) {
		t.Fatalf("other account claiming a renewal: err = %v, want ErrAppleSubOwnedByAnotherUser", err)
	}
	if err := upsert(f.otherID, orig); !errors.Is(err, ErrAppleSubOwnedByAnotherUser) {
		t.Fatalf("other account replaying the original: err = %v", err)
	}
	if err := upsert(f.userID, orig+"-r1"); err != nil {
		t.Fatalf("owner renewing: %v", err)
	}
}
