package service

import (
	entity2 "Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/pkg/token"
	"Real-time-Chat/internal/pkg/utils"
	"Real-time-Chat/internal/repository"
	"context"
	"errors"
	"log"
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
			return nil, errors.New("email is required")
		}

		// Проверяем, не зарегистрирован ли уже такой пользователь
		_, err := repo.GetUserByEmail(email)
		if err != entity2.ErrUserNotFound {
			if err == nil {
				return nil, errors.New("пользователь с такой почтой уже существует")
			}
			return nil, err
		}

		code := utils.GenerateVerificationCode()
		expiresAt := time.Now().Add(15 * time.Minute)

		if err := repo.SaveVerificationCode(email, code, expiresAt); err != nil {
			log.Printf("DB Error saving code: %v", err)
			return nil, err
		}

		if err := emailSender.SendVerificationCode(email, code); err != nil {
			log.Printf("Email Error sending code to %s: %v", email, err)
			return nil, errors.New("не удалось отправить письмо с кодом")
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
		userID := ctx.Value(entity2.ContextKeyUserID).(string)
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
		return errors.New("email is required")
	}
	if r.Email != r.ConfirmEmail {
		return errors.New("email does not match")
	}
	if r.Name == "" {
		return errors.New("name is required")
	}
	if r.Code == "" {
		return errors.New("code is required")
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
			log.Printf("DB Error checking code: %v", err)
			return nil, err
		}
		if !isValid {
			return nil, errors.New("неверный или просроченный код подтверждения")
		}

		// 2. Убеждаемся, что email не заняли, пока юзер вводил код
		_, err = repo.GetUserByEmail(req.Email)
		if err != entity2.ErrUserNotFound {
			return nil, errors.New("email already exists")
		}

		// 3. Создаем пользователя
		user := entity2.NewUser(req.Name, req.Email)
		if err := user.SetPassword(req.Password); err != nil {
			return nil, err
		}
		if err = repo.CreateUser(user); err != nil {
			log.Printf("DB Error creating user: %v", err)
			return nil, err
		}

		// 4. Удаляем использованный код
		_ = repo.DeleteVerificationCode(req.Email)

		token, err := signer.Sign(user.ID)
		if err != nil {
			return nil, err
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
			return nil, errors.New("неверный email или пароль")
		}
		if err := user.ComparePassword(req.Password); err != nil {
			return nil, errors.New("неверный email или пароль")
		}
		accessToken, err := signer.Sign(user.ID)
		if err != nil {
			return nil, err
		}
		return &LoginResponse{
			AccessToken: accessToken,
			ExpiresIn:   signer.ExpiresIn(),
		}, nil
	}
}
