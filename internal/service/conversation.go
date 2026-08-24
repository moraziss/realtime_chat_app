package service

import (
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/repository"
	"context"
	"errors"
)

type GetConversationsRequest struct {
	RoomID string
}

type GetConversationsResponse struct {
	Data []entity.Conversation `json:"data"`
	Room string                `json:"room"`
}

type GetConversations func(ctx context.Context, req GetConversationsRequest) (*GetConversationsResponse, error)

func NewGetConversationsService(repo repository.Conversation, rooms interface {
	GetRoom(userID string) ([]string, error)
}) GetConversations {
	return func(ctx context.Context, req GetConversationsRequest) (*GetConversationsResponse, error) {
		userID, _ := ctx.Value(entity.ContextKeyUserID).(string)
		userRooms, err := rooms.GetRoom(userID)
		if err != nil {
			return nil, err
		}
		isMember := false
		for _, id := range userRooms {
			if id == req.RoomID {
				isMember = true
				break
			}
		}
		if !isMember {
			return nil, errors.New("доступ запрещён: вы не состоите в этой комнате")
		}

		conversations, err := repo.GetConversations(req.RoomID)
		if err != nil {
			return nil, err
		}
		return &GetConversationsResponse{
			Data: conversations,
			Room: req.RoomID,
		}, nil
	}
}
