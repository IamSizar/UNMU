// store_refunds.go — the daily job that takes back Google Play tier
// purchases that were refunded (Voided Purchases API). Apple refunds
// arrive by webhook instead (handlers/apple_notifications.go).
// See docs/payments/REFUNDS_PLAN.md.
package services

import (
	"context"
	"fmt"

	"halalstocks/internal/repositories"
)

// JobStoreRefunds is the daily job name.
const JobStoreRefunds = "store_refunds"

// voidedTokenLister lists refunded Play purchase tokens.
type voidedTokenLister interface {
	ListVoidedProductTokens(ctx context.Context) ([]string, error)
}

// storeRevoker applies one refund.
type storeRevoker interface {
	Revoke(ctx context.Context, store, transactionRef string) (repositories.RevokeResult, error)
}

// GoogleRefundSync revokes every voided Play purchase we granted.
type GoogleRefundSync struct {
	Play    voidedTokenLister
	Revoker storeRevoker
}

// Run is the DailyJob body. Tokens we never granted count as unknown.
// A token that fails is reported and skipped so it cannot block the rest;
// the run then fails, is retried, and Revoke skips what already applied.
func (s *GoogleRefundSync) Run(ctx context.Context) (string, error) {
	tokens, err := s.Play.ListVoidedProductTokens(ctx)
	if err != nil {
		return "", err
	}
	counts := map[repositories.RevokeResult]int{}
	failed := 0
	var lastErr error
	for _, tok := range tokens {
		res, err := s.Revoker.Revoke(ctx, "google", tok)
		if err != nil {
			failed++
			lastErr = err
			CaptureError(err, map[string]string{"job": JobStoreRefunds})
			continue
		}
		counts[res]++
	}
	detail := fmt.Sprintf("%d voided: %d shortened, %d ended, %d already applied, %d no active, %d not ours, %d failed",
		len(tokens), counts[repositories.RevokeShortened], counts[repositories.RevokeEnded],
		counts[repositories.RevokeAlreadyDone], counts[repositories.RevokeNoActive],
		counts[repositories.RevokeUnknown], failed)
	if failed > 0 {
		return detail, fmt.Errorf("%s (last error: %w)", detail, lastErr)
	}
	return detail, nil
}
