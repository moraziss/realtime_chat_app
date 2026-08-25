package service

import (
	"Real-time-Chat/internal/apperr"
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/pkg/token"
	"context"
	"errors"
	"testing"
	"time"
)

func testSigner() token.Signer {
	return token.New(token.SignerOptions{
		Now:    time.Now,
		TTL:    time.Hour,
		Issuer: "test-issuer",
		Secret: []byte("test-secret"),
	})
}

func mustHaveCode(t *testing.T, err error, want apperr.Code) {
	t.Helper()
	var appErr *apperr.Error
	if !errors.As(err, &appErr) {
		t.Fatalf("error = %v, want an *apperr.Error", err)
	}
	if appErr.Code != want {
		t.Errorf("apperr code = %q, want %q", appErr.Code, want)
	}
}

func TestLoginRejectsUnknownEmail(t *testing.T) {
	login := NewLoginService(newFakeUserRepo(), newFakeRefreshTokenRepo(), testSigner(), time.Hour)

	_, err := login(context.Background(), LoginRequest{Email: "nobody@example.com", Password: "whatever"})
	if err == nil {
		t.Fatal("expected an error for an unknown email, got nil")
	}
	mustHaveCode(t, err, apperr.CodeUnauthorized)
}

func TestLoginRejectsWrongPassword(t *testing.T) {
	users := newFakeUserRepo()
	user := entity.NewUser("Alice", "alice@example.com")
	if err := user.SetPassword("correct-password"); err != nil {
		t.Fatalf("SetPassword() error = %v", err)
	}
	_ = users.CreateUser(user)

	login := NewLoginService(users, newFakeRefreshTokenRepo(), testSigner(), time.Hour)

	_, err := login(context.Background(), LoginRequest{Email: "alice@example.com", Password: "wrong-password"})
	if err == nil {
		t.Fatal("expected an error for a wrong password, got nil")
	}
	mustHaveCode(t, err, apperr.CodeUnauthorized)
}

func TestLoginSucceedsAndIssuesTokenPair(t *testing.T) {
	users := newFakeUserRepo()
	user := entity.NewUser("Alice", "alice@example.com")
	if err := user.SetPassword("correct-password"); err != nil {
		t.Fatalf("SetPassword() error = %v", err)
	}
	_ = users.CreateUser(user)
	refreshRepo := newFakeRefreshTokenRepo()

	login := NewLoginService(users, refreshRepo, testSigner(), time.Hour)

	res, err := login(context.Background(), LoginRequest{Email: "alice@example.com", Password: "correct-password"})
	if err != nil {
		t.Fatalf("Login() error = %v", err)
	}
	if res.AccessToken == "" {
		t.Error("AccessToken is empty")
	}
	if res.RefreshToken == "" {
		t.Error("RefreshToken is empty")
	}
	if len(refreshRepo.byHash) != 1 {
		t.Errorf("expected exactly one persisted refresh token, got %d", len(refreshRepo.byHash))
	}
}

func TestRegisterRejectsInvalidCode(t *testing.T) {
	users := newFakeUserRepo()
	_ = users.SaveVerificationCode("bob@example.com", "111111", time.Now().Add(time.Hour))

	register := NewRegisterService(users, newFakeRefreshTokenRepo(), testSigner(), time.Hour)

	_, err := register(context.Background(), RegisterRequest{
		Email: "bob@example.com", ConfirmEmail: "bob@example.com",
		Name: "Bob", Password: "password123", Code: "000000",
	})
	if err == nil {
		t.Fatal("expected an error for a wrong verification code, got nil")
	}
	mustHaveCode(t, err, apperr.CodeValidation)
}

func TestRegisterRejectsDuplicateEmail(t *testing.T) {
	users := newFakeUserRepo()
	existing := entity.NewUser("Existing", "bob@example.com")
	_ = existing.SetPassword("password123")
	_ = users.CreateUser(existing)
	_ = users.SaveVerificationCode("bob@example.com", "111111", time.Now().Add(time.Hour))

	register := NewRegisterService(users, newFakeRefreshTokenRepo(), testSigner(), time.Hour)

	_, err := register(context.Background(), RegisterRequest{
		Email: "bob@example.com", ConfirmEmail: "bob@example.com",
		Name: "Bob", Password: "password123", Code: "111111",
	})
	if err == nil {
		t.Fatal("expected an error for a duplicate email, got nil")
	}
	mustHaveCode(t, err, apperr.CodeValidation)
}

func TestRegisterSucceedsAndIssuesTokenPair(t *testing.T) {
	users := newFakeUserRepo()
	_ = users.SaveVerificationCode("carol@example.com", "222222", time.Now().Add(time.Hour))
	refreshRepo := newFakeRefreshTokenRepo()

	register := NewRegisterService(users, refreshRepo, testSigner(), time.Hour)

	res, err := register(context.Background(), RegisterRequest{
		Email: "carol@example.com", ConfirmEmail: "carol@example.com",
		Name: "Carol", Password: "password123", Code: "222222",
	})
	if err != nil {
		t.Fatalf("Register() error = %v", err)
	}
	if res.AccessToken == "" || res.RefreshToken == "" {
		t.Error("expected both AccessToken and RefreshToken to be set")
	}
	if _, ok := users.byEmail["carol@example.com"]; !ok {
		t.Error("expected the new user to be persisted")
	}
	if _, stillThere := users.codes["carol@example.com"]; stillThere {
		t.Error("expected the verification code to be deleted after successful registration")
	}
}

func TestSendCodeRejectsExistingEmail(t *testing.T) {
	users := newFakeUserRepo()
	existing := entity.NewUser("Dave", "dave@example.com")
	_ = existing.SetPassword("password123")
	_ = users.CreateUser(existing)

	sendCode := NewSendCodeService(users, &fakeEmailSender{})

	_, err := sendCode(context.Background(), SendCodeRequest{Email: "dave@example.com"})
	if err == nil {
		t.Fatal("expected an error for an already-registered email, got nil")
	}
	mustHaveCode(t, err, apperr.CodeValidation)
}

func TestSendCodeSendsEmailForNewAddress(t *testing.T) {
	users := newFakeUserRepo()
	sender := &fakeEmailSender{}
	sendCode := NewSendCodeService(users, sender)

	_, err := sendCode(context.Background(), SendCodeRequest{Email: "new@example.com"})
	if err != nil {
		t.Fatalf("SendCode() error = %v", err)
	}
	if len(sender.sentTo) != 1 || sender.sentTo[0] != "new@example.com" {
		t.Errorf("sentTo = %v, want exactly [new@example.com]", sender.sentTo)
	}
}
