// Package logging wraps the standard library's log/slog so the rest of the
// app gets structured, leveled logging with per-request correlation instead
// of unstructured log.Printf calls scattered across packages.
package logging

import (
	"Real-time-Chat/internal/entity"
	"context"
	"log/slog"
	"net/http"
	"os"

	"github.com/google/uuid"
)

// New builds the process-wide logger. JSON output is used everywhere except
// ENV=development, where a human-readable text handler is easier to read
// while working locally.
func New(env string) *slog.Logger {
	opts := &slog.HandlerOptions{Level: slog.LevelInfo}
	var handler slog.Handler
	if env == "development" {
		handler = slog.NewTextHandler(os.Stdout, opts)
	} else {
		handler = slog.NewJSONHandler(os.Stdout, opts)
	}
	return slog.New(handler)
}

// FromContext returns the default logger with request_id/user_id fields
// attached when present in ctx, so a log line written deep in a service or
// the WS hub can still be correlated back to the request that caused it.
// Falls back to slog.Default() when ctx carries neither.
func FromContext(ctx context.Context) *slog.Logger {
	logger := slog.Default()
	if reqID, ok := ctx.Value(entity.ContextKeyRequestID).(string); ok && reqID != "" {
		logger = logger.With("request_id", reqID)
	}
	if userID, ok := ctx.Value(entity.ContextKeyUserID).(string); ok && userID != "" {
		logger = logger.With("user_id", userID)
	}
	return logger
}

// WithRequestID assigns a correlation ID to each incoming request (echoed
// back via the X-Request-ID response header, or reused if the caller already
// sent one) so every log line produced while handling it — including ones
// several layers deep via FromContext — can be tied back together.
func WithRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqID := r.Header.Get("X-Request-ID")
		if reqID == "" {
			reqID = uuid.NewString()
		}
		w.Header().Set("X-Request-ID", reqID)
		ctx := context.WithValue(r.Context(), entity.ContextKeyRequestID, reqID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
