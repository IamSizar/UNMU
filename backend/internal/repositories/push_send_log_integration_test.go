package repositories

import (
	"fmt"
	"testing"
	"time"
)

// Sends are recorded and listed newest first. Needs PULSE_TEST_DSN.
func TestPushSendLogRecordAndRecent(t *testing.T) {
	db := openPulseTestDB(t)
	f := newPulseFixture(t, db)
	repo := NewPushSendLogRepository(db)
	tag := fmt.Sprintf("it-push-%d", time.Now().UnixNano())
	t.Cleanup(func() { db.Exec(`DELETE FROM push_send_log WHERE body = $1`, tag) })

	failed := "fcm unavailable"
	if err := repo.Record(PushSend{Title: "first", Body: tag, Target: "all",
		Recipients: 3, SuccessCount: 2, FailureCount: 1, SentBy: &f.userID}); err != nil {
		t.Fatalf("record first: %v", err)
	}
	if err := repo.Record(PushSend{Title: "second", Body: tag, Target: "ios",
		Recipients: 1, FailureCount: 1, SendError: &failed}); err != nil {
		t.Fatalf("record second: %v", err)
	}

	got, err := repo.Recent(0)
	if err != nil {
		t.Fatalf("recent: %v", err)
	}
	var mine []PushSend
	for _, s := range got {
		if s.Body == tag {
			mine = append(mine, s)
		}
	}
	if len(mine) != 2 || mine[0].Title != "second" || mine[1].Title != "first" {
		t.Fatalf("want [second first], got %+v", mine)
	}
	if mine[0].SendError == nil || *mine[0].SendError != failed || mine[0].SentBy != nil {
		t.Errorf("second row fields wrong: %+v", mine[0])
	}
	if mine[1].SentBy == nil || *mine[1].SentBy != f.userID || mine[1].SuccessCount != 2 {
		t.Errorf("first row fields wrong: %+v", mine[1])
	}
}
