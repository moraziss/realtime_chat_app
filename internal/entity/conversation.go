package entity

import (
	"encoding/json" // Добавь этот импорт
	"time"
)

type Conversation struct {
	ID        string          `json:"id"`
	UserID    string          `json:"user_id"`
	CreatedAt time.Time       `json:"created_at"`
	Text      string          `json:"text"`
	Metadata  json.RawMessage `json:"metadata,omitempty"` // Измени []byte на json.RawMessage
}
