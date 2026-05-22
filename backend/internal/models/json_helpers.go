package models

import (
	"database/sql"
	"encoding/json"
)

// Custom JSON marshaler for ShariahStatus to output simple types instead of sql.Null* structs
func (s ShariahStatus) MarshalJSON() ([]byte, error) {
	type Alias ShariahStatus
	return json.Marshal(&struct {
		Status           string   `json:"status"`
		Grade            *string  `json:"grade"`
		DebtRatio        *float64 `json:"debt_ratio"`
		HaramIncomeRatio *float64 `json:"haram_income_ratio"`
		PurificationRate *float64 `json:"purification_rate"`
		PaysZakat        bool     `json:"pays_zakat"`
		Explanation      string   `json:"explanation"`
		Reason           string   `json:"reason"`
		AsOfDate         string   `json:"as_of_date"`
		*Alias
	}{
		Status:           s.Status,
		Grade:            nullStringPtr(s.Grade),
		DebtRatio:        nullFloatPtr(s.DebtRatio),
		HaramIncomeRatio: nullFloatPtr(s.HaramIncomeRatio),
		PurificationRate: nullFloatPtr(s.PurificationRate),
		PaysZakat:        s.PaysZakat.Bool,
		Explanation:      s.Explanation.String,
		Reason:           s.Reason.String,
		AsOfDate:         s.AsOfDate.Format("2006-01-02"),
		Alias:            (*Alias)(&s),
	})
}

// Helpers
func nullStringPtr(ns sql.NullString) *string {
	if ns.Valid {
		return &ns.String
	}
	return nil
}

func nullFloatPtr(nf sql.NullFloat64) *float64 {
	if nf.Valid {
		return &nf.Float64
	}
	return nil
}
