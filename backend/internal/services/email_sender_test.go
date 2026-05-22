package services

import (
	"os"
	"strings"
	"testing"
)

// TestNewEmailSender_SoftFail verifies that an unset SMTP_HOST returns
// nil rather than a half-built sender. This is the contract that lets
// auth.go safely call h.emailSender == nil instead of a try/catch.
func TestNewEmailSender_SoftFail(t *testing.T) {
	old := os.Getenv("SMTP_HOST")
	defer os.Setenv("SMTP_HOST", old)

	os.Unsetenv("SMTP_HOST")
	if got := NewEmailSender(); got != nil {
		t.Fatalf("NewEmailSender with no SMTP_HOST = %+v, want nil", got)
	}

	os.Setenv("SMTP_HOST", "")
	if got := NewEmailSender(); got != nil {
		t.Fatalf("NewEmailSender with empty SMTP_HOST = %+v, want nil", got)
	}
}

// TestNewEmailSender_Configured verifies the env-var → struct mapping
// covers every field the sender uses at runtime.
func TestNewEmailSender_Configured(t *testing.T) {
	saved := map[string]string{}
	for _, k := range []string{"SMTP_HOST", "SMTP_PORT", "SMTP_USER", "SMTP_PASSWORD", "SMTP_FROM", "SMTP_FROM_NAME"} {
		saved[k] = os.Getenv(k)
		defer os.Setenv(k, saved[k])
	}

	os.Setenv("SMTP_HOST", "smtp.example.com")
	os.Setenv("SMTP_PORT", "465")
	os.Setenv("SMTP_USER", "apikey")
	os.Setenv("SMTP_PASSWORD", "secret")
	os.Setenv("SMTP_FROM", "noreply@example.com")
	os.Setenv("SMTP_FROM_NAME", "Example")

	s := NewEmailSender()
	if s == nil {
		t.Fatal("NewEmailSender returned nil with full env")
	}
	if s.host != "smtp.example.com" {
		t.Errorf("host = %q, want smtp.example.com", s.host)
	}
	if s.port != 465 {
		t.Errorf("port = %d, want 465", s.port)
	}
	if s.username != "apikey" {
		t.Errorf("username = %q, want apikey", s.username)
	}
	if s.from != "noreply@example.com" {
		t.Errorf("from = %q, want noreply@example.com", s.from)
	}
	if s.fromName != "Example" {
		t.Errorf("fromName = %q, want Example", s.fromName)
	}
}

// TestNewEmailSender_FromFallsBackToUser — many SMTP providers (Postmark
// in particular) want From to match the SMTP user. When SMTP_FROM is
// omitted we fall back to SMTP_USER rather than failing silently.
func TestNewEmailSender_FromFallsBackToUser(t *testing.T) {
	saved := map[string]string{}
	for _, k := range []string{"SMTP_HOST", "SMTP_USER", "SMTP_FROM"} {
		saved[k] = os.Getenv(k)
		defer os.Setenv(k, saved[k])
	}

	os.Setenv("SMTP_HOST", "smtp.example.com")
	os.Setenv("SMTP_USER", "fallback@example.com")
	os.Unsetenv("SMTP_FROM")

	s := NewEmailSender()
	if s == nil {
		t.Fatal("NewEmailSender returned nil")
	}
	if s.from != "fallback@example.com" {
		t.Errorf("from = %q, want SMTP_USER fallback", s.from)
	}
}

// TestSend_NilReceiverReturnsError — calling Send on a nil sender (the
// soft-fail case) must return an error rather than panic. Handlers
// inspect the error but never propagate it to the user; we just need it
// to not crash.
func TestSend_NilReceiverReturnsError(t *testing.T) {
	var s *EmailSender // nil
	err := s.Send("to@example.com", "hi", "<p>x</p>", "x")
	if err == nil {
		t.Fatal("Send on nil sender returned nil error; expected configuration error")
	}
	if !strings.Contains(err.Error(), "not configured") {
		t.Errorf("error = %q, want it to mention not configured", err)
	}
}

// TestSend_EmptyRecipient — defensive check for callers that forget to
// trim. Should error before even attempting to dial.
func TestSend_EmptyRecipient(t *testing.T) {
	s := &EmailSender{host: "smtp.example.com", port: 587, from: "x@y", fromName: "X"}
	if err := s.Send("   ", "subj", "<p>x</p>", "x"); err == nil {
		t.Fatal("Send with blank recipient returned nil error")
	}
}

// TestRandHex covers both length and alphabet (must be lowercase hex).
func TestRandHex(t *testing.T) {
	for _, n := range []int{1, 12, 32} {
		s, err := randHex(n)
		if err != nil {
			t.Fatalf("randHex(%d) error: %v", n, err)
		}
		if len(s) != n*2 {
			t.Errorf("randHex(%d) length = %d, want %d", n, len(s), n*2)
		}
		for _, c := range s {
			if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
				t.Errorf("randHex(%d) contains non-hex char %q", n, c)
				break
			}
		}
	}
}

// TestPublicAppURL verifies the default + override + trailing-slash
// trimming. Used by RequestPasswordReset to build the email link.
func TestPublicAppURL(t *testing.T) {
	old := os.Getenv("APP_PUBLIC_URL")
	defer os.Setenv("APP_PUBLIC_URL", old)

	os.Unsetenv("APP_PUBLIC_URL")
	if got := PublicAppURL(); got != "https://unmu.app" {
		t.Errorf("default = %q, want https://unmu.app", got)
	}

	os.Setenv("APP_PUBLIC_URL", "http://localhost:5173/")
	if got := PublicAppURL(); got != "http://localhost:5173" {
		t.Errorf("trim trailing slash = %q, want http://localhost:5173", got)
	}
}

// TestEncodeHeader — ASCII passes through unchanged; non-ASCII gets
// base64-encoded with RFC-2047 wrapping.
func TestEncodeHeader(t *testing.T) {
	if got := encodeHeader("Hello"); got != "Hello" {
		t.Errorf("ascii: got %q, want Hello", got)
	}
	got := encodeHeader("Héllo")
	if !strings.HasPrefix(got, "=?UTF-8?B?") || !strings.HasSuffix(got, "?=") {
		t.Errorf("non-ascii: got %q, want RFC-2047 encoded-word", got)
	}
}
