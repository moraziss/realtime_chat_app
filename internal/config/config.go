// Package config собирает всю конфигурацию приложения из переменных
// окружения в одном месте и проверяет её при старте, вместо того чтобы
// каждый пакет читал os.Getenv самостоятельно и тихо работал с пустыми
// значениями (например, с пустым JWT_SECRET).
package config

import (
	"fmt"
	"os"
	"strings"
	"time"
)

// minJWTSecretLen — минимальная длина JWT_SECRET, ниже которой отказываемся
// стартовать. Не завышаем порог намеренно: должен пропускать уже
// существующие в проде секреты, а не требовать их немедленной ротации.
const minJWTSecretLen = 16

type Config struct {
	Env  string // "development" | "production"
	Port string

	DBUser string
	DBPass string
	DBName string
	DBHost string

	JWTSecret  string
	JWTIssuer  string
	AccessTTL  time.Duration
	RefreshTTL time.Duration

	SMTPHost     string
	SMTPPort     string
	SMTPUser     string
	SMTPPassword string

	// AllowedOrigins — множество разрешённых Origin для CORS и WS.
	// nil означает "разрешён любой Origin" (ALLOWED_ORIGINS не задан).
	AllowedOrigins map[string]struct{}
}

// Load читает конфигурацию из окружения и валидирует обязательные поля.
// Возвращает ошибку вместо того, чтобы позволить приложению стартовать с
// пустым JWT-секретом или недостающими данными для подключения к БД.
func Load() (*Config, error) {
	cfg := &Config{
		Env:  getEnvDefault("ENV", "production"),
		Port: getEnvDefault("PORT", "8080"),

		DBUser: os.Getenv("DB_USER"),
		DBPass: os.Getenv("DB_PASS"),
		DBName: os.Getenv("DB_NAME"),
		DBHost: getEnvDefault("DB_HOST", "localhost"),

		JWTSecret: os.Getenv("JWT_SECRET"),
		JWTIssuer: os.Getenv("JWT_ISSUER"),

		SMTPHost:     os.Getenv("SMTP_HOST"),
		SMTPPort:     os.Getenv("SMTP_PORT"),
		SMTPUser:     os.Getenv("SMTP_USER"),
		SMTPPassword: firstNonEmpty(os.Getenv("SMTP_PASSWORD"), os.Getenv("SMTP_PASS")),

		AllowedOrigins: ParseAllowedOrigins(os.Getenv("ALLOWED_ORIGINS")),
	}

	// AccessTTL по умолчанию сохраняет текущее поведение (24ч, единственный
	// токен без обновления). Уменьшается до короткоживущего значения там, где
	// вводятся refresh-токены — см. соответствующий коммит.
	cfg.AccessTTL = parseDurationDefault("ACCESS_TOKEN_TTL", 24*time.Hour)
	cfg.RefreshTTL = parseDurationDefault("REFRESH_TOKEN_TTL", 30*24*time.Hour)

	if err := cfg.validate(); err != nil {
		return nil, err
	}
	return cfg, nil
}

func (c *Config) validate() error {
	var missing []string
	if c.DBUser == "" {
		missing = append(missing, "DB_USER")
	}
	if c.DBPass == "" {
		missing = append(missing, "DB_PASS")
	}
	if c.DBName == "" {
		missing = append(missing, "DB_NAME")
	}
	if c.JWTSecret == "" {
		missing = append(missing, "JWT_SECRET")
	}
	if c.JWTIssuer == "" {
		missing = append(missing, "JWT_ISSUER")
	}
	if len(missing) > 0 {
		return fmt.Errorf("config: missing required environment variables: %s", strings.Join(missing, ", "))
	}
	if len(c.JWTSecret) < minJWTSecretLen {
		return fmt.Errorf("config: JWT_SECRET must be at least %d characters long", minJWTSecretLen)
	}
	return nil
}

func getEnvDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

func parseDurationDefault(key string, def time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return def
	}
	return d
}

// ParseAllowedOrigins разбирает список Origin через запятую. Используется и
// для REST CORS, и для проверки Origin у WebSocket-апгрейда — раньше это был
// один и тот же код, скопированный в cmd/app и internal/ws по отдельности.
func ParseAllowedOrigins(v string) map[string]struct{} {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	set := make(map[string]struct{})
	for _, origin := range strings.Split(v, ",") {
		if origin = strings.TrimSpace(origin); origin != "" {
			set[origin] = struct{}{}
		}
	}
	return set
}
