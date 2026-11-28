package repositories

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"testing"
	"time"

	"halalstocks/internal/models"
)

// grantFixture creates a user, an expert and a paid community, removed
// again when the test ends. Uses PULSE_TEST_DSN (migrations up to 0063).
func grantFixture(t *testing.T, db *sql.DB) (userID, otherID int64, expertID, communityID string) {
	t.Helper()
	n := time.Now().UnixNano()
	expertID, communityID = fmt.Sprintf("grant-exp-%d", n), fmt.Sprintf("grant-com-%d", n)
	for i, id := range []*int64{&userID, &otherID} {
		if err := db.QueryRow(`INSERT INTO users (email, password_hash) VALUES ($1, 'x') RETURNING id`,
			fmt.Sprintf("grant%d-%d@test.local", i, n)).Scan(id); err != nil {
			t.Fatalf("user: %v", err)
		}
	}
	mustExec(t, db, `INSERT INTO experts (id, name, expertise, tier, price_tier) VALUES ($1, 'G', 'x', 'expert', 't3')`, expertID)
	mustExec(t, db, `INSERT INTO communities (id, name, price_tier) VALUES ($1, 'G', 't1')`, communityID)
	t.Cleanup(func() {
		db.Exec(`DELETE FROM store_access_grants WHERE user_id IN ($1, $2)`, userID, otherID)
		db.Exec(`DELETE FROM expert_subscriptions WHERE expert_id = $1`, expertID)
		db.Exec(`DELETE FROM community_subscriptions WHERE community_id = $1`, communityID)
		db.Exec(`DELETE FROM community_members WHERE community_id = $1`, communityID)
		db.Exec(`DELETE FROM communities WHERE id = $1`, communityID)
		db.Exec(`DELETE FROM experts WHERE id = $1`, expertID)
		db.Exec(`DELETE FROM users WHERE id IN ($1, $2)`, userID, otherID)
	})
	return userID, otherID, expertID, communityID
}

func mustExec(t *testing.T, db *sql.DB, q string, args ...any) {
	t.Helper()
	if _, err := db.Exec(q, args...); err != nil {
		t.Fatalf("%s: %v", q, err)
	}
}

func TestStoreAccessGrant(t *testing.T) {
	db := openPulseTestDB(t)
	repo := NewStoreAccessGrantRepository(db)
	ctx := context.Background()
	userID, otherID, expertID, communityID := grantFixture(t, db)

	g := StoreGrant{Store: "apple", TransactionRef: fmt.Sprintf("tx-%d", time.Now().UnixNano()),
		UserID: userID, TargetType: GrantTargetExpert, TargetID: expertID,
		ProductID: "com.unmu.access.t3.month", Plan: models.SubPlanMonthly, PriceCents: 1999,
		PaymentMethod: models.PaymentMethodAppleIAP, PaymentRef: "apple_iap:1"}
	first, err := repo.Grant(ctx, g)
	if err != nil {
		t.Fatalf("grant: %v", err)
	}
	if d := time.Until(first); d < 29*24*time.Hour || d > 31*24*time.Hour {
		t.Fatalf("expiry %v not ~30 days out", first)
	}

	t.Run("replay same user and target is already applied", func(t *testing.T) {
		if _, err := repo.Grant(ctx, g); !errors.Is(err, ErrGrantAlreadyApplied) {
			t.Fatalf("want ErrGrantAlreadyApplied, got %v", err)
		}
	})
	t.Run("replay by another user is refused", func(t *testing.T) {
		other := g
		other.UserID = otherID
		if _, err := repo.Grant(ctx, other); !errors.Is(err, ErrGrantUsedElsewhere) {
			t.Fatalf("want ErrGrantUsedElsewhere, got %v", err)
		}
	})
	t.Run("second purchase extends and adds the price", func(t *testing.T) {
		second := g
		second.TransactionRef += "-2"
		next, err := repo.Grant(ctx, second)
		if err != nil {
			t.Fatalf("second grant: %v", err)
		}
		if d := next.Sub(first); d < 29*24*time.Hour || d > 31*24*time.Hour {
			t.Fatalf("second expiry should be ~30 days after the first, got %v", d)
		}
		var price, rows int
		db.QueryRow(`SELECT SUM(price_cents), COUNT(*) FROM expert_subscriptions WHERE expert_id = $1`, expertID).Scan(&price, &rows)
		if price != 3998 || rows != 1 {
			t.Fatalf("want one row at 3998 cents, got %d rows at %d", rows, price)
		}
	})
	t.Run("community grant adds membership", func(t *testing.T) {
		c := g
		c.TransactionRef += "-c"
		c.TargetType, c.TargetID, c.PriceCents = GrantTargetCommunity, communityID, 499
		if _, err := repo.Grant(ctx, c); err != nil {
			t.Fatalf("community grant: %v", err)
		}
		var members int
		db.QueryRow(`SELECT COUNT(*) FROM community_members WHERE community_id = $1 AND user_id = $2`, communityID, userID).Scan(&members)
		if members != 1 {
			t.Fatal("member row missing")
		}
	})
	t.Run("partial days are honoured", func(t *testing.T) {
		c := g
		c.TransactionRef += "-days"
		c.TargetType, c.TargetID, c.Days = GrantTargetCommunity, communityID, 3
		before, _ := repo.Grant(ctx, c) // community row already exists from the earlier subtest
		c.TransactionRef += "-again"
		after, err := repo.Grant(ctx, c)
		if err != nil || after.Sub(before) < 71*time.Hour || after.Sub(before) > 73*time.Hour {
			t.Fatalf("want +3 days, got %v (%v)", after.Sub(before), err)
		}
	})
	t.Run("target tiers", func(t *testing.T) {
		if _, tier, _ := repo.TargetPriceTier(ctx, GrantTargetExpert, expertID); tier != "t3" {
			t.Fatalf("expert tier %q", tier)
		}
		if _, _, err := repo.TargetPriceTier(ctx, GrantTargetCommunity, "missing"); !errors.Is(err, sql.ErrNoRows) {
			t.Fatalf("want ErrNoRows, got %v", err)
		}
	})
}
