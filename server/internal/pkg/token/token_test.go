package token

import (
	"testing"
	"time"
)

func newTestSigner(now time.Time, ttl time.Duration, issuer, secret string) *SignerImpl {
	return New(SignerOptions{
		Now:    func() time.Time { return now },
		TTL:    ttl,
		Issuer: issuer,
		Secret: []byte(secret),
	})
}

func TestSignVerifyRoundTrip(t *testing.T) {
	signer := newTestSigner(time.Now(), time.Hour, "real-time-chat", "secret")

	tok, err := signer.Sign("user-123")
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}

	got, err := signer.Verify(tok)
	if err != nil {
		t.Fatalf("Verify() error = %v", err)
	}
	if got != "user-123" {
		t.Errorf("Verify() = %q, want %q", got, "user-123")
	}
}

func TestVerifyRejectsExpiredToken(t *testing.T) {
	// Подписываем токен так, будто "сейчас" далёкое прошлое: exp окажется
	// давно в прошлом относительно реальных часов, которые использует Verify.
	past := time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)
	signer := newTestSigner(past, time.Minute, "real-time-chat", "secret")

	tok, err := signer.Sign("user-123")
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}
	if _, err := signer.Verify(tok); err == nil {
		t.Error("Verify() expected an error for an expired token, got nil")
	}
}

func TestVerifyRejectsWrongIssuer(t *testing.T) {
	now := time.Now()
	issuedBy := newTestSigner(now, time.Hour, "issuer-a", "shared-secret")
	verifiedBy := newTestSigner(now, time.Hour, "issuer-b", "shared-secret")

	tok, err := issuedBy.Sign("user-123")
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}
	if _, err := verifiedBy.Verify(tok); err == nil {
		t.Error("Verify() expected an error for a mismatched issuer, got nil")
	}
}

func TestVerifyRejectsWrongSecret(t *testing.T) {
	now := time.Now()
	issuedBy := newTestSigner(now, time.Hour, "real-time-chat", "secret-a")
	verifiedBy := newTestSigner(now, time.Hour, "real-time-chat", "secret-b")

	tok, err := issuedBy.Sign("user-123")
	if err != nil {
		t.Fatalf("Sign() error = %v", err)
	}
	if _, err := verifiedBy.Verify(tok); err == nil {
		t.Error("Verify() expected an error for a mismatched secret, got nil")
	}
}
