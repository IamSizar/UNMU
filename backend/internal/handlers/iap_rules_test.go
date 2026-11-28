package handlers

import (
	"testing"
	"time"
)

// Expert SKUs are com.unmu.expert.<expertId>.<plan>; the backend must read
// the expert from the SKU Apple verified, never trust the client's expertId.
func TestExpertIDFromProductID(t *testing.T) {
	cases := map[string]string{
		"com.unmu.expert.abc-123.monthly": "abc-123",
		"com.unmu.expert.abc-123.yearly":  "abc-123",
		"com.unmu.expert..monthly":        "",
		"com.unmu.expert.abc.weekly":      "",
		"com.unmu.premium.monthly":        "",
		"":                                "",
	}
	for sku, want := range cases {
		if got := expertIDFromProductID(sku); got != want {
			t.Errorf("expertIDFromProductID(%q) = %q, want %q", sku, got, want)
		}
	}
}

func TestCheckVerifyRequest(t *testing.T) {
	cases := []struct {
		name, product, expert string
		ok                    bool
	}{
		{"missing product", "", "", false},
		{"premium", "com.unmu.premium.monthly", "", true},
		{"expert matches", "com.unmu.expert.e1.monthly", "e1", true},
		{"expert from another SKU", "com.unmu.expert.e1.monthly", "e2", false},
		{"expert id on premium SKU", "com.unmu.premium.monthly", "e1", false},
	}
	for _, c := range cases {
		err := checkVerifyRequest(c.product, c.expert)
		if (err == nil) != c.ok {
			t.Errorf("%s: err = %v, want ok=%v", c.name, err, c.ok)
		}
	}
}

func TestRequireCurrentSubscription(t *testing.T) {
	past := time.Now().Add(-time.Hour)
	future := time.Now().Add(time.Hour)
	if err := requireCurrentSubscription(storeEntitlement{ExpiresDate: &past}); err == nil {
		t.Error("expired receipt accepted")
	}
	if err := requireCurrentSubscription(storeEntitlement{}); err == nil {
		t.Error("receipt without expiry accepted")
	}
	if err := requireCurrentSubscription(storeEntitlement{ExpiresDate: &future}); err != nil {
		t.Errorf("current receipt refused: %v", err)
	}
}
