package token

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type Signer interface {
	Sign(id string) (string, error)
	Verify(token string) (string, error)
	ExpiresIn() int64
}

type SignerOptions struct {
	Now    func() time.Time
	TTL    time.Duration
	Issuer string
	Secret []byte
}

type SignerImpl struct {
	opts SignerOptions
}

func New(opts SignerOptions) *SignerImpl {
	return &SignerImpl{opts}
}

func (s *SignerImpl) ExpiresIn() int64 {
	return int64(s.opts.TTL.Seconds())
}

func (s *SignerImpl) Sign(id string) (string, error) {
	claims := jwt.RegisteredClaims{
		ExpiresAt: jwt.NewNumericDate(s.opts.Now().Add(s.opts.TTL)),
		Issuer:    s.opts.Issuer,
		Subject:   id,
	}
	signer := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return signer.SignedString(s.opts.Secret)
}

func (s *SignerImpl) Verify(tokenString string) (string, error) {
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return s.opts.Secret, nil
	})
	if err != nil {
		return "", err
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return "", errors.New("invalid token")
	}
	issuer, _ := claims["iss"].(string)
	if issuer != s.opts.Issuer {
		return "", errors.New("invalid token issuer")
	}
	sub, _ := claims["sub"].(string)
	return sub, nil
}
