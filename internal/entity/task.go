package entity

import "time"

type TaskStats struct {
	Total      int `json:"total"`
	InProgress int `json:"in_progress"`
	Done       int `json:"done"`
}

type Task struct {
	ID          string      `json:"id"`
	RoomID      string      `json:"room_id"`
	CreatedBy   string      `json:"created_by"`
	AssignedTo  *string     `json:"assigned_to"`
	Title       string      `json:"title"`
	Description string      `json:"description"`
	Status      string      `json:"status"`
	Priority    string      `json:"priority"`
	DueDate     *time.Time  `json:"due_date"` // Указатель, так как может быть nil
	Subtasks    interface{} `json:"subtasks,omitempty"`
	AcceptedBy  []string    `json:"accepted_by"`
	CreatedAt   time.Time   `json:"created_at"`
	UpdatedAt   time.Time   `json:"updated_at"`
}

type TaskMetadata struct {
	TaskID     string   `json:"task_id"`
	Status     string   `json:"status"`
	AcceptedBy []string `json:"accepted_by"`
}
