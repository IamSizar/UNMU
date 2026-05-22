package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
	"time"
)

type ShariahStatusRepository struct {
	db *sql.DB
}

func NewShariahStatusRepository(db *sql.DB) *ShariahStatusRepository {
	return &ShariahStatusRepository{db: db}
}

func (r *ShariahStatusRepository) CreateOrUpdate(status *models.ShariahStatus) error {
	// Use UPSERT with proper conflict handling on (stock_id, as_of_date)
	query := `
		INSERT INTO shariah_status (stock_id, status, grade, debt_ratio, haram_income_ratio, 
			purification_rate, pays_zakat, explanation, reason, as_of_date, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		ON CONFLICT (stock_id, as_of_date)
		DO UPDATE SET
			status = EXCLUDED.status,
			grade = EXCLUDED.grade,
			debt_ratio = EXCLUDED.debt_ratio,
			haram_income_ratio = EXCLUDED.haram_income_ratio,
			purification_rate = EXCLUDED.purification_rate,
			pays_zakat = EXCLUDED.pays_zakat,
			explanation = EXCLUDED.explanation,
			reason = EXCLUDED.reason,
			updated_at = EXCLUDED.updated_at
		RETURNING id
	`
	
	var id int64
	err := r.db.QueryRow(query,
		status.StockID, status.Status, status.Grade,
		status.DebtRatio, status.HaramIncomeRatio, status.PurificationRate,
		status.PaysZakat, status.Explanation, status.Reason,
		status.AsOfDate, time.Now(), time.Now(),
	).Scan(&id)
	if err == nil {
		status.ID = id
	}
	return err
}

func (r *ShariahStatusRepository) GetLatestStatus(stockID int64) (*models.ShariahStatus, error) {
	query := `
		SELECT id, stock_id, status, grade, debt_ratio, haram_income_ratio, purification_rate,
			pays_zakat, explanation, reason, as_of_date, created_at, updated_at
		FROM shariah_status
		WHERE stock_id = $1
		ORDER BY as_of_date DESC
		LIMIT 1
	`
	
	status := &models.ShariahStatus{}
	err := r.db.QueryRow(query, stockID).Scan(
		&status.ID, &status.StockID, &status.Status, &status.Grade,
		&status.DebtRatio, &status.HaramIncomeRatio, &status.PurificationRate,
		&status.PaysZakat, &status.Explanation, &status.Reason,
		&status.AsOfDate, &status.CreatedAt, &status.UpdatedAt,
	)
	
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return status, err
}

// GetLatestStatusBatch fetches latest Sharia statuses for multiple stocks in one query
// This eliminates N+1 query problem
func (r *ShariahStatusRepository) GetLatestStatusBatch(stockIDs []int64) (map[int64]*models.ShariahStatus, error) {
	if len(stockIDs) == 0 {
		return make(map[int64]*models.ShariahStatus), nil
	}

	// Use DISTINCT ON to get the latest status for each stock
	query := `
		SELECT DISTINCT ON (stock_id)
			id, stock_id, status, grade, debt_ratio, haram_income_ratio, purification_rate,
			pays_zakat, explanation, reason, as_of_date, created_at, updated_at
		FROM shariah_status
		WHERE stock_id = ANY($1)
		ORDER BY stock_id, as_of_date DESC
	`
	
	rows, err := r.db.Query(query, stockIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	
	statusMap := make(map[int64]*models.ShariahStatus)
	for rows.Next() {
		status := &models.ShariahStatus{}
		err := rows.Scan(
			&status.ID, &status.StockID, &status.Status, &status.Grade,
			&status.DebtRatio, &status.HaramIncomeRatio, &status.PurificationRate,
			&status.PaysZakat, &status.Explanation, &status.Reason,
			&status.AsOfDate, &status.CreatedAt, &status.UpdatedAt,
		)
		if err != nil {
			continue
		}
		statusMap[status.StockID] = status
	}
	
	return statusMap, rows.Err()
}

func (r *ShariahStatusRepository) GetPreviousStatus(stockID int64) (*models.ShariahStatus, error) {
	query := `
		SELECT id, stock_id, status, grade, debt_ratio, haram_income_ratio, purification_rate,
			pays_zakat, explanation, reason, as_of_date, created_at, updated_at
		FROM shariah_status
		WHERE stock_id = $1
		ORDER BY as_of_date DESC
		LIMIT 1 OFFSET 1
	`
	
	status := &models.ShariahStatus{}
	err := r.db.QueryRow(query, stockID).Scan(
		&status.ID, &status.StockID, &status.Status, &status.Grade,
		&status.DebtRatio, &status.HaramIncomeRatio, &status.PurificationRate,
		&status.PaysZakat, &status.Explanation, &status.Reason,
		&status.AsOfDate, &status.CreatedAt, &status.UpdatedAt,
	)
	
	if err == sql.ErrNoRows {
		return nil, nil
	}
	return status, err
}
