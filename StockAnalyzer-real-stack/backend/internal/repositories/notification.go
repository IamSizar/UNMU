package repositories

import (
	"database/sql"
	"halalstocks/internal/models"
	"time"
)

type NotificationRepository struct {
	db *sql.DB
}

func NewNotificationRepository(db *sql.DB) *NotificationRepository {
	return &NotificationRepository{db: db}
}

func (r *NotificationRepository) Create(notification *models.Notification) error {
	query := `
		INSERT INTO notifications (user_id, stock_id, type, title, message, is_read, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id
	`
	
	var userID, stockID sql.NullInt64
	if notification.UserID.Valid {
		userID = notification.UserID
	}
	if notification.StockID.Valid {
		stockID = notification.StockID
	}
	
	err := r.db.QueryRow(query,
		userID, stockID, notification.Type, notification.Title,
		notification.Message, notification.IsRead, time.Now(),
	).Scan(&notification.ID)
	
	return err
}

func (r *NotificationRepository) GetUserNotifications(userID int64, limit, offset int) ([]*models.Notification, error) {
	query := `
		SELECT id, user_id, stock_id, type, title, message, is_read, created_at
		FROM notifications
		WHERE user_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`
	
	rows, err := r.db.Query(query, userID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	
	var notifications []*models.Notification
	for rows.Next() {
		notification := &models.Notification{}
		err := rows.Scan(
			&notification.ID, &notification.UserID, &notification.StockID,
			&notification.Type, &notification.Title, &notification.Message,
			&notification.IsRead, &notification.CreatedAt,
		)
		if err != nil {
			continue
		}
		notifications = append(notifications, notification)
	}
	
	return notifications, rows.Err()
}

func (r *NotificationRepository) MarkAsRead(notificationID int64) error {
	query := `UPDATE notifications SET is_read = TRUE WHERE id = $1`
	_, err := r.db.Exec(query, notificationID)
	return err
}

func (r *NotificationRepository) GetUnreadCount(userID int64) (int, error) {
	query := `SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = FALSE`
	var count int
	err := r.db.QueryRow(query, userID).Scan(&count)
	return count, err
}
