package service

import (
	entity2 "Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/repository"
	"context"
	"encoding/json"
)

type GetUsersRequest struct {
	UserID string
}

type GetUserStatsRequest struct {
	UserID string
}

type GetUserStatsResponse struct {
	Total      int `json:"total"`
	InProgress int `json:"in_progress"`
	Done       int `json:"done"`
}

type GetUserStats func(ctx context.Context, req GetUserStatsRequest) (*GetUserStatsResponse, error)

func MakeGetUserStats(db interface {
	GetUserTaskStats(userID string) (*entity2.TaskStats, error)
}) GetUserStats {
	return func(ctx context.Context, req GetUserStatsRequest) (*GetUserStatsResponse, error) {
		stats, err := db.GetUserTaskStats(req.UserID)
		if err != nil {
			return nil, err
		}
		if stats == nil {
			return &GetUserStatsResponse{}, nil
		}
		return &GetUserStatsResponse{
			Total:      stats.Total,
			InProgress: stats.InProgress,
			Done:       stats.Done,
		}, nil
	}
}

type GetUsersResponse struct {
	Data []entity2.User `json:"data,omitempty"`
}

type GetUsers func(context.Context, GetUsersRequest) (*GetUsersResponse, error)

func NewGetUsersService(repo repository.User) GetUsers {
	return func(ctx context.Context, req GetUsersRequest) (*GetUsersResponse, error) {
		userID, _ := ctx.Value(entity2.ContextKeyUserID).(string)
		users, err := repo.GetUsers(userID)
		if err != nil {
			return nil, err
		}
		return &GetUsersResponse{Data: users}, nil
	}
}

// GetMe Сервис получения текущего пользователя
type GetMe func(ctx context.Context) (*entity2.User, error)

func NewGetMeService(repo repository.User) GetMe {
	return func(ctx context.Context) (*entity2.User, error) {
		userID, _ := ctx.Value(entity2.ContextKeyUserID).(string)
		user, err := repo.GetUser(userID)
		if err != nil {
			return nil, err
		}
		return user, nil
	}
}

// UpdateMe Сервис обновления профиля
type UpdateMe func(ctx context.Context, data map[string]interface{}) error

func NewUpdateMeService(repo repository.User) UpdateMe {
	return func(ctx context.Context, data map[string]interface{}) error {
		userID, _ := ctx.Value(entity2.ContextKeyUserID).(string)
		user, err := repo.GetUser(userID)
		if err != nil {
			return err
		}

		if val, ok := data["name"].(string); ok {
			user.Name = val
		}
		if val, ok := data["bio"].(string); ok {
			copyBio := val
			user.Bio = &copyBio
		}
		if val, ok := data["avatar_url"].(string); ok {
			copyAvatar := val
			user.AvatarURL = &copyAvatar
		}
		if val, ok := data["settings"].(map[string]interface{}); ok {
			settingsJSON, err := json.Marshal(val)
			if err == nil {
				user.Settings = json.RawMessage(settingsJSON)
			}
		}

		return repo.UpdateUser(user)
	}
}

// DeleteMe Сервис удаления текущего пользователя
type DeleteMe func(ctx context.Context) error

func NewDeleteMeService(repo repository.User) DeleteMe {
	return func(ctx context.Context) error {
		userID, _ := ctx.Value(entity2.ContextKeyUserID).(string)
		if userID == "" {
			return entity2.ErrUserNotFound
		}
		return repo.DeleteUser(userID)
	}
}

// GetExtendedStats Сервис получения расширенной статистики
type GetExtendedStats func(ctx context.Context) (map[string]interface{}, error)

func NewGetExtendedStatsService(db interface {
	GetExtendedStats(userID string) (map[string]interface{}, error)
}) GetExtendedStats {
	return func(ctx context.Context) (map[string]interface{}, error) {
		userID, _ := ctx.Value(entity2.ContextKeyUserID).(string)
		return db.GetExtendedStats(userID)
	}
}
