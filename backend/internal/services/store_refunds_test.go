package services

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"halalstocks/internal/repositories"
)

func TestListVoidedProductTokens_Pages(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/purchases/voidedpurchases") || r.URL.Query().Get("type") != "0" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if r.URL.Query().Get("token") == "" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"voidedPurchases": []map[string]any{{"purchaseToken": "a"}, {"purchaseToken": "b"}},
				"tokenPagination": map[string]any{"nextPageToken": "p2"},
			})
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"voidedPurchases": []map[string]any{{"purchaseToken": "c"}}})
	}))
	defer srv.Close()
	v, err := newGooglePlayVerifierForEndpoint(context.Background(), srv.URL+"/", "com.easytech.stocks")
	if err != nil {
		t.Fatal(err)
	}
	tokens, err := v.ListVoidedProductTokens(context.Background())
	if err != nil || strings.Join(tokens, ",") != "a,b,c" {
		t.Fatalf("got %v %v", tokens, err)
	}
}

type fakeVoided struct {
	tokens []string
	err    error
}

func (f fakeVoided) ListVoidedProductTokens(context.Context) ([]string, error) { return f.tokens, f.err }

type fakeRevoker struct {
	seen []string
	res  map[string]repositories.RevokeResult
	fail string
}

func (f *fakeRevoker) Revoke(_ context.Context, store, ref string) (repositories.RevokeResult, error) {
	f.seen = append(f.seen, store+":"+ref)
	if ref == f.fail {
		return "", errors.New("db down")
	}
	return f.res[ref], nil
}

func TestGoogleRefundSync(t *testing.T) {
	rev := &fakeRevoker{res: map[string]repositories.RevokeResult{
		"a": repositories.RevokeShortened, "b": repositories.RevokeEnded, "c": repositories.RevokeUnknown,
	}}
	detail, err := (&GoogleRefundSync{Play: fakeVoided{tokens: []string{"a", "b", "c"}}, Revoker: rev}).Run(context.Background())
	if err != nil || strings.Join(rev.seen, ",") != "google:a,google:b,google:c" {
		t.Fatalf("got %v %v", rev.seen, err)
	}
	if detail != "3 voided: 1 shortened, 1 ended, 0 already applied, 0 no active, 1 not ours, 0 failed" {
		t.Fatalf("detail %q", detail)
	}
	if _, err := (&GoogleRefundSync{Play: fakeVoided{err: errors.New("403")}, Revoker: rev}).Run(context.Background()); err == nil {
		t.Fatal("API error must fail the run")
	}
	failing := &fakeRevoker{fail: "a"}
	_, err = (&GoogleRefundSync{Play: fakeVoided{tokens: []string{"a", "b"}}, Revoker: failing}).Run(context.Background())
	if err == nil || strings.Join(failing.seen, ",") != "google:a,google:b" {
		t.Fatalf("a failed token must not block the rest but must fail the run: %v %v", failing.seen, err)
	}
}
