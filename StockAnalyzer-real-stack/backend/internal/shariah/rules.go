package shariah

import "fmt"

// HaramSectors contains list of prohibited sectors (Section 1 - Activity Screening)
// These activities make a stock 100% NOT_HALAL
var HaramSectors = []string{
	"conventional banking",
	"banking",
	"conventional finance",
	"interest-based banking",
	"interest-based finance",
	"insurance",
	"casinos",
	"gambling",
	"alcohol",
	"tobacco",
	"adult entertainment",
	"pork",
	"weapons",
	"defense",
	"cannabis",
	"recreational cannabis",
	"nightclubs",
}

// HaramKeywords contains keywords that indicate non-compliant activities
// Based on Section 1 rules: Banking, Interest-based Finance, Gambling, Alcohol, Tobacco, Pork, Adult Content, Prohibited Weapons
var HaramKeywords = []string{
	"casino",
	"betting",
	"gambling",
	"lottery",
	"alcohol",
	"beer",
	"wine",
	"vodka",
	"whiskey",
	"liquor",
	"spirits",
	"tobacco",
	"cigarette",
	"cigar",
	"nicotine",
	"porn",
	"pornography",
	"adult",
	"escort",
	"explicit",
	"pork",
	"pig",
	"swine",
	"conventional bank",
	"interest-bearing",
	"usury",
	"riba",
	"interest income",
	"debt financing",
	"credit cards",
	"loans with interest",
	"weapon",
	"weapons of mass destruction",
	"armament",
	"defense contractor",
	"prohibited arms",
	"recreational cannabis",
	"marijuana",
	"nightclub",
}

// Thresholds for Shariah compliance (AAOIFI Standards - Section 2)
const (
	// RULE 1 - Debt Ratio: Must be ≤ 30%
	MaxDebtRatio = 0.30 // 30% - mandatory limit

	// RULE 2 - Non-Halal Income Ratio: Must be ≤ 5%
	MaxHaramIncomeRatio = 0.05 // 5% - mandatory limit

	// Grade A thresholds (Section 4)
	GradeADebtThreshold   = 0.10 // 10% for Grade A (Very Pure)
	GradeAIncomeThreshold = 0.01 // 1% for Grade A (Very Pure)

	// RULE 3 - Cash + Receivables (optional, not currently enforced)
	MaxCashReceivablesRatio = 0.70 // 70% - if enabled, classify as MIXED
)

// CheckHaramActivity checks if sector, industry, or description contains haram keywords
// Section 1 - Activity Screening: If activity is haram → status = NOT_HALAL
// Rule: If activity ∈ {Banking, Interest-based Finance, Gambling, Alcohol, Tobacco, Pork, Adult Content, Prohibited Weapons} → status = NOT_HALAL
func CheckHaramActivity(sector, industry, description string) (bool, string) {
	// Combine all text fields for comprehensive checking
	text := sector + " " + industry + " " + description
	lowerText := toLower(text)

	// If all fields are empty, mark as unclear
	if sector == "" && industry == "" && description == "" {
		return false, "" // Will be marked as UNKNOWN later if no financial data
	}

	// Check sectors first (more specific)
	for _, haramSector := range HaramSectors {
		if contains(lowerText, toLower(haramSector)) {
			return true, fmt.Sprintf("❌ FAILED ACTIVITY SCREENING (Section 1): Main business activity is '%s', which is not Shariah-compliant. Rule: If activity ∈ {Banking, Interest-based Finance, Gambling, Alcohol, Tobacco, Pork, Adult Content, Prohibited Weapons} → status = NOT_HALAL", haramSector)
		}
	}

	// Check keywords (more comprehensive)
	for _, keyword := range HaramKeywords {
		if contains(lowerText, toLower(keyword)) {
			return true, fmt.Sprintf("❌ FAILED ACTIVITY SCREENING (Section 1): Company involved in '%s', which is not Shariah-compliant. Rule: If activity ∈ {Banking, Interest-based Finance, Gambling, Alcohol, Tobacco, Pork, Adult Content, Prohibited Weapons} → status = NOT_HALAL", keyword)
		}
	}

	return false, ""
}

// Helper functions
func toLower(s string) string {
	// Simple lowercase conversion
	result := make([]byte, len(s))
	for i := 0; i < len(s); i++ {
		if s[i] >= 'A' && s[i] <= 'Z' {
			result[i] = s[i] + 32
		} else {
			result[i] = s[i]
		}
	}
	return string(result)
}

func contains(text, substr string) bool {
	if len(substr) == 0 {
		return false
	}
	if len(substr) > len(text) {
		return false
	}
	for i := 0; i <= len(text)-len(substr); i++ {
		if text[i:i+len(substr)] == substr {
			// Check word boundaries
			if (i == 0 || !isAlphaNumeric(text[i-1])) &&
				(i+len(substr) == len(text) || !isAlphaNumeric(text[i+len(substr)])) {
				return true
			}
		}
	}
	return false
}

func isAlphaNumeric(b byte) bool {
	return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9')
}

