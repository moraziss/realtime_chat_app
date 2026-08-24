package utils

import (
	"crypto/rand"
	"fmt"
	"math/big"
)

func GenerateVerificationCode() string {
	const charset = "0123456789"
	code := make([]byte, 6)
	for i := range code {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			// crypto/rand практически никогда не должен возвращать ошибку;
			// сохраняем прежнее поведение в маловероятном случае сбоя.
			return fmt.Sprintf("%06d", 0)
		}
		code[i] = charset[n.Int64()]
	}
	return string(code)
}
