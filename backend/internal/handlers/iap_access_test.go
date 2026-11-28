package handlers

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"os"
	"testing"
	"time"

	"halalstocks/internal/repositories"

	_ "github.com/lib/pq"
)

// TestCheckAccessRequest covers the checks made before any store call.
// Needs a database with migration 0063 (PULSE_TEST_DSN).
func TestCheckAccessRequest(t *testing.T) {
	dsn := os.Getenv("PULSE_TEST_DSN")
	if dsn == "" {
		t.Skip("PULSE_TEST_DSN not set")
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	n := time.Now().UnixNano()
	expertID, paidID, freeID := fmt.Sprintf("acc-e-%d", n), fmt.Sprintf("acc-p-%d", n), fmt.Sprintf("acc-f-%d", n)
	mustRun := func(q string, args ...any) {
		if _, err := db.Exec(q, args...); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	mustRun(`INSERT INTO experts (id, name, expertise, tier, price_tier) VALUES ($1, 'A', 'x', 'expert', 't2')`, expertID)
	mustRun(`INSERT INTO communities (id, name, price_tier) VALUES ($1, 'P', 't4'), ($2, 'F', NULL)`, paidID, freeID)
	t.Cleanup(func() {
		db.Exec(`DELETE FROM communities WHERE id IN ($1, $2)`, paidID, freeID)
		db.Exec(`DELETE FROM experts WHERE id = $1`, expertID)
	})

	h := &IAPHandler{grantRepo: repositories.NewStoreAccessGrantRepository(db)}
	cases := []struct {
		name   string
		target accessTarget
		status int // 0 = accepted
	}{
		{"unknown target type", accessTarget{"com.unmu.access.t2.month", "user", expertID}, http.StatusBadRequest},
		{"missing target id", accessTarget{"com.unmu.access.t2.month", "expert", " "}, http.StatusBadRequest},
		{"not an access product", accessTarget{"com.unmu.premium.monthly", "expert", expertID}, http.StatusBadRequest},
		{"expert not found", accessTarget{"com.unmu.access.t2.month", "expert", "missing-" + expertID}, http.StatusNotFound},
		{"cheaper tier than the expert's is accepted (pro-rated)", accessTarget{"com.unmu.access.t1.month", "expert", expertID}, 0},
		{"community that turned free is still honoured", accessTarget{"com.unmu.access.t1.year", "community", freeID}, 0},
		{"expert at its tier", accessTarget{"com.unmu.access.t2.year", "expert", expertID}, 0},
		{"community at its tier", accessTarget{" com.unmu.access.t4.month ", "community", paidID}, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			p, herr := h.checkAccessRequest(context.Background(), 7, tc.target)
			if tc.status == 0 {
				if herr != nil || p == nil || p.userID != 7 {
					t.Fatalf("want accepted, got %+v %v", p, herr)
				}
				return
			}
			if herr == nil || herr.status != tc.status {
				t.Fatalf("want %d, got %+v", tc.status, herr)
			}
		})
	}
}

func TestGrantDaysProRated(t *testing.T) {
	cases := []struct {
		tier, plan, current string
		want                int
	}{
		{"t2", "monthly", "t2", 30},
		{"t3", "monthly", "t2", 30}, // paid more: full length, never more
		{"t1", "monthly", "t2", 14}, // 30 * 499 / 999
		{"t1", "yearly", "t4", 36},  // 365 * 4999 / 49999
		{"t2", "monthly", "", 30},   // community turned free: full length
	}
	for _, c := range cases {
		p := &accessPurchase{tier: c.tier, plan: c.plan, currentTier: c.current}
		if got := p.grantDays(); got != c.want {
			t.Errorf("%s %s vs %s: got %d, want %d", c.tier, c.plan, c.current, got, c.want)
		}
	}
}
