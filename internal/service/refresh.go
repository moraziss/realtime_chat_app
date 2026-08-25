package service

import (
	"Real-time-Chat/internal/apperr"
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/logging"
	"Real-time-Chat/internal/pkg/token"
	"Real-time-Chat/internal/repository"
	"context"
	"time"
)

// --- ОБНОВЛЕНИЕ ТОКЕНА ---

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type RefreshResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

type Refresh func(ctx context.Context, req RefreshRequest) (*RefreshResponse, error)

// NewRefreshService обменивает валидный refresh-токен на новую пару
// access+refresh. Старый refresh-токен отзывается сразу (ротация) — если он
// будет предъявлен повторно, это будет уже недействительный токен, что само
// по себе полезный сигнал (кто-то использует украденную/устаревшую копию).
func NewRefreshService(refreshRepo repository.RefreshToken, signer token.Signer, refreshTTL time.Duration) Refresh {
	return func(ctx context.Context, req RefreshRequest) (*RefreshResponse, error) {
		if req.RefreshToken == "" {
			return nil, apperr.Validation("refresh_token is required")
		}

		stored, err := refreshRepo.GetRefreshTokenByHash(token.HashRefreshToken(req.RefreshToken))
		if err != nil {
			if err == entity.ErrRefreshTokenInvalid {
				return nil, apperr.Unauthorized("недействительный refresh-токен")
			}
			logging.FromContext(ctx).Error("failed to look up refresh token", "err", err)
			return nil, apperr.Internal(err)
		}
		if !stored.IsValid(time.Now()) {
			return nil, apperr.Unauthorized("недействительный refresh-токен")
		}

		if err := refreshRepo.RevokeRefreshToken(stored.ID); err != nil {
			logging.FromContext(ctx).Error("failed to revoke rotated refresh token", "err", err)
			return nil, apperr.Internal(err)
		}

		accessToken, err := signer.Sign(stored.UserID)
		if err != nil {
			return nil, apperr.Internal(err)
		}

		newPlain, newHash, err := token.GenerateRefreshToken()
		if err != nil {
			return nil, apperr.Internal(err)
		}
		if err := refreshRepo.CreateRefreshToken(&entity.RefreshToken{
			UserID:    stored.UserID,
			TokenHash: newHash,
			ExpiresAt: time.Now().Add(refreshTTL),
		}); err != nil {
			logging.FromContext(ctx).Error("failed to persist rotated refresh token", "err", err)
			return nil, apperr.Internal(err)
		}

		return &RefreshResponse{
			AccessToken:  accessToken,
			RefreshToken: newPlain,
			ExpiresIn:    signer.ExpiresIn(),
		}, nil
	}
}

// --- ЛОГАУТ ---

type LogoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type LogoutResponse struct {
	Status bool `json:"status"`
}

type Logout func(ctx context.Context, req LogoutRequest) (*LogoutResponse, error)

func NewLogoutService(refreshRepo repository.RefreshToken) Logout {
	return func(ctx context.Context, req LogoutRequest) (*LogoutResponse, error) {
		if req.RefreshToken == "" {
			return nil, apperr.Validation("refresh_token is required")
		}

		stored, err := refreshRepo.GetRefreshTokenByHash(token.HashRefreshToken(req.RefreshToken))
		if err != nil {
			if err == entity.ErrRefreshTokenInvalid {
				// Токена уже нет — с точки зрения клиента цель достигнута.
				return &LogoutResponse{Status: true}, nil
			}
			logging.FromContext(ctx).Error("failed to look up refresh token for logout", "err", err)
			return nil, apperr.Internal(err)
		}

		if err := refreshRepo.RevokeRefreshToken(stored.ID); err != nil {
			logging.FromContext(ctx).Error("failed to revoke refresh token", "err", err)
			return nil, apperr.Internal(err)
		}
		return &LogoutResponse{Status: true}, nil
	}
}
