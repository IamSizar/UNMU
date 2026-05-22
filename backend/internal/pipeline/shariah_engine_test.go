package pipeline

import (
	"math"
	"testing"
)

// StandardRatioCalculator turns the raw fundamentals on a StockSnapshot
// into the four Shariah-screening ratios. The handler later compares
// each ratio against AAOIFI thresholds — so if this layer ever silently
// returns the wrong number, every downstream HALAL/HARAM call gets
// poisoned. These tests pin the formulas.

const ratioEps = 1e-9

func TestCalculateRatios_AllFourFormulas(t *testing.T) {
	calc := NewStandardRatioCalculator()
	snap := &StockSnapshot{
		TotalAssets:          1000,
		TotalDebt:            200,
		Revenue:              500,
		InterestIncome:       25,
		InterestExpense:      10,
		MarketCap:            2000,
		CashAndEquivalents:   400,
		ShortTermInvestments: 100,
	}
	got := calc.CalculateRatios(snap)

	// Each ratio is documented inline next to the impl as `value/base * 100`.
	mustRatio(t, "DebtRatio", got.DebtRatio, 20.0)             // 200/1000  → 20%
	mustRatio(t, "HaramIncomeRatio", got.HaramIncomeRatio, 5)  //  25/500   → 5%
	mustRatio(t, "CashToMarketCapRatio", got.CashToMarketCapRatio, 25) // 500/2000 → 25%
	mustRatio(t, "InterestExpenseRatio", got.InterestExpenseRatio, 2)  //  10/500   → 2%
}

// Zero-denominator guards — every ratio is divided by an externally-
// supplied number (TotalAssets / Revenue / MarketCap). The function
// MUST leave the result pointer nil rather than emit NaN / +Inf, because
// the JSON-serialized result is consumed by clients that expect a real
// number or the field's absence.
func TestCalculateRatios_ZeroDenominators(t *testing.T) {
	calc := NewStandardRatioCalculator()

	t.Run("zero assets ⇒ no DebtRatio", func(t *testing.T) {
		out := calc.CalculateRatios(&StockSnapshot{TotalAssets: 0, TotalDebt: 50})
		if out.DebtRatio != nil {
			t.Errorf("DebtRatio = %v, want nil", *out.DebtRatio)
		}
	})

	t.Run("zero revenue ⇒ no haram / interest ratio", func(t *testing.T) {
		out := calc.CalculateRatios(&StockSnapshot{Revenue: 0, InterestIncome: 10, InterestExpense: 10})
		if out.HaramIncomeRatio != nil {
			t.Errorf("HaramIncomeRatio = %v, want nil", *out.HaramIncomeRatio)
		}
		if out.InterestExpenseRatio != nil {
			t.Errorf("InterestExpenseRatio = %v, want nil", *out.InterestExpenseRatio)
		}
	})

	t.Run("zero market cap ⇒ no cash ratio", func(t *testing.T) {
		out := calc.CalculateRatios(&StockSnapshot{MarketCap: 0, CashAndEquivalents: 100})
		if out.CashToMarketCapRatio != nil {
			t.Errorf("CashToMarketCapRatio = %v, want nil", *out.CashToMarketCapRatio)
		}
	})

	t.Run("zero interest expense skips ratio", func(t *testing.T) {
		// The impl only emits InterestExpenseRatio when InterestExpense > 0.
		// Justified: companies with zero interest expense already pass the
		// rule; emitting 0% would clutter every clean response.
		out := calc.CalculateRatios(&StockSnapshot{Revenue: 100, InterestExpense: 0})
		if out.InterestExpenseRatio != nil {
			t.Errorf("InterestExpenseRatio = %v, want nil for zero expense", *out.InterestExpenseRatio)
		}
	})
}

