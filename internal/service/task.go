package service

import (
	"Real-time-Chat/internal/apperr"
	"Real-time-Chat/internal/entity"
	"Real-time-Chat/internal/repository"
	"Real-time-Chat/internal/ws"
	"context"
	"encoding/json"
	"log/slog"
	"time"
)

func isRoomMember(rooms interface {
	GetRoom(userID string) ([]string, error)
}, userID, roomID string) bool {
	userRooms, err := rooms.GetRoom(userID)
	if err != nil {
		return false
	}
	for _, id := range userRooms {
		if id == roomID {
			return true
		}
	}
	return false
}

type GetTasksRequest struct {
	RoomID string
}

type GetTasksResponse struct {
	Data []entity.Task `json:"data"`
}

type GetTasks func(ctx context.Context, req GetTasksRequest) (*GetTasksResponse, error)

func NewGetTasksService(repo repository.Task, rooms interface {
	GetRoom(userID string) ([]string, error)
}) GetTasks {
	return func(ctx context.Context, req GetTasksRequest) (*GetTasksResponse, error) {
		userID, _ := ctx.Value(entity.ContextKeyUserID).(string)
		if !isRoomMember(rooms, userID, req.RoomID) {
			return nil, apperr.Forbidden("доступ запрещён: вы не состоите в этой комнате")
		}
		tasks, err := repo.GetTasks(req.RoomID)
		if err != nil {
			return nil, apperr.Internal(err)
		}
		return &GetTasksResponse{Data: tasks}, nil
	}
}

type CreateTask func(ctx context.Context, req CreateTaskRequest) (*CreateTaskResponse, error)

type CreateTaskRequest struct {
	RoomID      string      `json:"room_id"`
	AssignedTo  string      `json:"assigned_to,omitempty"`
	Title       string      `json:"title"`
	Description string      `json:"description,omitempty"`
	Priority    string      `json:"priority"`
	DueDate     interface{} `json:"due_date"`
	Subtasks    interface{} `json:"subtasks,omitempty"`
}

type CreateTaskResponse struct {
	Data entity.Task `json:"data"`
}

// parseFlexibleTime пытается распарсить дату из разных форматов (ISO8601)
func parseFlexibleTime(val interface{}) *time.Time {
	if val == nil {
		return nil
	}
	str, ok := val.(string)
	if !ok || str == "" {
		return nil
	}

	// Список популярных форматов
	layouts := []string{
		time.RFC3339,
		"2006-01-02T15:04:05.999999999Z07:00",
		"2006-01-02T15:04:05.999999999",
		"2006-01-02T15:04:05",
		"2006-01-02",
	}

	for _, layout := range layouts {
		if t, err := time.Parse(layout, str); err == nil {
			return &t
		}
	}
	// Формат не распознан: срок просто не будет установлен. Это не приводит
	// к ошибке API, но стоит видеть в логах, а не терять молча.
	slog.Warn("unrecognized due_date format, deadline not set", "value", str)
	return nil
}

func NewCreateTaskService(repo repository.Task, chatHub *ws.Chat, rooms interface {
	GetRoom(userID string) ([]string, error)
}) CreateTask {
	return func(ctx context.Context, req CreateTaskRequest) (*CreateTaskResponse, error) {
		if req.Title == "" {
			return nil, apperr.Validation("title is required")
		}

		userID, _ := ctx.Value(entity.ContextKeyUserID).(string)
		if !isRoomMember(rooms, userID, req.RoomID) {
			return nil, apperr.Forbidden("доступ запрещён: вы не состоите в этой комнате")
		}

		var assignedToPtr *string
		if req.AssignedTo != "" {
			assignedToPtr = &req.AssignedTo
		}

		parsedDueDate := parseFlexibleTime(req.DueDate)

		task := &entity.Task{
			RoomID:      req.RoomID,
			CreatedBy:   userID,
			Title:       req.Title,
			Description: req.Description,
			Status:      "todo",
			Priority:    req.Priority,
			AssignedTo:  assignedToPtr,
			DueDate:     parsedDueDate,
			Subtasks:    req.Subtasks,
		}

		taskID, msgID, err := repo.CreateTaskWithMessage(task)
		if err != nil {
			return nil, apperr.Internal(err)
		}

		metaMap := map[string]interface{}{
			"task_id":     taskID,
			"title":       req.Title,
			"description": req.Description,
			"status":      "todo",
			"priority":    req.Priority,
			"accepted_by": []string{},
			"due_date":    parsedDueDate,
			"subtasks":    req.Subtasks,
		}

		metadataBytes, _ := json.Marshal(metaMap)

		wsMsg := ws.Message{
			ID:        msgID,
			Type:      "task_created",
			Sender:    userID,
			Receiver:  req.RoomID,
			Text:      "[Совместная задача]",
			Timestamp: time.Now().Unix(),
			Metadata:  metadataBytes,
		}

		chatHub.Broadcast(wsMsg)

		task.ID = taskID
		return &CreateTaskResponse{Data: *task}, nil
	}
}

