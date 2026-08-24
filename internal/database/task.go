package database

import (
	"Real-time-Chat/internal/entity"
	"encoding/json"
)

func (c *Conn) GetUserTaskStats(userID string) (*entity.TaskStats, error) {
	var stats entity.TaskStats
	query := `
       SELECT
          COUNT(*),
          COUNT(*) FILTER (WHERE status = 'in_progress'),
          COUNT(*) FILTER (WHERE status = 'done')
       FROM tasks
       WHERE created_by = $1
          OR assigned_to = $1
          OR (accepted_by @> jsonb_build_array($1::text))`
	err := c.db.QueryRow(query, userID).Scan(&stats.Total, &stats.InProgress, &stats.Done)
	return &stats, err
}

// AcceptTask регистрирует "принятие" задачи пользователем. accepted_by и
// status теперь читаются и пишутся только в таблице tasks — она единственный
// источник истины для состояния задачи (metadata в conversations больше не
// дублирует и не хранит эти поля, см. GetConversations/refreshTaskMetadata).
func (d *Conn) AcceptTask(taskID, userID string) (*entity.TaskMetadata, error) {
	var acceptedByJSON []byte
	var status string
	err := d.db.QueryRow(`SELECT accepted_by, status FROM tasks WHERE id = $1`, taskID).Scan(&acceptedByJSON, &status)
	if err != nil {
		return nil, err
	}

	var acceptedBy []string
	if len(acceptedByJSON) > 0 {
		_ = json.Unmarshal(acceptedByJSON, &acceptedBy)
	}

	alreadyAccepted := false
	for _, u := range acceptedBy {
		if u == userID {
			alreadyAccepted = true
			break
		}
	}
	if !alreadyAccepted {
		acceptedBy = append(acceptedBy, userID)
	}

	if len(acceptedBy) >= 2 && status == "todo" {
		status = "in_progress"
	}

	newAcceptedByJSON, err := json.Marshal(acceptedBy)
	if err != nil {
		return nil, err
	}

	_, err = d.db.Exec(`UPDATE tasks SET status = $1, accepted_by = $2, updated_at = NOW() WHERE id = $3`,
		status, string(newAcceptedByJSON), taskID)
	if err != nil {
		return nil, err
	}

	return &entity.TaskMetadata{TaskID: taskID, Status: status, AcceptedBy: acceptedBy}, nil
}

// UpdateTask перезаписывает поля задачи. Значения приходят от клиента как
// уже полный объект (см. TaskPanel во Flutter-клиенте), поэтому description
// пишется как есть — включая пустую строку, если пользователь намеренно
// очистил поле. Остальные текстовые поля защищены COALESCE(NULLIF(...))
// на случай частичных запросов, которые их не передают.
func (d *Conn) UpdateTask(task *entity.Task) error {
	subtasksJSON, _ := json.Marshal(task.Subtasks)
	if string(subtasksJSON) == "null" || task.Subtasks == nil {
		subtasksJSON = []byte("[]")
	}

	_, err := d.db.Exec(`UPDATE tasks SET
		title=COALESCE(NULLIF($1,''),title),
		description=$2,
		status=COALESCE(NULLIF($3,''),status),
		priority=COALESCE(NULLIF($4,''),priority),
		due_date=$5,
		subtasks=$6,
		assigned_to=COALESCE($7,assigned_to),
		updated_at=NOW()
		WHERE id=$8`,
		task.Title,
		task.Description,
		task.Status,
		task.Priority,
		task.DueDate,
		string(subtasksJSON),
		task.AssignedTo,
		task.ID,
	)
	return err
}

func (c *Conn) CreateTask(task *entity.Task) error {
	if task.Priority == "" {
		task.Priority = "medium"
	}

	subtasksJSON, _ := json.Marshal(task.Subtasks)
	if string(subtasksJSON) == "null" || task.Subtasks == nil {
		subtasksJSON = []byte("[]")
	}

	return c.db.QueryRow(`
		INSERT INTO tasks (room_id, created_by, assigned_to, title, description, status, priority, due_date, subtasks, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
		RETURNING id, created_at, updated_at`,
		task.RoomID,
		task.CreatedBy,
		task.AssignedTo,
		task.Title,
		task.Description,
		task.Status,
		task.Priority,
		task.DueDate,
		string(subtasksJSON),
	).Scan(&task.ID, &task.CreatedAt, &task.UpdatedAt)
}

func (d *Conn) UpdateTaskStatus(taskID string, newStatus string, acceptedBy []string) error {
	if len(acceptedBy) > 0 {
		acceptedByJSON, err := json.Marshal(acceptedBy)
		if err != nil {
			return err
		}
		_, err = d.db.Exec(`UPDATE tasks SET status = $1, accepted_by = $2, updated_at = NOW() WHERE id = $3`,
			newStatus, string(acceptedByJSON), taskID)
		return err
	}
	_, err := d.db.Exec(`UPDATE tasks SET status = $1, updated_at = NOW() WHERE id = $2`, newStatus, taskID)
	return err
}

func (c *Conn) GetTaskRoom(taskID string) (string, error) {
	var roomID string
	err := c.db.QueryRow(`SELECT room_id FROM tasks WHERE id = $1`, taskID).Scan(&roomID)
	return roomID, err
}

func (c *Conn) GetTasks(roomID string) ([]entity.Task, error) {
	rows, err := c.db.Query(`
       SELECT id, room_id, created_by, assigned_to, title, description, status, priority, due_date, subtasks, accepted_by, created_at, updated_at
       FROM tasks
       WHERE room_id = $1
       ORDER BY created_at DESC`, roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []entity.Task
	for rows.Next() {
		var t entity.Task
		var subtasksJSON, acceptedByJSON []byte
		if err := rows.Scan(
			&t.ID, &t.RoomID, &t.CreatedBy, &t.AssignedTo,
			&t.Title, &t.Description, &t.Status, &t.Priority,
			&t.DueDate, &subtasksJSON, &acceptedByJSON, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			return nil, err
		}
		// Сканировать jsonb прямо в t.Subtasks (interface{}) нельзя — database/sql
		// присвоит туда сырые []byte, а encoding/json потом закодирует их в base64
		// вместо настоящего массива. Поэтому декодируем явно.
		if len(subtasksJSON) > 0 {
			_ = json.Unmarshal(subtasksJSON, &t.Subtasks)
		}
		if len(acceptedByJSON) > 0 {
			_ = json.Unmarshal(acceptedByJSON, &t.AcceptedBy)
		}
		result = append(result, t)
	}
	return result, nil
}

func (c *Conn) DeleteTask(id string) error {
	_, err := c.db.Exec(`DELETE FROM tasks WHERE id = $1`, id)
	if err != nil {
		return err
	}
	_, err = c.db.Exec(`DELETE FROM conversations WHERE (metadata::jsonb)->>'task_id' = $1`, id)
	return err
}

func (d *Conn) MarkMessagesAsRead(roomID, userID string) error {
	_, err := d.db.Exec(`
		UPDATE conversations 
		SET metadata = COALESCE(metadata, '{}'::jsonb) || '{"is_read": true}'::jsonb 
		WHERE room_id = $1 AND user_id != $2 AND (metadata->>'is_read' IS NULL OR metadata->>'is_read' = 'false')`,
		roomID, userID)
	return err
}
