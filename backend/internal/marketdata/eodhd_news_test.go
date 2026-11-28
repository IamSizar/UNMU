package marketdata

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestFetchNewsParsesAndFilters(t *testing.T) {
	var queries []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		queries = append(queries, r.URL.RawQuery)
		if strings.Contains(r.URL.Query().Get("s"), ",") {
			w.WriteHeader(http.StatusUnprocessableEntity) // EODHD: one ticker per request
			return
		}
		if r.URL.Query().Get("s") == "MSFT.US" {
			w.Write([]byte(`[]`))
			return
		}
		w.Write([]byte(`[
		 {"date":"2026-11-28T06:30:00+00:00","title":" Apple beats ","content":"body","link":"https://ex.test/a",
		  "symbols":["AAPL.US"],"tags":["EARNINGS"],"sentiment":{"polarity":0.8,"neg":0,"neu":0.2,"pos":0.8}},
		 {"date":"2026-11-28T06:00:00+00:00","title":"no link","content":"x","link":""},
		 {"date":"bad","title":"no sentiment","content":"y","link":"https://ex.test/b"}
		]`))
	}))
	defer srv.Close()
	old := eodhdNewsURL
	eodhdNewsURL = srv.URL
	defer func() { eodhdNewsURL = old }()

	p := NewEODHDProvider("k")
	from := time.Date(2026, 11, 27, 9, 0, 0, 0, time.UTC)
	got, err := p.FetchNews(context.Background(), NewsQuery{Symbols: []string{"AAPL.US", "MSFT.US"}, From: from, Limit: 20})
	if err != nil {
		t.Fatal(err)
	}
	if len(queries) != 2 || !strings.Contains(queries[0], "s=AAPL.US") || !strings.Contains(queries[1], "s=MSFT.US") {
		t.Fatalf("want one request per symbol, got %v", queries)
	}
	for _, want := range []string{"from=2026-11-27", "limit=20", "fmt=json"} {
		if !strings.Contains(queries[0], want) {
			t.Errorf("query %q missing %q", queries[0], want)
		}
	}
	if len(got) != 2 {
		t.Fatalf("want 2 articles (no-link one dropped), got %d", len(got))
	}
	a := got[0]
	if a.Title != "Apple beats" || a.Polarity != 0.8 || a.PublishedAt.IsZero() || a.Symbols[0] != "AAPL.US" {
		t.Errorf("bad first article: %+v", a)
	}
	if !got[1].PublishedAt.IsZero() || got[1].Polarity != 0 {
		t.Errorf("bad date/sentiment should be zero: %+v", got[1])
	}
}

func TestFetchNewsHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusPaymentRequired)
	}))
	defer srv.Close()
	old := eodhdNewsURL
	eodhdNewsURL = srv.URL
	defer func() { eodhdNewsURL = old }()
	if _, err := NewEODHDProvider("k").FetchNews(context.Background(), NewsQuery{}); err == nil {
		t.Fatal("want error on HTTP 402")
	}
}

func TestEODHDSymbolsDropsUncovered(t *testing.T) {
	got := EODHDSymbols([]string{"aapl", "NOPE", "MSFT"})
	if strings.Join(got, ",") != "AAPL.US,MSFT.US" {
		t.Errorf("got %v", got)
	}
}

func TestFetchNewsErrorHidesAPIKey(t *testing.T) {
	old := eodhdNewsURL
	eodhdNewsURL = "http://127.0.0.1:1/api/news" // nothing listens: network error
	defer func() { eodhdNewsURL = old }()
	_, err := NewEODHDProvider("SECRET-KEY-123").FetchNews(context.Background(), NewsQuery{Symbols: []string{"AAPL.US"}})
	if err == nil {
		t.Fatal("want a network error")
	}
	if strings.Contains(err.Error(), "SECRET-KEY-123") || strings.Contains(err.Error(), "api_token") {
		t.Fatalf("error leaks the API key: %v", err)
	}
}
