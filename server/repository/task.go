package repository

import "Real-time-Chat/entity"

type Task interface {
	GetTasks(roomID string) ([]entity.Task, error)
	CreateTask(task *entity.Task) error
	UpdateTask(task *entity.Task) error
	UpdateTaskStatus(taskID string, newStatus string, acceptedBy []string) error
	DeleteTask(id string) error
	GetUserTaskStats(userID string) (*entity.TaskStats, error)
	CreateTaskWithMessage(task *entity.Task) (string, string, error)
}