type UpdateTaskRequest struct {
	ID          string      `json:"-"`
	Title       string      `json:"title"`
	Description string      `json:"description,omitempty"`
	Status      string      `json:"status"`
	AssignedTo  string      `json:"assigned_to,omitempty"`
	Priority    string      `json:"priority"`
	DueDate     interface{} `json:"due_date"`
	AcceptedBy  []string    `json:"accepted_by"`
	Subtasks    interface{} `json:"subtasks,omitempty"`
}

type UpdateTaskResponse struct {
	Data entity.Task `json:"data"`
}

type UpdateTask func(ctx context.Context, req UpdateTaskRequest) (*UpdateTaskResponse, error)

func NewUpdateTaskService(repo repository.Task, chatHub *ws.Chat, rooms interface {
	GetRoom(userID string) ([]string, error)
}) UpdateTask {
	return func(ctx context.Context, req UpdateTaskRequest) (*UpdateTaskResponse, error) {
		userID, _ := ctx.Value(entity.ContextKeyUserID).(string)
		taskRoomID, err := repo.GetTaskRoom(req.ID)
		if err != nil {
			return nil, apperr.Internal(err)
		}
		if !isRoomMember(rooms, userID, taskRoomID) {
			return nil, apperr.Forbidden("доступ запрещён: вы не состоите в комнате этой задачи")
		}

		if req.Title == "" && req.Priority == "" && req.Status != "" {
			finalStatus := req.Status

			if len(req.AcceptedBy) > 0 {
				// "Принятие" задачи: сервер сам решает итоговый accepted_by
				// (только добавляя ТЕКУЩЕГО авторизованного пользователя) и
				// статус (>=2 принявших -> in_progress), а не доверяет
				// списку/статусу, присланному клиентом — иначе PATCH-запрос
				// напрямую (не через UI) мог бы добавить в accepted_by
				// чужой userID или сразу выставить in_progress в одиночку,
				// обходя "рукопожатие обеими сторонами".
				meta, err := repo.AcceptTask(req.ID, userID)
				if err != nil {
					return nil, apperr.Internal(err)
				}
				finalStatus = meta.Status
			} else {
				if err := repo.UpdateTaskStatus(req.ID, req.Status, nil); err != nil {
					return nil, apperr.Internal(err)
				}
			}

			// Рассылаем уведомление об обновлении статуса через WebSocket
			// Чтобы найти RoomID, нам бы в идеале нужно было достать задачу из БД,
			// но для простоты мы можем слать тип 'task_updated',
			// а фронтенд сам поймет, что нужно обновить.
			statusMetadata, _ := json.Marshal(map[string]string{
				"task_id": req.ID,
				"status":  finalStatus,
			})
			chatHub.Broadcast(ws.Message{
				Type:     "task_updated",
				Metadata: statusMetadata,
			})

			return &UpdateTaskResponse{Data: entity.Task{ID: req.ID, Status: finalStatus}}, nil
		}

		parsedDueDate := parseFlexibleTime(req.DueDate)

		var assignedToPtr *string
		if req.AssignedTo != "" {
			assignedToPtr = &req.AssignedTo
		}

		task := &entity.Task{
			ID:          req.ID,
			Title:       req.Title,
			Description: req.Description,
			Status:      req.Status,
			Priority:    req.Priority,
			AssignedTo:  assignedToPtr,
			DueDate:     parsedDueDate,
			Subtasks:    req.Subtasks,
		}

		if err := repo.UpdateTask(task); err != nil {
			return nil, apperr.Internal(err)
		}

		// Рассылаем уведомление о полном обновлении задачи
		updateMetadata, _ := json.Marshal(map[string]string{"task_id": req.ID})
		chatHub.Broadcast(ws.Message{
			Type:     "task_updated",
			Metadata: updateMetadata,
		})

		return &UpdateTaskResponse{Data: *task}, nil
	}
}

type DeleteTaskRequest struct {
	ID string
}

type DeleteTaskResponse struct {
	Status bool `json:"status"`
}

type DeleteTask func(ctx context.Context, req DeleteTaskRequest) (*DeleteTaskResponse, error)

func NewDeleteTaskService(repo repository.Task, rooms interface {
	GetRoom(userID string) ([]string, error)
}) DeleteTask {
	return func(ctx context.Context, req DeleteTaskRequest) (*DeleteTaskResponse, error) {
		userID, _ := ctx.Value(entity.ContextKeyUserID).(string)
		taskRoomID, err := repo.GetTaskRoom(req.ID)
		if err != nil {
			return nil, apperr.Internal(err)
		}
		if !isRoomMember(rooms, userID, taskRoomID) {
			return nil, apperr.Forbidden("доступ запрещён: вы не состоите в комнате этой задачи")
		}

		if err := repo.DeleteTask(req.ID); err != nil {
			return nil, apperr.Internal(err)
		}
		return &DeleteTaskResponse{Status: true}, nil
	}
}
