package repositories

import (
	"context"
	"fmt"
	"testing"
	"time"

	"halalstocks/internal/models"
)

func TestStoreAccessRevoke(t *testing.T) {
	db := openPulseTestDB(t)
	repo := NewStoreAccessGrantRepository(db)
	ctx := context.Background()
	userID, _, expertID, communityID := grantFixture(t, db)
	ref := fmt.Sprintf("rv-%d", time.Now().UnixNano())
	grant := func(suffix, targetType, targetID string, price int) {
		t.Helper()
		_, err := repo.Grant(ctx, StoreGrant{Store: "google", TransactionRef: ref + suffix,
			UserID: userID, TargetType: targetType, TargetID: targetID,
			ProductID: "com.unmu.access.t3.month", Plan: models.SubPlanMonthly, PriceCents: price,
			PaymentMethod: models.PaymentMethodGoogleIAP, PaymentRef: "google_play:x"})
		if err != nil {
			t.Fatalf("grant %s: %v", suffix, err)
		}
	}
	expertRow := func() (status string, price int, expires time.Time) {
		db.QueryRow(`SELECT status, price_cents, expires_at FROM expert_subscriptions WHERE expert_id = $1`, expertID).
			Scan(&status, &price, &expires)
		return
	}

	grant("-a", GrantTargetExpert, expertID, 1999)
	grant("-b", GrantTargetExpert, expertID, 1999)
	_, _, before := expertRow()

	t.Run("unknown transaction changes nothing", func(t *testing.T) {
		if res, err := repo.Revoke(ctx, "google", "nope-"+ref); err != nil || res != RevokeUnknown {
			t.Fatalf("got %s %v", res, err)
		}
	})
	t.Run("refund of one of two purchases shortens", func(t *testing.T) {
		res, err := repo.Revoke(ctx, "google", ref+"-a")
		status, price, expires := expertRow()
		if err != nil || res != RevokeShortened || status != "active" || price != 1999 {
			t.Fatalf("got %s %v status=%s price=%d", res, err, status, price)
		}
		if d := before.Sub(expires); d < 29*24*time.Hour || d > 31*24*time.Hour {
			t.Fatalf("want 30 days removed, got %v", d)
		}
	})
	t.Run("repeat changes nothing", func(t *testing.T) {
		if res, _ := repo.Revoke(ctx, "google", ref+"-a"); res != RevokeAlreadyDone {
			t.Fatalf("got %s", res)
		}
	})
	t.Run("refund of the last purchase ends access", func(t *testing.T) {
		res, err := repo.Revoke(ctx, "google", ref+"-b")
		status, price, _ := expertRow()
		if err != nil || res != RevokeEnded || status != "expired" || price != 0 {
			t.Fatalf("got %s %v status=%s price=%d", res, err, status, price)
		}
	})
	t.Run("community refund removes the member", func(t *testing.T) {
		grant("-c", GrantTargetCommunity, communityID, 499)
		if res, err := repo.Revoke(ctx, "google", ref+"-c"); err != nil || res != RevokeEnded {
			t.Fatalf("got %s %v", res, err)
		}
		var members int
		db.QueryRow(`SELECT COUNT(*) FROM community_members WHERE community_id = $1 AND user_id = $2`, communityID, userID).Scan(&members)
		if members != 0 {
			t.Fatal("member should be removed")
		}
	})
	t.Run("refund of an ended period never touches the newer row", func(t *testing.T) {
		grant("-d", GrantTargetCommunity, communityID, 499)
		mustExec(t, db, `UPDATE community_subscriptions SET status = 'expired' WHERE community_id = $1`, communityID)
		grant("-e", GrantTargetCommunity, communityID, 499) // opens a new row
		var newExpires time.Time
		db.QueryRow(`SELECT expires_at FROM community_subscriptions WHERE community_id = $1 AND status = 'active'`, communityID).Scan(&newExpires)
		if res, err := repo.Revoke(ctx, "google", ref+"-d"); err != nil || res != RevokeNoActive {
			t.Fatalf("got %s %v", res, err)
		}
		var after time.Time
		db.QueryRow(`SELECT expires_at FROM community_subscriptions WHERE community_id = $1 AND status = 'active'`, communityID).Scan(&after)
		if !after.Equal(newExpires) {
			t.Fatalf("new row changed: %v -> %v", newExpires, after)
		}
	})
	t.Run("only the unused part of a partly used purchase is removed", func(t *testing.T) {
		// Pretend purchase -e started 20 days ago: 10 days are left.
		mustExec(t, db, `UPDATE store_access_grants SET period_start = period_start - interval '20 days',
			period_end = period_end - interval '20 days' WHERE transaction_ref = $1`, ref+"-e")
		mustExec(t, db, `UPDATE community_subscriptions SET expires_at = expires_at - interval '20 days'
			WHERE community_id = $1 AND status = 'active'`, communityID)
		grant("-f", GrantTargetCommunity, communityID, 499) // stacked after -e: +30 days
		res, err := repo.Revoke(ctx, "google", ref+"-e")
		var expires time.Time
		db.QueryRow(`SELECT expires_at FROM community_subscriptions WHERE community_id = $1 AND status = 'active'`, communityID).Scan(&expires)
		if d := time.Until(expires); err != nil || res != RevokeShortened || d < 29*24*time.Hour || d > 31*24*time.Hour {
			t.Fatalf("want ~30 days left (only -f), got %v %s %v", d, res, err)
		}
		// -f's span moved earlier, so refunding it now ends access exactly.
		if res, err := repo.Revoke(ctx, "google", ref+"-f"); err != nil || res != RevokeEnded {
			t.Fatalf("got %s %v", res, err)
		}
	})
	t.Run("a row without expiry is not an error", func(t *testing.T) {
		grant("-g", GrantTargetExpert, expertID, 1999)
		mustExec(t, db, `UPDATE expert_subscriptions SET expires_at = NULL WHERE expert_id = $1 AND status = 'active'`, expertID)
		if res, err := repo.Revoke(ctx, "google", ref+"-g"); err != nil || res != RevokeNoActive {
			t.Fatalf("got %s %v", res, err)
		}
	})
}
