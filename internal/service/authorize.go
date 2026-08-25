package service

import (
	"Real-time-Chat/internal/apperr"
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/logging"
	"Real-time-Chat/internal/pkg/token"
	"Real-time-Chat/internal/pkg/utils"
	"Real-time-Chat/internal/repository"
	"context"
	"strings"
	"time"
)

// --- ОТПРАВКА КОДА ---

type SendCodeRequest struct {
	Email string `json:"email"`
}

type SendCodeResponse struct {
	Message string `json:"message"`
}

type SendCode func(ctx context.Context, req SendCodeRequest) (*SendCodeResponse, error)

func NewSendCodeService(repo repository.User, emailSender EmailSender) SendCode {
	return func(ctx context.Context, req SendCodeRequest) (*SendCodeResponse, error) {
		email := strings.ToLower(strings.TrimSpace(req.Email))
		if email == "" {
			return nil, apperr.Validation("email is required")
		}

		// Проверяем, не зарегистрирован ли уже такой пользователь
		_, err := repo.GetUserByEmail(email)
		if err != entity.ErrUserNotFound {
			if err == nil {
				return nil, apperr.Validation("пользователь с такой почтой уже существует")
			}
			return nil, apperr.Internal(err)
		}

		code := utils.GenerateVerificationCode()
		expiresAt := time.Now().Add(15 * time.Minute)

		if err := repo.SaveVerificationCode(email, code, expiresAt); err != nil {
			logging.FromContext(ctx).Error("failed to save verification code", "err", err)
			return nil, apperr.Internal(err)
		}

		if err := emailSender.SendVerificationCode(email, code); err != nil {
			logging.FromContext(ctx).Error("failed to send verification email", "email", email, "err", err)
			return nil, apperr.Internal(err)
		}

		return &SendCodeResponse{Message: "Код отправлен на почту"}, nil
	}
}

// --- АВТОРИЗАЦИЯ ---

type AuthorizeRequest struct{}

type AuthorizeResponse struct {
	Name string `json:"name"`
}

type Authorize func(ctx context.Context, req AuthorizeRequest) (*AuthorizeResponse, error)

func NewAuthorizeService(repo repository.User) Authorize {
	return func(ctx context.Context, req AuthorizeRequest) (*AuthorizeResponse, error) {
		userID := ctx.Value(entity.ContextKeyUserID).(string)
		user, err := repo.GetUser(userID)
		if err != nil {
			return nil, err
		}
		return &AuthorizeResponse{
			Name: user.Name,
		}, nil
	}
}

// --- РЕГИСТРАЦИЯ ---

type RegisterRequest struct {
	Email        string `json:"email"`
	ConfirmEmail string `json:"confirm_email"`
	Password     string `json:"password"`
	Name         string `json:"name"`
	Code         string `json:"code"`
}

func (r *RegisterRequest) Validate() error {
	r.Email = strings.ToLower(strings.TrimSpace(r.Email))
	r.ConfirmEmail = strings.ToLower(strings.TrimSpace(r.ConfirmEmail))

	if r.Email == "" {
		return apperr.Validation("email is required")
	}
	if r.Email != r.ConfirmEmail {
		return apperr.Validation("email does not match")
	}
	if r.Name == "" {
		return apperr.Validation("name is required")
	}
	if r.Code == "" {
		return apperr.Validation("code is required")
	}
	return nil
}

type RegisterResponse struct {
	AccessToken string `json:"access_token"`
}

type Register func(ctx context.Context, req RegisterRequest) (*RegisterResponse, error)

func NewRegisterService(repo repository.User, signer token.Signer) Register {
	return func(ctx context.Context, req RegisterRequest) (*RegisterResponse, error) {
		if err := req.Validate(); err != nil {
			return nil, err
		}

		// 1. Проверяем код
		isValid, err := repo.CheckVerificationCode(req.Email, req.Code)
		if err != nil {
			logging.FromContext(ctx).Error("failed to check verification code", "err", err)
			return nil, apperr.Internal(err)
		}
		if !isValid {
			return nil, apperr.Validation("неверный или просроченный код подтверждения")
		}

		// 2. Убеждаемся, что email не заняли, пока юзер вводил код
		_, err = repo.GetUserByEmail(req.Email)
		if err != entity.ErrUserNotFound {
			return nil, apperr.Validation("email already exists")
		}

		// 3. Создаем пользователя
		user := entity.NewUser(req.Name, req.Email)
		if err := user.SetPassword(req.Password); err != nil {
			return nil, apperr.Validation(err.Error())
		}
		if err = repo.CreateUser(user); err != nil {
			logging.FromContext(ctx).Error("failed to create user", "err", err)
			return nil, apperr.Internal(err)
		}

		// 4. Удаляем использованный код
		_ = repo.DeleteVerificationCode(req.Email)

		token, err := signer.Sign(user.ID)
		if err != nil {
			return nil, apperr.Internal(err)
		}
		return &RegisterResponse{
			AccessToken: token,
		}, nil
	}
}

// --- ЛОГИН ---

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int64  `json:"expires_in"`
}

type Login func(ctx context.Context, req LoginRequest) (*LoginResponse, error)

func NewLoginService(repo repository.User, signer token.Signer) Login {
	return func(ctx context.Context, req LoginRequest) (*LoginResponse, error) {
		email := strings.ToLower(strings.TrimSpace(req.Email))
		user, err := repo.GetUserByEmail(email)
		if err != nil {
			return nil, apperr.Unauthorized("неверный email или пароль")
		}
		if err := user.ComparePassword(req.Password); err != nil {
			return nil, apperr.Unauthorized("неверный email или пароль")
		}
		accessToken, err := signer.Sign(user.ID)
		if err != nil {
			return nil, apperr.Internal(err)
		}
		return &LoginResponse{
			AccessToken: accessToken,
			ExpiresIn:   signer.ExpiresIn(),
		}, nil
	}
}
