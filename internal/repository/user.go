package repository

import (
	"Real-time-Chat/internal/entity"
	"time"
)

type User interface {
	CreateUser(user *entity.User) error
	UpdateUser(user *entity.User) error
	DeleteUser(id string) error
	GetUser(id string) (*entity.User, error) // Изменили на возвращаемый указатель
	GetUserByEmail(email string) (entity.User, error)
	GetUsers(currentUserID string) ([]entity.User, error)
	SaveVerificationCode(email, code string, expiresAt time.Time) error
	CheckVerificationCode(email, code string) (bool, error)
	DeleteVerificationCode(email string) error
}
