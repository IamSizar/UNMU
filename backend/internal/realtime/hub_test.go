package realtime

import (
	"testing"
)

// Channel formats are part of the wire contract between Postgres
// NOTIFY senders, the in-process Hub, and the mobile WebSocket
// clients. If the format string ever changes here, every NOTIFY
// payload in the database triggers and every client subscription
// must change in lock-step. These tests pin the contract.

func TestChannelUser(t *testing.T) {
	cases := []struct {
		in   int64
		want string
	}{
		{0, "user:0"},
		{1, "user:1"},
		{42, "user:42"},
		{1_000_000, "user:1000000"},
		{-7, "user:-7"},
	}
	for _, c := range cases {
		if got := ChannelUser(c.in); got != c.want {
			t.Errorf("ChannelUser(%d) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestChannelExpert(t *testing.T) {
	if got := ChannelExpert("abc"); got != "expert:abc" {
		t.Errorf("ChannelExpert(abc) = %q, want expert:abc", got)
	}
	if got := ChannelExpert(""); got != "expert:" {
		t.Errorf("ChannelExpert(empty) = %q, want expert:", got)
	}
}

func TestChannelCommunity(t *testing.T) {
	if got := ChannelCommunity("xyz"); got != "community:xyz" {
		t.Errorf("ChannelCommunity(xyz) = %q, want community:xyz", got)
	}
}

func TestChannelAdminConstant(t *testing.T) {
	// The admin broadcast channel is a fixed string, no formatter.
	// Pin the literal value so a careless rename trips this test.
	if ChannelAdmin != "admin" {
		t.Errorf("ChannelAdmin = %q, want admin", ChannelAdmin)
	}
}

// itoa is the inline strconv-free integer formatter that backs
// ChannelUser. Tested directly because the fast-path branches
// (zero, positive, negative) aren't all exercised by the channel
// tests above.
func TestItoa(t *testing.T) {
	cases := []struct {
		in   int64
		want string
	}{
		{0, "0"},
		{1, "1"},
		{9, "9"},
		{10, "10"},
		{99, "99"},
		{100, "100"},
		{12345, "12345"},
		{-1, "-1"},
		{-9, "-9"},
		{-12345, "-12345"},
		// Largest practical user ID range — pin against silent overflow.
		{9_223_372_036_854_775_806, "9223372036854775806"},
	}
	for _, c := range cases {
		if got := itoa(c.in); got != c.want {
			t.Errorf("itoa(%d) = %q, want %q", c.in, got, c.want)
		}
	}
}
