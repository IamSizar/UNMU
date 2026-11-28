package handlers

import "testing"

func TestCommunityTierPricing(t *testing.T) {
	str := func(s string) *string { return &s }
	n := func(i int) *int { return &i }

	if p, msg := communityTierPricing(nil, nil, nil); msg != "" || p.Tier != nil || p.Monthly != nil {
		t.Fatalf("no change expected, got %+v %q", p, msg)
	}
	if _, msg := communityTierPricing(nil, n(500), nil); msg == "" {
		t.Fatal("raw prices without a tier must be refused")
	}
	if _, msg := communityTierPricing(str("t7"), nil, nil); msg == "" {
		t.Fatal("unknown tier must be refused")
	}
	p, msg := communityTierPricing(str("t3"), n(1), n(2))
	if msg != "" || *p.Monthly != 1999 || *p.Yearly != 19999 || *p.Currency != "usd" {
		t.Fatalf("t3 should be 1999/19999 usd, got %+v %q", p, msg)
	}
	if p, _ = communityTierPricing(str(""), nil, nil); *p.Tier != "" || *p.Monthly != 0 || *p.Yearly != 0 {
		t.Fatalf("empty tier should be free, got %+v", p)
	}
}
