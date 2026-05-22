package repositories

import (
	"database/sql"
	"encoding/json"
	"halalstocks/internal/marketdata"
	"time"
)

type MarketRepository struct {
	db *sql.DB
}

func NewMarketRepository(db *sql.DB) *MarketRepository {
	return &MarketRepository{db: db}
}

// UpsertIndex updates or inserts a market index
func (r *MarketRepository) UpsertIndex(idx marketdata.IndexData) error {
	sparklineJSON, _ := json.Marshal(idx.Sparkline)
	datesJSON, _ := json.Marshal(idx.SparklineDates)

	query := `
		INSERT INTO market_indexes (symbol, name, price, change, change_percent, category, sparkline, sparkline_dates, last_updated)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (symbol) 
		DO UPDATE SET 
			name = EXCLUDED.name,
			price = EXCLUDED.price,
			change = EXCLUDED.change,
			change_percent = EXCLUDED.change_percent,
			category = EXCLUDED.category,
			sparkline = EXCLUDED.sparkline,
			sparkline_dates = EXCLUDED.sparkline_dates,
			last_updated = EXCLUDED.last_updated
	`

	_, err := r.db.Exec(query,
		idx.Symbol, idx.Name, idx.Price, idx.Change, idx.ChangePercent,
		idx.Category, sparklineJSON, datesJSON, time.Now(),
	)
	return err
}

// GetAllIndexes fetches all indexes from DB
func (r *MarketRepository) GetAllIndexes() ([]marketdata.IndexData, error) {
	query := `
		SELECT symbol, name, price, change, change_percent, category, sparkline, sparkline_dates
		FROM market_indexes
		ORDER BY category, id
	`

	rows, err := r.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var indexes []marketdata.IndexData
	for rows.Next() {
		var idx marketdata.IndexData
		var sparklineJSON []byte
		var datesJSON []byte
		err := rows.Scan(&idx.Symbol, &idx.Name, &idx.Price, &idx.Change, &idx.ChangePercent, &idx.Category, &sparklineJSON, &datesJSON)
		if err != nil {
			return nil, err
		}
		json.Unmarshal(sparklineJSON, &idx.Sparkline)
		if len(datesJSON) > 0 {
			json.Unmarshal(datesJSON, &idx.SparklineDates)
		}
		indexes = append(indexes, idx)
	}
	return indexes, nil
}

// SaveSentiment saves market sentiment data
func (r *MarketRepository) SaveSentiment(data marketdata.FearAndGreedData) error {
	// For now we just insert a new record or we could update the latest one.
	// Let's insert a new one to keep history, but we'll always fetch the latest.
	query := `
		INSERT INTO market_sentiment (value, label, color, last_updated)
		VALUES ($1, $2, $3, $4)
	`

	_, err := r.db.Exec(query, data.Value, data.Label, data.Color, time.Now())
	return err
}

// GetLatestSentiment fetches the latest sentiment data with trend
func (r *MarketRepository) GetLatestSentiment() (marketdata.FearAndGreedData, error) {
	// 1. Get latest record for main data
	query := `
		SELECT value, label, color, last_updated
		FROM market_sentiment
		ORDER BY last_updated DESC
		LIMIT 1
	`

	var data marketdata.FearAndGreedData
	var lastUpdated time.Time
	err := r.db.QueryRow(query).Scan(&data.Value, &data.Label, &data.Color, &lastUpdated)
	if err == sql.ErrNoRows {
		return marketdata.FearAndGreedData{}, nil
	}
	if err != nil {
		return marketdata.FearAndGreedData{}, err
	}
	data.LastUpdated = lastUpdated.Format("2006-01-02 15:04:05")

	// 2. Get trend (last 10 records)
	trendQuery := `
		SELECT value, last_updated
		FROM market_sentiment
		ORDER BY last_updated DESC
		LIMIT 10
	`
	rows, err := r.db.Query(trendQuery)
	if err == nil {
		defer rows.Close()
		var trend []int
		var dates []string
		for rows.Next() {
			var val int
			var t time.Time
			if err := rows.Scan(&val, &t); err == nil {
				trend = append(trend, val)
				dates = append(dates, t.Format(time.RFC3339))
			}
		}
		// Reverse to be chronological
		for i, j := 0, len(trend)-1; i < j; i, j = i+1, j-1 {
			trend[i], trend[j] = trend[j], trend[i]
			dates[i], dates[j] = dates[j], dates[i]
		}
		data.Trend = trend
		data.TrendDates = dates
	}

	return data, nil
}
