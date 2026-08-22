package repository

import (
	"Real-time-Chat/internal/entity"
)

type Conversation interface {
	GetConversations(roomID string) ([]entity.Conversation, error)
}
