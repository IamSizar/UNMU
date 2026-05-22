package services

import (
	"strings"
	"testing"
)

// truncToken is used by the FCM sender's log statements to print a
// device token without leaking the full secret. Contract from the
// inline comment + impl:
//
//   len(t) <= 12  →  returned unchanged
//   len(t) >  12  →  first 8 chars + "…"
//
// We pin both branches plus the 12-char boundary because logs leaking
// a full FCM token would let anyone with log access impersonate the
// device against Firebase.

func TestTruncToken_ShortStringsUnchanged(t *testing.T) {
	cases := []string{
		"",
		"a",
		"abcdefghij",   // 10
		"abcdefghijkl", // 12 — exact boundary, still unchanged
	}
	for _, in := range cases {
		t.Run("len="+itoa(len(in)), func(t *testing.T) {
			if got := truncToken(in); got != in {
				t.Errorf("truncToken(%q) = %q, want unchanged", in, got)
			}
		})
	}
}

func TestTruncToken_LongStringsTruncated(t *testing.T) {
	// 13 is the smallest length that triggers truncation (boundary + 1).
	tok := "abcdefghijklm"
	got := truncToken(tok)
	if !strings.HasPrefix(got, "abcdefgh") {
		t.Errorf("truncToken(%q) = %q, want prefix %q", tok, got, "abcdefgh")
	}
	if !strings.HasSuffix(got, "…") {
		t.Errorf("truncToken(%q) = %q, want trailing ellipsis", tok, got)
	}
	// Output should always be exactly 8 + ellipsis rune (3 bytes UTF-8).
	if got != "abcdefgh…" {
		t.Errorf("truncToken(%q) = %q, want %q", tok, got, "abcdefgh…")
	}
}

func TestTruncToken_RealFCMTokenLength(t *testing.T) {
	// Real FCM tokens are ~152 chars. The truncator must hide the bulk
	// of the secret while still leaving enough prefix to correlate
	// across log lines for a single device.
	tok := strings.Repeat("x", 152)
	got := truncToken(tok)
	if got != "xxxxxxxx…" {
		t.Errorf("truncToken(152 x's) = %q, want %q", got, "xxxxxxxx…")
	}
	// Make absolutely sure the suffix isn't leaking.
	if strings.Contains(got, "xxxxxxxxx") {
		t.Errorf("truncToken leaks more than 8 chars: %q", got)
	}
}

// itoa is a local helper to avoid importing strconv just for sub-test
// names. The behaviour is trivial enough that no separate test is
// required.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
