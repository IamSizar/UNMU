package handlers

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

type fakeAppleParser struct {
	n   *services.AppleNotification
	err error
}

func (f fakeAppleParser) Parse(string) (*services.AppleNotification, error) { return f.n, f.err }

type fakeRefunder struct {
	refs []string
	err  error
}

func (f *fakeRefunder) Revoke(_ context.Context, store, ref string) (repositories.RevokeResult, error) {
	f.refs = append(f.refs, store+":"+ref)
	return repositories.RevokeShortened, f.err
}

func postAppleNotification(h *AppleNotificationsHandler, body string) int {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/n", h.Receive)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/n", strings.NewReader(body)))
	return w.Code
}

func TestAppleNotificationsWebhook(t *testing.T) {
	access := &services.AppleNotificationTransaction{TransactionID: "T1", ProductID: "com.unmu.access.t2.month"}
	premium := &services.AppleNotificationTransaction{TransactionID: "P1", ProductID: "com.unmu.premium.monthly"}
	cases := []struct {
		name       string
		parser     fakeAppleParser
		revokeErr  error
		body       string
		wantStatus int
		wantRefs   int
	}{
		{"refund of a tier product is applied", fakeAppleParser{n: &services.AppleNotification{Type: "REFUND", Transaction: access}}, nil, `{"signedPayload":"x"}`, 200, 1},
		{"revoke is applied", fakeAppleParser{n: &services.AppleNotification{Type: "REVOKE", Transaction: access}}, nil, `{"signedPayload":"x"}`, 200, 1},
		{"other types are ignored", fakeAppleParser{n: &services.AppleNotification{Type: "CONSUMPTION_REQUEST", Transaction: access}}, nil, `{"signedPayload":"x"}`, 200, 0},
		{"refund of a non-tier product is ignored", fakeAppleParser{n: &services.AppleNotification{Type: "REFUND", Transaction: premium}}, nil, `{"signedPayload":"x"}`, 200, 0},
		{"bad signature is 400", fakeAppleParser{err: errors.New("bad")}, nil, `{"signedPayload":"x"}`, 400, 0},
		{"missing payload is 400", fakeAppleParser{}, nil, `{}`, 400, 0},
		{"oversized body is 400", fakeAppleParser{n: &services.AppleNotification{Type: "REFUND", Transaction: access}}, nil, `{"signedPayload":"` + strings.Repeat("x", 70<<10) + `"}`, 400, 0},
		{"failed revoke is 500 so Apple retries", fakeAppleParser{n: &services.AppleNotification{Type: "REFUND", Transaction: access}}, errors.New("db"), `{"signedPayload":"x"}`, 500, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ref := &fakeRefunder{err: tc.revokeErr}
			code := postAppleNotification(NewAppleNotificationsHandler(tc.parser, ref), tc.body)
			if code != tc.wantStatus || len(ref.refs) != tc.wantRefs {
				t.Fatalf("got %d with %v", code, ref.refs)
			}
			if tc.wantRefs == 1 && ref.refs[0] != "apple:T1" {
				t.Fatalf("revoked %v", ref.refs)
			}
		})
	}
}
