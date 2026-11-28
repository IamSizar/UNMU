package services

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/anthropics/anthropic-sdk-go/v2"

	"halalstocks/internal/marketdata"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
)

type fakeNews struct{ stock, general []marketdata.NewsArticle }

func (f fakeNews) FetchNews(_ context.Context, q marketdata.NewsQuery) ([]marketdata.NewsArticle, error) {
	if len(q.Symbols) > 0 {
		return f.stock, nil
	}
	return f.general, nil
}

type fakeDraftStore struct {
	taken   map[string]bool
	changes []repositories.ShariahChange
	saved   []models.PulseItemInput
}

func (f *fakeDraftStore) TakenSlots(context.Context, string) (map[string]bool, error) {
	return f.taken, nil
}
func (f *fakeDraftStore) CreateAutoDraft(_ context.Context, in models.PulseItemInput) (*models.PulseAdminItem, error) {
	f.saved = append(f.saved, in)
	return &models.PulseAdminItem{}, nil
}
func (f *fakeDraftStore) RecentShariahChanges(context.Context, time.Time) ([]repositories.ShariahChange, error) {
	return f.changes, nil
}

type fakeStocks struct{}

func (fakeStocks) GetAll(int, int) ([]*models.Stock, error) {
	return []*models.Stock{{ID: 7, Ticker: "AAPL"}, {ID: 9, Ticker: "2222"}}, nil
}

type fakeWriter struct {
	drafts []PulseDraft
	got    PulseDraftRequest
}

func (f *fakeWriter) WriteDrafts(_ context.Context, req PulseDraftRequest) ([]PulseDraft, error) {
	f.got = req
	return f.drafts, nil
}

var testNow = time.Date(2026, 11, 28, 3, 0, 0, 0, time.UTC)

func fullDraft(slot string, idx int) PulseDraft {
	return PulseDraft{Slot: slot, ArticleIndex: idx, Classification: "confirmed",
		TitleAr: "ع", TitleEn: "t", SummaryAr: "ع", SummaryEn: "s", DetailsAr: "ع", DetailsEn: "d",
		EvidenceAr: "ع", EvidenceEn: "e", StockTicker: "aapl"}
}

func newTestDrafter(store *fakeDraftStore, w *fakeWriter) *PulseAutoDrafter {
	news := fakeNews{
		stock: []marketdata.NewsArticle{
			{Title: "Apple up", Link: "https://www.reuters.com/a", PublishedAt: testNow.Add(-2 * time.Hour)},
			{Title: "old", Link: "https://ex.test/old", PublishedAt: testNow.Add(-72 * time.Hour)},
		},
		general: []marketdata.NewsArticle{
			{Title: "Apple up dup", Link: "https://www.reuters.com/a", PublishedAt: testNow.Add(-2 * time.Hour)},
			{Title: "Oil", Link: "https://ex.test/oil", PublishedAt: testNow.Add(-1 * time.Hour)},
		},
	}
	return &PulseAutoDrafter{News: news, Store: store, Stocks: fakeStocks{}, Writer: w,
		Now: func() time.Time { return testNow }}
}

func TestAutoDraftSavesOnlyValidPicks(t *testing.T) {
	store := &fakeDraftStore{taken: map[string]bool{"global": true}}
	sharia := fullDraft("sharia", -1) // no screening changes → rejected
	empty := fullDraft("opportunity", 1)
	empty.EvidenceEn = " "
	w := &fakeWriter{drafts: []PulseDraft{
		fullDraft("global", 0), // slot taken by a human item
		fullDraft("gulf", 1),   // valid
		fullDraft("gulf", 0),   // second pick for the same slot
		fullDraft("opportunity", 5),
		empty, sharia,
	}}
	summary, err := newTestDrafter(store, w).Run(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(w.got.OpenSlots, ",") != "gulf,sharia,opportunity" {
		t.Errorf("open slots: %v", w.got.OpenSlots)
	}
	if len(w.got.Articles) != 2 || w.got.Articles[0].Title != "Oil" {
		t.Fatalf("want 2 fresh, deduped, newest-first articles, got %+v", w.got.Articles)
	}
	if len(store.saved) != 1 {
		t.Fatalf("want exactly 1 saved draft, got %d: %s", len(store.saved), summary)
	}
	in := store.saved[0]
	if in.Slot != "gulf" || in.SourceURL != "https://www.reuters.com/a" || in.SourceName != "reuters.com" {
		t.Errorf("source must come from the article: %+v", in)
	}
	if in.VerifiedAt != nil || in.IsSensitive || in.StockID == nil || *in.StockID != 7 || in.PulseDate != "2026-11-28" {
		t.Errorf("bad draft fields: %+v", in)
	}
	if !strings.Contains(summary, "rejected") {
		t.Errorf("summary should list rejections: %s", summary)
	}
}

func TestAutoDraftShariaFromScreeningData(t *testing.T) {
	store := &fakeDraftStore{taken: map[string]bool{}, changes: []repositories.ShariahChange{
		{Ticker: "AAPL", From: "HALAL", To: "MIXED"},
	}}
	w := &fakeWriter{drafts: []PulseDraft{fullDraft("sharia", -1)}}
	if _, err := newTestDrafter(store, w).Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(store.saved) != 1 || !store.saved[0].IsSensitive || store.saved[0].SourceName != ShariahDataSource {
		t.Fatalf("sharia draft must be sensitive and cite our data: %+v", store.saved)
	}
}

func TestAutoDraftSkipsWhenNothingOpen(t *testing.T) {
	store := &fakeDraftStore{taken: map[string]bool{"global": true, "gulf": true, "sharia": true, "opportunity": true}}
	w := &fakeWriter{}
	got, err := newTestDrafter(store, w).Run(context.Background())
	if err != nil || !strings.Contains(got, "all slots") || w.got.Date != "" {
		t.Fatalf("must not call the writer: %q %v", got, err)
	}
}

func TestParsePulseDraftReply(t *testing.T) {
	var msg anthropic.BetaMessage
	raw := `{"id":"m","type":"message","role":"assistant","model":"claude-opus-5-5","stop_reason":"end_turn",
	  "content":[{"type":"text","text":"{\"items\":[{\"slot\":\"gulf\",\"article_index\":2,\"classification\":\"analysis\"}]}"}],
	  "usage":{"input_tokens":1,"output_tokens":1}}`
	if err := json.Unmarshal([]byte(raw), &msg); err != nil {
		t.Fatal(err)
	}
	got, err := parsePulseDraftReply(&msg)
	if err != nil || len(got) != 1 || got[0].Slot != "gulf" || got[0].ArticleIndex != 2 {
		t.Fatalf("got %+v %v", got, err)
	}
	msg.StopReason = anthropic.BetaStopReasonRefusal
	if _, err := parsePulseDraftReply(&msg); err == nil {
		t.Error("refusal must be an error")
	}
}
