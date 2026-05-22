package models

import (
	"database/sql"
	"time"
)

type Stock struct {
	ID          int64
	Ticker      string
	Exchange    string
	Name        string
	Country     sql.NullString
	RegionCode  sql.NullString
	Sector      sql.NullString
	Industry    sql.NullString
	Description sql.NullString
	MarketCap   sql.NullInt64
	IsActive    bool
	CreatedAt   time.Time
	UpdatedAt   time.Time
}

type Fundamental struct {
	ID                int64
	StockID           int64
	TotalAssets       sql.NullFloat64
	TotalDebt         sql.NullFloat64
	CashAndEquiv      sql.NullFloat64
	TotalRevenue      sql.NullFloat64
	InterestIncome    sql.NullFloat64
	InterestExpense   sql.NullFloat64
	NetIncome         sql.NullFloat64
	DividendsPerShare sql.NullFloat64
	AsOfDate          sql.NullTime
	Source            sql.NullString
	RawJSON           sql.NullString
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

type ShariahStatus struct {
	ID               int64
	StockID          int64
	Status           string         // HALAL, HARAM, MIXED, UNKNOWN
	Grade            sql.NullString // A, B, C, F
	DebtRatio        sql.NullFloat64
	HaramIncomeRatio sql.NullFloat64
	PurificationRate sql.NullFloat64
	PaysZakat        sql.NullBool
	Explanation      sql.NullString
	Reason           sql.NullString
	AsOfDate         time.Time
	CreatedAt        time.Time
	UpdatedAt        time.Time
}

type User struct {
	ID                  int64
	Email               string
	PasswordHash        string
	Name                sql.NullString
	SubscriptionTier    string // FREE, PREMIUM
	SubscriptionStatus  string // ACTIVE, CANCELED, EXPIRED
	SubscriptionEndDate sql.NullTime
	CreatedAt           time.Time
	UpdatedAt           time.Time
}

type UserPortfolio struct {
	ID          int64
	UserID      int64
	StockID     int64
	Shares      sql.NullFloat64
	AvgBuyPrice sql.NullFloat64
	AddedAt     time.Time
}

type Notification struct {
	ID        int64
	UserID    sql.NullInt64
	StockID   sql.NullInt64
	Type      string
	Title     string
	Message   string
	IsRead    bool
	CreatedAt time.Time
}

type AnalystRating struct {
	ID          int64
	StockID     int64
	AnalystName sql.NullString
	Rating      sql.NullString // BUY, HOLD, SELL
	TargetPrice sql.NullFloat64
	RatingDate  sql.NullTime
	Source      sql.NullString
	CreatedAt   time.Time
}

type Ad struct {
	ID          int64
	CompanyName string
	Title       string
	Description sql.NullString
	ImageURL    sql.NullString
	TargetURL   sql.NullString
	RegionCode  sql.NullString
	IsActive    bool
	StartDate   sql.NullTime
	EndDate     sql.NullTime
	CreatedAt   time.Time
}

type PromoCode struct {
	ID            int64
	Code          string
	DiscountType  string // PERCENTAGE, FIXED
	DiscountValue float64
	MaxUses       sql.NullInt64
	UsedCount     int64
	IsActive      bool
	ValidFrom     sql.NullTime
	ValidUntil    sql.NullTime
	CreatedAt     time.Time
}
