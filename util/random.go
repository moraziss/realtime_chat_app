package util

import (
	"math/rand"
	"time"
)

func GenerateVerificationCode() string {
	rand.Seed(time.Now().UnixNano())

	// Алфавит из цифр
	charset := "0123456789"
	code := make([]byte, 6)
	for i := range code {
		code[i] = charset[rand.Intn(len(charset))]
	}

	return string(code)
}
