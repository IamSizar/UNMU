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
	// AvatarURL — profile image. Populated by PATCH /me/profile (mig 0038).
	// Stays NULL until the user uploads an avatar; clients fall back to
	// a gradient + initials when empty.
	AvatarURL           sql.NullString
	Role                string         // USER, EXPERT, SCHOLAR (default USER)
	ExpertID            sql.NullString // FK → experts.id when role != USER
	SubscriptionTier    string         // FREE, PREMIUM
	SubscriptionStatus  string         // ACTIVE, CANCELED, EXPIRED
	SubscriptionEndDate sql.NullTime
	// Locale — UI language synced from the app ('en' / 'ar'). Drives
	// per-recipient notification push localization. NOT NULL default 'en'.
	Locale              string
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

// Ad — one row in the `ads` table. Used both by the public
// /api/ads?region_code=… endpoint and by the admin CRUD. JSON tags use
// the camelCase shape the admin dashboard + Flutter clients expect.
type Ad struct {
	ID          int64          `json:"id"`
	CompanyName string         `json:"companyName"`
	Title       string         `json:"title"`
	Description sql.NullString `json:"-"`
	ImageURL    sql.NullString `json:"-"`
	TargetURL   sql.NullString `json:"-"`
	RegionCode  sql.NullString `json:"-"`
	IsActive    bool           `json:"isActive"`
	StartDate   sql.NullTime   `json:"-"`
	EndDate     sql.NullTime   `json:"-"`
	CreatedAt   time.Time      `json:"createdAt"`
}

// AdJSON is the wire shape — collapses the sql.Null* wrappers into
// nullable pointer fields so the client sees `null` instead of
// `{String:"", Valid:false}`. The repo returns these for HTTP paths.
type AdJSON struct {
	ID          int64      `json:"id"`
	CompanyName string     `json:"companyName"`
	Title       string     `json:"title"`
	Description *string    `json:"description,omitempty"`
	ImageURL    *string    `json:"imageUrl,omitempty"`
	TargetURL   *string    `json:"targetUrl,omitempty"`
	RegionCode  *string    `json:"regionCode,omitempty"`
	IsActive    bool       `json:"isActive"`
	StartDate   *time.Time `json:"startDate,omitempty"`
	EndDate     *time.Time `json:"endDate,omitempty"`
	CreatedAt   time.Time  `json:"createdAt"`
}

// ToJSON unwraps the sql.Null* fields. Empty strings/zero times remain
// non-nil if the column was set to "" rather than NULL — that's
// intentional, the admin's "clear" flow uses NULL.
func (a *Ad) ToJSON() AdJSON {
	out := AdJSON{
		ID:          a.ID,
		CompanyName: a.CompanyName,
		Title:       a.Title,
		IsActive:    a.IsActive,
		CreatedAt:   a.CreatedAt,
	}
	if a.Description.Valid {
		s := a.Description.String
		out.Description = &s
	}
	if a.ImageURL.Valid {
		s := a.ImageURL.String
		out.ImageURL = &s
	}
	if a.TargetURL.Valid {
		s := a.TargetURL.String
		out.TargetURL = &s
	}
	if a.RegionCode.Valid {
		s := a.RegionCode.String
		out.RegionCode = &s
	}
	if a.StartDate.Valid {
		t := a.StartDate.Time
		out.StartDate = &t
	}
	if a.EndDate.Valid {
		t := a.EndDate.Time
		out.EndDate = &t
	}
	return out
}

// PromoCode — one row in promo_codes. Same JSON-tag pattern as Ad.
type PromoCode struct {
	ID            int64         `json:"id"`
	Code          string        `json:"code"`
	DiscountType  string        `json:"discountType"` // PERCENTAGE, FIXED
	DiscountValue float64       `json:"discountValue"`
	// Scope — which kind of purchase the code applies to:
	// "all" (default), "expert", or "community".
	Scope         string        `json:"scope"`
	MaxUses       sql.NullInt64 `json:"-"`
	UsedCount     int64         `json:"usedCount"`
	IsActive      bool          `json:"isActive"`
	ValidFrom     sql.NullTime  `json:"-"`
	ValidUntil    sql.NullTime  `json:"-"`
	CreatedAt     time.Time     `json:"createdAt"`
}

// PromoCodeJSON — wire shape for admin endpoints.
type PromoCodeJSON struct {
	ID            int64      `json:"id"`
	Code          string     `json:"code"`
	DiscountType  string     `json:"discountType"`
	DiscountValue float64    `json:"discountValue"`
	Scope         string     `json:"scope"`
	MaxUses       *int64     `json:"maxUses,omitempty"`
	UsedCount     int64      `json:"usedCount"`
	IsActive      bool       `json:"isActive"`
	ValidFrom     *time.Time `json:"validFrom,omitempty"`
	ValidUntil    *time.Time `json:"validUntil,omitempty"`
	CreatedAt     time.Time  `json:"createdAt"`
}

func (p *PromoCode) ToJSON() PromoCodeJSON {
	scope := p.Scope
	if scope == "" {
		scope = "all"
	}
	out := PromoCodeJSON{
		ID:            p.ID,
		Code:          p.Code,
		DiscountType:  p.DiscountType,
		DiscountValue: p.DiscountValue,
		Scope:         scope,
		UsedCount:     p.UsedCount,
		IsActive:      p.IsActive,
		CreatedAt:     p.CreatedAt,
	}
	if p.MaxUses.Valid {
		v := p.MaxUses.Int64
		out.MaxUses = &v
	}
	if p.ValidFrom.Valid {
		t := p.ValidFrom.Time
		out.ValidFrom = &t
	}
	if p.ValidUntil.Valid {
		t := p.ValidUntil.Time
		out.ValidUntil = &t
	}
	return out
}
