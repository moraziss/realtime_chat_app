package utils

import (
	"strings"
	"testing"
)

func TestGenerateVerificationCodeShape(t *testing.T) {
	for i := 0; i < 100; i++ {
		code := GenerateVerificationCode()
		if len(code) != 6 {
			t.Fatalf("GenerateVerificationCode() = %q, want length 6", code)
		}
		if strings.Trim(code, "0123456789") != "" {
			t.Fatalf("GenerateVerificationCode() = %q, want only digits", code)
		}
	}
}

func TestGenerateVerificationCodeVaries(t *testing.T) {
	seen := make(map[string]bool)
	for i := 0; i < 20; i++ {
		seen[GenerateVerificationCode()] = true
	}
	// С 6 цифрами (миллион вариантов) 20 попыток почти наверняка дадут
	// разные коды; допускаем небольшую погрешность, чтобы тест не был флаки.
	if len(seen) < 15 {
		t.Fatalf("GenerateVerificationCode() produced too few distinct codes in 20 tries: %d", len(seen))
	}
}
