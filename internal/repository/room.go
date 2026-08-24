package repository

import (
	"Real-time-Chat/internal/entity"
)

type Room interface {
	CreateRoom(users ...string) (string, error)
	GetRoom(userID string) ([]string, error)
	GetRooms(userID string) ([]entity.UserRoom, error)
	GetDirectRoom(user1, user2 string) (string, error)
}
