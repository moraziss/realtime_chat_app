package service

import (
	"context"
	"errors"

	"Real-time-Chat/entity"
	"Real-time-Chat/repository"
)

type GetRoomsRequest struct{}

type GetRoomsResponse struct {
	Data []entity.UserRoom `json:"data"`
}

type GetRooms func(ctx context.Context, req GetRoomsRequest) (*GetRoomsResponse, error)

func NewGetRoomsService(repo repository.Room) GetRooms {
	return func(ctx context.Context, req GetRoomsRequest) (*GetRoomsResponse, error) {
		userID, _ := ctx.Value(entity.ContextKeyUserID).(string)
		if userID == "" {
			return nil, errors.New("user_id is required")
		}
		rooms, err := repo.GetRooms(userID)
		if err != nil {
			return nil, err
		}
		return &GetRoomsResponse{Data: rooms}, nil
	}
}

type PostRoomsRequest struct {
	UserID   string `json:"-"`
	FriendID string `json:"friend_id"`
}

type PostRoomsResponse struct {
	Data entity.UserRoom `json:"data"`
}

type PostRooms func(ctx context.Context, req PostRoomsRequest) (*PostRoomsResponse, error)

func NewPostRoomsService(repo repository.Room) PostRooms {
	return func(ctx context.Context, req PostRoomsRequest) (*PostRoomsResponse, error) {
		if req.FriendID == "" {
			return nil, errors.New("friend_id is required")
		}

		// ПРОВЕРКА: существует ли уже чат между этими пользователями
		existingRoomID, err := repo.GetDirectRoom(req.UserID, req.FriendID)
		if err == nil && existingRoomID != "" {
			// Если чат уже есть, возвращаем его ID вместо создания нового
			return &PostRoomsResponse{
				Data: entity.UserRoom{
					UserID: req.FriendID,
					RoomID: existingRoomID,
				},
			}, nil
		}

		// Если чата нет, создаем новый
		roomID, err := repo.CreateRoom(req.UserID, req.FriendID)
		if err != nil {
			return nil, err
		}
		return &PostRoomsResponse{
			Data: entity.UserRoom{
				UserID: req.FriendID,
				RoomID: roomID,
			},
		}, nil
	}
}
