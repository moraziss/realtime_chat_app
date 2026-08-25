package repository

import "Real-time-Chat/internal/entity"

type RefreshToken interface {
	CreateRefreshToken(t *entity.RefreshToken) error
	GetRefreshTokenByHash(hash string) (*entity.RefreshToken, error)
	RevokeRefreshToken(id string) error
	RevokeAllRefreshTokensForUser(userID string) error
}
