package repository

import "Real-time-Chat/entity"

type Conversation interface {
	GetConversations(roomID string) ([]entity.Conversation, error)
}
