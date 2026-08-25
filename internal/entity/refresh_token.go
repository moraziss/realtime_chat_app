package entity

import (
	"errors"
	"time"
)

// ErrRefreshTokenInvalid is returned when a refresh token doesn't exist at
// all (unknown hash) - expired/revoked tokens are still found by hash but
// rejected by the caller based on ExpiresAt/RevokedAt, so the caller can
// tell "never existed" apart from "existed but is no longer valid" if it
// ever needs to.
var ErrRefreshTokenInvalid = errors.New("refresh token invalid")

type RefreshToken struct {
	ID        string
	UserID    string
	TokenHash string
	ExpiresAt time.Time
	CreatedAt time.Time
	RevokedAt *time.Time
}

func (t *RefreshToken) IsValid(now time.Time) bool {
	return t.RevokedAt == nil && now.Before(t.ExpiresAt)
}