// IsComplete decides whether the screener has enough data to run.
//
// The current implementation uses `TotalDebt >= 0` and `CashAndEquivalents >= 0`
// — and Go's zero value for float64 is 0, so those branches are ALWAYS true
// on a zero-initialized struct. Net effect: the "at least one of
// revenue/debt/cash" guard collapses to "always true", and IsComplete is
// effectively just `TotalAssets > 0 && MarketCap > 0`. These tests pin
// the actual behavior so any future fix (e.g. tightening the predicates
// to `> 0` or adding a populated-flag) will trip a visible failure.
func TestStockSnapshot_IsComplete(t *testing.T) {
	cases := []struct {
		name string
		snap StockSnapshot
		want bool
	}{
		{"empty snapshot is not complete", StockSnapshot{}, false},
		{"only market cap is not complete", StockSnapshot{MarketCap: 1}, false},
		{"only assets is not complete", StockSnapshot{TotalAssets: 1}, false},
		{
			// Currently TRUE — see comment on the function above.
			"assets + market cap alone passes (because hasDebt is always true)",
			StockSnapshot{TotalAssets: 1, MarketCap: 1},
			true,
		},
		{
			"assets + market cap + revenue",
			StockSnapshot{TotalAssets: 1, MarketCap: 1, Revenue: 100},
			true,
		},
		{
			"assets + market cap + cash",
			StockSnapshot{TotalAssets: 1, MarketCap: 1, CashAndEquivalents: 1},
			true,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := c.snap.IsComplete(); got != c.want {
				t.Errorf("IsComplete() = %v, want %v", got, c.want)
			}
		})
	}
}

// CompletenessScore counts how many of 8 critical fields are present
// and returns a 0..1 ratio. AAOIFI-style thresholds (set in AssessQuality)
// then bin them into COMPLETE / PARTIAL / INSUFFICIENT.
//
// Same caveat as IsComplete: four of the eight predicates are `>= 0`,
// so they fire on zero-initialized float64 fields. Net effect: every
// snapshot gets a free 4/8 = 0.5 baseline, and the actually-informative
// signal is the remaining 4 fields (Revenue, TotalAssets, Price, MarketCap).
// These tests pin that actual behavior.
func TestStockSnapshot_CompletenessScore(t *testing.T) {
	empty := StockSnapshot{}
	if got := empty.CompletenessScore(); math.Abs(got-0.5) > ratioEps {
		t.Errorf("empty.CompletenessScore() = %v, want 0.5 (4 of 8 'always true' branches)", got)
	}

	full := StockSnapshot{
		Revenue: 1, TotalAssets: 1, TotalDebt: 0, CashAndEquivalents: 0,
		Price: 1, MarketCap: 1, InterestIncome: 0, InterestExpense: 0,
	}
	if got := full.CompletenessScore(); math.Abs(got-1.0) > ratioEps {
		t.Errorf("full.CompletenessScore() = %v, want 1.0", got)
	}

	// 4 "always true" baseline + 4 explicitly populated = 1.0 (NOT 0.5).
	allFourTrue := StockSnapshot{Revenue: 1, TotalAssets: 1, Price: 1, MarketCap: 1}
	if got := allFourTrue.CompletenessScore(); math.Abs(got-1.0) > ratioEps {
		t.Errorf("allFourTrue.CompletenessScore() = %v, want 1.0", got)
	}
}

// AssessQuality bins the score: ≥0.8 ⇒ COMPLETE, ≥0.5 ⇒ PARTIAL,
// otherwise INSUFFICIENT. With the always-true baseline of 0.5, an
// empty snapshot lands in PARTIAL — pinning this explicitly so the
// known data-completeness false positive isn't accidentally fixed and
// the bin boundaries shift in a downstream-breaking way.
func TestStockSnapshot_AssessQuality(t *testing.T) {
	t.Run("complete (1.0)", func(t *testing.T) {
		s := StockSnapshot{
			Revenue: 1, TotalAssets: 1, TotalDebt: 0, CashAndEquivalents: 0,
			Price: 1, MarketCap: 1, InterestIncome: 0, InterestExpense: 0,
		}
		s.AssessQuality()
		if s.DataQuality != DataQualityComplete {
			t.Errorf("DataQuality = %q, want %q", s.DataQuality, DataQualityComplete)
		}
	})

	t.Run("empty lands in PARTIAL (always-true baseline = 0.5)", func(t *testing.T) {
		s := StockSnapshot{}
		s.AssessQuality()
		if s.DataQuality != DataQualityPartial {
			t.Errorf("DataQuality = %q, want %q", s.DataQuality, DataQualityPartial)
		}
	})
}

// mustRatio asserts a pointer ratio is non-nil and matches `want` to
// within `ratioEps`. Reused across the table-driven happy-path test.
func mustRatio(t *testing.T, name string, got *float64, want float64) {
	t.Helper()
	if got == nil {
		t.Errorf("%s = nil, want %v", name, want)
		return
	}
	if math.Abs(*got-want) > ratioEps {
		t.Errorf("%s = %v, want %v", name, *got, want)
	}
}
