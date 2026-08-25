package controller

import (
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/pkg/token"
	"Real-time-Chat/internal/service"
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// Минимальные in-memory реализации repository.User/RefreshToken - только то,
// что нужно, чтобы прогнать реальный HTTP-слой (роут -> контроллер -> сервис
// -> apperr.WriteError) сквозным образом, а не только сам сервис.

type fakeUsers struct {
	byEmail map[string]entity.User
	byID    map[string]entity.User
}

func newFakeUsers() *fakeUsers {
	return &fakeUsers{byEmail: map[string]entity.User{}, byID: map[string]entity.User{}}
}
func (f *fakeUsers) CreateUser(u *entity.User) error {
	if u.ID == "" {
		u.ID = "user-1"
	}
	f.byEmail[u.Email] = *u
	f.byID[u.ID] = *u
	return nil
}
func (f *fakeUsers) UpdateUser(u *entity.User) error { f.byID[u.ID] = *u; return nil }
func (f *fakeUsers) DeleteUser(id string) error      { delete(f.byID, id); return nil }
func (f *fakeUsers) GetUser(id string) (*entity.User, error) {
	u, ok := f.byID[id]
	if !ok {
		return nil, entity.ErrUserNotFound
	}
	return &u, nil
}
func (f *fakeUsers) GetUserByEmail(email string) (entity.User, error) {
	u, ok := f.byEmail[email]
	if !ok {
		return entity.User{}, entity.ErrUserNotFound
	}
	return u, nil
}
func (f *fakeUsers) GetUsers(currentUserID string) ([]entity.User, error) { return nil, nil }
func (f *fakeUsers) SaveVerificationCode(email, code string, expiresAt time.Time) error {
	return nil
}
func (f *fakeUsers) CheckVerificationCode(email, code string) (bool, error) { return false, nil }
func (f *fakeUsers) DeleteVerificationCode(email string) error              { return nil }

type fakeRefreshTokens struct {
	byHash map[string]*entity.RefreshToken
}

func newFakeRefreshTokens() *fakeRefreshTokens {
	return &fakeRefreshTokens{byHash: map[string]*entity.RefreshToken{}}
}
func (f *fakeRefreshTokens) CreateRefreshToken(t *entity.RefreshToken) error {
	t.ID = "rt-1"
	cp := *t
	f.byHash[t.TokenHash] = &cp
	return nil
}
func (f *fakeRefreshTokens) GetRefreshTokenByHash(hash string) (*entity.RefreshToken, error) {
	t, ok := f.byHash[hash]
	if !ok {
		return nil, entity.ErrRefreshTokenInvalid
	}
	return t, nil
}
func (f *fakeRefreshTokens) RevokeRefreshToken(id string) error                { return nil }
func (f *fakeRefreshTokens) RevokeAllRefreshTokensForUser(userID string) error { return nil }

func testSigner() token.Signer {
	return token.New(token.SignerOptions{
		Now:    time.Now,
		TTL:    time.Hour,
		Issuer: "test-issuer",
		Secret: []byte("test-secret"),
	})
}

type errorEnvelope struct {
	Error struct {
		Message string `json:"message"`
	} `json:"error"`
}

func decodeErrorBody(t *testing.T, body *bytes.Buffer) errorEnvelope {
	t.Helper()
	var env errorEnvelope
	if err := json.NewDecoder(body).Decode(&env); err != nil {
		t.Fatalf("failed to decode error envelope: %v (body: %s)", err, body.String())
	}
	return env
}

func TestPostLoginWrongPasswordReturns401Envelope(t *testing.T) {
	users := newFakeUsers()
	u := entity.NewUser("Alice", "alice@example.com")
	_ = u.SetPassword("correct-password")
	_ = users.CreateUser(u)

	handle := New().PostLogin(service.NewLoginService(users, newFakeRefreshTokens(), testSigner(), time.Hour))

	body, _ := json.Marshal(map[string]string{"email": "alice@example.com", "password": "wrong"})
	req := httptest.NewRequest(http.MethodPost, "/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	handle(rec, req, nil)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusUnauthorized)
	}
	env := decodeErrorBody(t, rec.Body)
	if env.Error.Message == "" {
		t.Error("expected a non-empty error message in the response envelope")
	}
}

func TestPostLoginSuccessReturnsTokenPair(t *testing.T) {
	users := newFakeUsers()
	u := entity.NewUser("Alice", "alice@example.com")
	_ = u.SetPassword("correct-password")
	_ = users.CreateUser(u)

	handle := New().PostLogin(service.NewLoginService(users, newFakeRefreshTokens(), testSigner(), time.Hour))

	body, _ := json.Marshal(map[string]string{"email": "alice@example.com", "password": "correct-password"})
	req := httptest.NewRequest(http.MethodPost, "/login", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	handle(rec, req, nil)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d (body: %s)", rec.Code, http.StatusOK, rec.Body.String())
	}
	var res service.LoginResponse
	if err := json.NewDecoder(rec.Body).Decode(&res); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if res.AccessToken == "" || res.RefreshToken == "" {
		t.Error("expected both access_token and refresh_token to be set")
	}
}

func TestPostRefreshUnknownTokenReturns401Envelope(t *testing.T) {
	handle := New().PostRefresh(service.NewRefreshService(newFakeRefreshTokens(), testSigner(), time.Hour))

	body, _ := json.Marshal(map[string]string{"refresh_token": "does-not-exist"})
	req := httptest.NewRequest(http.MethodPost, "/auth/refresh", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	handle(rec, req, nil)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusUnauthorized)
	}
	decodeErrorBody(t, rec.Body)
}

func TestPostRegisterMismatchedEmailReturns400Envelope(t *testing.T) {
	handle := New().PostRegister(service.NewRegisterService(newFakeUsers(), newFakeRefreshTokens(), testSigner(), time.Hour))

	body, _ := json.Marshal(map[string]string{
		"email": "a@example.com", "confirm_email": "b@example.com",
		"name": "A", "password": "password123", "code": "123456",
	})
	req := httptest.NewRequest(http.MethodPost, "/register", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	handle(rec, req, nil)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
	decodeErrorBody(t, rec.Body)
}

func TestPostLoginMalformedBodyReturns400Envelope(t *testing.T) {
	handle := New().PostLogin(service.NewLoginService(newFakeUsers(), newFakeRefreshTokens(), testSigner(), time.Hour))

	req := httptest.NewRequest(http.MethodPost, "/login", bytes.NewReader([]byte("not-json")))
	rec := httptest.NewRecorder()

	handle(rec, req, nil)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
	decodeErrorBody(t, rec.Body)
}
