// Package apperr gives services a small, explicit vocabulary of error kinds
// (validation, unauthorized, forbidden, not found, internal) and gives HTTP
// handlers a single WriteError helper that maps them to the right status
// code and a consistent JSON body - instead of every handler doing
// http.Error(w, err.Error(), http.StatusBadRequest) regardless of what
// actually went wrong, which leaks raw internal error strings to clients and
// returns 400 even for auth/permission/not-found failures.
package apperr

import (
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/logging"
	"encoding/json"
	"errors"
	"net/http"
)

type Code string

const (
	CodeValidation   Code = "validation"
	CodeUnauthorized Code = "unauthorized"
	CodeForbidden    Code = "forbidden"
	CodeNotFound     Code = "not_found"
	CodeInternal     Code = "internal"
)

// Error is the typed application error services should return whenever the
// failure reason matters to the caller (bad input, missing auth, no
// permission, missing resource). Message is safe to show to the client;
// Err, if set, is the underlying cause and is only ever logged, never sent.
type Error struct {
	Code    Code
	Message string
	Err     error
}

func (e *Error) Error() string {
	if e.Err != nil {
		return e.Message + ": " + e.Err.Error()
	}
	return e.Message
}

func (e *Error) Unwrap() error { return e.Err }

func Validation(msg string) *Error   { return &Error{Code: CodeValidation, Message: msg} }
func Unauthorized(msg string) *Error { return &Error{Code: CodeUnauthorized, Message: msg} }
func Forbidden(msg string) *Error    { return &Error{Code: CodeForbidden, Message: msg} }
func NotFound(msg string) *Error     { return &Error{Code: CodeNotFound, Message: msg} }

// Internal wraps an unexpected error (DB failure, etc.). The client only
// ever sees a generic message; err is logged server-side in full.
func Internal(err error) *Error {
	return &Error{Code: CodeInternal, Message: "internal server error", Err: err}
}

func statusFor(code Code) int {
	switch code {
	case CodeValidation:
		return http.StatusBadRequest
	case CodeUnauthorized:
		return http.StatusUnauthorized
	case CodeForbidden:
		return http.StatusForbidden
	case CodeNotFound:
		return http.StatusNotFound
	default:
		return http.StatusInternalServerError
	}
}

type errorResponse struct {
	Error struct {
		Message string `json:"message"`
	} `json:"error"`
}

// WriteError maps err to an HTTP status and a {"error":{"message":"..."}}
// JSON body, and logs it via logging.FromContext so it's correlated with the
// request that caused it. Anything that isn't an *Error (an unclassified
// error bubbling up from a repository, a stdlib error, etc.) is treated as
// internal: logged in full, but the client only ever gets a generic
// "internal server error" message - never the raw err.Error() string, which
// could contain DB/driver details.
func WriteError(w http.ResponseWriter, r *http.Request, err error) {
	var appErr *Error
	switch {
	case errors.As(err, &appErr):
		// use as-is
	case errors.Is(err, entity.ErrUserNotFound):
		appErr = NotFound("пользователь не найден")
	default:
		appErr = Internal(err)
	}

	status := statusFor(appErr.Code)
	logger := logging.FromContext(r.Context())
	if status >= http.StatusInternalServerError {
		logger.Error("request failed", "status", status, "path", r.URL.Path, "err", appErr.Error())
	} else {
		logger.Warn("request failed", "status", status, "path", r.URL.Path, "err", appErr.Error())
	}

	clientMsg := appErr.Message
	if status >= http.StatusInternalServerError {
		clientMsg = "internal server error"
	}

	var body errorResponse
	body.Error.Message = clientMsg

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
