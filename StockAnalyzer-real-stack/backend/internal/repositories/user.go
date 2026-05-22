package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
	"time"
)

type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) Create(user *models.User) error {
	query := `
		INSERT INTO users (email, password_hash, name, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`

	var name sql.NullString
	if user.Name.Valid {
		name = user.Name
	}

	err := r.db.QueryRow(query,
		user.Email, user.PasswordHash, name, time.Now(), time.Now(),
	).Scan(&user.ID)

	return err
}

func (r *UserRepository) GetByEmail(email string) (*models.User, error) {
	query := `
		SELECT id, email, password_hash, name, 
		       COALESCE(subscription_tier, 'FREE'), 
		       COALESCE(subscription_status, 'ACTIVE'), 
		       subscription_end_date,
		       created_at, updated_at
		FROM users
		WHERE email = $1
	`

	user := &models.User{}
	err := r.db.QueryRow(query, email).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.Name,
		&user.SubscriptionTier, &user.SubscriptionStatus, &user.SubscriptionEndDate,
		&user.CreatedAt, &user.UpdatedAt,
	)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	return user, err
}

func (r *UserRepository) GetByID(id int64) (*models.User, error) {
	query := `
		SELECT id, email, password_hash, name, 
		       COALESCE(subscription_tier, 'FREE'), 
		       COALESCE(subscription_status, 'ACTIVE'), 
		       subscription_end_date,
		       created_at, updated_at
		FROM users
		WHERE id = $1
	`

	user := &models.User{}
	err := r.db.QueryRow(query, id).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.Name,
		&user.SubscriptionTier, &user.SubscriptionStatus, &user.SubscriptionEndDate,
		&user.CreatedAt, &user.UpdatedAt,
	)

	if err == sql.ErrNoRows {
		return nil, nil
	}
	return user, err
}

func (r *UserRepository) UpdateSubscription(userID int64, tier, status string, endDate *time.Time) error {
	query := `
		UPDATE users
		SET subscription_tier = $1, subscription_status = $2, subscription_end_date = $3, updated_at = $4
		WHERE id = $5
	`
	_, err := r.db.Exec(query, tier, status, endDate, time.Now(), userID)
	return err
}
