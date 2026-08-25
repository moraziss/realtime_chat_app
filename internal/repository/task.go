package repository

import (
	"Real-time-Chat/internal/entity"
)

type Task interface {
	GetTasks(roomID string) ([]entity.Task, error)
	GetTaskRoom(taskID string) (string, error)
	CreateTask(task *entity.Task) error
	UpdateTask(task *entity.Task) error
	UpdateTaskStatus(taskID string, newStatus string, acceptedBy []string) error
	DeleteTask(id string) error
	GetUserTaskStats(userID string) (*entity.TaskStats, error)
	CreateTaskWithMessage(task *entity.Task) (string, string, error)
	AcceptTask(taskID, userID string) (*entity.TaskMetadata, error)
}
