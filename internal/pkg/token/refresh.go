package token

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
)

// GenerateRefreshToken returns a new random opaque refresh token (256 bits
// of entropy, hex-encoded) plus the SHA-256 hash that should be persisted
// instead of the token itself, so a leaked database can't be used to
// reconstruct valid tokens.
func GenerateRefreshToken() (plaintext string, hash string, err error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", "", err
	}
	plaintext = hex.EncodeToString(buf)
	return plaintext, HashRefreshToken(plaintext), nil
}

// HashRefreshToken hashes a refresh token for lookup/storage. Deterministic
// (unlike a password hash) because refresh tokens are already
// high-entropy random values - the goal is only to avoid storing them in
// recoverable plaintext, not to defend against brute force.
func HashRefreshToken(plaintext string) string {
	sum := sha256.Sum256([]byte(plaintext))
	return hex.EncodeToString(sum[:])
}
