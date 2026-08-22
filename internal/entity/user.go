package entity

import (
	"encoding/json"
	"errors"
	"time"

	"golang.org/x/crypto/bcrypt"
)

var ErrUserNotFound = errors.New("user not found")

type User struct {
	ID             string          `json:"id,omitempty"`
	Name           string          `json:"name,omitempty"`
	Email          string          `json:"email,omitempty"`
	AvatarURL      *string         `json:"avatar_url,omitempty"`
	Bio            *string         `json:"bio,omitempty"`
	Settings       json.RawMessage `json:"settings,omitempty"`
	CreatedAt      time.Time       `json:"created_at,omitempty"`
	UpdatedAt      time.Time       `json:"updated_at,omitempty"`
	HashedPassword string          `json:"hashed_password,omitempty"`
}

func NewUser(name, email string) *User {
	return &User{
		Name:     name,
		Email:    email,
		Settings: json.RawMessage("{}"),
	}
}

func (u *User) SetPassword(password string) error {
	if len(password) < 6 {
		return errors.New("пароль должен быть не менее 6 символов")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	u.HashedPassword = string(hash)
	return nil
}

func (u *User) ComparePassword(password string) error {
	return bcrypt.CompareHashAndPassword([]byte(u.HashedPassword), []byte(password))
}
