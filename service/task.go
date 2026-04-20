package service

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"Real-time-Chat/chat"
	"Real-time-Chat/entity"
	"Real-time-Chat/repository"
)

type GetTasksRequest struct {
	RoomID string
}

type GetTasksResponse struct {
	Data []entity.Task `json:"data"`
}

type GetTasks func(ctx context.Context, req GetTasksRequest) (*GetTasksResponse, error)

func NewGetTasksService(repo repository.Task) GetTasks {
	return func(ctx context.Context, req GetTasksRequest) (*GetTasksResponse, error) {
		tasks, err := repo.GetTasks(req.RoomID)
		if err != nil {
			return nil, err
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
	return nil
}

func NewCreateTaskService(repo repository.Task, chatHub *chat.Chat) CreateTask {
	return func(ctx context.Context, req CreateTaskRequest) (*CreateTaskResponse, error) {
		if req.Title == "" {
			return nil, errors.New("title is required")
		}

		userID, _ := ctx.Value(entity.ContextKeyUserID).(string)

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
			return nil, err
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

		wsMsg := chat.Message{
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

func NewUpdateTaskService(repo repository.Task, chatHub *chat.Chat) UpdateTask {
	return func(ctx context.Context, req UpdateTaskRequest) (*UpdateTaskResponse, error) {

		if req.Title == "" && req.Priority == "" && req.Status != "" {
			err := repo.UpdateTaskStatus(req.ID, req.Status, req.AcceptedBy)
			if err != nil {
				return nil, err
			}
			
			// Рассылаем уведомление об обновлении статуса через WebSocket
			// Чтобы найти RoomID, нам бы в идеале нужно было достать задачу из БД,
			// но для простоты мы можем слать тип 'task_updated', 
			// а фронтенд сам поймет, что нужно обновить.
			chatHub.Broadcast(chat.Message{
				Type: "task_updated",
				Metadata: []byte(`{"task_id":"` + req.ID + `", "status":"` + req.Status + `"}`),
			})

			return &UpdateTaskResponse{Data: entity.Task{ID: req.ID, Status: req.Status}}, nil
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
			return nil, err
		}

		// Рассылаем уведомление о полном обновлении задачи
		chatHub.Broadcast(chat.Message{
			Type: "task_updated",
			Metadata: []byte(`{"task_id":"` + req.ID + `"}`),
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

func NewDeleteTaskService(repo repository.Task) DeleteTask {
	return func(ctx context.Context, req DeleteTaskRequest) (*DeleteTaskResponse, error) {
		if err := repo.DeleteTask(req.ID); err != nil {
			return nil, err
		}
		return &DeleteTaskResponse{Status: true}, nil
	}
}
