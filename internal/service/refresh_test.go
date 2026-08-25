package service

import (
	"Real-time-Chat/internal/apperr"
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/pkg/token"
	"context"
	"testing"
	"time"
)

func TestRefreshRejectsUnknownToken(t *testing.T) {
	refresh := NewRefreshService(newFakeRefreshTokenRepo(), testSigner(), time.Hour)

	_, err := refresh(context.Background(), RefreshRequest{RefreshToken: "not-a-real-token"})
	if err == nil {
		t.Fatal("expected an error for an unknown refresh token, got nil")
	}
	mustHaveCode(t, err, apperr.CodeUnauthorized)
}

func TestRefreshRejectsExpiredToken(t *testing.T) {
	repo := newFakeRefreshTokenRepo()
	plain, hash, err := token.GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken() error = %v", err)
	}
	_ = repo.CreateRefreshToken(&entity.RefreshToken{
		UserID:    "user-1",
		TokenHash: hash,
		ExpiresAt: time.Now().Add(-time.Minute), // уже истёк
	})

	refresh := NewRefreshService(repo, testSigner(), time.Hour)

	_, err = refresh(context.Background(), RefreshRequest{RefreshToken: plain})
	if err == nil {
		t.Fatal("expected an error for an expired refresh token, got nil")
	}
	mustHaveCode(t, err, apperr.CodeUnauthorized)
}

func TestRefreshRejectsRevokedToken(t *testing.T) {
	repo := newFakeRefreshTokenRepo()
	plain, hash, err := token.GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken() error = %v", err)
	}
	_ = repo.CreateRefreshToken(&entity.RefreshToken{
		UserID:    "user-1",
		TokenHash: hash,
		ExpiresAt: time.Now().Add(time.Hour),
	})
	_ = repo.RevokeRefreshToken(repo.byHash[hash].ID)

	refresh := NewRefreshService(repo, testSigner(), time.Hour)

	_, err = refresh(context.Background(), RefreshRequest{RefreshToken: plain})
	if err == nil {
		t.Fatal("expected an error for a revoked refresh token, got nil")
	}
	mustHaveCode(t, err, apperr.CodeUnauthorized)
}

func TestRefreshRotatesTokenAndOldOneStopsWorking(t *testing.T) {
	repo := newFakeRefreshTokenRepo()
	plain, hash, err := token.GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken() error = %v", err)
	}
	_ = repo.CreateRefreshToken(&entity.RefreshToken{
		UserID:    "user-1",
		TokenHash: hash,
		ExpiresAt: time.Now().Add(time.Hour),
	})

	refresh := NewRefreshService(repo, testSigner(), time.Hour)

	res, err := refresh(context.Background(), RefreshRequest{RefreshToken: plain})
	if err != nil {
		t.Fatalf("Refresh() error = %v", err)
	}
	if res.AccessToken == "" || res.RefreshToken == "" {
		t.Fatal("expected both a new access and refresh token")
	}
	if res.RefreshToken == plain {
		t.Error("expected a newly rotated refresh token, got the same one back")
	}

	// Старый токен теперь должен быть отклонён.
	if _, err := refresh(context.Background(), RefreshRequest{RefreshToken: plain}); err == nil {
		t.Error("expected the rotated-out refresh token to now be rejected, got nil error")
	}

	// А новый — работать.
	if _, err := refresh(context.Background(), RefreshRequest{RefreshToken: res.RefreshToken}); err != nil {
		t.Errorf("expected the newly issued refresh token to work, got error: %v", err)
	}
}

func TestLogoutRevokesToken(t *testing.T) {
	repo := newFakeRefreshTokenRepo()
	plain, hash, err := token.GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken() error = %v", err)
	}
	_ = repo.CreateRefreshToken(&entity.RefreshToken{
		UserID:    "user-1",
		TokenHash: hash,
		ExpiresAt: time.Now().Add(time.Hour),
	})

	logout := NewLogoutService(repo)
	res, err := logout(context.Background(), LogoutRequest{RefreshToken: plain})
	if err != nil {
		t.Fatalf("Logout() error = %v", err)
	}
	if !res.Status {
		t.Error("expected Status = true")
	}

	refresh := NewRefreshService(repo, testSigner(), time.Hour)
	if _, err := refresh(context.Background(), RefreshRequest{RefreshToken: plain}); err == nil {
		t.Error("expected the logged-out refresh token to be rejected, got nil error")
	}
}

func TestLogoutIsIdempotentForUnknownToken(t *testing.T) {
	logout := NewLogoutService(newFakeRefreshTokenRepo())

	res, err := logout(context.Background(), LogoutRequest{RefreshToken: "already-gone"})
	if err != nil {
		t.Fatalf("Logout() error = %v, want nil for an already-invalid token", err)
	}
	if !res.Status {
		t.Error("expected Status = true")
	}
}
