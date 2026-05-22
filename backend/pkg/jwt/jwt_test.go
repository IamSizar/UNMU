package jwt

import (
	"strings"
	"testing"
	"time"

	gojwt "github.com/golang-jwt/jwt/v5"
)

// Init sets a package-level secret. Every test that touches Generate or
// Validate calls it explicitly so the secret is deterministic regardless
// of test order. The "no init" tests explicitly clear the secret again.

const testSecret = "test-secret-do-not-use-in-prod"

// Round-trip — the most important contract. Anything we put into the
// token must come back out unchanged on the other side, otherwise auth
// would mis-attribute requests.
func TestGenerateThenValidate_RoundTrip(t *testing.T) {
	Init(testSecret)

	tok, err := GenerateToken(42, "user@example.com")
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	if tok == "" {
		t.Fatal("token was empty")
	}

	claims, err := ValidateToken(tok)
	if err != nil {
		t.Fatalf("ValidateToken: %v", err)
	}
	if claims.UserID != 42 {
		t.Errorf("UserID = %d, want 42", claims.UserID)
	}
	if claims.Email != "user@example.com" {
		t.Errorf("Email = %q, want user@example.com", claims.Email)
	}
	if claims.Issuer != "halalstocks" {
		t.Errorf("Issuer = %q, want halalstocks", claims.Issuer)
	}
}

// Without Init() both calls must error rather than silently signing
// with an empty key — an empty key would accept ANY HS256 token,
// which is the worst possible failure mode for an auth library.
func TestGenerateValidate_RequireInit(t *testing.T) {
	jwtSecret = nil
	defer Init(testSecret) // restore for subsequent tests

	if _, err := GenerateToken(1, "x@y"); err == nil {
		t.Error("GenerateToken with no secret should error")
	}
	if _, err := ValidateToken("anything"); err == nil {
		t.Error("ValidateToken with no secret should error")
	}
}

// A token mutated after issuance must not validate. We flip one byte
// of the signature portion (the trailing segment after the final '.').
func TestValidateToken_RejectsTampered(t *testing.T) {
	Init(testSecret)

	tok, err := GenerateToken(7, "tamper@example.com")
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		t.Fatalf("expected 3 JWT segments, got %d", len(parts))
	}
	// Flip the last character of the signature. The signature is the
	// HMAC over header.payload, so any change breaks verification.
	sig := []byte(parts[2])
	sig[len(sig)-1] ^= 0x01
	tampered := parts[0] + "." + parts[1] + "." + string(sig)

	if _, err := ValidateToken(tampered); err == nil {
		t.Fatal("tampered token validated — signature check is broken")
	}
}

// A token signed with secret A must not be accepted when the server is
// configured with secret B. Otherwise rotating the secret wouldn't
// actually invalidate old sessions.
func TestValidateToken_RejectsWrongSecret(t *testing.T) {
	Init("secret-a")
	tok, err := GenerateToken(7, "foo@example.com")
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}

	Init("secret-b")
	defer Init(testSecret) // restore

	if _, err := ValidateToken(tok); err == nil {
		t.Fatal("token from different secret should not validate")
	}
}

// Expired tokens are rejected by the underlying library — we just
// verify that path is wired. We construct the expired token directly
// with the same secret since GenerateToken hardcodes a 24h expiry.
func TestValidateToken_RejectsExpired(t *testing.T) {
	Init(testSecret)

	expiredClaims := Claims{
		UserID: 9,
		Email:  "old@example.com",
		RegisteredClaims: gojwt.RegisteredClaims{
			ExpiresAt: gojwt.NewNumericDate(time.Now().Add(-1 * time.Hour)),
			IssuedAt:  gojwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
			Issuer:    "halalstocks",
		},
	}
	expired, err := gojwt.NewWithClaims(gojwt.SigningMethodHS256, expiredClaims).
		SignedString(jwtSecret)
	if err != nil {
		t.Fatalf("sign expired token: %v", err)
	}

	if _, err := ValidateToken(expired); err == nil {
		t.Fatal("expired token should not validate")
	}
}

// Garbage input must not panic or accidentally produce a non-nil
// claims pointer — both would let a non-token slip through middleware.
func TestValidateToken_RejectsGarbage(t *testing.T) {
	Init(testSecret)

	for _, bad := range []string{"", "not.a.token", "abc.def.ghi", "..."} {
		claims, err := ValidateToken(bad)
		if err == nil {
			t.Errorf("input %q: expected error, got nil", bad)
		}
		if claims != nil {
			t.Errorf("input %q: expected nil claims, got %+v", bad, claims)
		}
	}
}
