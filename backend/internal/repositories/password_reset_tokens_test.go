package repositories

import (
	"encoding/hex"
	"regexp"
	"testing"
)

// Token format contract — 32 bytes of crypto/rand entropy hex-encoded,
// so the output string is always 64 characters of lowercase hex.
// Anything else means GeneratePasswordResetToken changed shape and the
// password-reset URLs we email out would no longer round-trip.
func TestGeneratePasswordResetToken_Format(t *testing.T) {
	tok, err := GeneratePasswordResetToken()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(tok) != 64 {
		t.Errorf("len(tok) = %d, want 64", len(tok))
	}
	if !regexp.MustCompile(`^[0-9a-f]{64}$`).MatchString(tok) {
		t.Errorf("token is not 64 lowercase-hex chars: %q", tok)
	}
	if _, err := hex.DecodeString(tok); err != nil {
		t.Errorf("token does not decode as hex: %v", err)
	}
}

// Uniqueness contract — across a sample of 1000 calls we should not see
// a single collision. crypto/rand makes the odds astronomical; any
// duplicate here means rand.Read was bypassed.
func TestGeneratePasswordResetToken_Unique(t *testing.T) {
	const n = 1000
	seen := make(map[string]struct{}, n)
	for i := 0; i < n; i++ {
		tok, err := GeneratePasswordResetToken()
		if err != nil {
			t.Fatalf("call %d: %v", i, err)
		}
		if _, dup := seen[tok]; dup {
			t.Fatalf("collision after %d calls: %q", i+1, tok)
		}
		seen[tok] = struct{}{}
	}
}

// HashResetToken is the function the password-reset flow uses to derive
// the DB-side lookup key. It MUST be deterministic — otherwise tokens
// stored in the table would never match the inbound URL parameter.
func TestHashResetToken_Deterministic(t *testing.T) {
	const in = "abcd1234"
	if a, b := HashResetToken(in), HashResetToken(in); a != b {
		t.Fatalf("non-deterministic: %q vs %q", a, b)
	}
}

// The whole point of hashing tokens before insertion is that a DB leak
// can't be replayed. So the output must NOT equal the input, must be
// the 64-char SHA-256 hex shape, and must differ for distinct inputs.
func TestHashResetToken_HidesAndDiscriminates(t *testing.T) {
	const in = "secret-token"
	out := HashResetToken(in)
	if out == in {
		t.Fatal("hash equals input — not actually hashed")
	}
	if len(out) != 64 {
		t.Errorf("len(hash) = %d, want 64 (sha256 hex)", len(out))
	}
	if HashResetToken("a") == HashResetToken("b") {
		t.Fatal("distinct inputs gave identical hash — sha256 broken")
	}
}

// Round-trip contract used by the rest of the codebase: Create() stores
// the hash, Consume() looks up by HashResetToken(rawToken). Both paths
// must call the same function so a token generated here lands in the
// right row when used.
func TestGenerateThenHash_RoundTrip(t *testing.T) {
	raw, err := GeneratePasswordResetToken()
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	h1 := HashResetToken(raw)
	h2 := HashResetToken(raw)
	if h1 != h2 {
		t.Fatalf("hash round-trip diverged: %q vs %q", h1, h2)
	}
	if h1 == raw {
		t.Fatal("raw token leaked through hash — would defeat at-rest protection")
	}
}
