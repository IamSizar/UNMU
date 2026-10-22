package repositories

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"halalstocks/internal/models"

	"github.com/lib/pq"
)

// Integration test for the Pulse read repository.
//
// Runs only when PULSE_TEST_DSN points at a scratch database that already has
// migration 0056_pulse.sql applied, for example:
//
//	PULSE_TEST_DSN="host=/tmp dbname=unmu_pulse_dev sslmode=disable" \
//	  go test ./internal/repositories -run Pulse -v
//
// Without the variable the test is skipped, so plain `go test ./...` (CI) is
// unaffected. Every row it creates is removed again in t.Cleanup.

type pulseFixture struct {
	t       *testing.T
	db      *sql.DB
	userID  int64
	otherID int64
	stockID int64
	itemIDs []int64
	day     string // the test day, in 2090 so it can never clash with real data
}

func openPulseTestDB(t *testing.T) *sql.DB {
	t.Helper()
	dsn := os.Getenv("PULSE_TEST_DSN")
	if dsn == "" {
		t.Skip("PULSE_TEST_DSN not set; skipping Pulse database test")
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := db.Ping(); err != nil {
		t.Fatalf("ping: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

func newPulseFixture(t *testing.T, db *sql.DB) *pulseFixture {
	t.Helper()
	f := &pulseFixture{t: t, db: db, day: "2090-01-10"}
	suffix := time.Now().UnixNano()

	mustScan := func(q string, args ...any) int64 {
		var id int64
		if err := db.QueryRow(q, args...).Scan(&id); err != nil {
			t.Fatalf("fixture insert failed: %v\n%s", err, q)
		}
		return id
	}
	f.userID = mustScan(`INSERT INTO users (email, password_hash, role) VALUES ($1,'x','ADMIN') RETURNING id`,
		fmt.Sprintf("pulse-it-a-%d@test.invalid", suffix))
	f.otherID = mustScan(`INSERT INTO users (email, password_hash, role) VALUES ($1,'x','USER') RETURNING id`,
		fmt.Sprintf("pulse-it-b-%d@test.invalid", suffix))
	f.stockID = mustScan(`INSERT INTO stocks (ticker, exchange, name) VALUES ($1,'TEST','Pulse Test Co') RETURNING id`,
		fmt.Sprintf("PIT%d", suffix%1_000_000))

	t.Cleanup(func() {
		for _, id := range f.itemIDs {
			db.Exec(`DELETE FROM pulse_items WHERE id = $1`, id)
		}
		db.Exec(`DELETE FROM user_portfolios WHERE user_id IN ($1,$2)`, f.userID, f.otherID)
		db.Exec(`DELETE FROM stocks WHERE id = $1`, f.stockID)
		db.Exec(`DELETE FROM users WHERE id IN ($1,$2)`, f.userID, f.otherID)
	})
	return f
}

// item inserts one Pulse item. Published items get the reviewer/approver and
// timestamps the table constraints demand.
func (f *pulseFixture) item(date, slot, status, titleEn string, stock bool) int64 {
	f.t.Helper()
	var stockID any
	if stock {
		stockID = f.stockID
	}
	sensitive := slot == models.PulseSlotSharia
	var id int64
	err := f.db.QueryRow(`
		INSERT INTO pulse_items
		  (pulse_date, slot, classification, status, is_sensitive,
		   title_ar, title_en, summary_ar, summary_en,
		   details_en, evidence_en, source_name, verified_at, stock_id,
		   publish_at, published_at, created_by, reviewed_by, approved_by)
		VALUES ($1,$2,'confirmed',$3,$4,
		        'عنوان',$5,'ملخص','Summary',
		        'Full details','Evidence text','Source',now(),$6,
		        CASE WHEN $3='scheduled' THEN now() + interval '1 day' END,
		        CASE WHEN $3='published' THEN now() END,
		        $7,$7,$7)
		RETURNING id`,
		date, slot, status, sensitive, titleEn, stockID, f.userID).Scan(&id)
	if err != nil {
		f.t.Fatalf("insert item %q: %v", titleEn, err)
	}
	f.itemIDs = append(f.itemIDs, id)
	return id
}

func TestPulseRepository(t *testing.T) {
	db := openPulseTestDB(t)
	f := newPulseFixture(t, db)
	repo := NewPulseRepository(db)
	ctx := context.Background()

	global := f.item(f.day, "global", "published", "Global headline", false)
	sharia := f.item(f.day, "sharia", "published", "Sharia headline", true)
	draft := f.item(f.day, "gulf", "draft", "Draft gulf", false)
	sched := f.item(f.day, "opportunity", "scheduled", "Scheduled opportunity", false)

	t.Run("day returns only published items in slot order", func(t *testing.T) {
		day, err := repo.Day(ctx, f.userID, f.day)
		if err != nil {
			t.Fatal(err)
		}
		if len(day.Items) != 2 || day.Items[0].ID != global || day.Items[1].ID != sharia {
			t.Fatalf("got %+v, want [global, sharia]", day.Items)
		}
		if day.UpdatedAt == nil {
			t.Error("UpdatedAt should be set when items exist")
		}
		if day.Items[0].DetailsEn != "" || day.Items[0].EvidenceEn != "" {
			t.Error("list payload must not carry details/evidence")
		}
	})

	t.Run("item detail has evidence; drafts and scheduled are hidden", func(t *testing.T) {
		it, err := repo.Item(ctx, f.userID, global)
		if err != nil {
			t.Fatal(err)
		}
		if it.DetailsEn != "Full details" || it.EvidenceEn != "Evidence text" {
			t.Errorf("detail missing: %+v", it)
		}
		for _, hidden := range []int64{draft, sched} {
			if _, err := repo.Item(ctx, f.userID, hidden); !errors.Is(err, ErrPulseNotFound) {
				t.Errorf("item %d: err = %v, want ErrPulseNotFound", hidden, err)
			}
		}
	})

	t.Run("relation: none, watchlist, portfolio", func(t *testing.T) {
		rel := func() *string {
			it, err := repo.Item(ctx, f.userID, sharia)
			if err != nil {
				t.Fatal(err)
			}
			return it.Relation
		}
		if rel() != nil {
			t.Error("no portfolio row: relation should be nil")
		}
		db.Exec(`INSERT INTO user_portfolios (user_id, stock_id, shares) VALUES ($1,$2,0)`, f.userID, f.stockID)
		if r := rel(); r == nil || *r != "watchlist" {
			t.Errorf("zero shares: relation = %v, want watchlist", r)
		}
		db.Exec(`UPDATE user_portfolios SET shares = 5 WHERE user_id = $1`, f.userID)
		if r := rel(); r == nil || *r != "portfolio" {
			t.Errorf("5 shares: relation = %v, want portfolio", r)
		}
		// Another user must not see this user's relation.
		it, _ := repo.Item(ctx, f.otherID, sharia)
		if it.Relation != nil {
			t.Error("relation leaked to a different user")
		}
	})

	t.Run("save is idempotent, private, and rejects unpublished items", func(t *testing.T) {
		for i := 0; i < 2; i++ {
			if err := repo.Save(ctx, f.userID, global); err != nil {
				t.Fatalf("save #%d: %v", i+1, err)
			}
		}
		if err := repo.Save(ctx, f.userID, draft); !errors.Is(err, ErrPulseNotFound) {
			t.Errorf("saving a draft: err = %v, want ErrPulseNotFound", err)
		}
		saved, _, err := repo.Saved(ctx, f.userID, 10, 0)
		if err != nil || len(saved) != 1 || saved[0].ID != global || !saved[0].IsSaved {
			t.Fatalf("saved list wrong: %+v err=%v", saved, err)
		}
		other, _, _ := repo.Saved(ctx, f.otherID, 10, 0)
		if len(other) != 0 {
			t.Error("another user's saves must not appear")
		}
		if err := repo.Unsave(ctx, f.userID, global); err != nil {
			t.Fatal(err)
		}
		if err := repo.Unsave(ctx, f.userID, global); err != nil {
			t.Errorf("unsaving twice should be a no-op: %v", err)
		}
	})

	t.Run("archive: date range, literal search, paging", func(t *testing.T) {
		f.item("2090-01-11", "global", "published", "Growth 100% year", false)
		f.item("2090-01-12", "global", "published", "Growth 1000 year", false)
		f.item("2090-01-12", "gulf", "published", "Plain_title", false)

		filter := ArchiveFilter{From: "2090-01-11", To: "2090-01-12"}
		items, more, err := repo.Archive(ctx, f.userID, filter, 10, 0)
		if err != nil || len(items) != 3 || more {
			t.Fatalf("range: len=%d more=%v err=%v, want 3 items", len(items), more, err)
		}
		if items[0].Date < items[len(items)-1].Date {
			t.Error("archive must be newest day first")
		}

		// '%' must be matched literally, not as a wildcard.
		filter.Query = "100%"
		items, _, _ = repo.Archive(ctx, f.userID, filter, 10, 0)
		if len(items) != 1 || items[0].TitleEn != "Growth 100% year" {
			t.Errorf("literal %% search matched %d items, want exactly 1", len(items))
		}
		// '_' must be literal too ("Plain_title", not "Plain-title").
		filter.Query = "n_t"
		items, _, _ = repo.Archive(ctx, f.userID, filter, 10, 0)
		if len(items) != 1 || items[0].TitleEn != "Plain_title" {
			t.Errorf("literal _ search matched %d items, want exactly 1", len(items))
		}

		// Arabic search over the Arabic title.
		filter.Query = "عنوان"
		items, _, _ = repo.Archive(ctx, f.userID, filter, 10, 0)
		if len(items) != 3 {
			t.Errorf("Arabic search matched %d items, want 3", len(items))
		}

		// Paging: 3 matches, page size 2 -> first page has more, second does not.
		filter.Query = ""
		page1, more1, _ := repo.Archive(ctx, f.userID, filter, 2, 0)
		page2, more2, _ := repo.Archive(ctx, f.userID, filter, 2, 2)
		if len(page1) != 2 || !more1 || len(page2) != 1 || more2 {
			t.Errorf("paging wrong: %d/%v then %d/%v", len(page1), more1, len(page2), more2)
		}
	})

	t.Run("events: stored, and an unknown item is rejected by the database", func(t *testing.T) {
		if err := repo.RecordEvent(ctx, f.userID, &global, models.PulseEventOpenItem); err != nil {
			t.Fatal(err)
		}
		if err := repo.RecordEvent(ctx, f.userID, nil, models.PulseEventViewDay); err != nil {
			t.Fatal(err)
		}
		missing := int64(999_999_999)
		err := repo.RecordEvent(ctx, f.userID, &missing, models.PulseEventOpenItem)
		var pgErr *pq.Error
		if !errors.As(err, &pgErr) || pgErr.Code != "23503" {
			t.Errorf("missing item: err = %v, want a foreign-key violation", err)
		}
	})
}
