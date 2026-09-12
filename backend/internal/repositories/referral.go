package repositories

import (
	"crypto/rand"
	"database/sql"
	"fmt"
	"strings"

	"github.com/lib/pq"
)

// ReferralRepository backs the give-one-get-one referral program (mig
// 0055). It deliberately does NOT touch subscription state directly —
// rewarding a referral mints a promo_codes row via PromoCodeRepository.Create
// and lets the existing, already-tested promo redemption path apply it.
type ReferralRepository struct {
	db *sql.DB
}

func NewReferralRepository(db *sql.DB) *ReferralRepository {
	return &ReferralRepository{db: db}
}

// GetOrCreateCode returns the user's personal referral code, generating one
// on first request. Codes are short (6 uppercase alphanumeric chars) and
// globally unique; a handful of retries on the rare collision is simpler
// and safer than a longer code every user has to type/share.
func (r *ReferralRepository) GetOrCreateCode(userID int64) (string, error) {
	var code string
	err := r.db.QueryRow(`SELECT code FROM user_referral_codes WHERE user_id = $1`, userID).Scan(&code)
	if err == nil {
		return code, nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}

	for attempt := 0; attempt < 5; attempt++ {
		candidate, genErr := randomCode(6)
		if genErr != nil {
			return "", genErr
		}
		_, insErr := r.db.Exec(
			`INSERT INTO user_referral_codes (user_id, code) VALUES ($1, $2)`,
			userID, candidate,
		)
		if insErr == nil {
			return candidate, nil
		}
		pgErr, isPgErr := insErr.(*pq.Error)
		if !isPgErr || pgErr.Code != "23505" {
			return "", insErr
		}
		// Either the code collided (retry with a new candidate) or a
		// concurrent request for the SAME user already inserted one
		// (user_id is the PK) — check the latter before retrying.
		if err := r.db.QueryRow(`SELECT code FROM user_referral_codes WHERE user_id = $1`, userID).Scan(&code); err == nil {
			return code, nil
		}
	}
	return "", fmt.Errorf("could not generate a unique referral code after 5 attempts")
}

// LookupOwner returns the user_id that owns a referral code, or 0 if the
// code doesn't exist.
func (r *ReferralRepository) LookupOwner(code string) (int64, error) {
	var userID int64
	err := r.db.QueryRow(
		`SELECT user_id FROM user_referral_codes WHERE code = $1`,
		strings.ToUpper(strings.TrimSpace(code)),
	).Scan(&userID)
	if err == sql.ErrNoRows {
		return 0, nil
	}
	return userID, err
}

// ClaimSlot atomically claims the "one referral per new user" slot via
// INSERT ... ON CONFLICT DO NOTHING against the UNIQUE(referred_user_id)
// constraint, closing the check-then-act race a separate HasBeenReferred
// pre-check would leave open between two concurrent Redeem calls for the
// same new user. Returns claimed=false (no error) when the slot was
// already taken — the caller should reject with 409, not retry.
//
// The claim happens BEFORE any promo code is minted, so a losing
// concurrent request never creates an orphaned reward.
func (r *ReferralRepository) ClaimSlot(referrerUserID, referredUserID int64, code string) (referralID int64, claimed bool, err error) {
	err = r.db.QueryRow(`
		INSERT INTO referrals (referrer_user_id, referred_user_id, referral_code)
		VALUES ($1, $2, $3)
		ON CONFLICT (referred_user_id) DO NOTHING
		RETURNING id
	`, referrerUserID, referredUserID, code).Scan(&referralID)
	if err == sql.ErrNoRows {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	return referralID, true, nil
}

// AttachPromoIDs records which promo codes were minted for an already-
// claimed referral. Called after ClaimSlot succeeds; if promo creation
// fails after the claim, the referral row is left with NULL promo ids —
// a discoverable degraded state (queryable by admins) rather than a
// silent double-reward.
func (r *ReferralRepository) AttachPromoIDs(referralID, referrerPromoID, referredPromoID int64) error {
	_, err := r.db.Exec(
		`UPDATE referrals SET referrer_promo_id = $2, referred_promo_id = $3 WHERE id = $1`,
		referralID, referrerPromoID, referredPromoID,
	)
	return err
}

// CountByReferrer returns how many successful referrals a user has made —
// shown on their referral screen ("You've referred 3 friends").
func (r *ReferralRepository) CountByReferrer(userID int64) (int, error) {
	var count int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM referrals WHERE referrer_user_id = $1`, userID).Scan(&count)
	return count, err
}

func randomCode(length int) (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no 0/O/1/I — avoids visual ambiguity when shared verbally/in text
	b := make([]byte, length)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	return string(b), nil
}
