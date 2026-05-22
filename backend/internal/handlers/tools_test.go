package handlers

import (
	"math"
	"testing"
)

// pow() is the hand-rolled exponent helper that backs the DCA
// future-value formula. The DCA endpoint always calls it with an
// INTEGER exponent (months over the savings horizon), so the integer
// code path is the one that matters and the one this file pins down.
//
// Tolerance is 1e-9 because the loop is float64 multiplication with at
// most a few dozen iterations — anything coarser would mask a real
// regression while still passing on a buggy build.

const powEps = 1e-9

func TestPow_IntegerExponents(t *testing.T) {
	cases := []struct {
		name string
		base float64
		exp  float64
		want float64
	}{
		{"any^0 = 1", 7, 0, 1},
		{"base^1 = base", 2, 1, 2},
		{"2^10", 2, 10, 1024},
		{"3^3", 3, 3, 27},
		{"10^4", 10, 4, 10000},
		// 5%/12 monthly rate compounded 12 months — the exact shape
		// DCA uses every time the user picks "1 year, 5% annual".
		{"(1+0.05/12)^12", 1 + 0.05/12, 12, math.Pow(1+0.05/12, 12)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := pow(c.base, c.exp)
			if math.Abs(got-c.want) > powEps {
				t.Errorf("pow(%v, %v) = %v, want %v (Δ=%v)",
					c.base, c.exp, got, c.want, got-c.want)
			}
		})
	}
}

func TestPow_NegativeExponent(t *testing.T) {
	// 2^-3 = 1/8 = 0.125. The implementation handles this by recursing
	// on the absolute exponent and reciprocating.
	if got, want := pow(2, -3), 0.125; math.Abs(got-want) > powEps {
		t.Errorf("pow(2, -3) = %v, want %v", got, want)
	}
}

func TestPow_ZeroExponentBeforeNegativeCheck(t *testing.T) {
	// The function returns 1 for any base when exp == 0 — including
	// the indeterminate-form base==0 case (the DCA code never feeds 0
	// here, but pinning the convention guards future call sites).
	if got := pow(0, 0); got != 1 {
		t.Errorf("pow(0, 0) = %v, want 1 (function's convention)", got)
	}
}

func TestPow_OneIsIdentity(t *testing.T) {
	// 1^n = 1 for any n. Catches accumulator bugs where the loop's
	// `result *= base` would otherwise hide a wrong initial value.
	for _, exp := range []float64{0, 1, 5, 50} {
		if got := pow(1, exp); got != 1 {
			t.Errorf("pow(1, %v) = %v, want 1", exp, got)
		}
	}
}
