package database

import (
	"Real-time-Chat/internal/entity"
	"database/sql"
)

func (c *Conn) CreateRefreshToken(t *entity.RefreshToken) error {
	return c.db.QueryRow(`
		INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
		VALUES ($1, $2, $3)
		RETURNING id, created_at`,
		t.UserID, t.TokenHash, t.ExpiresAt,
	).Scan(&t.ID, &t.CreatedAt)
}

func (c *Conn) GetRefreshTokenByHash(hash string) (*entity.RefreshToken, error) {
	var t entity.RefreshToken
	err := c.db.QueryRow(`
		SELECT id, user_id, token_hash, expires_at, created_at, revoked_at
		FROM refresh_tokens
		WHERE token_hash = $1`, hash).Scan(
		&t.ID, &t.UserID, &t.TokenHash, &t.ExpiresAt, &t.CreatedAt, &t.RevokedAt,
	)
	if err == sql.ErrNoRows {
		return nil, entity.ErrRefreshTokenInvalid
	}
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func (c *Conn) RevokeRefreshToken(id string) error {
	_, err := c.db.Exec(`UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1`, id)
	return err
}

func (c *Conn) RevokeAllRefreshTokensForUser(userID string) error {
	_, err := c.db.Exec(`UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL`, userID)
	return err
}
